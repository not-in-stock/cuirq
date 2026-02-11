# ADR-007: Multi-Window Support

## Status
Proposed

## Context

cuirq currently supports a single window (`g_window`) with a single QML engine. All state, models, and the reload popup are scoped to this one window. As applications grow more complex (e.g., inspector panels, preferences windows, detached viewers), we need to support multiple windows — each potentially loading different QML files.

The recent move to inject the reload popup directly into `g_window->contentItem()` (shadow-cljs style, ADR-006) raised the question: if a QML error occurs in only one window's file, can we show the error in exactly the affected window(s)?

### Current Architecture (Single Window)

```
g_window (QQuickWindow, persistent)
├── g_rootItem (QQuickItem, from main QQmlEngine — swapped on reload)
└── popupItem  (QQuickItem, from popup QQmlEngine — survives reload, z=9999)
```

- One `QQmlEngine` for app content, one for the popup
- `QmlWatcher` watches all QML files, reloads the entire engine on any change
- Popup is injected into the single window's content tree

## Decision

Design multi-window support around **engine-per-window** with **per-window popup injection**.

### Architecture

```
WindowManager
├── Window A (QQuickWindow)
│   ├── rootItem A (from QQmlEngine A)
│   └── popupItem A (from popup QQmlEngine — shared)
├── Window B (QQuickWindow)
│   ├── rootItem B (from QQmlEngine B)
│   └── popupItem B (from popup QQmlEngine — shared)
└── QmlWatcher (shared, file → window mapping)
```

### Key Design Decisions

#### 1. Engine-per-Window

Each window gets its own `QQmlEngine`. Benefits:
- Reload one window without affecting others
- Errors in one QML tree don't crash the whole app
- Natural isolation of singletons (`pragma Singleton` scoped per-engine)

Trade-off: shared state (`QQmlPropertyMap`, models) must be registered on all engines.

#### 2. WindowManager

Replace the global `g_window` / `g_rootItem` with a `WindowManager` that tracks:
- Window ID → `QQuickWindow*` mapping
- Window ID → `QQmlEngine*` mapping
- Window ID → root QML file path
- Window ID → `QQuickItem*` root item

Public API (exposed via Panama bridge):
```cpp
int  create_window(const char* qml_path);  // returns window ID
void close_window(int window_id);
void show_window(int window_id);
void hide_window(int window_id);
// Per-window: hide_titlebar, enable_vibrancy, etc.
```

#### 3. Per-Window Popup Injection

Each window gets its own popup `QQuickItem` instance, all created from a single popup `QQmlEngine`. The `ReloadPopup` class manages a map of `window_id → QQuickItem*`.

When an error occurs in a specific QML file:
1. `QmlWatcher` knows which file changed
2. It looks up which window(s) load that file (directly or via imports)
3. Popup is shown only in those windows

For transitive dependency errors (e.g., `Theme.qml` used by all windows), all affected windows show the error.

#### 4. File → Window Mapping

`QmlWatcher` maintains a reverse index: `file_path → Set<window_id>`. Built by:
- Recording the root QML file for each window
- Intercepting `QQmlEngine::warnings` per-engine to attribute errors
- Watching import directories per-window

On file change:
1. Look up affected windows via reverse index
2. Reload only those windows' engines
3. Show success/error popup in those windows

#### 5. Shared State

`QQmlPropertyMap` (state), `StateNotifier`, `SignalForwarder`, and `JvmListModel` instances are shared across windows. On engine creation for any window, all shared objects are registered as context properties.

Models that are window-specific (e.g., a file list for a specific directory) can be scoped to a window via the `create_window` call or a separate `set_window_model` API.

### API Changes

Current single-window API remains as convenience (operates on window 0):
```cpp
bool load_qml(const char* path);          // creates window 0
void hide_titlebar();                      // window 0
void enable_sidebar_vibrancy(int width);   // window 0
```

New multi-window API:
```cpp
int  create_window(const char* qml_path);
void close_window(int id);
void window_hide_titlebar(int id);
void window_enable_sidebar_vibrancy(int id, int width);
```

### Window Properties Convention

Each QML root Item declares optional properties (same as ADR-006):
```qml
Item {
    property string windowTitle: "Inspector"
    property int windowWidth: 600
    property int windowHeight: 400
    property color windowColor: "#ffffff"
}
```

`WindowManager` reads these when creating each window.

## Consequences

### Positive
- Isolated reload per window — errors don't affect other windows
- Error popup shown in context (the window where the error matters)
- Natural scaling for complex apps (preferences, inspectors, detached panels)
- Shared state model keeps things simple for common cases

### Negative
- More complex engine lifecycle management
- Shared singletons (like `Theme.qml`) need re-registration per engine, or a shared import path
- Memory overhead: one QQmlEngine per window (each has its own JIT cache, component cache)

### Risks
- Scene graph isolation: each `QQuickWindow` has its own render thread/context. Cross-window item reparenting is not safe. Popup items must be created per-window.
- Engine startup cost: creating a `QQmlEngine` is ~50-100ms. For many windows, lazy creation is important.
- `pragma Singleton` per-engine means Theme changes in one engine don't propagate to others unless we use a shared C++ object for theme state.

## Implementation Plan

1. Extract `WindowManager` class from current globals in `qt_engine.cpp`
2. Migrate single-window code to use `WindowManager` with window ID 0
3. Add `create_window` / `close_window` to Panama API
4. Update `QmlWatcher` with file → window reverse index
5. Update `ReloadPopup` to manage per-window popup items
6. Expose multi-window API in Java bridge and Clojure layer
