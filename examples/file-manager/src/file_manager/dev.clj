(ns file-manager.dev
  "Development entry point with nREPL server."
  (:require [file-manager.core :as core]
            [nrepl.server :as nrepl]
            [cider.nrepl :refer [cider-nrepl-handler]])
  (:gen-class))

(defn -main [& args]
  (let [port 7889
        server (nrepl/start-server :port port :handler cider-nrepl-handler)]
    (println (str " nREPL server started on port " port))
    (try
      (apply core/-main args)
      (finally
        (nrepl/stop-server server)
        (println "nREPL server stopped")))))
