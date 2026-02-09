(ns file-manager.core
  (:require [cuirq.core :as cuirq]
            [cuirq.state :as state]
            [cuirq.models :as models]
            [clojure.data.json :as json]
            [nrepl.server :as nrepl]
            [cider.nrepl :refer [cider-nrepl-handler]])
  (:import [java.io File])
  (:gen-class))

;; Navigation history
(defonce nav-history (atom {:back [] :forward []}))

;; Cache last directory listing to avoid redundant updates from FSEvents
(defonce ^:private last-listing (atom nil))

(defn- file-type
  "Classify file extension into a type category."
  [^String ext]
  (let [ext (some-> ext .toLowerCase)]
    (cond
      (nil? ext)                                          "other"
      (#{"txt" "pdf" "doc" "docx" "rtf" "odt"} ext)      "document"
      (#{"jpg" "jpeg" "png" "gif" "bmp" "svg" "webp"
         "ico" "tiff" "heic"} ext)                        "image"
      (#{"mp3" "wav" "flac" "aac" "ogg" "m4a" "wma"} ext) "audio"
      (#{"mp4" "avi" "mkv" "mov" "wmv" "flv" "webm"} ext) "video"
      (#{"clj" "cljs" "cljc" "java" "py" "js" "ts" "cpp"
         "c" "h" "rs" "go" "rb" "sh" "html" "css" "qml"
         "json" "xml" "yaml" "yml" "toml" "edn" "md"} ext) "code"
      (#{"zip" "tar" "gz" "bz2" "xz" "rar" "7z"
         "jar" "war"} ext)                                "archive"
      :else                                               "other")))

(defn- format-size
  "Format file size in human-readable form."
  [^long size]
  (cond
    (< size 1024)               (str size " B")
    (< size (* 1024 1024))      (format "%.1f KB" (/ size 1024.0))
    (< size (* 1024 1024 1024)) (format "%.1f MB" (/ size (* 1024.0 1024)))
    :else                       (format "%.1f GB" (/ size (* 1024.0 1024 1024)))))

(defn- extension [^String name]
  (let [idx (.lastIndexOf name ".")]
    (when (pos? idx)
      (subs name (inc idx)))))

(defn- list-directory
  "List contents of a directory, returning a vec of maps."
  [^String path]
  (let [dir (File. path)
        children (some-> (.listFiles dir) seq)]
    (->> (or children [])
         (filter #(not (.isHidden ^File %)))
         (sort-by (fn [^File f]
                    [(if (.isDirectory f) 0 1)
                     (.toLowerCase (.getName f))]))
         (mapv (fn [^File f]
                 (let [name (.getName f)
                       is-dir (.isDirectory f)
                       ext (when-not is-dir (extension name))]
                   {:name      name
                    :path      (.getAbsolutePath f)
                    :isDir     is-dir
                    :size      (if is-dir "" (format-size (.length f)))
                    :modified  (.lastModified f)
                    :extension (or ext "")
                    :fileType  (if is-dir "folder" (file-type ext))}))))))

(defn- build-breadcrumbs
  "Build breadcrumb trail from a path."
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
        ;; List directory and update model
        (let [items (list-directory canonical)]
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
          (cuirq/start-directory-watch! canonical))))))

(defn go-back!
  "Navigate back in history."
  []
  (let [{:keys [back]} @nav-history]
    (when (seq back)
      (let [prev (peek back)
            current (:currentPath (state/get-state))]
        (swap! nav-history (fn [h]
                             (-> h
                                 (update :back pop)
                                 (update :forward conj current))))
        ;; Navigate without pushing to back stack
        (let [items (list-directory prev)]
          (reset! last-listing items)
          (models/set-data! :files items)
          (state/set-state!
           {:currentPath  prev
            :canGoBack    (boolean (seq (:back @nav-history)))
            :canGoForward (boolean (seq (:forward @nav-history)))
            :itemCount    (count items)
            :breadcrumbs  (json/write-str (build-breadcrumbs prev))})
          (cuirq/start-directory-watch! prev))))))

(defn go-forward!
  "Navigate forward in history."
  []
  (let [{:keys [forward]} @nav-history]
    (when (seq forward)
      (let [next-path (peek forward)
            current (:currentPath (state/get-state))]
        (swap! nav-history (fn [h]
                             (-> h
                                 (update :forward pop)
                                 (update :back conj current))))
        (let [items (list-directory next-path)]
          (reset! last-listing items)
          (models/set-data! :files items)
          (state/set-state!
           {:currentPath  next-path
            :canGoBack    (boolean (seq (:back @nav-history)))
            :canGoForward (boolean (seq (:forward @nav-history)))
            :itemCount    (count items)
            :breadcrumbs  (json/write-str (build-breadcrumbs next-path))})
          (cuirq/start-directory-watch! next-path))))))

(defn- resolve-sidebar-location
  "Map sidebar location key to filesystem path."
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

        (cuirq/on-signal! :directoryChanged
                          (fn [_ json-args]
                            (let [args (json/read-str json-args)
                                  changed-path (first args)
                                  current-path (:currentPath (state/get-state))]
                              (when (= changed-path current-path)
                                (let [items (list-directory current-path)]
                                  (when (not= items @last-listing)
                                    (reset! last-listing items)
                                    (models/update-data! :files items "path")
                                    (state/update-state! assoc :itemCount (count items))))))))

        (cuirq/on-signal! :themeChanged
                          (fn [_ json-args]
                            (let [args (json/read-str json-args)
                                  mode (first args)]
                              (cuirq/set-vibrancy-appearance! mode))))

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
