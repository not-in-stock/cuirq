(ns file-manager.views
  "Flat view state — grid/list mode, sorting, and file list refresh."
  (:require [file-manager.nav :as nav]
            [file-manager.dirs :as dirs]
            [file-manager.tree :as tree]
            [cuirq.core :as cuirq]
            [cuirq.models :as models]))

(defonce *view-mode (atom "grid"))

(defonce *sort-state (atom {:field "name" :ascending true}))

(defonce *last-listing (atom nil))

(defn- refresh-watcher!
  "Update directory watcher to match currently visible dirs."
  [visible-dirs]
  (dirs/retain-paths! visible-dirs)
  (let [paths (dirs/active-paths)]
    (if (seq paths)
      (cuirq/watch-directories! paths)
      (cuirq/stop-directory-watch!))))

(defn refresh-file-list!
  "Rebuild the flat tree and push to model. Updates watcher paths."
  []
  (let [current-path (:path @nav/*nav)
        items (tree/build-flat-list current-path @*sort-state)
        visible-dirs (into #{current-path}
                           (comp (filter :expanded) (map :path))
                           items)]
    (when (not= items @*last-listing)
      (reset! *last-listing items)
      (models/update-data! :files items "path")
      (cuirq/set-property! :itemCount (count items)))
    (refresh-watcher! visible-dirs)))

(defn navigate-flat!
  "Full flat-view navigation: collapse tree, invalidate caches,
   rebuild file list, update model + itemCount, set watcher."
  [^String path]
  (tree/collapse-all!)
  (dirs/invalidate-all!)
  (let [items (tree/build-flat-list path @*sort-state)]
    (reset! *last-listing items)
    (models/set-data! :files items)
    (cuirq/set-property! :itemCount (count items))
    (refresh-watcher! #{path})))
