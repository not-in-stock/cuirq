# ADR-006: Hot Reload Improvements

## Status
Proposed

## Context

cuirq has a working QML hot-reload system (shell.qml + Loader + QmlWatcher). ADR-005 explored replacing it with file I/O interception via `QAbstractFileEngineHandler`. A spike validated that the interception works, but revealed that any approach that destroys the `QQuickWindow` causes visible flicker on macOS — an unavoidable limitation of full window recreation.

Investigation of [quickshell](https://git.outfoxxed.me/quickshell/quickshell.git), a Qt/QML shell framework with production-quality hot-reload, revealed a more productive direction: instead of changing *how* files are intercepted, improve *what happens during reload*.

### Current Limitations

1. **Singleton reload impossible** — `pragma Singleton` types (e.g. `Theme.qml`) are cached per-engine. `clearComponentCache()` does not evict singletons. The current workaround loads Theme.qml manually as a context property, losing QML tooling support (no autocompletion, no type checking).

2. **Truncate-then-write race** — editors like VSCode save in two steps: truncate to 0 bytes, then write new content. If `QFileSystemWatcher` fires between the two steps, we reload a 0-byte file. The 150ms debounce timer *usually* avoids this, but it's not guaranteed.

3. **Atomic save loses file watch** — editors that use atomic saves (write temp file, rename over original) cause FSEvents to stop tracking the original path. We re-add the path in `onFileChanged`, but rely on FSEvents firing for the original path at all, which is not guaranteed for all editors.

4. **No reload feedback** — when QML has a syntax error, the Loader silently fails. The developer must check the terminal for errors. There's no visual indication of reload success or failure.

### Quickshell's Architecture

Quickshell solves these problems with a **generational** approach:

- Each reload creates a **new `QQmlEngine`** with a fresh component tree
- The `QQuickWindow` is **transferred** from the old generation to the new one (never destroyed)
- `Reloadable` objects receive `onReload(oldInstance)` to transfer state
- On compilation error, the old generation stays alive and an error popup is shown
- File watching includes parent directories to catch atomic saves
- Zero-size file events are ignored

## Decision

Improve the existing hot-reload system with six changes, ordered by implementation dependency:

### 1. Robust file watching

**Problem:** Truncate-then-write and atomic saves can trigger false or missed reloads.

**Changes to `QmlWatcher`:**

a) **Ignore zero-size file events.** When `onFileChanged` fires, check `QFileInfo(path).size()`. If 0, skip — the real write hasn't happened yet. The directory watcher or a subsequent file event will catch the completed write.

```cpp
void QmlWatcher::onFileChanged(const QString& path) {
    if (!m_autoReload || !path.endsWith(".qml")) return;

    // Ignore truncate step of truncate-then-write editors (VSCode)
    QFileInfo fi(path);
    if (fi.isFile() && fi.size() == 0) return;

    if (!m_watcher->files().contains(path))
        m_watcher->addPath(path);
    m_debounce->start();
}
```

b) **Track deleted-then-recreated files via directory events.** When a watched file disappears (atomic save removes it), record it. When the directory changes, check if any recorded files have reappeared.

```cpp
void QmlWatcher::onFileChanged(const QString& path) {
    // ...existing checks...
    if (!m_watcher->files().contains(path)) {
        m_deletedFiles.append(path);  // track for directory-based recovery
        m_watcher->addPath(path);     // try re-add (may fail if file doesn't exist yet)
    }
    m_debounce->start();
}

void QmlWatcher::onDirectoryChanged(const QString& path) {
    // Check if any tracked deleted files have reappeared
    for (auto it = m_deletedFiles.begin(); it != m_deletedFiles.end(); ) {
        if (QFileInfo(*it).exists()) {
            m_watcher->addPath(*it);
            it = m_deletedFiles.erase(it);
            m_debounce->start();
        } else {
            ++it;
        }
    }
    // ...existing new/removed file scanning...
}
```

### 2. Engine-per-reload (generational approach)

**Problem:** `clearComponentCache()` doesn't evict singletons. Theme.qml must be loaded as a context property hack.

**Solution:** Create a new `QQmlEngine` on each reload instead of reusing one.

**Reload sequence:**

```
File change detected
  → QmlWatcher creates new QQmlApplicationEngine
  → Re-register context properties (state, stateNotifier, signalForwarder, models)
  → Load root QML via QQmlComponent on the new engine
  → Transfer QQuickWindow from old engine to new component tree
  → Destroy old engine
```

**Key details:**

- **Context properties** are all C++ objects that outlive the engine (`StateObject`, `JvmListModel`, `PanamaSignalForwarder`). They are re-registered on the new engine's root context. Their parent is set to the application, not the engine.

- **Window transfer.** The current `ApplicationWindow` (a `QQuickWindow`) is detached from the old QML tree and attached to the new one. The new root component's `contentItem` is reparented into the existing window. This is the technique quickshell uses to avoid flicker — the native window is never destroyed.

- **shell.qml is eliminated.** With a new engine per reload, there's no need for a stable shell — the engine itself provides the stable container. The root QML file (e.g. `file_manager.qml`) becomes a self-contained `ApplicationWindow`. The Loader indirection and `_cuirq_content_url` are removed.

- **Singletons work naturally.** Each new engine loads singletons from scratch. `pragma Singleton` in `Theme.qml` works with standard QML tooling. The `loadTheme()` hack in QmlWatcher is removed.

- **Models survive.** `JvmListModel` instances are C++ objects owned by the application. They are registered as context properties on each new engine. QML delegates reconnect to the model automatically.

**Impact on `qt_engine.cpp`:**

The `initialize()` function creates long-lived objects (forwarder, state, models) parented to `g_app` instead of `g_engine`. A new `setupEngine()` function handles engine creation and context property registration, called both at startup and on reload.

```cpp
static void setupEngine() {
    g_engine = new QQmlApplicationEngine();
    auto* ctx = g_engine->rootContext();
    ctx->setContextProperty("signalForwarder", g_signalForwarder);
    ctx->setContextProperty("state", g_state);
    ctx->setContextProperty("stateNotifier", g_stateNotifier);
    for (auto it = g_models.begin(); it != g_models.end(); ++it)
        ctx->setContextProperty(it.key(), it.value());
    // import paths, etc.
}
```

### 3. Reload error popup

**Problem:** QML syntax errors fail silently — the developer must check the terminal.

**Solution:** Show an in-app overlay when reload fails, inspired by quickshell's `ReloadPopup` and shadow-cljs's HUD.

**Behavior:**

- **On successful reload:** brief green flash or "Reloaded" toast (auto-dismiss after 1s)
- **On failed reload:** red overlay with error message, stays until next successful reload
- **Old UI stays visible** underneath the error overlay — the previous working state is preserved (this is natural with the generational approach: on error, the old engine stays alive)

**Implementation:**

The popup is a separate, minimal `QQmlEngine` + `QQuickWindow` overlay — independent of the application's engine. This ensures it can display even when the main engine is in a broken state.

```cpp
// Simplified — ReloadPopup manages its own mini-engine
class ReloadPopup : public QObject {
    Q_OBJECT
public:
    void showSuccess();
    void showError(const QString& errorText);
    void hide();
private:
    QQmlEngine* m_popupEngine = nullptr;
    QQuickWindow* m_popupWindow = nullptr;
};
```

The popup QML is embedded as a resource (qrc) so it doesn't depend on the watched file system.

**Visual design:**

```
┌──────────────────────────────────────────┐
│  ✕  Reload failed                        │
│                                          │
│  file_manager.qml:42:5                   │
│  Expected token '}'                      │
│                                          │
└──────────────────────────────────────────┘
```

- Semi-transparent dark background over the top portion of the window
- Monospace error text
- Click to dismiss (or auto-dismiss on next successful reload)
- Matches the pattern from shadow-cljs: errors are visible in-app, not buried in terminal output

### 4. QML error interception

**Problem:** QML binding errors, property assignment errors, and runtime warnings go to stderr and are easy to miss among other log output.

**Solution:** Intercept QML engine warnings via `QQmlEngine::warnings` signal and route them to the reload popup.

Quickshell uses two complementary mechanisms:
- `QQmlEngine::warnings` signal — catches QML-specific errors with file:line:column
- `qInstallMessageHandler()` — catches all Qt log messages including `console.log` from QML

For cuirq, the `QQmlEngine::warnings` connection is the essential piece — it provides structured error data (`QQmlError` with URL, line, column, description) that feeds directly into the reload popup.

```cpp
// In setupEngine(), after creating the engine:
g_engine->setOutputWarningsToStandardError(false);
QObject::connect(g_engine, &QQmlEngine::warnings,
    [](const QList<QQmlError>& warnings) {
        for (const auto& error : warnings) {
            QString msg = QString("%1:%2:%3: %4")
                .arg(error.url().toLocalFile())
                .arg(error.line())
                .arg(error.column())
                .arg(error.description());
            qWarning().noquote() << msg;
            // Route to reload popup if visible
            if (g_reloadPopup)
                g_reloadPopup->appendWarning(msg);
        }
    });
```

This captures:
- QML binding errors (e.g. `TypeError: Cannot read property of undefined`)
- Property assignment type mismatches
- Missing required properties
- Import resolution failures during reload

Runtime `console.log`/`console.warn` from QML continue to go through Qt's standard logging. A full `qInstallMessageHandler()` can be added later if needed, but is not required for the reload workflow.

### 5. Compile-time exclusion of dev-only code

**Problem:** Hot-reload infrastructure (file watcher, reload popup, engine recreation) is only needed during development. Production bundles (native-image + macOS .app) should not carry this code.

**Solution:** Guard all reload-related code behind a CMake option and compile definition.

```cmake
option(CUIRQ_DEV_RELOAD "Enable QML hot-reload support (dev only)" ON)

if(CUIRQ_DEV_RELOAD)
    target_compile_definitions(qmlbridge PRIVATE CUIRQ_DEV_RELOAD)
    target_sources(qmlbridge PRIVATE
        qmlwatcher.cpp
        reload_popup.cpp
    )
endif()
```

In `qt_engine.cpp`, all reload-related code is wrapped:

```cpp
#ifdef CUIRQ_DEV_RELOAD
#include "qmlwatcher.h"
#include "reload_popup.h"
static QmlWatcher* g_qmlWatcher = nullptr;
static ReloadPopup* g_reloadPopup = nullptr;
#endif

bool initialize(int argc, char* argv[]) {
    // ...core setup (always present)...

#ifdef CUIRQ_DEV_RELOAD
    g_qmlWatcher = new QmlWatcher(g_engine, g_app);
    g_reloadPopup = new ReloadPopup(g_app);
#endif
}
```

**What is excluded in production (`-DCUIRQ_DEV_RELOAD=OFF`):**
- `QmlWatcher` — file watching, debounce, reload orchestration
- `ReloadPopup` — popup engine, QML resource, overlay window
- `QFileSystemWatcher` — no file system monitoring overhead
- Engine recreation logic — `setupEngine()` is called once at startup, never again
- `QQmlEngine::warnings` interception — errors go to stderr as normal

**What remains in production:**
- `setupEngine()` — single call, creates engine + registers context properties
- Core C++ objects — `StateObject`, `JvmListModel`, `PanamaSignalForwarder`
- QML loading — `load_qml()` loads the root QML file directly (no shell.qml, no Loader)

**Build integration:**

The bundle script (`scripts/bundle.bb`) passes `-DCUIRQ_DEV_RELOAD=OFF` when building for distribution:

```clojure
(defn- cmake-build! [src-dir build-dir & {:keys [dev-reload] :or {dev-reload false}}]
  (p/shell "cmake" "-B" build-dir "-S" src-dir "-G" "Ninja"
           (str "-DCUIRQ_DEV_RELOAD=" (if dev-reload "ON" "OFF")))
  (p/shell "cmake" "--build" build-dir))
```

Development builds (`bb build`, `bb run`, `bb dev`) default to `ON`. This matches quickshell's philosophy of runtime control during development, with the option to strip completely for distribution.

### 6. Supersede ADR-005

ADR-005 proposed file I/O interception via `QAbstractFileEngineHandler` as a way to eliminate the Loader. The generational approach in this ADR achieves the same goals (no Loader, no shell.qml, singleton reload) without using Qt private APIs. ADR-005's status should be updated to **Superseded by ADR-006**.

## Consequences

### Positive
- `pragma Singleton` works naturally — standard QML, standard tooling
- shell.qml and Loader eliminated — examples are self-contained `ApplicationWindow` files
- `_cuirq_content_url` context property removed
- Robust file watching handles all editor save strategies
- Visual reload feedback catches QML errors immediately, like shadow-cljs HUD
- QML engine warnings surfaced in-app, not buried in terminal
- Old UI preserved on error — not a blank screen
- No Qt private APIs required (unlike ADR-005's `QAbstractFileEngine`)
- Zero reload overhead in production — compile-time exclusion removes all dev code

### Negative
- New `QQmlEngine` per reload is heavier than `clearComponentCache()` — but this is dev-only, sub-second overhead is acceptable
- Window transfer requires careful handling of Cocoa-level state (vibrancy, titlebar customization) — may need to re-apply after transfer
- Reload popup adds ~200 lines of C++ and a QML resource
- More complex reload path — generation lifecycle must be carefully managed to avoid leaks
- `#ifdef` guards add conditional complexity to `qt_engine.cpp`

### Risks
- Window transfer between engines is not a documented Qt use case. Quickshell proves it works, but it relies on `QQuickWindow` being a plain `QWindow` wrapper internally. A future Qt version could break this.
- Cocoa effects (vibrancy, hidden titlebar) are tied to the native `NSWindow`. Since the window is reused, these should survive — but need testing.
- Two `QQmlEngine` instances briefly coexist during reload. Memory-constrained environments (unlikely for desktop dev) could spike.

## Implementation Order

1. **Robust file watching** (standalone improvement, no architecture change)
2. **Compile-time flag** (`CUIRQ_DEV_RELOAD` option, wrap existing code)
3. **Engine-per-reload** (enables singleton reload, removes shell.qml)
4. **QML error interception** (depends on engine-per-reload for `QQmlEngine::warnings` reconnection)
5. **Reload popup** (depends on error interception for content, engine-per-reload for error recovery)

## References

- quickshell source: `src/core/generation.cpp`, `src/core/rootwrapper.cpp`, `src/window/proxywindow.cpp`
- quickshell reload system: `src/core/reload.hpp`, `src/core/reload.cpp`
- quickshell logging: `src/core/logging.cpp` — `qInstallMessageHandler()`, `QQmlEngine::warnings` interception
- [shadow-cljs HUD](https://shadow-cljs.github.io/docs/UsersGuide.html#_hud) — in-browser error overlay for ClojureScript
- [Qt QQmlEngine::warnings](https://doc.qt.io/qt-6/qqmlengine.html#warnings) — signal for QML runtime errors
- ADR-005: QML Hot Reload via File I/O Interception (superseded)
- Spike: `spike/file-intercept/` — validated `QAbstractFileEngineHandler` approach, demonstrated flicker limitation
