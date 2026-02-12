(ns file-manager.signals
  "Signal handlers and dispatch functions (navigate-to!, go-back!, go-forward!)."
  (:require [file-manager.nav :as nav]
            [file-manager.miller :as miller]
            [file-manager.views :as views]
            [file-manager.dirs :as dirs]
            [file-manager.tree :as tree]
            [cuirq.core :as cuirq]
            [cuirq.state :as state]
            [clojure.data.json :as json])
  (:import [java.io File]))

(defn- resolve-sidebar-location
  [^String key]
  (let [home (System/getProperty "user.home")]
    (case key
      "home"      home
      "desktop"   (str home "/Desktop")
      "documents" (str home "/Documents")
      "downloads" (str home "/Downloads")
      "pictures"  (str home "/Pictures")
      "music"     (str home "/Music")
      home)))

(defn- dispatch-navigate!
  "Invalidate caches and refresh the active view for the given path."
  [^String path]
  (if (= @views/*view-mode "columns")
    (do (dirs/invalidate-all!)
        (miller/navigate-to! path))
    (views/navigate-flat! path)))

(defn navigate-to!
  "Navigate to a directory path."
  [^String path]
  (let [dir (File. path)]
    (when (.isDirectory dir)
      (let [canonical (.getCanonicalPath dir)
            current (:path @nav/*nav)]
        (if (and (seq current) (not= current canonical))
          (swap! nav/*nav nav/nav-push canonical)
          (swap! nav/*nav assoc :path canonical))
        (dispatch-navigate! canonical)))))

(defn go-back!
  []
  (when (seq (:back @nav/*nav))
    (swap! nav/*nav nav/nav-back)
    (dispatch-navigate! (:path @nav/*nav))))

(defn go-forward!
  []
  (when (seq (:forward @nav/*nav))
    (swap! nav/*nav nav/nav-forward)
    (dispatch-navigate! (:path @nav/*nav))))

(defn register-all!
  "Register all signal handlers with cuirq."
  []
  (cuirq/on-signal! :navigate
                    (fn [_ json-args]
                      (let [args (json/read-str json-args)]
                        (navigate-to! (first args)))))

  (cuirq/on-signal! :goBack
                    (fn [_ _] (go-back!)))

  (cuirq/on-signal! :goForward
                    (fn [_ _] (go-forward!)))

  (cuirq/on-signal! :sidebarNavigate
                    (fn [_ json-args]
                      (let [args (json/read-str json-args)
                            path (resolve-sidebar-location (first args))]
                        (navigate-to! path))))

  (cuirq/on-signal! :toggleExpand
                    (fn [_ json-args]
                      (let [args (json/read-str json-args)
                            path (first args)]
                        (tree/toggle! path)
                        (when (tree/expanded? path)
                          (dirs/invalidate! path))
                        (views/refresh-file-list!))))

  (cuirq/on-signal! :directoryChanged
                    (fn [_ json-args]
                      (let [args (json/read-str json-args)
                            changed-path (first args)]
                        (dirs/invalidate! changed-path)
                        (if (= @views/*view-mode "columns")
                          (miller/refresh-column! changed-path)
                          (views/refresh-file-list!)))))

  (cuirq/on-signal! :millerSelect
                    (fn [_ json-args]
                      (let [args (json/read-str json-args)
                            ->long #(if (string? %) (Long/parseLong %) (long %))
                            col-idx (->long (first args))
                            item-index (->long (second args))]
                        (miller/select! col-idx item-index))))

  (cuirq/on-signal! :viewModeChanged
                    (fn [_ json-args]
                      (let [args (json/read-str json-args)
                            mode (first args)
                            current-path (:path @nav/*nav)]
                        (reset! views/*view-mode mode)
                        (state/update-state! assoc :viewMode mode)
                        (when (and current-path (not= current-path ""))
                          (dispatch-navigate! current-path)))))

  (cuirq/on-signal! :themeChanged
                    (fn [_ json-args]
                      (let [args (json/read-str json-args)
                            mode (first args)]
                        (cuirq/set-vibrancy-appearance! mode))))

  (cuirq/on-signal! :sortChanged
                    (fn [_ json-args]
                      (let [args (json/read-str json-args)
                            field (first args)
                            ascending (= (second args) "true")]
                        (reset! views/*sort-state {:field field :ascending ascending})
                        (dirs/invalidate-all!)
                        (views/refresh-file-list!)
                        (state/update-state! assoc
                                             :sortField field
                                             :sortAscending ascending)))))
