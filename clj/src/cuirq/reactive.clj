(ns cuirq.reactive
  "Reactive state sync for QML using missionary flows.
   Auto-computes derived values and pushes only changes to QML."
  (:require [missionary.core :as m]
            [cuirq.core :as cuirq]))

(defn subscribe!
  "Subscribe to a flow, calling callback on each value.
   Returns a cancel function.

   Example:
     (def cancel (subscribe! (m/watch *state) println))
     (cancel) ;; stop"
  [flow callback]
  (let [task (m/reduce (fn [_ v] (callback v) nil) nil flow)]
    (task (fn [_]) (fn [e] (println "[reactive] Subscription error:" e)))))

(defn sync-props!
  "Auto-sync missionary flows to QML context properties.
   Only pushes changed values (diffs against previous).
   Returns a cancel function.

   Example:
     (sync-props!
       {\"currentPath\"  (m/latest :path nav-flow)
        \"canGoBack\"    (m/latest #(boolean (seq (:back %))) nav-flow)})

   Each flow independently pushes its QML property when the value changes."
  [prop-flow-map]
  (let [cancels (mapv (fn [[prop-name flow]]
                        (let [prev (volatile! ::none)]
                          (subscribe! flow
                                      (fn [v]
                                        (when (not= v @prev)
                                          (vreset! prev v)
                                          (cuirq/set-property! prop-name v))))))
                      prop-flow-map)]
    (fn [] (doseq [c cancels] (c)))))
