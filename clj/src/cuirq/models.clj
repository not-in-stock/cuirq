(ns cuirq.models
  "List model API for QML ListView/GridView."
  (:require [clojure.data.json :as json])
  (:import [qml Bridge]))

(set! *warn-on-reflection* true)

(defn create-model!
  "Create a list model and register it as a QML context property.

   Example:
     (create-model! :items)
     ;; Now 'items' is available in QML"
  [model-name]
  (Bridge/createModel (name model-name))
  (println (str "[CLJ] Created model: " (name model-name))))

(defn set-data!
  "Set model data from a Clojure sequence of maps.

   Each map represents one item with named fields.
   Field names become QML roles automatically.

   Example:
     (set-data! :items [{:name \"Alice\" :age 30}
                        {:name \"Bob\" :age 25}])

   In QML:
     ListView {
       model: items
       delegate: Text { text: model.name + \" (\" + model.age + \")\" }
     }"
  [model-name data]
  (let [json-str (json/write-str data)]
    (Bridge/setModelData (name model-name) json-str)
    (println (str "[CLJ] Set data for model: " (name model-name)
                  " (" (count data) " items)"))))

(defn clear!
  "Clear all items from a model."
  [model-name]
  (Bridge/clearModel (name model-name))
  (println (str "[CLJ] Cleared model: " (name model-name))))

(defn count-items
  "Get number of items in a model."
  [model-name]
  (Bridge/getModelCount (name model-name)))

(comment
  ;; Usage examples

  ;; Create model
  (create-model! :people)

  ;; Set initial data
  (set-data! :people [{:name "Alice" :age 30 :city "NYC"}
                      {:name "Bob" :age 25 :city "SF"}
                      {:name "Charlie" :age 35 :city "LA"}])

  ;; Update data (full replacement)
  (set-data! :people [{:name "Alice" :age 31 :city "NYC"}
                      {:name "Bob" :age 25 :city "SF"}])

  ;; Clear
  (clear! :people)

  ;; Check count
  (count-items :people))
