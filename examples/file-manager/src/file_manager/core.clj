(ns file-manager.core
  (:require [cuirq.core :as cuirq]
            [cuirq.state :as state]
            [cuirq.models :as models]
            [file-manager.dirs :as dirs]
            [file-manager.tree :as tree]
            [clojure.data.json :as json]
            [nrepl.server :as nrepl]
            [cider.nrepl :refer [cider-nrepl-handler]])
  (:import [java.io File])
  (:gen-class))

;; Navigation history
(defonce nav-history (atom {:back [] :forward []}))

;; Cache last flat listing to avoid redundant updates from FSEvents
(defonce ^:private last-listing (atom nil))

;; Sort state — persists across navigation
(defonce ^:private sort-state (atom {:field "name" :ascending true}))

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
        ;; Reset tree state for new root
        (tree/collapse-all!)
        (dirs/invalidate-all!)
        ;; List directory and update model
        (let [items (tree/build-flat-list canonical @sort-state)]
          (reset! last-listing items)
          (models/set-data! :files items)
          ;; Update state
          (state/set-state!
           {:currentPath  canonical
            :canGoBack    (boolean (seq (:back @nav-history)))
            :canGoForward (boolean (seq (:forward @nav-history)))
            :itemCount    (count items)
            :breadcrumbs  (json/write-str (build-breadcrumbs canonical))})
          ;; Watch for filesystem changes
          (let [paths (dirs/active-paths)]
            (if (seq paths)
              (cuirq/watch-directories! paths)
              (cuirq/start-directory-watch! canonical))))))))

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
        (tree/collapse-all!)
        (dirs/invalidate-all!)
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
              (cuirq/start-directory-watch! prev))))))))

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
        (tree/collapse-all!)
        (dirs/invalidate-all!)
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
              (cuirq/start-directory-watch! next-path))))))))

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

  (let [port 7889
        server (atom nil)]
    (try
      (reset! server (nrepl/start-server :port port :handler cider-nrepl-handler))
      (println (str " nREPL server started on port " port))

      (cuirq/with-qt ["-platform" "cocoa"]
        ;; Create files model
        (println " [1/4] Creating models...")
        (models/create-model! :files)

        ;; Initialize state
        (println " [2/4] Initializing state...")
        (state/set-state! {:currentPath ""
                           :canGoBack "false"
                           :canGoForward "false"
                           :itemCount 0
                           :breadcrumbs "[]"})

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
                              ;; Invalidate the changed dir and rebuild
                              (dirs/invalidate! changed-path)
                              (refresh-file-list!))))

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
        (when @server
          (nrepl/stop-server @server)
          (println "nREPL server stopped"))
        (println "Bye!")))))
