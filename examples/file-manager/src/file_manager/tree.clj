(ns file-manager.tree
  "Tree expand/collapse state and flat-list builder for FileList."
  (:require [file-manager.dirs :as dirs]))

;; Set of expanded directory paths
(defonce *expanded (atom #{}))

(defn toggle! [path]
  (swap! *expanded
         (fn [s] (if (contains? s path) (disj s path) (conj s path)))))

(defn expand! [path]
  (swap! *expanded conj path))

(defn collapse! [path]
  (swap! *expanded disj path))

(defn collapse-all! []
  (reset! *expanded #{}))

(defn expanded? [path]
  (contains? @*expanded path))

(defn- sort-items
  "Sort items according to sort-state: dirs first, then by field.
   Directories always come first regardless of sort direction."
  [items {:keys [field ascending] :or {field "name" ascending true}}]
  (let [key-fn (case field
                 "name"     (fn [m] (.toLowerCase ^String (:name m)))
                 "size"     :sizeBytes
                 "modified" :modified
                 "type"     (fn [m] (.toLowerCase ^String (:typeLabel m)))
                 (fn [m] (.toLowerCase ^String (:name m))))
        {dirs true files false} (group-by :isDir items)
        sort-group (fn [group]
                     (let [sorted (sort-by key-fn group)]
                       (if ascending sorted (reverse sorted))))]
    (vec (concat (sort-group dirs) (sort-group files)))))

(defn build-flat-list
  "Build a flat vector from root-path, recursively expanding directories
   that are in the expanded set. Each item gets :depth, :expanded, :hasChildren."
  ([root-path] (build-flat-list root-path nil))
  ([root-path sort-state]
   (let [expanded @*expanded]
     (letfn [(walk [path depth]
               (let [items (dirs/list-dir! path)
                     sorted (if sort-state (sort-items items sort-state) items)]
                 (reduce
                  (fn [acc item]
                    (let [is-dir (:isDir item)
                          item-path (:path item)
                          is-expanded (and is-dir (contains? expanded item-path))
                          enriched (assoc item
                                         :depth depth
                                         :expanded is-expanded
                                         :hasChildren is-dir)]
                      (if is-expanded
                        (into (conj acc enriched) (walk item-path (inc depth)))
                        (conj acc enriched))))
                  []
                  sorted)))]
       (walk root-path 0)))))
