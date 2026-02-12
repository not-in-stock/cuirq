# ADR-001: Declarative State Management

## Status
Accepted (amended)

## Context

cuirq is a framework for building desktop applications in Clojure with Qt/QML UI. We need a state management system that is:

1. **Lightweight** - without re-frame overhead (registries, interceptors, keyword-based dispatch)
2. **Reactive** - automatic UI updates when data changes
3. **Multi-layered** - raw data -> derived -> QML-ready, with automatic propagation
4. **I/O-friendly** - async operations on virtual threads without callback hell
5. **Multi-window ready** - global vs per-window state decomposition (see ADR-007)
6. **Performance-first** - transducers for single-pass transforms, diffing before QML push

### Current Problems

The file manager works but has ~70% imperative glue code:

- **14 manual `state/update-state!` / `state/set-state!` calls** — each navigation function manually pushes `currentPath`, `canGoBack`, `canGoForward`, `breadcrumbs`, `itemCount` to QML
- **84 lines duplicated** across `navigate-to!`, `go-back!`, `go-forward!` — identical state update blocks, model pushes, view-mode branching, directory watch setup
- **6 manual `models/set-data!` calls** — grid/list and miller columns each push models separately
- **2 dedup atoms** (`last-listing`, `refreshing?`) — manual deduplication instead of flow-based
- **Inconsistent state push**: miller columns uses `update-state!` (incremental), grid/list uses `set-state!` (full replace)

### Alternatives Considered

| Solution | Pros | Cons |
|----------|------|------|
| **re-frame** | Mature, multi-level subscriptions | Heavy registries, ClojureScript-oriented, keyword dispatch overhead |
| **missionary** | Reactive flows, function composition, Virtual Threads, cancellation | Less known, requires learning |
| **core.async** | Well-known CSP model | Different concurrency model, no built-in reactivity |
| **atom + watcher** | Zero deps, simple | No derived values, no backpressure, manual everything |

## Decision

Two-layer architecture with missionary for reactive composition:

1. **cuirq.state** — base layer on atoms, works standalone for simple apps
2. **cuirq.state.reactive** — optional missionary layer for derived flows, auto-sync, effects

Key principles:
- **No registries** — "subscriptions" are just `m/latest` compositions, plain functions
- **Transducers first** — single-pass transforms everywhere (file listing, model sync, miller columns)
- **Multi-window native** — single atom with global/per-window decomposition
- **Pluggable native utilities** — C++ plugins for hot-path I/O (FSEvents, batch stat)

### Architecture

```
+------------------------------------------------------+
|  App Code (file-manager, counter, etc.)              |
|  - Pure update functions: signal -> state transition |
|  - Transducer pipelines for transforms               |
+------------------------------------------------------+
               | uses
+--------------v---------------------------------------+
|  cuirq.state.reactive (optional missionary layer)    |
|  - m/watch atom -> state-flow                        |
|  - m/latest for derived flows (scoped by window-id)  |
|  - Auto-diff + push to QML (state props + models)    |
|  - Effects via m/observe (native plugin signals)     |
|  - Transducer support in derive/sync                 |
+--------------+---------------------------------------+
               | uses
+--------------v---------------------------------------+
|  cuirq.state (base layer, zero deps)                 |
|  - atom {:global {...} :windows {id {...}}}           |
|  - get/set/update + watches                          |
|  - Works standalone for simple apps                  |
+--------------+---------------------------------------+
               | signals from
+--------------v---------------------------------------+
|  Native Plugins (C++ via Panama FFM)                 |
|  - DirectoryWatcher (FSEvents) -- exists             |
|  - Future: batch stat, thumbnails, theme observer    |
+------------------------------------------------------+
```

### Usage

```clojure
;; Simple application — base layer only
(ns counter.core
  (:require [cuirq.state :as state]))

(def *app (state/create-store {:count 0}))
(state/watch! *app :qt #(qt/set-property "count" (:count %)))
(state/update! *app update :count inc)

;; Complex application — add reactive layer
(ns complex-app.core
  (:require [cuirq.state :as state]
            [cuirq.state.reactive :as r]
            [missionary.core :as m]))

(def *app (state/create-store {:items [] :filter :all}))

;; Derived flow — just m/latest, no registry
(def filtered-items
  (m/latest
    (fn [{:keys [items filter]}]
      (into [] (r/filter-xf filter) items))
    (m/watch *app)))

;; Auto-sync to QML — replaces manual state pushes
(r/sync-state! {:itemCount (m/latest count filtered-items)})
(r/sync-model! :items filtered-items)
```

## Implementation

### 1. Base Layer: cuirq.state

Base layer without external dependencies. Sufficient for simple applications.

```clojure
(ns cuirq.state)

(defn create-store
  "Creates a state store with optional multi-window structure.

   Simple:  (create-store {:count 0})
   Multi:   (create-store {:global {:theme :dark}
                           :windows {}})"
  [initial-state]
  (atom initial-state))

(defn get-state [store] @store)

(defn update!
  "Updates state with a function.
   (update! *store assoc :loading true)
   (update! *store update :count inc)"
  [store f & args]
  (apply swap! store f args))

(defn set! [store new-state]
  (reset! store new-state))

(defn update-in!
  "Updates value at path.
   (update-in! *store [:windows win-id :path] (constantly new-path))"
  [store path f & args]
  (apply swap! store update-in path f args))

;; Watches for Qt binding
(defn watch!
  "Adds a watch. Returns a cancel function."
  [store key callback]
  (add-watch store key (fn [_ _ _ new-val] (callback new-val)))
  #(remove-watch store key))

(defn unwatch! [store key]
  (remove-watch store key))

;; Selectors (simple, no caching)
(defn select
  "Extracts value from state.
   (select *app :count)
   (select *app [:user :name])
   (select *app #(filter :active (:items %)))"
  [store selector]
  (let [state @store]
    (cond
      (keyword? selector) (get state selector)
      (vector? selector)  (get-in state selector)
      (fn? selector)      (selector state)
      :else               state)))
```

### 2. Multi-Window State

Single atom with global/per-window decomposition. Cross-window ops (drag-and-drop) are atomic `swap!` on shared atom.

```clojure
;; State shape
{:global {:theme :dark
          :favorites ["~/Documents" "~/Downloads"]}
 :windows {"win-0" {:path "/Users/me/Documents"
                     :history {:back [] :forward []}
                     :sort {:field :name :order :asc}
                     :view-mode "list"
                     :selection #{}}
           "win-1" {:path "/Users/me/Downloads"
                     :history {:back [] :forward []}
                     :sort {:field :modified :order :desc}
                     :view-mode "grid"
                     :selection #{}}}}

;; Window-scoped flow — recalculates only when this window's slice changes
(defn window-flow [win-id key]
  (m/latest #(get-in % [:windows win-id key]) (m/watch *app)))

;; Global flow
(defn global-flow [key]
  (m/latest #(get-in % [:global key]) (m/watch *app)))

;; Pure navigation — one function, not three
(defn navigate [state win-id path]
  (let [current (get-in state [:windows win-id :path])]
    (-> state
        (update-in [:windows win-id :history :back] conj current)
        (assoc-in  [:windows win-id :history :forward] [])
        (assoc-in  [:windows win-id :path] path)
        (assoc-in  [:windows win-id :selection] #{}))))

(defn go-back [state win-id]
  (let [win    (get-in state [:windows win-id])
        prev   (peek (get-in win [:history :back]))]
    (when prev
      (-> state
          (update-in [:windows win-id :history :back] pop)
          (update-in [:windows win-id :history :forward] conj (:path win))
          (assoc-in  [:windows win-id :path] prev)
          (assoc-in  [:windows win-id :selection] #{})))))

(defn go-forward [state win-id]
  (let [win    (get-in state [:windows win-id])
        next-p (peek (get-in win [:history :forward]))]
    (when next-p
      (-> state
          (update-in [:windows win-id :history :forward] pop)
          (update-in [:windows win-id :history :back] conj (:path win))
          (assoc-in  [:windows win-id :path] next-p)
          (assoc-in  [:windows win-id :selection] #{})))))
```

### 3. Reactive Layer: cuirq.state.reactive

Optional missionary layer. No registries — flows are plain functions composed with `m/latest`.

```clojure
(ns cuirq.state.reactive
  (:require [missionary.core :as m]
            [cuirq.state :as state]))

;; ============================================================
;; Derived Flows
;; ============================================================

(defn derive
  "Creates a derived flow from store.
   (derive *store :items)
   (derive *store :items (filter :active))
   (derive *store :items (comp (filter :active) (take 10)))"
  ([store selector]
   (let [f (if (keyword? selector) selector selector)]
     (m/latest f (m/watch store))))
  ([store selector xf]
   (let [f (if (keyword? selector) selector selector)]
     (m/latest #(into [] xf (f %)) (m/watch store)))))

(defn derive-from
  "Derived flow from multiple sources.
   (derive-from [items-flow filter-flow]
     (fn [items flt] (filter #(= (:status %) flt) items)))"
  [flows combine-fn]
  (apply m/latest combine-fn flows))

;; ============================================================
;; Subscriptions (no registry — just cancel functions)
;; ============================================================

(defn subscribe!
  "Subscribes to a flow. Returns a cancel function."
  [flow callback]
  (let [task (m/reduce (fn [_ v] (callback v) nil) nil flow)]
    (task (fn [_]) (fn [e] (println "Subscription error:" e)))))

;; ============================================================
;; QML Sync — replaces manual state/model pushes
;; ============================================================

(defn sync-state!
  "Binds a map of {qml-prop-name flow} to QML state properties.
   Auto-diffs: only pushes changed properties.
   Returns a cancel function.

   (sync-state! win-id
     {:currentPath path-flow
      :canGoBack   can-go-back-flow
      :itemCount   item-count-flow})"
  [win-id prop-flow-map]
  (let [combined (apply m/latest
                   (fn [& vals]
                     (zipmap (keys prop-flow-map) vals))
                   (vals prop-flow-map))
        prev (atom {})]
    (subscribe! combined
      (fn [new-map]
        (let [old @prev
              changed (into {}
                       (remove (fn [[k v]] (= v (get old k))))
                       new-map)]
          (reset! prev new-map)
          (when (seq changed)
            ;; push only changed props to Qt thread
            (send-to-qt-thread!
              #(doseq [[k v] changed]
                 (qt/set-context-property (name k) v)))))))))

(defn sync-model!
  "Binds a flow to a QML ListModel. Applies optional transducer.
   Returns a cancel function.

   (sync-model! :files files-flow)
   (sync-model! :files files-flow (map #(select-keys % [:name :path :size])))"
  ([model-key flow]
   (subscribe! flow
     (fn [items]
       (send-to-qt-thread!
         #(qt/set-model-data (name model-key) items)))))
  ([model-key flow xf]
   (subscribe! (m/latest #(into [] xf %) flow)
     (fn [items]
       (send-to-qt-thread!
         #(qt/set-model-data (name model-key) items))))))

;; ============================================================
;; Async Effects
;; ============================================================

(defn async!
  "Executes async operation on virtual thread. Returns cancel fn."
  [operation on-success on-error]
  (let [task (m/sp
               (try
                 (let [result (m/? (m/via m/blk (operation)))]
                   (on-success result))
                 (catch Exception e
                   (on-error e))))]
    (task (fn [_]) (fn [e] (println "Async task error:" e)))))

(defmacro go
  "Sequential async operations on virtual threads. Returns cancel fn.
   (go
     (let [user (m/? (fetch-user id))
           items (m/? (fetch-items (:id user)))]
       (state/update! *store assoc :user user :items items)))"
  [& body]
  `(let [task# (m/sp ~@body)]
     (task# (fn [_#]) (fn [e#] (println "async error:" e#)))))
```

### 4. Transducers

First-class, not afterthought. Reusable pipelines applied at every stage.

```clojure
;; Reusable file transform pipelines
(def visible-files-xf
  "Removes hidden files and enriches metadata in a single pass."
  (comp
    (remove :hidden?)
    (map (fn [f] (assoc f :display-size (format-size (:size f)))))))

(def grid-view-xf
  "Compact payload for grid delegates — fewer properties = faster QML binding."
  (comp
    visible-files-xf
    (map #(select-keys % [:name :path :dir? :display-size :icon]))))

(def miller-column-xf
  "Minimal payload for miller column delegates."
  (comp
    visible-files-xf
    (map #(select-keys % [:name :path :dir?]))))

;; Usage in flows
(def files-flow
  (m/latest
    (fn [path sort-state]
      (into [] visible-files-xf
        (sort-by (sort-fn sort-state) (list-dir path))))
    (window-flow win-id :path)
    (window-flow win-id :sort)))

;; Same pipeline works for sync
(sync-model! :files files-flow grid-view-xf)

;; Same pipeline works for one-off computations
(into [] grid-view-xf (list-dir "/tmp"))
```

### 5. Pluggable Native Utilities

Generalize the existing DirectoryWatcher pattern into a plugin architecture for hot-path I/O that's too slow in JVM.

```clojure
;; Current pattern (DirectoryWatcher, already exists):
;; C++ FSEvents -> SignalForwarder -> Clojure handler -> swap! state

;; Generalized: native plugin emits signals, feeds into missionary flows
(defn native-signal-flow
  "Creates a missionary flow from a native C++ signal.
   (native-signal-flow :directory-changed)"
  [signal-key]
  (m/observe
    (fn [emit!]
      (let [handler (fn [data] (emit! data))]
        (cuirq/on-signal! signal-key handler)
        #(cuirq/remove-signal-handler! signal-key handler)))))

;; Files re-read when directory changes (native FSEvents)
(def dir-changed-flow (native-signal-flow :directory-changed))

(def files-flow
  (m/latest
    (fn [path sort-state _trigger]
      (into [] visible-files-xf
        (sort-by (sort-fn sort-state) (list-dir path))))
    (window-flow win-id :path)
    (window-flow win-id :sort)
    (m/relieve {} dir-changed-flow)))

;; Future native plugins (same pattern):
;; - Batch file metadata (stat syscall batching)
;; - Thumbnail generation (libvips/CoreGraphics)
;; - System accent color observer (NSApp.effectiveAppearance KVO)
```

## File Manager Refactoring Blueprint

Concrete before/after showing how the declarative layer eliminates imperative glue.

### Before (current — imperative)

```clojure
;; 3 functions x ~30 lines each, nearly identical
;; navigate-to!, go-back!, go-forward! all contain:

(defn navigate-to! [path]
  ;; 1. History manipulation
  (swap! nav-history (fn [h]
                       (-> h
                           (update :back conj current-path)
                           (assoc :forward []))))
  ;; 2. View-mode branching (duplicated in all 3 functions)
  (if (= @view-mode "columns")
    (do
      (dirs/invalidate-all!)
      (miller-navigate-to! path)
      ;; 3. Manual state push (same 5 properties in all 3 functions)
      (state/update-state! assoc
                           :currentPath path
                           :canGoBack (boolean (seq (:back @nav-history)))
                           :canGoForward (boolean (seq (:forward @nav-history)))
                           :breadcrumbs (json/write-str (build-breadcrumbs path))
                           :itemCount (count (dirs/list-dir! path))))
    (do
      (tree/collapse-all!)
      (dirs/invalidate-all!)
      ;; 4. Manual model push
      (let [items (tree/build-flat-list path @sort-state)]
        (reset! last-listing items)
        (models/set-data! :files items)
        ;; 5. Manual state push (same properties, different API)
        (state/set-state!
         {:currentPath  path
          :canGoBack    (boolean (seq (:back @nav-history)))
          :canGoForward (boolean (seq (:forward @nav-history)))
          :itemCount    (count items)
          :breadcrumbs  (json/write-str (build-breadcrumbs path))})
        ;; 6. Manual watch setup
        (let [paths (dirs/active-paths)]
          (if (seq paths)
            (cuirq/watch-directories! paths)
            (cuirq/start-directory-watch! path)))))))
```

### After (declarative with missionary)

```clojure
;; Pure state transitions — one function replaces three
(defn navigate [state win-id path]
  (-> state
      (update-in [:windows win-id :history :back] conj (get-in state [:windows win-id :path]))
      (assoc-in  [:windows win-id :history :forward] [])
      (assoc-in  [:windows win-id :path] path)
      (assoc-in  [:windows win-id :selection] #{})))

;; Signal handlers — just swap!, no manual pushes
(cuirq/on-signal! :navigate  #(state/update! *app navigate win-id %))
(cuirq/on-signal! :goBack    #(state/update! *app go-back win-id))
(cuirq/on-signal! :goForward #(state/update! *app go-forward win-id))

;; Derived flows — auto-recomputed on state change
(def path-flow       (window-flow win-id :path))
(def history-flow    (window-flow win-id :history))
(def sort-flow       (window-flow win-id :sort))
(def can-go-back-flow    (m/latest #(boolean (seq (:back %))) history-flow))
(def can-go-forward-flow (m/latest #(boolean (seq (:forward %))) history-flow))
(def breadcrumbs-flow    (m/latest build-breadcrumbs path-flow))
(def files-flow
  (m/latest
    (fn [path sort-state _fs-event]
      (into [] visible-files-xf
        (sort-by (sort-fn sort-state) (list-dir path))))
    path-flow sort-flow dir-changed-flow))
(def item-count-flow (m/latest count files-flow))

;; Auto-sync to QML — replaces 14 manual state pushes
(sync-state! win-id
  {:currentPath  path-flow
   :canGoBack    can-go-back-flow
   :canGoForward can-go-forward-flow
   :breadcrumbs  breadcrumbs-flow
   :itemCount    item-count-flow})

(sync-model! :files files-flow grid-view-xf)
```

**What's eliminated:**
- 3 near-identical 30-line functions -> 3 pure 5-line functions
- 14 manual state pushes -> 1 `sync-state!` declaration
- 6 manual model pushes -> 1 `sync-model!` declaration
- 2 dedup atoms -> flow deduplication is automatic
- View-mode branching in nav -> transducer selection at sync level
- Manual directory watch setup -> native signal flow composition

## Consequences

### Positive

1. **Modularity** — base layer works without dependencies, reactive is optional
2. **No registries** — flows are functions, composed with `m/latest`, no keyword dispatch
3. **Multi-window native** — `window-flow` scopes derived data per window, cross-window ops atomic
4. **Transducer performance** — single-pass transforms, reusable across flows and one-off ops
5. **Native plugin extensibility** — hot-path I/O in C++, signals feed into missionary flows
6. **Drastic glue reduction** — file manager refactoring eliminates ~70% of imperative navigation code
7. **Auto-diff sync** — only changed properties pushed to QML, no manual dedup
8. **Cancellation** — all flows and effects cancellable
9. **Testability** — pure state transition functions, deterministic

### Negative

1. **Learning curve** — missionary is less known than core.async (mitigated: simple base layer works standalone)
2. **Debugging** — reactive flows harder to trace than imperative code (mitigated: logging middleware)
3. **Two APIs** — need to understand when to use which layer (guideline: base for simple apps, reactive when you have derived values or need auto-sync)

## References

- [Missionary Documentation](https://github.com/leonoel/missionary)
- [Java Virtual Threads (JEP 444)](https://openjdk.org/jeps/444)
- ADR-006: Hot Reload Improvements (proxy window, engine-per-reload)
- ADR-007: Multi-Window Support (engine-per-window, WindowManager)
