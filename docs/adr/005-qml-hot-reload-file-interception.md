# ADR-005: QML Hot Reload via File I/O Interception

## Status
Superseded by [ADR-006](006-hot-reload-improvements.md)

## Context

cuirq currently has a working hot-reload mechanism for QML files during development. When a `.qml` file changes on disk, the UI updates automatically without restarting the application.

### Current Implementation

The reload system has three layers:

1. **`QmlWatcher`** (C++, `cpp/qmlwatcher.cpp`) — uses `QFileSystemWatcher` (FSEvents on macOS) to detect file changes, with a debounce timer to batch rapid saves.

2. **Shell + Loader pattern** (`qml/shell.qml`) — the `ApplicationWindow` is loaded once and never destroyed. Content is loaded via a `Loader` component bound to a `_cuirq_content_url` context property.

3. **Reload sequence** — on file change:
   ```
   _cuirq_content_url = QUrl()           // unload content
   QTimer::singleShot(0, ...)            // yield to event loop
     → engine->clearComponentCache()     // purge cached QML
     → _cuirq_content_url = originalUrl  // reload content
   ```

This works reliably but has structural constraints:
- **Loader indirection** — all content must go through a `Loader`, adding a level of nesting that affects anchoring (e.g., `anchors.topMargin: -_cuirq_titlebar_height`)
- **Shell is static** — changes to `shell.qml` itself require a full app restart
- **State loss** — scroll positions, text input, expansion state, and animation progress are lost on every reload because the entire content tree is destroyed
- **Context property coupling** — `_cuirq_content_url` is a framework-level detail that leaks into the QML architecture

### Qt's QML Preview Approach

Qt's `qmlpreview` tool (part of `qtdeclarative`) takes a different approach: it intercepts file I/O at the `QAbstractFileEngine` level, so the QML engine transparently reads modified files from memory rather than from disk.

Key components (from Qt source `src/plugins/qmltooling/qmldbg_preview/`):

- **`QQmlPreviewFileEngine`** — a custom `QAbstractFileEngine` that intercepts all QML/JS file reads. When a file has been updated, it serves the new contents from an in-memory store. It marks intercepted files as always "newer" than cached versions, forcing the QML engine to recompile rather than use bytecode cache (`.qmlc`).

- **`QQmlPreviewHandler`** — handles the reload: `clearComponentCache()` → delete all created QML objects → create new `QQmlComponent` → instantiate fresh object tree.

- **`QQmlPreviewFileLoader`** — background thread that loads files from disk and stores them in the in-memory map.

The reload itself is still destructive (full tree recreation), but the file interception is the interesting part — it makes the mechanism transparent to the QML engine, requiring no Loader, no context properties, and no special QML structure.

## Decision

Implement file I/O interception as an alternative reload backend in `libqmlbridge`, replacing the Loader-based approach. The shell+content split is eliminated — the application's root QML file is loaded directly by `QQmlApplicationEngine`.

### Architecture

```
Current:
  QQmlApplicationEngine → shell.qml → Loader → content.qml
  QmlWatcher detects change → empty Loader → clearCache → reload Loader

Proposed:
  QQmlApplicationEngine → file_manager.qml (directly)
  QmlWatcher detects change → FileOverride intercepts I/O → clearCache → reload root
```

### Implementation

#### 1. `QmlFileOverride` — file I/O interceptor

A custom `QAbstractFileEngineHandler` that:
- Maintains an in-memory `QHash<QString, QByteArray>` of file contents
- When a file is in the override map, returns a custom `QAbstractFileEngine` that serves from memory
- When a file is not overridden, returns `nullptr` (falls through to default file engine)
- Reports overridden files as always modified (forces QML engine to skip `.qmlc` cache)

```cpp
class QmlFileOverride : public QAbstractFileEngineHandler {
public:
    QAbstractFileEngine* create(const QString& fileName) const override {
        if (m_overrides.contains(fileName))
            return new QmlMemoryFileEngine(fileName, m_overrides[fileName]);
        return nullptr;  // use default file engine
    }

    void setFileContents(const QString& path, const QByteArray& contents);
    void removeOverride(const QString& path);

private:
    QHash<QString, QByteArray> m_overrides;
};
```

Registration: `QAbstractFileEngineHandler` self-registers on construction (Qt manages a global handler list). Instantiate before the first QML load.

#### 2. Modified reload sequence

```
File change detected (FSEvents)
  → QmlWatcher reads new file contents from disk
  → QmlFileOverride::setFileContents(path, contents)
  → engine->clearComponentCache()
  → Delete root QML objects
  → engine->load(rootUrl)  // QML engine reads from override, not disk
```

No Loader. No `_cuirq_content_url`. The QML engine believes it's reading from disk but gets the updated contents.

#### 3. Remove shell.qml

The `ApplicationWindow` moves into each example's root QML file. The shell was only needed to provide a stable container for the Loader; with file interception, the engine reloads the root directly.

Before:
```
qml/shell.qml          → ApplicationWindow + Loader
examples/.../main.qml   → content loaded by Loader
```

After:
```
examples/.../main.qml   → ApplicationWindow + content (self-contained)
```

#### 4. Scope

- **Dev only** — file interception is only active when `QmlWatcher` is enabled (hot-reload mode). Production bundles load QML normally.
- **All files** — not just the root; any QML/JS file change triggers override + reload. Import resolution works naturally since the file engine intercepts by absolute path.

### What This Enables

- **Direct QML loading** — no Loader nesting, no context property indirection
- **Shell changes reload** — modifying the root `ApplicationWindow` (title, menubar, window flags) applies without restart
- **Simpler QML** — examples don't need to know about the reload mechanism; no `_cuirq_content_url`, no shell/content split
- **Singleton reload** — `pragma Singleton` files can be reloaded (currently impossible with Loader approach since singletons are cached per-engine)

### What This Does NOT Solve

- **State loss** — still full tree destruction on reload (same as Qt's qmlpreview). Scroll positions, text input, focus state are lost. Solving this would require either:
  - QML state serialization/restoration (complex, fragile)
  - Incremental component replacement (Qt doesn't support this)
  - External state (already partially done — our `StateObject` survives reload)
- **C++ object lifetime** — vibrancy effects, titlebar customization, and other Cocoa-level setup re-execute on each reload, potentially causing flicker

## Consequences

### Positive
- Eliminates `shell.qml` and the `Loader` indirection pattern
- Examples become self-contained — each root QML file is a complete `ApplicationWindow`
- No framework-specific context properties leak into QML (`_cuirq_content_url`)
- Singleton QML files (`Theme.qml` with `pragma Singleton`) can be hot-reloaded
- Smaller API surface in `libqmlbridge` — no `_cuirq_content_url` management

### Negative
- `QAbstractFileEngine` is a Qt internal API (not private, but rarely used outside Qt itself) — may change between Qt versions
- Full tree destruction means brief visual flash on reload (same as current approach, but now includes the window chrome too)
- Cocoa vibrancy/titlebar effects reinstall on each reload — may need deferred setup or guard against duplicate installation
- More C++ code in the bridge (file engine implementation ~150 lines)

### Risks
- `QAbstractFileEngineHandler` registration is process-global — if multiple engines exist, all are affected. Currently we have one engine, so this is fine.
- Qt may deprecate `QAbstractFileEngine` in favor of newer I/O abstractions. The `qmldbg_preview` plugin uses it in Qt 6.10, so it's stable for now.
- `.qmlc` bytecode cache interaction — need to ensure overridden files always bypass cache. Qt's preview implementation handles this by reporting a future modification time.

## Alternatives Considered

### Keep current Loader approach
Works today. Main downsides are the indirection and inability to reload `shell.qml` or singletons. If those limitations are acceptable, no change needed.

### Use `qmlpreview` directly
Not viable — requires `QT_QML_DEBUG` compile flag, launches the app itself (can't attach to our Clojure→Panama→C++ startup), and `qmlimportscanner` is broken in nix (hardcoded path lookup). See investigation notes in MEMORY.md.

### QML Live / third-party tools
[QML Live](https://doc.qt.io/QmlLive/) is a more sophisticated tool but has the same `QT_QML_DEBUG` requirement and assumes a Qt Creator workflow. Our CLI-first development loop doesn't fit.

## References

- Qt source: `qtdeclarative/src/plugins/qmltooling/qmldbg_preview/qqmlpreviewfileengine.cpp`
- Qt source: `qtdeclarative/src/plugins/qmltooling/qmldbg_preview/qqmlpreviewhandler.cpp`
- [Qt QAbstractFileEngineHandler docs](https://doc.qt.io/qt-6/qabstractfileenginehandler.html)
- [Qt QML Preview tool](https://doc.qt.io/qt-6/qtqml-tooling-qmlpreview.html)
- [Debugging QML Applications](https://doc.qt.io/qt-6/qtquick-debugging.html)
