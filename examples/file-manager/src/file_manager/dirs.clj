(ns file-manager.dirs
  "Directory data layer — listing, caching, and helpers.
   Shared between tree view and future Miller columns."
  (:import [java.io File]
           [java.text SimpleDateFormat]
           [java.util Date]))

(set! *warn-on-reflection* true)

;; Directory cache: {path → [items]}
(defonce !dir-cache (atom {}))

(def ^:private ^SimpleDateFormat date-fmt
  (SimpleDateFormat. "dd.MM.yyyy"))

(defn- format-size
  [^long size]
  (cond
    (< size 1024)               (str size " B")
    (< size (* 1024 1024))      (format "%.1f KB" (/ size 1024.0))
    (< size (* 1024 1024 1024)) (format "%.1f MB" (/ size (* 1024.0 1024)))
    :else                       (format "%.1f GB" (/ size (* 1024.0 1024 1024)))))

(defn- format-date [^long millis]
  (if (pos? millis)
    (.format date-fmt (Date. millis))
    ""))

(defn- extension [^String name]
  (let [idx (.lastIndexOf name ".")]
    (when (pos? idx)
      (subs name (inc idx)))))

(defn- file-type
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

(defn- default-sort
  "Sort files: directories first, then by name (case-insensitive)."
  [files]
  (sort-by (fn [^File f]
             [(if (.isDirectory f) 0 1)
              (.toLowerCase (.getName f))])
           files))

(defn- file->map
  "Convert a java.io.File to a data map."
  [^File f]
  (let [name (.getName f)
        is-dir (.isDirectory f)
        ext (when-not is-dir (extension name))
        modified (.lastModified f)]
    {:name              name
     :path              (.getAbsolutePath f)
     :isDir             is-dir
     :size              (if is-dir "" (format-size (.length f)))
     :sizeBytes         (if is-dir 0 (.length f))
     :modified          modified
     :modifiedFormatted (format-date modified)
     :extension         (or ext "")
     :fileType          (if is-dir "folder" (file-type ext))
     :typeLabel         (if is-dir "Folder" (if ext (.toUpperCase ^String ext) ""))}))

(defn list-dir!
  "List contents of a directory. Returns cached result if available.
   Optional sort-fn applies to the File objects before mapping."
  ([^String path] (list-dir! path nil))
  ([^String path sort-fn]
   (if-let [cached (get @!dir-cache path)]
     cached
     (let [dir (File. path)
           children (some-> (.listFiles dir) seq)
           sorted ((or sort-fn default-sort)
                   (filter #(not (.isHidden ^File %))
                           (or children [])))
           items (mapv file->map sorted)]
       (swap! !dir-cache assoc path items)
       items))))

(defn invalidate!
  "Remove a specific path from the cache."
  [path]
  (swap! !dir-cache dissoc path))

(defn invalidate-all!
  "Clear the entire directory cache."
  []
  (reset! !dir-cache {}))

(defn retain-paths!
  "Prune cache to only keep the given set of paths."
  [paths-to-keep]
  (swap! !dir-cache select-keys paths-to-keep))

(defn active-paths
  "Return all currently cached directory paths."
  []
  (keys @!dir-cache))
