(ns cuirq.core
  "Core Qt QML integration API for cuirq."
  (:require [clojure.data.json])
  (:import [qml PanamaBridge PanamaBridge$SignalHandler]))

(defmacro with-qt
  "Initialize Qt, execute body, and ensure cleanup.
   Example:
     (with-qt [\"-platform\" \"cocoa\"]
       (load-qml! \"main.qml\")
       (exec!))"
  [args & body]
  `(try
     (PanamaBridge/initialize (into-array String ~args))
     ~@body
     (finally
       (PanamaBridge/shutdown)
       (println "[Clojure] Qt session ended"))))

(defn load-qml!
  "Load a QML file. Automatically starts watching for changes.
   Returns true if successful, false otherwise."
  [path]
  (PanamaBridge/loadQml path))

(defn set-property!
  "Set a context property available in QML."
  [name value]
  (PanamaBridge/setContextProperty (clojure.core/name name) (str value)))

(defn exec!
  "Run Qt event loop (blocking until window closes)."
  []
  (PanamaBridge/exec))

(defn quit!
  "Request Qt event loop to quit."
  []
  (PanamaBridge/quit))

(defn on-signal!
  "Register a Clojure function to handle a QML signal.
   The handler function receives the signal name and a JSON args string."
  [signal-name handler-fn]
  (let [java-handler (reify PanamaBridge$SignalHandler
                       (handle [_ name json-args]
                         (try
                           (handler-fn name json-args)
                           (catch Throwable t
                             (println (str "[Clojure] Error in signal handler for " signal-name ": " (.getMessage t)))
                             (.printStackTrace t)))))]
    (PanamaBridge/registerSignalHandler (clojure.core/name signal-name) java-handler)
    (println (str "[Clojure] Registered signal handler for: " (clojure.core/name signal-name)))))

(defn set-auto-reload!
  "Enable or disable automatic QML hot-reload (dev mode).

   Example:
     (set-auto-reload! true)  ; Enable
     (set-auto-reload! false) ; Disable"
  [enabled]
  (PanamaBridge/setAutoReload enabled)
  (println (str "[Clojure] Auto-reload " (if enabled "enabled" "disabled"))))

(defn auto-reload-enabled?
  "Check if automatic QML hot-reload is enabled."
  []
  (PanamaBridge/isAutoReloadEnabled))

(defn start-directory-watch!
  "Start watching a directory for changes (macOS FSEvents).
   Automatically stops any previous watch. On change, fires
   a 'directoryChanged' signal with the path."
  [path]
  (PanamaBridge/startDirectoryWatch (str path)))

(defn watch-directories!
  "Watch multiple directories for changes (macOS FSEvents).
   Replaces any previous watch. On change, fires 'directoryChanged'
   with the specific changed directory path.
   Paths should be a sequence of strings."
  [paths]
  (let [json-str (clojure.data.json/write-str (vec paths))]
    (PanamaBridge/watchDirectories json-str)))

(defn stop-directory-watch!
  "Stop watching the current directory."
  []
  (PanamaBridge/stopDirectoryWatch))

