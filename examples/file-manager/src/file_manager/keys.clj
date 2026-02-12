(ns file-manager.keys
  "Keymap engine: resolves raw key events to action keywords.
   Supports multi-key sequences (e.g. gg, dd) with timeout."
  (:import [java.util.concurrent Executors ScheduledFuture TimeUnit]))

(def default-keymap
  [{:keys ["Down"]    :action :move-down}
   {:keys ["Up"]      :action :move-up}
   {:keys ["Left"]    :action :move-left}
   {:keys ["Right"]   :action :move-right}
   {:keys ["j"]       :action :move-down}
   {:keys ["k"]       :action :move-up}
   {:keys ["h"]       :action :move-left}
   {:keys ["l"]       :action :move-right}
   {:keys ["Return"]  :action :open}
   {:keys ["Escape"]  :action :go-parent}
   {:keys ["g" "g"]   :action :move-first}
   {:keys ["G"]       :action :move-last}
   {:keys ["Cmd+1"]   :action :view-grid}
   {:keys ["Cmd+2"]   :action :view-list}
   {:keys ["Cmd+3"]   :action :view-columns}
   {:keys ["Cmd+["]   :action :go-back}
   {:keys ["Cmd+]"]   :action :go-forward}])

(defonce ^:private *key-buffer (atom []))
(defonce ^:private *pending-timer (atom nil))
(defonce ^:private scheduler (Executors/newSingleThreadScheduledExecutor))

(def ^:private timeout-ms 500)

(defn- cancel-timer! []
  (when-let [^ScheduledFuture timer @*pending-timer]
    (.cancel timer false)
    (reset! *pending-timer nil)))

(defn- exact-match
  "Find a binding whose :keys exactly matches the buffer."
  [keymap buffer]
  (some (fn [{:keys [keys action]}]
          (when (= keys buffer)
            action))
        keymap))

(defn- prefix-match?
  "True if any binding's :keys starts with the given buffer."
  [keymap buffer]
  (let [n (count buffer)]
    (some (fn [{:keys [keys]}]
            (and (> (count keys) n)
                 (= (subvec (vec keys) 0 n) buffer)))
          keymap)))

(defn resolve-key
  "Given a keymap and a key string, update buffer and return:
   {:action :keyword} — resolved action
   {:pending true}    — waiting for more keys
   nil                — no match"
  [keymap key-str on-timeout-action]
  (cancel-timer!)
  (let [buffer (swap! *key-buffer conj key-str)]
    (if-let [action (exact-match keymap buffer)]
      (do (reset! *key-buffer [])
          {:action action})
      (if (prefix-match? keymap buffer)
        (do (reset! *pending-timer
                    (.schedule scheduler
                              ^Runnable (fn []
                                          (let [buf @*key-buffer]
                                            (reset! *key-buffer [])
                                            (when-let [action (exact-match keymap (vec (take 1 buf)))]
                                              (on-timeout-action action))))
                              (long timeout-ms) TimeUnit/MILLISECONDS))
            {:pending true})
        ;; No match — try single-key resolve (handles typo mid-sequence)
        (do (reset! *key-buffer [])
            (when-let [action (exact-match keymap [key-str])]
              {:action action}))))))

(defn reset-buffer!
  "Clear key buffer and cancel pending timer."
  []
  (cancel-timer!)
  (reset! *key-buffer []))
