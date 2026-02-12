(ns file-manager.sync
  "Reactive sync — auto-pushes nav and miller state to QML."
  (:require [file-manager.nav :as nav]
            [file-manager.miller :as miller]
            [cuirq.reactive :as reactive]
            [missionary.core :as m]
            [clojure.data.json :as json])
  (:import [java.io File]))

(defn- build-breadcrumbs
  [^String path]
  (let [parts (->> (.split path File/separator)
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

(defn start!
  "Start reactive auto-sync of nav-derived properties to QML.
   Returns a cancel function."
  []
  (println "[reactive] Starting nav property sync...")
  (reactive/sync-props!
    {"currentPath"       (m/latest :path nav/nav-flow)
     "canGoBack"         (m/latest #(boolean (seq (:back %))) nav/nav-flow)
     "canGoForward"      (m/latest #(boolean (seq (:forward %))) nav/nav-flow)
     "breadcrumbs"       (m/latest #(json/write-str (build-breadcrumbs (:path %))) nav/nav-flow)
     "millerActiveCount" (m/latest :active-count miller/state-flow)
     "millerColumns"     (m/latest #(json/write-str
                                      (mapv (fn [col]
                                              {:name (:name col)
                                               :path (:path col)
                                               :selectedPath (or (:selected-path col) "")})
                                            (:columns %)))
                                   miller/state-flow)}))
