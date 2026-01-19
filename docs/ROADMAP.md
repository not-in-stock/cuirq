# cuirq Roadmap

## Current Status: POC

### Implemented Features

- **Hot-reload** - QML file watching with automatic reload
- **REPL-driven state management** - Atom-based state with automatic UI sync
- **Reactive property updates** - Clojure → QML data binding
- **Signal handling** - QML → Clojure callbacks
- **List models** - Dynamic data binding for ListView/GridView
- **nREPL server** - Editor integration (Emacs, VSCode, IntelliJ)
- **GraalVM Native Image** - Support for native builds

## Planned Features

This roadmap outlines planned optimizations and features for production-ready desktop applications.

### Target Use Cases

1. **File Managers** - Fast list updates, drag & drop, hierarchical tree view (10K+ items)
2. **Node Editors** - Canvas with draggable nodes, real-time updates (100+ nodes @ 60 FPS)
3. **Graphics Editors** - Custom painting, tool palettes, undo/redo (60 FPS drawing)

---

## Phase 1: Performance Optimizations

### 1.1 Differential State Updates

**Problem:** Currently all properties sync on every state change, even if only one property changed.

**Solution:** Track last synced state and only update changed properties via JNI.

**Benefits:**
- 10-50x faster state updates
- Reduces JNI overhead dramatically
- No API changes required

**Effort:** ~2 hours
**Impact:** HIGH

---

### 1.2 Incremental List Model Updates

**Problem:** `setJsonData()` calls `beginResetModel()` which recreates all delegates, losing scroll position and selection.

**Solution:** Add granular operations:

```cpp
// New methods
void insertItem(int index, const QVariantMap& item);
void updateItem(int index, const QVariantMap& item);
void removeItem(int index);
void moveItem(int from, int to);
```

**Benefits:**
- Preserves scroll position and selection
- Smooth animations for add/remove/move
- 10-100x faster for large lists
- Only changed delegates update

**Impact:** VERY HIGH

---

### 1.3 Efficient Signal Data Transfer

**Problem:** Currently pass data as JSON strings from QML to Clojure.

**Solution:** Add direct object passing:

```cpp
Q_INVOKABLE void emitSignalWithData(const QString& signalName,
                                     const QVariantMap& data);
```

**Benefits:**
- Cleaner QML API (no `JSON.stringify`)
- Faster (C++ JSON encoding)
- Type preservation
- Backward compatible

**Effort:** ~2 hours
**Impact:** MEDIUM

---

### 1.4 Component-Level Hot Reload

**Problem:** QmlWatcher only monitors main QML file, not imported components.

**Solution:** Recursively watch component directories and parse imports.

**Benefits:**
- Auto-detects component changes
- Works with nested imports
- Supports component libraries

**Effort:** ~4 hours
**Impact:** HIGH

---

## Phase 2: Developer Experience

### 2.1 High-Level Framework API

**Current:** ~50 lines of boilerplate per app.

**Solution:** Zero-boilerplate macro:

```clojure
(defapp my-app
  {:main "ui/counter.qml"
   :state {:count 0}
   :handlers {:increment #(update % :count inc)}
   :window {:title "My App" :width 800 :height 600}
   :hot-reload true
   :nrepl {:port 7888}})

(defn -main [& args]
  (my-app-start!))
```

**Benefits:**
- 90% less boilerplate
- Declarative configuration
- Convention over configuration

**Impact:** VERY HIGH

---

### 2.2 Re-frame Style Event System

**Solution:** Separate pure state transformations from side effects:

**Benefits:**
- Clear separation of concerns
- Testable (pure functions)
- Composable side effects
- Familiar to re-frame users

**Impact:** MEDIUM-HIGH

---

### 2.3 Subscriptions for Derived State

**Solution:** Memoized derived state:

**Benefits:**
- Derived state in one place
- Memoization/caching built-in
- Clean separation from events

**Impact:** MEDIUM

---

## Phase 3: Advanced QML Features

### 3.1 Built-in Animation Helpers

**Solution:** Pre-built QML animation components:

```qml
ListView {
    model: items

    // One-liner for professional animations
    add: QmlClj.Animations.listTransition().add
    remove: QmlClj.Animations.listTransition().remove
    displaced: QmlClj.Animations.listTransition().displaced
}
```

**Effort:** ~6 hours
**Impact:** MEDIUM (visual polish)

---

### 3.2 Tree Model Support

**For:** Hierarchical file browser, nested data structures.

**Solution:** Implement `QAbstractItemModel` with parent/child relationships:

```cpp
class JvmTreeModel : public QAbstractItemModel {
    Q_INVOKABLE void setJsonData(const QString& jsonData);
    Q_INVOKABLE void insertChild(const QString& parentId, int index, ...);
    Q_INVOKABLE void removeChild(const QString& parentId, int index);
};
```

**Impact:** HIGH (for file manager)

---

### 3.3 Canvas Integration

**For:** Graphics editor, custom painting.

**Solution:** Custom `QQuickPaintedItem` for drawing:

```cpp
class QmlCanvas : public QQuickPaintedItem {
    Q_INVOKABLE void startStroke(qreal x, qreal y);
    Q_INVOKABLE void addStrokePoint(qreal x, qreal y);
    Q_INVOKABLE void endStroke();
    Q_INVOKABLE void undo();
    Q_INVOKABLE void redo();
};
```

**Effort:** ~8 hours
**Impact:** HIGH (for graphics editor)

## Future Considerations

Beyond the initial roadmap, potential areas for exploration:

- **MessagePack** - Binary serialization if JSON becomes bottleneck
- **WebAssembly** - For compute-intensive tasks (image processing)
- **Multi-threading** - Background file scanning for file manager
- **Native OS Integration** - File notifications, system tray, etc.

