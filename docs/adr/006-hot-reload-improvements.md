# ADR-006: Hot Reload Improvements

## Status
Implemented

## Context

cuirq has a working QML hot-reload system (shell.qml + Loader + QmlWatcher). ADR-005 explored replacing it with file I/O interception via `QAbstractFileEngineHandler`. A spike validated that the interception works, but revealed that any approach that destroys the `QQuickWindow` causes visible flicker on macOS — an unavoidable limitation of full window recreation.

Investigation of [quickshell](https://git.outfoxxed.me/quickshell/quickshell.git), a Qt/QML shell framework with production-quality hot-reload, revealed a more productive direction: instead of changing *how* files are intercepted, improve *what happens during reload*.

### Previous Limitations

1. **Singleton reload impossible** — `pragma Singleton` types (e.g. `Theme.qml`) are cached per-engine. `clearComponentCache()` does not evict singletons.

2. **Truncate-then-write race** — editors like VSCode save in two steps: truncate to 0 bytes, then write new content. If `QFileSystemWatcher` fires between the two steps, we reload a 0-byte file.

3. **Atomic save loses file watch** — editors that use atomic saves (write temp file, rename over original) cause FSEvents to stop tracking the original path.

4. **No reload feedback** — when QML has a syntax error, the Loader silently fails. No visual indication of reload success or failure.

5. **Window flicker on reload** — destroying and recreating `QQuickWindow` causes visible flicker and repositioning in tiling WMs like yabai.

## Decision

Six improvements were implemented, building on quickshell's generational approach and shadow-cljs's in-app error overlay pattern.

### 1. Robust file watching

**Changes to `QmlWatcher`:**

a) **Ignore zero-size file events.** When `onFileChanged` fires, check `QFileInfo(path).size()`. If 0, skip — the real write hasn't happened yet.

b) **Track deleted-then-recreated files via directory events.** When a watched file disappears (atomic save), record it. When the directory changes, check if any recorded files have reappeared and re-add them to the watcher.

### 2. Proxy window (flicker-free reload)

**Problem:** Engine-per-reload originally destroyed and recreated the `QQuickWindow`, causing flicker and yabai repositioning.

**Solution:** Persistent `QQuickWindow` that is never destroyed. QML root is an `Item` (not `ApplicationWindow`). On reload: create new `QQmlEngine` + `QQmlComponent`, load QML as `QQuickItem`, swap `parentItem` in the persistent window, destroy old engine.

**Window property convention:** QML root Item declares optional properties that C++ reads on first load:

```qml
Item {
    property string windowTitle: "cuirq File Manager"
    property int windowWidth: 1024
    property int windowHeight: 700
    property color windowColor: "transparent"
    // ... content
}
```

**Key implementation details:**

- `g_window` (`QQuickWindow*`) is created once in `load_qml()` and never destroyed until shutdown
- `g_rootItem` (`QQuickItem*`) is the current QML root, parented to `g_window->contentItem()`
- Resize connections use `g_window` as receiver with lambdas reading global `g_rootItem` — no disconnect/reconnect needed on reload
- macOS native setup (titlebar, vibrancy) survives reload because the window survives — `reapplyMacOSSetup()` was removed entirely
- If new QML fails to load, old content stays visible (old root item still renders even after engine deletion)
- Uses `QQmlEngine` + `QQmlComponent` instead of `QQmlApplicationEngine` for manual window management

**Files changed:**
- `qt_engine.cpp` — persistent window, `QQmlEngine` instead of `QQmlApplicationEngine`, removed macOS state tracking vars and `reapplyMacOSSetup()`
- `qmlwatcher.cpp` — swap content items instead of window destruction
- `file_manager.qml`, `counter.qml` — `ApplicationWindow` → `Item` with window properties

### 3. Engine-per-reload (generational approach)

Each reload creates a new `QQmlEngine` with a fresh component tree. Long-lived C++ objects (`StateObject`, `JvmListModel`, `PanamaSignalForwarder`, `StateNotifier`) are parented to `g_app` and re-registered as context properties on each new engine via `setupEngine()`.

- `pragma Singleton` works naturally — each new engine loads singletons from scratch
- shell.qml and Loader eliminated — examples are self-contained `Item` files
- Models survive reload — `JvmListModel` instances persist, QML delegates reconnect automatically
- State is re-emitted after reload via `StateObject::reemitAll()`

### 4. QML error interception

QML engine warnings are intercepted via `QQmlEngine::warnings` signal in `setupEngine()` and routed to the reload popup:

```cpp
QObject::connect(g_engine, &QQmlEngine::warnings,
    [](const QList<QQmlError>& warnings) {
        for (const auto& error : warnings) {
            auto msg = QString("%1:%2:%3: %4")
                .arg(error.url().toLocalFile())
                .arg(error.line()).arg(error.column())
                .arg(error.description());
            qWarning().noquote() << msg;
            if (g_reloadPopup) g_reloadPopup->appendWarning(msg);
        }
    });
```

### 5. Reload popup (injected overlay)

**Implementation:** The popup is a `QQuickItem` (not a separate window) injected directly into `g_window->contentItem()` with `z=9999` — inspired by shadow-cljs's approach of injecting instrumentation into the page DOM. This eliminates system window borders/shadows and simplifies positioning.

The popup uses its own `QQmlEngine` so it survives main engine destruction. The QML is loaded from disk first (`CUIRQ_SOURCE_DIR/cpp/qml/ReloadPopup.qml`) for dev editability, falling back to qrc for production.

**Behavior:**
- **Success:** Green pill with spinning refresh icon (Canvas-drawn, two arcs with tangent arrowheads) + "Reloaded" text. Auto-dismiss after 1.5s with fade-out + slide animation.
- **Error:** Red panel with blockquote-styled error lines (accent bar + background, per-corner radius). Copy button (Phosphor-style Canvas icon) with `QGuiApplication::clipboard()`. Stays visible until next file change triggers reload.
- **Animations:** C++ emits `showAnimationRequested`/`hideAnimationRequested` signals. QML runs fade + slide (200ms appear, 150ms disappear). On `showAnimationRequested`: stop any disappear animation, restart appear. Content opacity 0 when hidden via `visible: opacity > 0`.

**Key design decisions:**
- Item injection vs separate Window — no system borders, no Cocoa hacks, naturally positioned via anchors, scales to multi-window (see ADR-007)
- Separate QQmlEngine — survives main engine reload, immune to QML errors in user code
- `CUIRQ_SOURCE_DIR` compile definition for disk-first QML loading (`applicationDirPath()` points to JVM binary, not project root)

### 6. Compile-time exclusion of dev-only code

All reload infrastructure is guarded behind `CUIRQ_DEV_RELOAD` CMake option:

```cmake
option(CUIRQ_DEV_RELOAD "Enable QML hot-reload support (dev only)" ON)

if(CUIRQ_DEV_RELOAD)
    target_compile_definitions(qmlbridge PRIVATE
        CUIRQ_DEV_RELOAD
        CUIRQ_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
    )
    target_sources(qmlbridge PRIVATE qmlwatcher.cpp reload_popup.cpp)
else()
    set_source_files_properties(cpp/qmlwatcher.h cpp/reload_popup.h
        PROPERTIES SKIP_AUTOMOC ON)
endif()
```

**Note:** Switching `CUIRQ_DEV_RELOAD` ON↔OFF requires clean build (`rm -rf build`) — AUTOMOC caches stale MOC state.

## Consequences

### Positive
- `pragma Singleton` works naturally — standard QML, standard tooling
- shell.qml and Loader eliminated — examples are self-contained `Item` files
- Zero flicker on reload — native window persists, no yabai repositioning
- macOS native setup (titlebar, vibrancy) survives reload without re-application
- Failed reload preserves old UI — not a blank screen
- Visual reload feedback catches QML errors immediately (shadow-cljs style)
- Popup has no system borders — injected as Item, not as separate OS window
- QML engine warnings surfaced in-app with copy-to-clipboard
- No Qt private APIs required (unlike ADR-005)
- Zero reload overhead in production — compile-time exclusion

### Negative
- New `QQmlEngine` per reload is heavier than `clearComponentCache()` — but sub-second, dev-only
- QML root must be `Item` not `ApplicationWindow` — window properties declared as Item properties
- Two engines briefly coexist during reload (main + popup permanently)
- `#ifdef` guards add conditional complexity to `qt_engine.cpp`

### Lessons Learned
- `QObject::disconnect(sender, signal, nullptr, nullptr)` disconnects ALL receivers including Qt internals — breaks scene graph. Use specific receiver or persistent connections.
- Popup loaded from `qrc:` doesn't update without rebuild. Disk-first loading with `CUIRQ_SOURCE_DIR` compile definition solved this.
- `QCoreApplication::applicationDirPath()` returns JVM binary path, not project root — unusable for finding project files.
- QML `clip: true` clips to bounding rectangle, NOT rounded corners. Per-corner radius (`topLeftRadius` etc., Qt 6.7+) with sibling rectangles solves blockquote styling.
- Animation binding conflicts: declarative bindings (`opacity: shown ? 1 : 0`) conflict with explicit `NumberAnimation` — use only one approach.

## References

- quickshell source: `src/core/generation.cpp`, `src/core/rootwrapper.cpp`, `src/window/proxywindow.cpp`
- [shadow-cljs HUD](https://shadow-cljs.github.io/docs/UsersGuide.html#_hud) — in-browser error overlay, inspiration for injected popup
- ADR-005: QML Hot Reload via File I/O Interception (superseded)
- ADR-007: Multi-Window Support (future, builds on injected popup pattern)
