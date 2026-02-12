(ns file-manager.miller
  "Miller columns - pool management, navigation, and selection."
  (:require [file-manager.nav :as nav]
            [file-manager.dirs :as dirs]
            [cuirq.core :as cuirq]
            [cuirq.models :as models]
            [missionary.core :as m])
  (:import [java.io File]))

(def pool-size 16)

(defonce *state (atom {:columns [] :active-count 0}))

(def state-flow (m/watch *state))

(defn model-key
  "Return the keyword for miller column model at index i."
  [i]
  (keyword (str "mc" i)))

;; Cache last data set on each miller model to avoid redundant updates
(defonce ^:private *last-data (atom {}))

(defn- path->chain
  "Build a chain of directory paths from / to the given path.
   E.g. '/Users/foo/bar' → ['/' '/Users' '/Users/foo' '/Users/foo/bar']"
  [^String path]
  (let [parts (->> (.split path File/separator)
                   (remove empty?))]
    (loop [remaining parts
           acc-path ""
           result ["/"]]
      (if (empty? remaining)
        result
        (let [part (first remaining)
              new-path (str acc-path "/" part)]
          (recur (rest remaining)
                 new-path
                 (conj result new-path)))))))

(defn- populate-model!
  "Fill miller column model at index i with directory contents.
   Skips update if data hasn't changed (dedup)."
  [i ^String path]
  (let [items (dirs/list-dir! path)]
    (when (not= items (get @*last-data i))
      (swap! *last-data assoc i items)
      (models/update-data! (model-key i) items "path"))))

(defn- clear-model!
  "Reset dedup cache for miller column model at index i.
   Does NOT clear the model data — remove transitions need old content for fade-out."
  [i]
  (swap! *last-data dissoc i))

(defn navigate-to!
  "Navigate to a path in Miller columns mode.
   Builds the full path chain and populates column models.
   Expects a canonical path."
  [^String path]
  (let [dir (File. path)]
    (when (.isDirectory dir)
      (let [chain (path->chain path)
            window (if (> (count chain) pool-size)
                     (vec (take-last pool-size chain))
                     chain)
            active-count (count window)
            columns (mapv (fn [p]
                            {:path p
                             :name (let [f (File. ^String p)]
                                     (if (= p "/") "/" (.getName f)))
                             :selected-index -1})
                          window)
            columns-with-sel
              (vec (map-indexed
                    (fn [i col]
                      (if (< (inc i) active-count)
                        (let [next-path (:path (nth columns (inc i)))
                              items (dirs/list-dir! (:path col))
                              idx (or (first (keep-indexed
                                              (fn [j item]
                                                (when (= (:path item) next-path) j))
                                              items))
                                      -1)]
                          (assoc col :selected-index idx :selected-path next-path))
                        col))
                    columns))]
        (doseq [i (range active-count)]
          (populate-model! i (:path (nth columns-with-sel i))))
        (doseq [i (range active-count pool-size)]
          (clear-model! i))
        (reset! *state {:columns columns-with-sel :active-count active-count})
        (swap! nav/*nav assoc :path path)
        (cuirq/set-property! :itemCount (count (dirs/list-dir! path)))
        (let [visible-dirs (set (map :path columns-with-sel))]
          (dirs/retain-paths! visible-dirs)
          (if (seq visible-dirs)
            (cuirq/watch-directories! (vec visible-dirs))
            (cuirq/stop-directory-watch!)))))))

(defn select!
  "Handle selection in Miller columns.
   col-idx: which column was clicked
   item-index: which item in that column"
  [col-idx item-index]
  (let [{:keys [columns]} @*state
        col (nth columns col-idx)
        items (dirs/list-dir! (:path col))
        item (nth items item-index nil)]
    (when item
      (if (:isDir item)
        (let [next-col-idx (inc col-idx)
              item-path (:path item)]
          (if (>= next-col-idx pool-size)
            (navigate-to! item-path)
            (let [new-active (inc next-col-idx)]
              (populate-model! next-col-idx item-path)
              (doseq [i (range new-active pool-size)]
                (clear-model! i))
              (let [kept (subvec columns 0 (inc col-idx))
                    kept (-> kept
                             (assoc-in [col-idx :selected-index] item-index)
                             (assoc-in [col-idx :selected-path] item-path))
                    new-col {:path item-path
                             :name (.getName (File. ^String item-path))
                             :selected-index -1
                             :selected-path ""}
                    new-columns (conj kept new-col)
                    new-state {:columns new-columns :active-count new-active}]
                (reset! *state new-state)
                (swap! nav/*nav assoc :path item-path)
                (cuirq/set-property! :itemCount (count (dirs/list-dir! item-path)))
                (let [visible-dirs (set (map :path new-columns))]
                  (dirs/retain-paths! visible-dirs)
                  (cuirq/watch-directories! (vec visible-dirs)))))))
        (let [new-active (inc col-idx)]
          (doseq [i (range new-active pool-size)]
            (clear-model! i))
          (let [kept (subvec columns 0 (inc col-idx))
                kept (-> kept
                         (assoc-in [col-idx :selected-index] item-index)
                         (assoc-in [col-idx :selected-path] (:path item)))
                new-state {:columns kept :active-count new-active}]
            (reset! *state new-state)))))))

(defn refresh-column!
  "Re-read a specific miller column whose directory changed."
  [changed-path]
  (let [{:keys [columns active-count]} @*state]
    (doseq [i (range active-count)]
      (let [col (nth columns i)]
        (when (= (:path col) changed-path)
          (populate-model! i changed-path))))))
