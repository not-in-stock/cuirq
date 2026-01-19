(ns counter.core
  "Counter example application for cuirq.

   Demonstrates:
   - REPL-driven development
   - Hot-reload (edit counter.qml and save)
   - Reactive state updates
   - nREPL server for editor integration"
  (:require [cuirq.core :as cuirq]
            [cuirq.state :as state]
            [nrepl.server :as nrepl]
            [cider.nrepl :refer [cider-nrepl-handler]])
  (:gen-class))

(defn -main [& _args]
  (println "\n========================================")
  (println "cuirq Counter Example")
  (println "Clojure + UI + REPL + Qt")
  (println "========================================\n")

  ;; Start nREPL server in background thread
  (let [port 7888
        server (atom nil)]
    (try
      ;; Start nREPL server
      (reset! server (nrepl/start-server :port port :handler cider-nrepl-handler))

      (println (str " nREPL server started on port " port))
      (println "Connect from your editor:\n")
      (println (str "localhost:" port "\n"))
      (println "========================================\n")

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
        (println " Ready for REPL connections!")
        (println "========================================\n")
        (println "Try these from your editor:\n")
        (println "  ;; Update state")
        (println "  (require '[cuirq.state :as state])")
        (println "  (state/update-state! assoc :count 42)")
        (println "  (state/update-state! update :count inc)")
        (println "  (state/update-state! assoc :message \"From Editor!\")\n")
        (println "  ;; Get current state")
        (println "  (state/get-state)\n")
        (println "  ;; Edit counter.qml and save to see hot-reload\n")
        (println "========================================\n")

        ;; Start event loop (blocking until window closes)
        (cuirq/exec!))

      (catch Exception e
        (println "\n[Clojure] Error:" (.getMessage e))
        (when-let [data (ex-data e)]
          (println "   Details:" data)))

      (finally
        ;; Always cleanup, even on error
        (when @server
          (println "[Clojure] Stopping nREPL server...")
          (try
            (nrepl/stop-server @server)
            (println "[Clojure] nREPL server stopped")
            (catch Exception e
              (println "[Clojure] Warning: Error stopping nREPL:" (.getMessage e)))))
        (println "[Clojure] Bye! \n")))))
