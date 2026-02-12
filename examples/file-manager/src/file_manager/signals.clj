(ns file-manager.signals
  "Signal handlers and dispatch functions (navigate-to!, go-back!, go-forward!)."
  (:require [file-manager.nav :as nav]
            [file-manager.miller :as miller]
            [file-manager.views :as views]
            [file-manager.dirs :as dirs]
            [file-manager.tree :as tree]
            [cuirq.core :as cuirq]
            [cuirq.state :as state]
            [cuirq.models :as models]
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
        (if (= @views/*view-mode "columns")
          (do
            (dirs/invalidate-all!)
            (miller/navigate-to! canonical)
            (cuirq/set-property! :itemCount (count (dirs/list-dir! canonical))))
          (do
            (tree/collapse-all!)
            (dirs/invalidate-all!)
            (let [items (tree/build-flat-list canonical @views/*sort-state)]
              (reset! views/*last-listing items)
              (models/set-data! :files items)
              (cuirq/set-property! :itemCount (count items))
              (let [paths (dirs/active-paths)]
                (if (seq paths)
                  (cuirq/watch-directories! paths)
                  (cuirq/start-directory-watch! canonical))))))))))

(defn go-back!
  []
  (let [{:keys [back]} @nav/*nav]
    (when (seq back)
      (swap! nav/*nav nav/nav-back)
      (let [prev (:path @nav/*nav)]
        (dirs/invalidate-all!)
        (if (= @views/*view-mode "columns")
          (do
            (miller/navigate-to! prev)
            (cuirq/set-property! :itemCount (count (dirs/list-dir! prev))))
          (do
            (tree/collapse-all!)
            (let [items (tree/build-flat-list prev @views/*sort-state)]
              (reset! views/*last-listing items)
              (models/set-data! :files items)
              (cuirq/set-property! :itemCount (count items))
              (let [paths (dirs/active-paths)]
                (if (seq paths)
                  (cuirq/watch-directories! paths)
                  (cuirq/start-directory-watch! prev))))))))))

(defn go-forward!
  []
  (let [{:keys [forward]} @nav/*nav]
    (when (seq forward)
      (swap! nav/*nav nav/nav-forward)
      (let [next-path (:path @nav/*nav)]
        (dirs/invalidate-all!)
        (if (= @views/*view-mode "columns")
          (do
            (miller/navigate-to! next-path)
            (cuirq/set-property! :itemCount (count (dirs/list-dir! next-path))))
          (do
            (tree/collapse-all!)
            (let [items (tree/build-flat-list next-path @views/*sort-state)]
              (reset! views/*last-listing items)
              (models/set-data! :files items)
              (cuirq/set-property! :itemCount (count items))
              (let [paths (dirs/active-paths)]
                (if (seq paths)
                  (cuirq/watch-directories! paths)
                  (cuirq/start-directory-watch! next-path))))))))))

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
                          (if (= mode "columns")
                            (do (dirs/invalidate-all!)
                                (miller/navigate-to! current-path))
                            (do (tree/collapse-all!)
                                (dirs/invalidate-all!)
                                (let [items (tree/build-flat-list current-path @views/*sort-state)]
                                  (reset! views/*last-listing items)
                                  (models/set-data! :files items)
                                  (cuirq/set-property! :itemCount (count items)))))))))

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
