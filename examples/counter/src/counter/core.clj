(ns counter.core
  "Counter example application for cuirq.

   Demonstrates:
   - Hot-reload (edit counter.qml and save)
   - Reactive state updates"
  (:require [cuirq.core :as cuirq]
            [cuirq.state :as state])
  (:gen-class))

(defn -main [& _args]
  (println "\n========================================")
  (println "cuirq Counter Example")
  (println "========================================\n")

  (try
    ;; Initialize Qt in main thread
    (cuirq/with-qt ["-platform" "cocoa"]
      ;; Initialize state
      (println " [1/3] Initializing state...")
      (state/set-state! {:count 0 :message "Hello cuirq!"})
      (println " State initialized\n")

      ;; Load QML (will auto-watch for changes)
      (println " [2/3] Loading QML...")
      (let [qml-path (str (System/getProperty "user.dir") "/resources/counter.qml")]
        (when-not (cuirq/load-qml! qml-path)
          (println "Failed to load QML")
          (throw (ex-info "Failed to load QML" {:path qml-path}))))

      (println " QML loaded")
      (println " File watching enabled\n")

      (println " [3/3] Starting Qt event loop...\n")
      (println "========================================")
      (println " Counter ready!")
      (println "========================================\n")

      ;; Start event loop (blocking until window closes)
      (cuirq/exec!))

    (catch Exception e
      (println "\n[Clojure] Error:" (.getMessage e))
      (when-let [data (ex-data e)]
        (println "   Details:" data)))

    (finally
      (println "[Clojure] Bye!\n"))))
