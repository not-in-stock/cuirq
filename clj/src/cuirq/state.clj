(ns cuirq.state
  "State management for REPL-driven development.
   This namespace provides a simple atom-based state management system
   that automatically syncs to QML context properties."
  (:require [cuirq.core :as cuirq]
            [clojure.string :as str]))

(defonce ^:private app-state (atom {}))

(defn get-state
  "Get current application state."
  []
  @app-state)

(defn set-state!
  "Set application state and sync to QML.

   Example:
     (set-state! {:count 42 :message \"Hello\"})"
  [new-state]
  (reset! app-state new-state)
  (doseq [[k v] new-state]
    (cuirq/set-property! k v))
  (println (str "[Clojure] State updated: " new-state)))

(defn update-state!
  "Update application state with a function and sync to QML.

   Examples:
     (update-state! assoc :count 42)
     (update-state! update :count inc)
     (update-state! dissoc :old-key)"
  [f & args]
  (let [new-state (apply f @app-state args)]
    (set-state! new-state)
    new-state))

(defn get-in-state
  "Get value at path in state.

   Example:
     (get-in-state [:user :name])"
  [path]
  (get-in @app-state path))

(defn assoc-in-state!
  "Associate value at path in state and sync to QML.

   Example:
     (assoc-in-state! [:user :name] \"Alice\")"
  [path value]
  (update-state! assoc-in path value))

(defn update-in-state!
  "Update value at path in state with function and sync to QML.

   Example:
     (update-in-state! [:count] inc)"
  [path f & args]
  (apply update-state! update-in path f args))

(defn watch-state!
  "Add a watch function that is called when state changes.
  Example:
     (watch-state! :logger
       (fn [key ref old new]
         (println \"State changed:\" old \"->\" new)))"
  [key watch-fn]
  (add-watch app-state key watch-fn))

(defn unwatch-state!
  "Remove a watch function."
  [key]
  (remove-watch app-state key))

(update-state! update :count inc)

;; (set-state! {:count 200 :message "Hey it finally works!"})

(comment
  ;; Usage examples

  ;; Set initial state
  (set-state! {:count 0 :message "Hello REPL"})

  ;; Update single value
  (update-state! assoc :count 42)

  ;; Increment counter
  (update-state! update :count inc)

  ;; Nested updates
  (assoc-in-state! [:user :name] "Alice")
  (update-in-state! [:user :age] inc)

  ;; Watch state changes
  (watch-state! :logger
    (fn [_ _ old new]
      (println "Changed:" old "->" new)))
  )
