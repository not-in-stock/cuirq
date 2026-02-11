# ADR-003: Dedicated Thread for Qt/Panama Calls

## Status
Partially Implemented

## Context

cuirq bridges Clojure (JVM) and Qt/QML (C++) via Panama FFM. Qt GUI operations must happen on the main thread (the thread that created `QGuiApplication`). Currently, Panama downcalls to Qt can originate from arbitrary JVM threads:

- **nREPL thread** — when evaluating `(state/update-state! ...)` from editor
- **Signal handler thread** — upcalls from Qt fire `PanamaBridge.onSignal()`, which invokes Clojure handlers that may call back into Qt
- **Virtual threads** — future I/O operations completing on virtual threads
- **Application threads** — `(cuirq/exec!)` blocks the main thread in `QGuiApplication::exec()`

### Current Mitigation

The C++ side handles thread marshaling per-function:
- `StateObject::setProp()` uses `QQmlPropertyMap::insert()` which internally posts to the Qt event loop via `QueuedConnection`
- macOS `QTimer::singleShot(0, ...)` defers Cocoa-specific calls
- `set_model_data()`, `update_model_data()`, `clear_model()` in `qt_engine.cpp` check `QThread::currentThread() != model->thread()` and marshal via `QMetaObject::invokeMethod(..., Qt::QueuedConnection)` when needed (added 2026-02-11)

This ad-hoc approach works but duplicates the same thread-check pattern in every function. The centralized dispatch queue below would replace all per-function checks with a single mechanism.

### Problems

1. **Thread safety violations** — `QAbstractListModel` methods (`beginResetModel`, `beginInsertRows`, `dataChanged`) must be called from the thread that owns the model (Qt main thread). Calling from nREPL or signal handler threads causes undefined behavior.
2. **Inconsistent marshalling** — some calls are safely marshalled, others are not. Developer must know which are safe.
3. **Hard to debug** — thread violations may work 99% of the time but cause rare crashes or rendering glitches.
4. **`-XstartOnFirstThread`** — on macOS, the JVM main thread becomes the Qt thread. `cuirq/exec!` blocks it. All subsequent Clojure code runs on other threads.

## Decision

Introduce a **Qt dispatch queue** pattern: all Panama downcalls to Qt are serialized through a single mechanism that ensures execution on the Qt main thread.

### Architecture

```
JVM Threads                          Qt Main Thread
─────────────                        ──────────────
nREPL          ─┐
Signal handler ─┤──▶ qt-invoke! ──▶ QMetaObject::invokeMethod() ──▶ Qt API
Virtual thread ─┤                   (QueuedConnection)
App thread     ─┘
```

### Implementation

#### 1. C++ side: `cuirq_invoke_on_qt_thread`

New extern "C" function that accepts a callback and executes it on the Qt main thread:

```cpp
// panama_api.h
extern "C" void cuirq_invoke_on_qt_thread(void (*fn)(void* ctx), void* ctx);
```

```cpp
// qt_engine.cpp
void invoke_on_qt_thread(void (*fn)(void* ctx), void* ctx) {
    if (QThread::currentThread() == g_app->thread()) {
        // Already on Qt thread — execute directly
        fn(ctx);
    } else {
        // Post to Qt event loop
        QMetaObject::invokeMethod(g_app, [fn, ctx]() {
            fn(ctx);
        }, Qt::QueuedConnection);
    }
}
```

#### 2. Java side: `QtThread` dispatcher

```java
// java/qml/QtThread.java
public class QtThread {
    private static final MethodHandle INVOKE_ON_QT;

    static {
        INVOKE_ON_QT = downcall("cuirq_invoke_on_qt_thread",
            FunctionDescriptor.ofVoid(ADDRESS, ADDRESS));
    }

    /**
     * Run a Runnable on the Qt main thread.
     * If already on Qt thread, executes synchronously.
     */
    public static void invoke(Runnable task) {
        // Create upcall stub for this task
        // ... (implementation details)
    }
}
```

#### 3. Clojure side: `cuirq.qt/invoke!`

```clojure
(ns cuirq.qt)

(defn invoke!
  "Execute f on the Qt main thread. Returns immediately (fire-and-forget)."
  [f]
  (QtThread/invoke (reify Runnable (run [_] (f)))))
```

#### 4. Wrap existing API

All public cuirq functions that touch Qt should go through `invoke!`:

```clojure
;; cuirq.state
(defn update-state! [f & args]
  (let [new-state (apply swap! !state f args)]
    ;; Sync to Qt on the correct thread
    (qt/invoke!
      #(doseq [[k v] new-state]
         (PanamaBridge/setContextProperty (name k) (str v))))))

;; cuirq.models
(defn set-data! [model-name data]
  (qt/invoke!
    #(PanamaBridge/setModelData (name model-name) (json/write-str data))))
```

### Alternative Considered: Blocking Dispatch

A synchronous version (`invoke-sync!`) that blocks until the Qt thread completes the work:

```clojure
(defn invoke-sync!
  "Execute f on the Qt main thread. Blocks calling thread until complete."
  [f]
  (if (qt-thread?)
    (f)
    (let [p (promise)]
      (invoke! #(deliver p (f)))
      @p)))
```

This is useful for operations that need return values (e.g., `get-model-count`), but should be used sparingly to avoid deadlocks. The fire-and-forget `invoke!` should be the default.

### Thread Rules

| Operation | Thread | Mechanism |
|-----------|--------|-----------|
| State updates (Clojure → QML) | Qt main | `invoke!` wraps `setContextProperty` |
| Model data updates | Qt main | `invoke!` wraps `setModelData`, `updateModelData` |
| Signal handlers (QML → Clojure) | Any | Upcall arrives on Qt thread, handler runs on virtual thread |
| `cuirq/exec!` | Main | Blocks in `QGuiApplication::exec()` |
| I/O operations | Virtual thread | `Thread/startVirtualThread` |
| QML loading | Qt main | `invoke!` wraps `loadQml` |

### Signal Handler Threading

Signal upcalls arrive on the Qt main thread. Handlers should **not** block it. Two options:

1. **Short handlers** — execute directly on Qt thread (e.g., `navigate!` that just does `swap!` + `invoke!`)
2. **Long handlers** — dispatch to virtual thread:

```clojure
(cuirq/on-signal! :search
  (fn [_ [query]]
    (Thread/startVirtualThread
      #(let [results (search-files query)]
         (models/set-data! :results results)))))
```

## Consequences

### Positive

1. **Thread safety guaranteed** — all Qt API calls happen on the correct thread
2. **Simple mental model** — developers don't need to think about thread safety
3. **No behavior change** — existing API stays the same, marshalling is internal
4. **Debuggable** — single point to log/trace all Qt interactions
5. **Compatible with virtual threads** — fire-and-forget plays well with structured concurrency

### Negative

1. **Slight latency** — `QueuedConnection` adds one event loop iteration (~16ms at 60fps)
2. **Fire-and-forget** — errors in Qt calls are harder to propagate back to caller
3. **Potential ordering issues** — rapid state updates may arrive out of order (mitigated by using `swap!` which is always consistent)

### Mitigation

1. Batch updates when possible (diff state, send only changes)
2. Log errors in Qt thread callbacks with clear context
3. State atom is the source of truth; Qt thread always applies latest state

## Progress

### Done
- Per-function thread marshaling in `qt_engine.cpp` for `set_model_data`, `update_model_data`, `clear_model` (same `QThread::currentThread()` + `QueuedConnection` pattern as `StateObject::setProp`)

### Remaining
- Centralized `cuirq_invoke_on_qt_thread` C++ function
- Java `QtThread` dispatcher
- Clojure `cuirq.qt/invoke!` wrapper
- Migrate existing per-function checks to centralized dispatch

## References

- [Qt Threading Basics](https://doc.qt.io/qt-6/threads.html)
- [QMetaObject::invokeMethod](https://doc.qt.io/qt-6/qmetaobject.html#invokeMethod)
- [JEP 454: Foreign Function & Memory API](https://openjdk.org/jeps/454)
