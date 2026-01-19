# counter example

basic counter application demonstrating cuirq features.

## features demonstrated

-  **repl-driven development** - update state from your editor
-  **hot-reload** - edit qml and see changes instantly
-  **reactive state** - automatic ui updates
-  **nrepl server** - editor integration (emacs, vscode, intellij)

## quick start

```bash
./run.sh
```

this will:
1. build c++ bridge (if needed)
2. start the counter app
3. launch nrepl server on port 7888

## connect your editor
```
localhost:7888
```

## update state from repl

```clojure
;; load state namespace
(require '[cuirq.state :as state])

;; update counter
(state/update-state! assoc :count 42)
(state/update-state! update :count inc)
(state/update-state! update :count dec)

;; update message
(state/update-state! assoc :message "hello from repl!")

;; get current state
(state/get-state)
;; => {:count 43, :message "hello from repl!"}
```

## hot-reload

1. open `resources/counter.qml` in your editor
2. change something (e.g., font size, colors, text)
3. save the file
4. watch the window update automatically
