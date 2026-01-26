# ADR-001: State Management with Missionary

## Status
Proposed

## Context

cuirq is a framework for building desktop applications in Clojure with Qt/QML UI. We need a state management system that is:

1. **Lightweight** - without re-frame overhead (registries, interceptors, vector interpretation)
2. **Reactive** - automatic UI updates when data changes
3. **Multi-layered** - like re-frame: raw data → derived → component data
4. **I/O-friendly** - async operations support without callback hell
5. **Virtual threads compatible** - leveraging Java 21 Virtual Threads
6. **Offline-first ready** - ability to work with local and remote data

### Alternatives Considered

| Solution | Pros | Cons |
|----------|------|------|
| **re-frame** | Mature, well-documented, multi-level subscriptions | Heavy, ClojureScript-oriented, interpretation overhead |
| **citrus** | Lighter than re-frame | Still carries ClojureScript/Rum legacy |
| **cljfx approach** | Simple, functions instead of data events | No built-in reactivity |
| **core.async** | Well-known, CSP model | Different concurrency model, harder for simple cases |
| **missionary** | Reactive flows, Virtual Threads integration, built-in cancellation | Less known, requires learning |

## Decision

Two-layer architecture similar to reagent/re-frame:

1. **cuirq.state** - base layer on atoms, works standalone
2. **cuirq.state.reactive** - optional missionary layer for complex scenarios

This allows:
- Using simple API for simple applications
- Adding reactive layer when derived values, cancellation, backpressure are needed
- Evolving both layers in parallel
- Extracting reactive layer into a separate library in the future

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    cuirq.state.reactive                     │
│               (optional missionary layer)                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                   Derived Layer                        │ │
│  │  - m/latest for cached derived values                  │ │
│  │  - Transducer support                                  │ │
│  │  - Flow composition                                    │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                   Effect Layer                         │ │
│  │  - I/O on virtual threads (m/via m/blk)                │ │
│  │  - Operation cancellation                              │ │
│  │  - Backpressure                                        │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────────┬──────────────────────────────────┘
                           │ uses
┌──────────────────────────▼──────────────────────────────────┐
│                      cuirq.state                            │
│                     (base layer)                            │
│  - Atoms with immutable data                                │
│  - get/set/update state                                     │
│  - Simple watches for Qt binding                            │
│  - Works without dependencies                               │
└─────────────────────────────────────────────────────────────┘
```

### Usage

```clojure
;; Simple application - base layer only
(ns simple-app.core
  (:require [cuirq.state :as state]))

(def !app (state/create-store {:count 0}))
(state/watch! !app :qt #(qt/set-property "count" (:count %)))
(state/update! !app update :count inc)

;; Complex application - add reactive layer
(ns complex-app.core
  (:require [cuirq.state :as state]
            [cuirq.state.reactive :as r]))

(def !app (state/create-store {:items [] :filter :all}))

;; Cached derived values
(def filtered-items
  (r/derive !app
    (fn [{:keys [items filter]}]
      (case filter
        :active (remove :done items)
        :done (filter :done items)
        items))))

;; Subscription with automatic cancellation
(r/subscribe! filtered-items ::items-view
  #(qt/set-model "itemsModel" %))
```

## Implementation

### 1. Base Layer: cuirq.state

Base layer without external dependencies. Sufficient for simple applications.

```clojure
(ns cuirq.state)

;; ============================================================
;; State Store
;; ============================================================

(defn create-store
  "Creates a state store.

   Example:
     (def !app (create-store {:user nil :items []}))"
  [initial-state]
  (atom initial-state))

(defn get-state
  "Gets the current state."
  [store]
  @store)

;; ============================================================
;; State Updates
;; ============================================================

(defn update!
  "Updates state with a function.

   Examples:
     (update! !store assoc :loading true)
     (update! !store update :count inc)"
  [store f & args]
  (apply swap! store f args))

(defn set!
  "Sets new state."
  [store new-state]
  (reset! store new-state))

(defn update-in!
  "Updates value at path."
  [store path f & args]
  (apply swap! store update-in path f args))

;; ============================================================
;; Simple Watches (for Qt binding)
;; ============================================================

(defn watch!
  "Adds a watch to the store. Returns a cancel function.

   Example:
     (watch! !app :qt-sync
       (fn [new-state]
         (qt/set-context-property \"appState\" new-state)))"
  [store key callback]
  (add-watch store key (fn [_ _ _ new-val] (callback new-val)))
  #(remove-watch store key))

(defn unwatch!
  "Removes watch by key."
  [store key]
  (remove-watch store key))

;; ============================================================
;; Selectors (simple, no caching)
;; ============================================================

(defn select
  "Extracts value from state.

   Examples:
     (select !app :count)
     (select !app [:user :name])
     (select !app #(filter :active (:items %)))"
  [store selector]
  (let [state @store]
    (cond
      (keyword? selector) (get state selector)
      (vector? selector)  (get-in state selector)
      (fn? selector)      (selector state)
      :else               state)))
```

### 2. Reactive Layer: cuirq.state.reactive

Optional missionary layer for complex scenarios.

```clojure
(ns cuirq.state.reactive
  (:require [missionary.core :as m]
            [cuirq.state :as state]))

;; ============================================================
;; Subscriptions Registry
;; ============================================================

(defonce ^:private subscriptions (atom {}))

;; ============================================================
;; Derived Values (Flows)
;; ============================================================

(defn derive
  "Creates a derived flow from store with automatic caching.

   Usage variants:

   ;; Simple selector
   (derive !store :items)
   (derive !store #(get-in % [:user :name]))

   ;; With transducer
   (derive !store :items (filter :active))
   (derive !store :items (comp (filter :active) (take 10)))"
  ([store selector]
   (let [select-fn (if (keyword? selector) selector selector)]
     (m/latest select-fn (m/watch store))))
  ([store selector xf]
   (let [select-fn (if (keyword? selector) selector selector)]
     (m/latest #(into [] xf (select-fn %)) (m/watch store)))))

(defn derive-from
  "Creates a derived flow from multiple sources.

   Example:
     (derive-from [items-flow filter-flow]
       (fn [items flt]
         (filter #(= (:status %) flt) items)))"
  [flows combine-fn]
  (apply m/latest combine-fn flows))

;; ============================================================
;; Subscriptions
;; ============================================================

(defn subscribe!
  "Subscribes to a flow with callback.
   Returns a cancel function.

   Example:
     (def cancel (subscribe! filtered-items ::my-sub
                   (fn [items] (println \"Items:\" items))))
     ;; Cancel
     (cancel)"
  [flow key callback]
  (let [task (m/reduce
               (fn [_ value]
                 (callback value)
                 nil)
               nil
               flow)
        cancel (task
                 (fn [_] (swap! subscriptions dissoc key))
                 (fn [e] (println "Subscription error:" key e)))]
    (swap! subscriptions assoc key cancel)
    cancel))

(defn unsubscribe!
  "Cancels subscription by key."
  [key]
  (when-let [cancel (get @subscriptions key)]
    (cancel)
    (swap! subscriptions dissoc key)))

(defn unsubscribe-all!
  "Cancels all subscriptions."
  []
  (doseq [[_ cancel] @subscriptions]
    (cancel))
  (reset! subscriptions {}))
```

### 3. Async Effects (cuirq.state.reactive)

```clojure
;; ============================================================
;; Async Effects with Virtual Threads
;; ============================================================

(defn async!
  "Executes async operation on virtual thread.
   Returns a cancel function.

   Example:
     (async!
       (fn [] (http/get \"https://api.example.com/items\"))
       (fn [items] (state/update! !store assoc :items items))
       (fn [error] (state/update! !store assoc :error error)))"
  [operation on-success on-error]
  (let [task (m/sp
               (try
                 (let [result (m/? (m/via m/blk (operation)))]
                   (on-success result))
                 (catch Exception e
                   (on-error e))))]
    (task (fn [_]) (fn [e] (println "Async task error:" e)))))

(defn async-task
  "Creates a missionary task for I/O operation.

   Example:
     (def fetch-items
       (async-task #(http/get \"/api/items\")))

     ;; Usage in m/sp context
     (m/? fetch-items)"
  [operation]
  (m/via m/blk (operation)))

(defmacro go
  "Macro for sequential async operations.
   Returns a cancel function.

   Example:
     (go
       (let [user (m/? (fetch-user id))
             items (m/? (fetch-items (:id user)))]
         (state/update! !store assoc
           :user user
           :items items)))"
  [& body]
  `(let [task# (m/sp ~@body)]
     (task# (fn [_#]) (fn [e#] (println "async error:" e#)))))
```

### 4. Qt Integration (cuirq.state.reactive)

```clojure
;; continued from cuirq.state.reactive
;; ============================================================
;; Qt/QML Integration
;; ============================================================

(defn bind-qt!
  "Binds flow to Qt updates.
   Returns a cancel function.

   Example:
     (bind-qt! filtered-items-flow
       (fn [items] (qt/update-list-model \"itemsModel\" items)))"
  [flow qt-updater]
  (subscribe! flow (gensym "qt-binding")
    (fn [value]
      ;; send-to-qt-thread should be implemented in cuirq.core
      (send-to-qt-thread #(qt-updater value)))))

(defn bind-property!
  "Binds flow to Qt context property.

   Example:
     (bind-property! user-name-flow \"userName\")"
  [flow property-name]
  (bind-qt! flow
    (fn [value]
      (qt/set-context-property property-name value))))
```

### 5. Transducers Support (cuirq.state.reactive)

```clojure
;; continued from cuirq.state.reactive
;; ============================================================
;; Transducers - first-class citizen
;; ============================================================

;; Library of standard transformations
(def active (filter :active))
(def completed (filter :completed))
(def not-deleted (remove :deleted))

(defn sorted-by
  "Transducer-friendly sorting (via into with post-sorting)."
  [key-fn]
  (fn [coll] (sort-by key-fn coll)))

(defn derive-xf
  "Creates a derived flow with transducer.

   Example:
     (def !active-items
       (derive-xf !store :items
         (comp active
               (map #(select-keys % [:id :title]))
               (take 20))))"
  [store path xf]
  (m/latest
    #(into [] xf (get-in % (if (vector? path) path [path])))
    (m/watch store)))

;; Composition example
(comment
  ;; Define reusable transformations
  (def item-pipeline
    (comp (filter :valid)
          (map normalize)
          (remove :archived)))

  ;; Use everywhere
  (def !processed-items (derive-xf !store :items item-pipeline))

  ;; Same pipeline for I/O
  (into [] item-pipeline (fetch-items-from-api))

  ;; For streaming
  (run! process! (eduction item-pipeline items)))
```

## Example: File Manager

Complete file manager example based on the proposed architecture:

```clojure
(ns filemanager.core
  (:require [cuirq.state :as state]
            [cuirq.state.reactive :as r]
            [missionary.core :as m]
            [clojure.java.io :as io])
  (:import [java.nio.file FileSystems StandardWatchEventKinds]))

;; ============================================================
;; State
;; ============================================================

(def !app
  (state/create-store
    {:current-path (System/getProperty "user.home")
     :history []
     :sort {:field :name :order :asc}
     :selection #{}}))

;; Thumbnails in separate atom - independent lifecycle
(def !thumbnails
  (state/create-store {})) ; {path -> {:status :loading/:ready/:error, :uri "..."}}

;; ============================================================
;; File System
;; ============================================================

(defn list-files [path]
  (let [dir (io/file path)]
    (when (.isDirectory dir)
      (->> (.listFiles dir)
           (map (fn [f]
                  {:name (.getName f)
                   :path (.getAbsolutePath f)
                   :dir? (.isDirectory f)
                   :size (.length f)
                   :modified (.lastModified f)
                   :hidden? (.isHidden f)}))
           (remove :hidden?)))))

(defn watch-directory-flow
  "Flow that emits on directory changes."
  [path-flow]
  (m/ap
    (let [path (m/?> path-flow)]
      (m/? (m/observe
             (fn [emit!]
               (let [watcher (.newWatchService (FileSystems/getDefault))
                     dir-path (.toPath (io/file path))]
                 (.register dir-path watcher
                   (into-array [StandardWatchEventKinds/ENTRY_CREATE
                                StandardWatchEventKinds/ENTRY_DELETE
                                StandardWatchEventKinds/ENTRY_MODIFY]))
                 (emit! :init)
                 (future
                   (loop []
                     (when-let [key (.take watcher)]
                       (.pollEvents key)
                       (.reset key)
                       (emit! :changed)
                       (recur))))
                 #(.close watcher))))))))

;; ============================================================
;; Derived Flows
;; ============================================================

(def app-flow (m/watch !app))

(def current-path-flow
  (r/derive !app :current-path))

(def sort-flow
  (r/derive !app :sort))

(def history-flow
  (r/derive !app :history))

;; Files are re-read when:
;; 1. Directory changes
;; 2. File watcher event
(def files-flow
  (m/latest
    (fn [path _trigger]
      (or (list-files path) []))
    current-path-flow
    (m/relieve {} (watch-directory-flow current-path-flow))))

;; Sorting
(def sorted-files-flow
  (m/latest
    (fn [files {:keys [field order]}]
      (let [sorted (sort-by field files)]
        (if (= order :desc)
          (reverse sorted)
          sorted)))
    files-flow
    sort-flow))

;; Thumbnails
(def thumbnails-flow (m/watch !thumbnails))

;; Final view for UI
(def view-flow
  (m/latest
    (fn [files path history thumbs selection]
      {:dirs (->> files
                  (filter :dir?)
                  (map #(assoc % :selected? (contains? selection (:path %)))))
       :files (->> files
                   (remove :dir?)
                   (map (fn [{:keys [path] :as f}]
                          (let [thumb (get thumbs path)]
                            (assoc f
                              :selected? (contains? selection (:path f))
                              :thumbnail-uri
                              (case (:status thumb)
                                :ready (:uri thumb)
                                :loading "qrc:/icons/loading.png"
                                :error "qrc:/icons/error.png"
                                "qrc:/icons/file.png"))))))
       :current-path path
       :can-go-back? (boolean (seq history))
       :breadcrumbs (clojure.string/split path #"/")})
    sorted-files-flow
    current-path-flow
    history-flow
    thumbnails-flow
    (r/derive !app :selection)))

;; ============================================================
;; Actions (use base state/)
;; ============================================================

(defn navigate! [path]
  (state/set! !thumbnails {}) ; Clear thumbnail cache
  (state/update! !app
    (fn [state]
      (-> state
          (update :history conj (:current-path state))
          (assoc :current-path path)
          (assoc :selection #{})))))

(defn go-back! []
  (when (seq (:history @!app))
    (state/set! !thumbnails {})
    (state/update! !app
      (fn [{:keys [history] :as state}]
        (-> state
            (assoc :current-path (peek history))
            (update :history pop)
            (assoc :selection #{}))))))

(defn set-sort! [field]
  (state/update! !app
    (fn [state]
      (update state :sort
        (fn [{old-field :field old-order :order}]
          (if (= old-field field)
            {:field field :order (if (= old-order :asc) :desc :asc)}
            {:field field :order :asc}))))))

(defn toggle-selection! [path]
  (state/update! !app
    (fn [state]
      (update state :selection
        (fn [sel]
          (if (contains? sel path)
            (disj sel path)
            (conj sel path)))))))

(defn select-all! []
  (let [files (state/select !app :files)]
    (state/update! !app assoc :selection
      (set (map :path files)))))

(defn clear-selection! []
  (state/update! !app assoc :selection #{}))

;; ============================================================
;; Thumbnails
;; ============================================================

(def thumbnail-cache-dir
  (io/file (System/getProperty "java.io.tmpdir") "cuirq-thumbs"))

(defn thumbnail-path [original-path]
  (io/file thumbnail-cache-dir
           (str (Math/abs (hash original-path)) ".png")))

(defn image-file? [path]
  (some #(.endsWith (.toLowerCase path) %)
        [".jpg" ".jpeg" ".png" ".gif" ".webp" ".bmp"]))

(defn request-thumbnail! [path]
  (when (and (image-file? path)
             (not (contains? @!thumbnails path)))
    (state/update! !thumbnails assoc path {:status :loading})
    (r/async!
      (fn []
        (.mkdirs thumbnail-cache-dir)
        (let [thumb-file (thumbnail-path path)]
          ;; Real thumbnail generation would go here
          ;; (generate-thumbnail! path thumb-file)
          (str "file://" (.getAbsolutePath thumb-file))))
      (fn [uri]
        (state/update! !thumbnails assoc path {:status :ready :uri uri}))
      (fn [_error]
        (state/update! !thumbnails assoc path {:status :error})))))

(defn request-thumbnails! [files]
  (doseq [{:keys [path dir?]} files
          :when (and (not dir?) (image-file? path))]
    (request-thumbnail! path)))

;; ============================================================
;; Startup
;; ============================================================

(defn start! []
  ;; Bind view to Qt (reactive layer)
  (r/bind-qt! view-flow
    (fn [{:keys [dirs files current-path can-go-back? breadcrumbs]}]
      ;; Update QML models
      (qt/set-model-data "dirsModel" dirs)
      (qt/set-model-data "filesModel" files)
      (qt/set-context-property "currentPath" current-path)
      (qt/set-context-property "canGoBack" can-go-back?)
      (qt/set-context-property "breadcrumbs" breadcrumbs)
      ;; Request thumbnails for visible files
      (request-thumbnails! files)))

  ;; Register QML signal handlers
  (cuirq/on-signal! :navigate navigate!)
  (cuirq/on-signal! :goBack (fn [_] (go-back!)))
  (cuirq/on-signal! :setSort (fn [[field]] (set-sort! (keyword field))))
  (cuirq/on-signal! :toggleSelection toggle-selection!)
  (cuirq/on-signal! :selectAll (fn [_] (select-all!)))
  (cuirq/on-signal! :clearSelection (fn [_] (clear-selection!))))

(defn stop! []
  (r/unsubscribe-all!))
```

## Example: Offline-First App

```clojure
(ns myapp.offline
  (:require [cuirq.state :as state]
            [cuirq.state.reactive :as r]
            [missionary.core :as m]))

;; ============================================================
;; State - local/remote separation
;; ============================================================

(def !app
  (state/create-store
    {:local {:items {}     ; Local changes
             :pending []}  ; Sync queue
     :remote {:items {}    ; Server data
              :last-sync nil}
     :sync {:status :idle  ; :idle, :syncing, :error
            :error nil}}))

;; ============================================================
;; Derived - data merging
;; ============================================================

(def local-items-flow
  (r/derive !app #(get-in % [:local :items])))

(def remote-items-flow
  (r/derive !app #(get-in % [:remote :items])))

;; Merge: local data takes priority
(def merged-items-flow
  (m/latest
    (fn [local remote]
      (merge remote local)) ; local overwrites remote
    local-items-flow
    remote-items-flow))

(def pending-flow
  (r/derive !app #(get-in % [:local :pending])))

(def sync-status-flow
  (r/derive !app #(get-in % [:sync :status])))

;; View
(def view-flow
  (m/latest
    (fn [items pending status]
      {:items (vals items)
       :has-pending? (boolean (seq pending))
       :pending-count (count pending)
       :sync-status status})
    merged-items-flow
    pending-flow
    sync-status-flow))

;; ============================================================
;; Actions
;; ============================================================

(defn add-item! [item]
  (let [id (or (:id item) (random-uuid))
        item-with-id (assoc item :id id :_local true)]
    (state/update! !app
      (fn [state]
        (-> state
            (assoc-in [:local :items id] item-with-id)
            (update-in [:local :pending] conj {:op :create :item item-with-id}))))))

(defn update-item! [id updates]
  (state/update! !app
    (fn [state]
      (-> state
          (update-in [:local :items id] merge updates)
          (update-in [:local :pending] conj {:op :update :id id :updates updates})))))

(defn delete-item! [id]
  (state/update! !app
    (fn [state]
      (-> state
          (update-in [:local :items] dissoc id)
          (update-in [:local :pending] conj {:op :delete :id id})))))

;; ============================================================
;; Sync
;; ============================================================

(defn sync-to-server! []
  (r/go
    (state/update! !app assoc-in [:sync :status] :syncing)
    (try
      (let [pending (get-in @!app [:local :pending])]
        (doseq [op pending]
          (m/? (m/via m/blk
                 (case (:op op)
                   :create (api/create-item (:item op))
                   :update (api/update-item (:id op) (:updates op))
                   :delete (api/delete-item (:id op))))))
        ;; Successfully synced
        (state/update! !app
          (fn [state]
            (-> state
                (assoc-in [:local :pending] [])
                (assoc-in [:sync :status] :idle)
                (assoc-in [:sync :error] nil)))))
      (catch Exception e
        (state/update! !app
          (fn [state]
            (-> state
                (assoc-in [:sync :status] :error)
                (assoc-in [:sync :error] (.getMessage e)))))))))

(defn fetch-from-server! []
  (r/go
    (try
      (let [items (m/? (m/via m/blk (api/get-items)))]
        (state/update! !app
          (fn [state]
            (-> state
                (assoc-in [:remote :items] (into {} (map (juxt :id identity) items)))
                (assoc-in [:remote :last-sync] (System/currentTimeMillis))))))
      (catch Exception e
        (println "Fetch error:" e)))))
```

## Consequences

### Positive

1. **Modularity** - base layer works without dependencies, reactive is optional
2. **Simplicity** - state is just atoms, actions are just functions
3. **Reactivity** - missionary flows auto-recompute (in reactive layer)
4. **Efficiency** - caching, laziness, virtual threads
5. **Composition** - flows and transducers combine easily
6. **Cancellation** - all operations can be cancelled
7. **Testability** - pure functions, deterministic state
8. **Flexibility** - simple apps use only cuirq.state, complex apps add cuirq.state.reactive

### Negative

1. **Learning curve** - missionary is less known than core.async
2. **Debugging** - reactive flows are harder to debug than imperative code
3. **Two APIs** - need to understand when to use which layer

### Mitigation

1. Good documentation with examples for both layers
2. Logging middleware for reactive layer debugging
3. missionary is actively developed and well-supported
4. Clear guidelines on when to use which layer

## References

- [Missionary Documentation](https://github.com/leonoel/missionary)
- [Re-frame Concepts](https://day8.github.io/re-frame/re-frame/)
- [Java Virtual Threads](https://openjdk.org/jeps/444)
- [cljfx Discussion](https://github.com/cljfx/cljfx/issues/33)
