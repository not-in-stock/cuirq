# cuirq

**Clojure + UI + REPL + Qt** - REPL-driven desktop application development

## State of the project

> [!IMPORTANT]
>  Under development. Things will break!

Featuring:
- **Hot-reload** - Edit QML and see changes instantly
- **REPL-driven** - Update app state from your editor
- **Native binaries** - GraalVM Native Image ready
- **Modern UI** - Qt6 QML declarative framework
- **Zero boilerplate** - Simple, high-level API

## Quick Example

```clojure
(ns my-app.core
  (:require [cuirq.core :as cuirq]
            [cuirq.state :as state]))

(defn -main [& args]
  (cuirq/with-qt ["-platform" "cocoa"]
    ;; Set initial state
    (state/set-state! {:count 0 :message "Hello cuirq!"})

    ;; Register signal handlers
    (cuirq/on-signal! :increment
      (fn [_] (state/update-state! update :count inc)))

    ;; Load QML and run
    (cuirq/load-qml! "ui/counter.qml")
    (cuirq/exec!)))
```
## Key Features

### Hot-Reload
Edit QML files and see changes instantly. No restart needed - state is preserved across reloads.

### REPL-Driven Development
Connect your editor (Emacs/VSCode/IntelliJ) and update your running app:
```clojure
(state/update-state! assoc :message "Live coding!")
(state/update-state! update :count inc)
```

### Reactive State Management
Bidirectional data flow between Clojure and QML:
- **Clojure → QML**: Automatic property updates
- **QML → Clojure**: Signal handlers for user interactions

### Dynamic Data Binding
List models with efficient updates for complex UIs:
```clojure
(models/create-model! :todos)
(models/set-data! :todos [{:text "Buy milk" :done false} ...])
```

### Native Performance
GraalVM Native Image support for fast startup (~50ms) and small binaries (~80MB).


## Getting Started

### Prerequisites

**Option 1: Nix (Recommended)**
```bash
curl -L https://nixos.org/nix/install | sh
```

**Option 2: Manual Setup**
- Qt6 - https://www.qt.io/download
- Java 11+ - OpenJDK or GraalVM
- Clojure CLI - https://clojure.org/guides/getting_started
- CMake 3.16+

### Installation

```bash
git clone https://github.com/YOUR_USERNAME/cuirq.git
cd cuirq

# With Nix
nix develop

# Build C++ bridge
cmake -B build -G Ninja
cmake --build build

# Run counter example
cd examples/counter
./run.sh
```

See [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md) for detailed tutorial.

## Documentation

- **[Getting Started Guide](docs/GETTING_STARTED.md)** - Step-by-step tutorial
- **[Roadmap](docs/ROADMAP.md)** - Planned features and optimizations
- **[Counter Example](examples/counter/)** - Working example with hot-reload

## Core API Reference

### State Management
```clojure
(require '[cuirq.state :as state])

(state/get-state)                          ;; Get current state
(state/set-state! {:count 0})              ;; Set state
(state/update-state! assoc :count 42)      ;; Update state
(state/watch-state! :watcher fn)           ;; Watch changes
```

### Signal Handlers
```clojure
(require '[cuirq.core :as cuirq])

(cuirq/on-signal! :buttonClicked
  (fn [args]
    (state/update-state! update :count inc)))
```

### List Models
```clojure
(require '[cuirq.models :as models])

(models/create-model! :items)
(models/set-data! :items [{:name "Alice"} {:name "Bob"}])
(models/clear! :items)
```

### Qt Lifecycle
```clojure
(cuirq/with-qt ["-platform" "cocoa"]
  (cuirq/load-qml! "ui/main.qml")
  (cuirq/exec!))
```

## Building Native Image

```bash
cmake -B build -G Ninja && cmake --build build
cd examples/counter
./build-native.sh
./counter-native
```

## License

MIT
