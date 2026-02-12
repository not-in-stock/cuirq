(ns file-manager.signals
  "Signal handlers and dispatch functions (navigate-to!, go-back!, go-forward!)."
  (:require [file-manager.nav :as nav]
            [file-manager.miller :as miller]
            [file-manager.views :as views]
            [file-manager.dirs :as dirs]
            [file-manager.tree :as tree]
            [file-manager.keys :as keys]
            [cuirq.core :as cuirq]
            [cuirq.macos.window :as macos.window]
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

;; Grid column count, synced from QML via keyPress signal
(defonce ^:private *grid-columns (atom 1))

(defn- current-item-count
  "Item count for the active view."
  []
  (if (= @views/*view-mode "columns")
    (let [{:keys [columns active-count]} @miller/*state
          last-col (when (pos? active-count) (nth columns (dec active-count)))]
      (if last-col
        (count (dirs/list-dir! (:path last-col)))
        0))
    (count (or @views/*last-listing []))))

(defn- sync-selected-index!
  "Push selected index to QML state."
  [idx]
  (reset! views/*selected-index idx)
  (cuirq/set-property! :selectedIndex idx))

(defn- move-selection!
  "Move selection by delta, clamped to [0, count-1]. In grid mode,
   left/right map to ±1 and up/down map to ±columns."
  [delta]
  (let [total (current-item-count)]
    (when (pos? total)
      (let [cur @views/*selected-index
            cur (if (neg? cur) 0 cur)
            new-idx (max 0 (min (dec total) (+ cur delta)))]
        (sync-selected-index! new-idx)))))

(declare open-selected! go-parent-column!)

(defn- move-horizontal!
  "Horizontal movement — in grid mode moves by ±1, in columns mode
   navigates between columns."
  [direction]
  (let [mode @views/*view-mode]
    (case mode
      "grid"    (move-selection! direction)
      "list"    nil  ;; no horizontal movement in list
      "columns" (if (pos? direction)
                  (open-selected!)
                  (go-parent-column!))
      nil)))

(defn ^:private open-selected!
  "Open the item at selectedIndex. In grid/list: navigate if dir.
   In columns: select in active column."
  []
  (let [mode @views/*view-mode
        idx @views/*selected-index]
    (when-not (neg? idx)
      (if (= mode "columns")
        (let [{:keys [active-count]} @miller/*state]
          (when (pos? active-count)
            (let [col-idx (dec active-count)]
              (miller/select! col-idx idx)
              (sync-selected-index! 0))))
        (let [items @views/*last-listing
              item (nth items idx nil)]
          (when (and item (:isDir item))
            (navigate-to! (:path item))
            (sync-selected-index! 0)))))))

(defn ^:private go-parent-column!
  "In columns mode, navigate to the parent column's path.
   Preserves selection: focuses the item that was the child we came from."
  []
  (let [{:keys [columns active-count]} @miller/*state]
    (when (> active-count 1)
      (let [parent-col (nth columns (- active-count 2))
            parent-path (:path parent-col)
            parent-sel (:selected-index parent-col -1)]
        (navigate-to! parent-path)
        (sync-selected-index! (if (>= parent-sel 0) parent-sel 0))))))

(defn- move-selection-to!
  "Move selection to absolute position. :last → last item."
  [pos]
  (let [total (current-item-count)]
    (when (pos? total)
      (let [idx (if (= pos :last) (dec total) (min pos (dec total)))]
        (sync-selected-index! idx)))))

(defn- set-view-mode!
  "Switch view mode."
  [mode]
  (let [current-path (:path @nav/*nav)]
    (reset! views/*view-mode mode)
    (state/update-state! assoc :viewMode mode)
    (keys/reset-buffer!)
    (sync-selected-index! -1)
    (when (and current-path (not= current-path ""))
      (dispatch-navigate! current-path))))

(defn- dispatch-action!
  "Map an action keyword to a navigation function."
  [action]
  (let [mode @views/*view-mode]
    (case action
      :move-down    (if (= mode "grid")
                      (move-selection! @*grid-columns)
                      (move-selection! 1))
      :move-up      (if (= mode "grid")
                      (move-selection! (- @*grid-columns))
                      (move-selection! -1))
      :move-left    (move-horizontal! -1)
      :move-right   (move-horizontal! 1)
      :open         (open-selected!)
      :go-parent    (let [current (:path @nav/*nav)
                          parent (when (and current (not= current "/"))
                                   (.getParent (java.io.File. ^String current)))]
                      (when parent
                        (navigate-to! parent)
                        (sync-selected-index! 0)))
      :move-first   (move-selection-to! 0)
      :move-last    (move-selection-to! :last)
      :go-back      (go-back!)
      :go-forward   (go-forward!)
      :view-grid    (set-view-mode! "grid")
      :view-list    (set-view-mode! "list")
      :view-columns (set-view-mode! "columns")
      nil)))

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
                        (macos.window/set-vibrancy-appearance! mode))))

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
                                             :sortAscending ascending))))

  (cuirq/on-signal! :keyPress
                    (fn [_ json-args]
                      (let [args (json/read-str json-args)
                            key-str (first args)
                            grid-cols (when (second args)
                                        (let [v (second args)]
                                          (if (string? v) (Long/parseLong v) (long v))))]
                        (when grid-cols
                          (reset! *grid-columns (max 1 grid-cols)))
                        (let [result (keys/resolve-key keys/default-keymap key-str dispatch-action!)]
                          (when-let [action (:action result)]
                            (dispatch-action! action))))))

  (cuirq/on-signal! :selectIndex
                    (fn [_ json-args]
                      (let [args (json/read-str json-args)
                            idx (if (string? (first args))
                                  (Long/parseLong (first args))
                                  (long (first args)))]
                        (sync-selected-index! idx)))))
