(ns file-manager.nav
  "Navigation state — path, back/forward stacks, and derived flows."
  (:require [missionary.core :as m]))

(defonce *nav (atom {:path "" :back [] :forward []}))

(defn nav-push
  "Push current path to back stack, navigate to new path."
  [nav path]
  (-> nav
      (update :back conj (:path nav))
      (assoc :forward [] :path path)))

(defn nav-back
  "Pop from back stack, push current to forward."
  [nav]
  (let [prev (peek (:back nav))]
    (-> nav
        (update :back pop)
        (update :forward conj (:path nav))
        (assoc :path prev))))

(defn nav-forward
  "Pop from forward stack, push current to back."
  [nav]
  (let [next-p (peek (:forward nav))]
    (-> nav
        (update :forward pop)
        (update :back conj (:path nav))
        (assoc :path next-p))))

(def nav-flow (m/watch *nav))
