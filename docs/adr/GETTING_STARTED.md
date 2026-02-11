# Getting Started with cuirq

This guide walks you through setting up cuirq and building your first desktop app with Clojure and Qt QML.

## Prerequisites

### Option 1: Nix (Recommended)

Nix provides a reproducible development environment with all dependencies:

```bash
# Install Nix (if not installed)
curl -L https://nixos.org/nix/install | sh

# Restart your shell
```

### Option 2: Manual Setup

Install these tools manually:

- **Qt6** (6.0+) - https://www.qt.io/download
- **Java** (11+) - OpenJDK or GraalVM
- **Clojure CLI** - https://clojure.org/guides/getting_started
- **CMake** (3.16+) - https://cmake.org/download/

**Platform-specific Qt6 installation:**
- macOS: `brew install qt6`
- Ubuntu/Debian: `sudo apt install qt6-base-dev qt6-declarative-dev`
- Fedora: `sudo dnf install qt6-qtbase-devel qt6-qtdeclarative-devel`

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/cuirq.git
cd cuirq
```

### 2. Enter Development Environment

**With Nix:**
```bash
nix develop
# This provides Qt6, Java, Clojure, CMake automatically
```

**Without Nix:**
Ensure all prerequisites are installed and in your PATH.

### 3. Build C++ Bridge

The C++ bridge connects Clojure (JVM) to Qt:

```bash
cmake -B build -G Ninja
cmake --build build
```

This creates `libqmlbridge.dylib` (macOS) / `.so` (Linux) in the `build/` directory.

## Running the Counter Example

The counter example demonstrates all core features:

```bash
cd examples/counter
./run.sh
```

You should see:
- A GUI window with counter display
- Increment/Decrement buttons
- Terminal output showing nREPL server on port 7888

## REPL-Driven Development

- Host: `localhost`
- Port: `7888`

Once connected, you can update the running app from your editor.

### Basic State Updates

```clojure
;; Load the state namespace
(require '[cuirq.state :as state])

;; Check current state
(state/get-state)
;; => {:count 0, :message "Counter Example"}

;; Update the counter - watch UI change instantly!
(state/update-state! assoc :count 42)

;; Increment/decrement
(state/update-state! update :count inc)
(state/update-state! update :count dec)

;; Change the message
(state/update-state! assoc :message "Hello from REPL!")

;; Multiple properties at once
(state/update-state! merge {:count 100 :message "Updated!"})
```

### Working with Models

```clojure
;; Load models namespace
(require '[cuirq.models :as models])

;; Check if you have any models
(models/count-items :todos)  ;; Returns count or error if model doesn't exist
```

## Hot-Reload in Action

cuirq watches QML files for changes and reloads them automatically.

### What Gets Hot-Reloaded:

- QML layout changes
- Styling (colors, fonts, spacing)
- Component properties
- Animations and transitions

### What Doesn't Get Hot-Reloaded:

- Clojure code (use REPL for that)
- C++ bridge changes (requires restart)

