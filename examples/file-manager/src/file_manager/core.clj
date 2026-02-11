(ns file-manager.core
  (:require [cuirq.core :as cuirq]
            [cuirq.state :as state]
            [cuirq.models :as models]
            [file-manager.dirs :as dirs]
            [file-manager.tree :as tree]
            [clojure.data.json :as json])
  (:import [java.io File])
  (:gen-class))

;; Navigation history
(defonce nav-history (atom {:back [] :forward []}))

;; Cache last flat listing to avoid redundant updates from FSEvents
(defonce ^:private last-listing (atom nil))

;; Sort state — persists across navigation
(defonce ^:private sort-state (atom {:field "name" :ascending true}))

;; Current view mode: "grid", "list", or "columns"
(defonce ^:private view-mode (atom "grid"))

;; Miller columns pool size
(def ^:private miller-pool-size 16)

;; Miller columns state:
;; {:columns [{:path "/..." :name "dirname" :selected-index -1} ...]
;;  :active-count N}
(defonce ^:private miller-state (atom {:columns [] :active-count 0}))

;; Cache last data set on each miller model to avoid redundant updates
(defonce ^:private last-miller-data (atom {}))

(defn- refresh-file-list!
  "Rebuild the flat tree and push to model. Updates watcher paths."
  []
  (let [current-path (:currentPath (state/get-state))
        items (tree/build-flat-list current-path @sort-state)
        ;; Visible dirs = root + every expanded dir in the flat list
        visible-dirs (into #{current-path}
                           (comp (filter :expanded) (map :path))
                           items)]
    (when (not= items @last-listing)
      (reset! last-listing items)
      (models/update-data! :files items "path")
      (state/update-state! assoc :itemCount (count items)))
    ;; Prune cache and watcher to only visible directories
    (dirs/retain-paths! visible-dirs)
    (let [paths (dirs/active-paths)]
      (if (seq paths)
        (cuirq/watch-directories! paths)
        (cuirq/stop-directory-watch!)))))

(defn- path->chain
  "Build a chain of directory paths from / to the given path.
   E.g. '/Users/foo/bar' → ['/' '/Users' '/Users/foo' '/Users/foo/bar']"
  [^String path]
  (let [parts (->> (.split path (File/separator))
                   (remove empty?))]
    (loop [remaining parts
           acc-path ""
           result ["/"]]
      (if (empty? remaining)
        result
        (let [part (first remaining)
              new-path (str acc-path "/" part)]
          (recur (rest remaining)
                 new-path
                 (conj result new-path)))))))

(defn- miller-model-key
  "Return the keyword for miller column model at index i."
  [i]
  (keyword (str "mc" i)))

(defn- build-breadcrumbs
  [^String path]
  (let [parts (->> (.split path (File/separator))
                   (remove empty?))]
    (loop [remaining parts
           acc-path ""
           result [{:name "/" :path "/"}]]
      (if (empty? remaining)
        result
        (let [part (first remaining)
              new-path (str acc-path "/" part)]
          (recur (rest remaining)
                 new-path
                 (conj result {:name part :path new-path})))))))

(defn- push-miller-state!
  "Push miller columns metadata to QML state."
  [{:keys [columns active-count]}]
  (let [cols-json (json/write-str
                   (mapv (fn [col]
                           {:name (:name col)
                            :path (:path col)
                            :selectedPath (or (:selected-path col) "")})
                         columns))]
    (state/update-state! assoc
                         :millerActiveCount active-count
                         :millerColumns cols-json)))

(defn- populate-miller-model!
  "Fill miller column model at index i with directory contents.
   Skips update if data hasn't changed (dedup)."
  [i ^String path]
  (let [items (dirs/list-dir! path)]
    (when (not= items (get @last-miller-data i))
      (swap! last-miller-data assoc i items)
      (models/update-data! (miller-model-key i) items "path"))))

(defn- clear-miller-model!
  "Reset dedup cache for miller column model at index i.
   Does NOT clear the model data — remove transitions need old content for fade-out."
  [i]
  (swap! last-miller-data dissoc i))

(defn miller-navigate-to!
  "Navigate to a path in Miller columns mode.
   Builds the full path chain and populates column models.
   Expects a canonical path."
  [^String path]
  (let [dir (File. path)]
    (when (.isDirectory dir)
      (let [chain (path->chain path)
            ;; If chain > pool-size, use sliding window (last N)
            window (if (> (count chain) miller-pool-size)
                     (vec (take-last miller-pool-size chain))
                     chain)
            active-count (count window)
            columns (mapv (fn [p]
                            {:path p
                             :name (let [f (File. ^String p)]
                                     (if (= p "/") "/" (.getName f)))
                             :selected-index -1})
                          window)]
        ;; Set selected-index for each column (which child leads to next column)
        (let [columns-with-sel
              (vec (map-indexed
                    (fn [i col]
                      (if (< (inc i) active-count)
                        ;; Find index of next column's path in this column's listing
                        (let [next-path (:path (nth columns (inc i)))
                              items (dirs/list-dir! (:path col))
                              idx (or (first (keep-indexed
                                              (fn [j item]
                                                (when (= (:path item) next-path) j))
                                              items))
                                      -1)]
                          (assoc col :selected-index idx :selected-path next-path))
                        col))
                    columns))]
          ;; Populate models
          (doseq [i (range active-count)]
            (populate-miller-model! i (:path (nth columns-with-sel i))))
          ;; Clear unused models
          (doseq [i (range active-count miller-pool-size)]
            (clear-miller-model! i))
          ;; Update state
          (let [new-state {:columns columns-with-sel :active-count active-count}]
            (reset! miller-state new-state)
            (push-miller-state! new-state))
          ;; Update currentPath & breadcrumbs to the navigated path
          (state/update-state! assoc
                               :currentPath path
                               :breadcrumbs (json/write-str (build-breadcrumbs path))
                               :itemCount (count (dirs/list-dir! path)))
          ;; Watch visible directories
          (let [visible-dirs (set (map :path columns-with-sel))
                paths (dirs/active-paths)
                all-paths (into visible-dirs paths)]
            (dirs/retain-paths! visible-dirs)
            (if (seq visible-dirs)
              (cuirq/watch-directories! (vec visible-dirs))
              (cuirq/stop-directory-watch!))))))))

(defn- miller-select!
  "Handle selection in Miller columns.
   col-idx: which column was clicked
   item-index: which item in that column"
  [col-idx item-index]
  (let [{:keys [columns active-count]} @miller-state
        col (nth columns col-idx)
        items (dirs/list-dir! (:path col))
        item (nth items item-index nil)]
    (when item
      (if (:isDir item)
        ;; Directory: open next column, clear columns beyond
        (let [next-col-idx (inc col-idx)
              item-path (:path item)]
          (if (>= next-col-idx miller-pool-size)
            ;; Pool exhausted — slide window via full navigate
            (miller-navigate-to! item-path)
            ;; Room in pool — populate in place
            (let [new-active (inc next-col-idx)]
              ;; Populate next column
              (populate-miller-model! next-col-idx item-path)
              ;; Clear columns beyond
              (doseq [i (range new-active miller-pool-size)]
                (clear-miller-model! i))
              ;; Update miller state
              (let [;; Keep columns up to col-idx, update selected-index
                    kept (subvec columns 0 (inc col-idx))
                    kept (-> kept
                             (assoc-in [col-idx :selected-index] item-index)
                             (assoc-in [col-idx :selected-path] item-path))
                    ;; Add new column
                    new-col {:path item-path
                             :name (.getName (File. ^String item-path))
                             :selected-index -1
                             :selected-path ""}
                    new-columns (conj kept new-col)
                    new-state {:columns new-columns :active-count new-active}]
                (reset! miller-state new-state)
                (push-miller-state! new-state)
                ;; Update currentPath & breadcrumbs to the deepest directory
                (state/update-state! assoc
                                     :currentPath item-path
                                     :breadcrumbs (json/write-str (build-breadcrumbs item-path))
                                     :itemCount (count (dirs/list-dir! item-path)))
                ;; Update watcher
                (let [visible-dirs (set (map :path new-columns))]
                  (dirs/retain-paths! visible-dirs)
                  (cuirq/watch-directories! (vec visible-dirs)))))))
        ;; File: just update selection, clear columns right of current
        (let [new-active (inc col-idx)]
          (doseq [i (range new-active miller-pool-size)]
            (clear-miller-model! i))
          (let [kept (subvec columns 0 (inc col-idx))
                kept (-> kept
                         (assoc-in [col-idx :selected-index] item-index)
                         (assoc-in [col-idx :selected-path] (:path item)))
                new-state {:columns kept :active-count new-active}]
            (reset! miller-state new-state)
            (push-miller-state! new-state)))))))

(defn- refresh-miller-column!
  "Re-read a specific miller column whose directory changed.
   The path should already be invalidated in the cache."
  [changed-path]
  (let [{:keys [columns active-count]} @miller-state]
    (doseq [i (range active-count)]
      (let [col (nth columns i)]
        (when (= (:path col) changed-path)
          (populate-miller-model! i changed-path))))))

(defn navigate-to!
  "Navigate to a directory path."
  [^String path]
  (let [dir (File. path)]
    (when (.isDirectory dir)
      (let [canonical (.getCanonicalPath dir)
            current-path (:currentPath (state/get-state))]
        ;; Push current path to back stack
        (when (and current-path (not= current-path canonical))
          (swap! nav-history (fn [h]
                               (-> h
                                   (update :back conj current-path)
                                   (assoc :forward [])))))
        (if (= @view-mode "columns")
          ;; Miller columns mode
          (do
            (dirs/invalidate-all!)
            (miller-navigate-to! canonical)
            (state/update-state! assoc
                                 :currentPath canonical
                                 :canGoBack (boolean (seq (:back @nav-history)))
                                 :canGoForward (boolean (seq (:forward @nav-history)))
                                 :breadcrumbs (json/write-str (build-breadcrumbs canonical))
                                 :itemCount (count (dirs/list-dir! canonical))))
          ;; Grid/list mode
          (do
            (tree/collapse-all!)
            (dirs/invalidate-all!)
            (let [items (tree/build-flat-list canonical @sort-state)]
              (reset! last-listing items)
              (models/set-data! :files items)
              (state/set-state!
               {:currentPath  canonical
                :canGoBack    (boolean (seq (:back @nav-history)))
                :canGoForward (boolean (seq (:forward @nav-history)))
                :itemCount    (count items)
                :breadcrumbs  (json/write-str (build-breadcrumbs canonical))})
              (let [paths (dirs/active-paths)]
                (if (seq paths)
                  (cuirq/watch-directories! paths)
                  (cuirq/start-directory-watch! canonical))))))))))

(defn go-back!
  []
  (let [{:keys [back]} @nav-history]
    (when (seq back)
      (let [prev (peek back)
            current (:currentPath (state/get-state))]
        (swap! nav-history (fn [h]
                             (-> h
                                 (update :back pop)
                                 (update :forward conj current))))
        (dirs/invalidate-all!)
        (if (= @view-mode "columns")
          (do
            (miller-navigate-to! prev)
            (state/update-state! assoc
                                 :currentPath prev
                                 :canGoBack (boolean (seq (:back @nav-history)))
                                 :canGoForward (boolean (seq (:forward @nav-history)))
                                 :breadcrumbs (json/write-str (build-breadcrumbs prev))
                                 :itemCount (count (dirs/list-dir! prev))))
          (do
            (tree/collapse-all!)
            (let [items (tree/build-flat-list prev @sort-state)]
              (reset! last-listing items)
              (models/set-data! :files items)
              (state/set-state!
               {:currentPath  prev
                :canGoBack    (boolean (seq (:back @nav-history)))
                :canGoForward (boolean (seq (:forward @nav-history)))
                :itemCount    (count items)
                :breadcrumbs  (json/write-str (build-breadcrumbs prev))})
              (let [paths (dirs/active-paths)]
                (if (seq paths)
                  (cuirq/watch-directories! paths)
                  (cuirq/start-directory-watch! prev))))))))))

(defn go-forward!
  []
  (let [{:keys [forward]} @nav-history]
    (when (seq forward)
      (let [next-path (peek forward)
            current (:currentPath (state/get-state))]
        (swap! nav-history (fn [h]
                             (-> h
                                 (update :forward pop)
                                 (update :back conj current))))
        (dirs/invalidate-all!)
        (if (= @view-mode "columns")
          (do
            (miller-navigate-to! next-path)
            (state/update-state! assoc
                                 :currentPath next-path
                                 :canGoBack (boolean (seq (:back @nav-history)))
                                 :canGoForward (boolean (seq (:forward @nav-history)))
                                 :breadcrumbs (json/write-str (build-breadcrumbs next-path))
                                 :itemCount (count (dirs/list-dir! next-path))))
          (do
            (tree/collapse-all!)
            (let [items (tree/build-flat-list next-path @sort-state)]
              (reset! last-listing items)
              (models/set-data! :files items)
              (state/set-state!
               {:currentPath  next-path
                :canGoBack    (boolean (seq (:back @nav-history)))
                :canGoForward (boolean (seq (:forward @nav-history)))
                :itemCount    (count items)
                :breadcrumbs  (json/write-str (build-breadcrumbs next-path))})
              (let [paths (dirs/active-paths)]
                (if (seq paths)
                  (cuirq/watch-directories! paths)
                  (cuirq/start-directory-watch! next-path))))))))))

(defn- resolve-sidebar-location
  [^String key]
  (let [home (System/getProperty "user.home")]
    (case key
      "home"      home
      "desktop"   (str home "/Desktop")
      "documents" (str home "/Documents")
      "downloads" (str home "/Downloads")
      "pictures"  (str home "/Pictures")
      "music"     (str home "/Music")
      home)))

(defn -main [& _args]
  (println "\n========================================")
  (println "cuirq File Manager")
  (println "========================================\n")

  (try
    (cuirq/with-qt ["-platform" "cocoa"]
        ;; Create files model + miller column pool
        (println " [1/4] Creating models...")
        (models/create-model! :files)
        (doseq [i (range miller-pool-size)]
          (models/create-model! (miller-model-key i)))

        ;; Initialize state
        (println " [2/4] Initializing state...")
        (state/set-state! {:currentPath ""
                           :canGoBack "false"
                           :canGoForward "false"
                           :itemCount 0
                           :breadcrumbs "[]"
                           :viewMode "grid"
                           :millerActiveCount 0
                           :millerColumns "[]"})

        ;; Register signal handlers
        (println " [3/4] Registering signal handlers...")
        (cuirq/on-signal! :navigate
                          (fn [_ json-args]
                            (let [args (json/read-str json-args)]
                              (navigate-to! (first args)))))

        (cuirq/on-signal! :goBack
                          (fn [_ _] (go-back!)))

        (cuirq/on-signal! :goForward
                          (fn [_ _] (go-forward!)))

        (cuirq/on-signal! :sidebarNavigate
                          (fn [_ json-args]
                            (let [args (json/read-str json-args)
                                  path (resolve-sidebar-location (first args))]
                              (navigate-to! path))))

        (cuirq/on-signal! :toggleExpand
                          (fn [_ json-args]
                            (let [args (json/read-str json-args)
                                  path (first args)]
                              (tree/toggle! path)
                              ;; Invalidate cache for the toggled dir so it's re-read
                              (when (tree/expanded? path)
                                (dirs/invalidate! path))
                              (refresh-file-list!))))

        (cuirq/on-signal! :directoryChanged
                          (fn [_ json-args]
                            (let [args (json/read-str json-args)
                                  changed-path (first args)]
                              (dirs/invalidate! changed-path)
                              (if (= @view-mode "columns")
                                (refresh-miller-column! changed-path)
                                (refresh-file-list!)))))

        (cuirq/on-signal! :millerSelect
                          (fn [_ json-args]
                            (let [args (json/read-str json-args)
                                  ->long #(if (string? %) (Long/parseLong %) (long %))
                                  col-idx (->long (first args))
                                  item-index (->long (second args))]
                              (miller-select! col-idx item-index))))

        (cuirq/on-signal! :viewModeChanged
                          (fn [_ json-args]
                            (let [args (json/read-str json-args)
                                  mode (first args)
                                  current-path (:currentPath (state/get-state))]
                              (reset! view-mode mode)
                              (state/update-state! assoc :viewMode mode)
                              (when (and current-path (not= current-path ""))
                                (if (= mode "columns")
                                  (do (dirs/invalidate-all!)
                                      (miller-navigate-to! current-path))
                                  (do (tree/collapse-all!)
                                      (dirs/invalidate-all!)
                                      (let [items (tree/build-flat-list current-path @sort-state)]
                                        (reset! last-listing items)
                                        (models/set-data! :files items)
                                        (state/update-state! assoc :itemCount (count items)))))))))

        (cuirq/on-signal! :themeChanged
                          (fn [_ json-args]
                            (let [args (json/read-str json-args)
                                  mode (first args)]
                              (cuirq/set-vibrancy-appearance! mode))))

        (cuirq/on-signal! :sortChanged
                          (fn [_ json-args]
                            (let [args (json/read-str json-args)
                                  field (first args)
                                  ascending (= (second args) "true")]
                              (reset! sort-state {:field field :ascending ascending})
                              ;; Invalidate all caches so items are re-sorted
                              (dirs/invalidate-all!)
                              (refresh-file-list!)
                              (state/update-state! assoc
                                                   :sortField field
                                                   :sortAscending ascending))))

        ;; Load QML
        (println " [4/4] Loading QML...")
        (cuirq/set-app-name! "cuirq File Manager")
        (let [qml-path (str (System/getProperty "user.dir") "/resources/file_manager.qml")]
          (when-not (cuirq/load-qml! qml-path)
            (throw (ex-info "Failed to load QML" {:path qml-path}))))
        (cuirq/hide-titlebar!)
        (cuirq/enable-sidebar-vibrancy! 220)
        (cuirq/enable-toolbar-vibrancy! 220 48)

        ;; Navigate to home directory
        (navigate-to! (System/getProperty "user.home"))

        (println "\n========================================")
        (println " File Manager ready!")
        (println "========================================\n")

        (cuirq/exec!))

    (catch Exception e
      (println "\nError:" (.getMessage e))
      (when-let [data (ex-data e)]
        (println "  Details:" data)))

    (finally
      (println "Bye!"))))
