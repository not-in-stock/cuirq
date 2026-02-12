(ns file-manager.core
  (:require [cuirq.core :as cuirq]
            [cuirq.state :as state]
            [cuirq.models :as models]
            [file-manager.miller :as miller]
            [file-manager.sync :as sync]
            [file-manager.signals :as signals])
  (:gen-class))

(defn -main [& _args]
  (println "\n========================================")
  (println "cuirq File Manager")
  (println "========================================\n")

  (try
    (cuirq/with-qt ["-platform" "cocoa"]
      ;; Create files model + miller column pool
      (println " [1/5] Creating models...")
      (models/create-model! :files)
      (doseq [i (range miller/pool-size)]
        (models/create-model! (miller/model-key i)))

      ;; Initialize non-reactive state
      (println " [2/5] Initializing state...")
      (state/set-state! {:itemCount 0
                         :viewMode "grid"})

      ;; Start reactive sync (currentPath, canGoBack, canGoForward, breadcrumbs)
      (println " [3/5] Starting reactive sync...")
      (sync/start!)

      ;; Register signal handlers
      (println " [4/5] Registering signal handlers...")
      (signals/register-all!)

      ;; Load QML
      (println " [5/5] Loading QML...")
      (cuirq/set-app-name! "cuirq File Manager")
      (let [qml-path (str (System/getProperty "user.dir") "/resources/file_manager.qml")]
        (when-not (cuirq/load-qml! qml-path)
          (throw (ex-info "Failed to load QML" {:path qml-path}))))
      (cuirq/hide-titlebar!)
      (cuirq/enable-sidebar-vibrancy! 220)
      (cuirq/enable-toolbar-vibrancy! 220 48)

      ;; Navigate to home directory
      (signals/navigate-to! (System/getProperty "user.home"))

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
