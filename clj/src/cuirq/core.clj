(ns cuirq.core
  "Core Qt QML integration API for cuirq."
  (:import [qml Bridge Bridge$SignalHandler]))

(set! *warn-on-reflection* true)

(defmacro with-qt
  "Initialize Qt, execute body, and ensure cleanup.
   Example:
     (with-qt [\"-platform\" \"cocoa\"]
       (load-qml! \"main.qml\")
       (exec!))"
  [args & body]
  `(try
     (Bridge/initialize (into-array String ~args))
     ~@body
     (finally
       (println "[Clojure] Qt session ended"))))

(defn load-qml!
  "Load a QML file. Automatically starts watching for changes.
   Returns true if successful, false otherwise."
  [path]
  (Bridge/loadQml path))

(defn set-property!
  "Set a context property available in QML."
  [name value]
  (Bridge/setContextProperty (clojure.core/name name) (str value)))

(defn exec!
  "Run Qt event loop (blocking until window closes)."
  []
  (Bridge/exec))

(defn quit!
  "Request Qt event loop to quit."
  []
  (Bridge/quit))

(defn on-signal!
  "Register a Clojure function to handle a QML signal.
   The handler function will receive a sequence of string arguments."
  [signal-name handler-fn]
  (let [java-handler (reify Bridge$SignalHandler
                       (handle [_ args]
                         (try
                           (handler-fn (vec args))
                           (catch Throwable t
                             (println (str "[Clojure] Error in signal handler for " signal-name ": " (.getMessage t)))
                             (.printStackTrace t)))))]
    (Bridge/registerSignalHandler (name signal-name) java-handler)
    (println (str "[Clojure] Registered signal handler for: " (name signal-name)))))

(defn set-auto-reload!
  "Enable or disable automatic QML hot-reload (dev mode).

   Example:
     (set-auto-reload! true)  ; Enable
     (set-auto-reload! false) ; Disable"
  [enabled]
  (Bridge/setAutoReload enabled)
  (println (str "[Clojure] Auto-reload " (if enabled "enabled" "disabled"))))

(defn auto-reload-enabled?
  "Check if automatic QML hot-reload is enabled."
  []
  (Bridge/isAutoReloadEnabled))
