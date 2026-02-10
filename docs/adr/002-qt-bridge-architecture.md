# ADR-002: Qt Bridge Architecture

## Status
Accepted (amended — JNI fallback removed, Panama FFM is the sole bridge mechanism)

## Context

cuirq needs a bridge between Clojure (JVM) and Qt/QML (C++). Unlike reagent which wraps React's reactive API directly, we have a fundamental boundary between two runtimes.

### Current Architecture

```
Clojure ←→ [JSON] ←→ Java Bridge ←→ [Panama FFM] ←→ C++ Bridge ←→ Qt/QML Engine
```

Current implementation uses Panama FFM (JEP 454) for native interop:
- All data serialized to JSON
- Panama downcalls (Java → C++) and upcall stubs (C++ → Java)
- No JNI — pure Foreign Function & Memory API
- Simple, safe, no boilerplate

### Comparison with Other Approaches

| Framework | Bridge Type | Pros | Cons |
|-----------|-------------|------|------|
| **QtJambi** | Generated JNI bindings | Full Qt API, type-safe | Complex build, large surface |
| **cljfx** | JavaFX interop | Direct Java access | JavaFX only, not Qt |
| **React Native** | JSON bridge + Fabric | Cross-platform | Serialization overhead |
| **Flutter** | Platform channels | Simple protocol | Limited to messages |

### Requirements

1. **Simplicity** - Easy to understand and debug
2. **Performance** - Efficient for common UI updates
3. **Flexibility** - Support different binding strategies
4. **Extensibility** - Allow optimization without breaking changes
5. **REPL-friendly** - Hot-reload must work

## Decision

Implement a **layered bridge architecture** with protocol abstraction, using **Panama FFM API** as the sole native interop mechanism.

### Technology Choice: Panama FFM

**Decision**: Use Java Foreign Function & Memory API (Panama, JEP 454) as the native interop mechanism. No JNI fallback.

**Rationale**:
- Panama is cleaner, safer, and more maintainable than JNI
- Zero-copy memory access built-in
- GraalVM 25 supports Panama FFM out of the box
- Less C++ boilerplate — plain `extern "C"` functions, no JNI headers
- No JNI fallback needed — cuirq targets Java 25+ exclusively
- Framework has no existing users on older JVMs

**Layers**:
1. **cuirq.qt.panama** - Core implementation using FFM API (implemented)
2. **cuirq.qt.codegen** - Compile-time code generation (future)

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Application                             │
│                   (uses protocol, not impl)                     │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                      QtBridge Protocol                          │
│  - set-property! / get-property                                 │
│  - emit-signal! / on-signal!                                    │
│  - set-model-data! / update-model!                              │
└───────────────────────────┬─────────────────────────────────────┘
                            │
        ┌───────────────────┴───────────────────┐
        │                                       │
        ▼                                       ▼
┌───────────────┐                       ┌───────────────┐
│ PanamaBridge  │                       │ CodegenBridge │
│  (default)    │                       │   (future)    │
│               │                       │               │
│ FFM + JSON    │                       │ Generated     │
│ Simple debug  │                       │ Type-safe     │
└───────────────┘                       └───────────────┘
```

## Implementation

### 1. Core Protocol

```clojure
(ns cuirq.qt.protocol)

(defprotocol QtBridge
  "Protocol for Qt/QML communication.
   Multiple implementations allow different performance/complexity trade-offs."

  ;; Lifecycle
  (initialize! [this config]
    "Initialize the bridge with configuration.")
  (shutdown! [this]
    "Clean up resources.")

  ;; Context Properties (simple values)
  (set-property! [this name value]
    "Set a QML context property. Value is auto-converted.")
  (get-property [this name]
    "Get a QML context property value.")
  (watch-property! [this name callback]
    "Watch property changes from QML. Returns cancel fn.")

  ;; Signals (QML → Clojure)
  (on-signal! [this signal-name handler]
    "Register handler for QML signal. Returns cancel fn.")
  (off-signal! [this signal-name]
    "Remove signal handler.")

  ;; Slots (Clojure → QML)
  (emit! [this signal-name args]
    "Emit signal to QML.")

  ;; List Models (efficient collection binding)
  (create-model! [this model-name roles]
    "Create a QML ListModel with given roles.")
  (set-model-data! [this model-name data]
    "Replace all model data.")
  (append-model! [this model-name items]
    "Append items to model.")
  (update-model! [this model-name index item]
    "Update single item at index.")
  (remove-model! [this model-name index count]
    "Remove items from model.")
  (clear-model! [this model-name]
    "Clear all model data.")

  ;; QML Loading
  (load-qml! [this path]
    "Load QML file.")
  (reload-qml! [this]
    "Hot-reload current QML."))

(defprotocol QtBridgeAsync
  "Optional async extensions for bridges that support it."

  (set-property-async! [this name value]
    "Non-blocking property set. Returns immediately.")
  (batch! [this operations]
    "Execute multiple operations in single round-trip."))
```

### 2. Panama Bridge (Default Implementation)

Current approach using Panama FFM, wrapped in protocol:

```clojure
(ns cuirq.qt.panama-bridge
  (:require [cuirq.qt.protocol :as proto]
            [clojure.data.json :as json])
  (:import [qml PanamaBridge]))

(defrecord PanamaBridgeImpl [signal-handlers
                              property-watches]

  proto/QtBridge

  (initialize! [this config]
    (PanamaBridge/initialize (into-array String (:args config)))
    this)

  (shutdown! [this]
    (PanamaBridge/shutdown)
    (reset! signal-handlers {})
    (reset! property-watches {}))

  (set-property! [_ name value]
    (PanamaBridge/setContextProperty
      (clj-name->qml name)
      (json/write-str value)))

  (on-signal! [this signal-name handler]
    (PanamaBridge/registerSignalHandler
      (name signal-name)
      (reify PanamaBridge$SignalHandler
        (handle [_ n args]
          (handler (keyword n) (json/read-str args :key-fn keyword)))))
    #(swap! signal-handlers dissoc signal-name))

  (create-model! [_ model-name roles]
    (PanamaBridge/createModel (name model-name)))

  (set-model-data! [_ model-name data]
    (PanamaBridge/setModelData
      (name model-name)
      (json/write-str data)))

  (clear-model! [_ model-name]
    (PanamaBridge/clearModel (name model-name)))

  (load-qml! [_ path]
    (PanamaBridge/loadQml path))

  (reload-qml! [this]
    ;; Reload handled by QmlWatcher C++ side
    ))

;; Helper functions
(defn- clj-name->qml [kw-or-str]
  (-> (name kw-or-str)
      (clojure.string/replace #"-" "_")))

;; Constructor
(defn create-bridge []
  (map->PanamaBridgeImpl
    {:signal-handlers (atom {})
     :property-watches (atom {})}))
```

### 3. Panama FFM Implementation (Actual)

The actual `PanamaBridge.java` uses static methods with `MethodHandle` downcalls to `extern "C"` functions in `libqmlbridge`. See `java/qml/PanamaBridge.java` for the full implementation.

Key patterns:
- **Downcalls**: `MethodHandle` per C function, looked up once in `static {}` block
- **Upcalls**: Signal callback via `Linker.upcallStub()` — C function pointer that calls `PanamaBridge.onSignal()`
- **Memory**: `Arena.ofConfined()` for short-lived string allocations (args to C functions)
- **Routing**: `ConcurrentHashMap<String, SignalHandler>` routes signal names to handlers

```cpp
// C++ side: plain extern "C" functions in panama_api.h
extern "C" {
    bool cuirq_initialize(int argc, char* argv[]);
    void cuirq_shutdown();
    int  cuirq_exec();
    void cuirq_set_property(const char* name, const char* json_value);
    void cuirq_set_signal_callback(void (*callback)(const char*, const char*));
    void cuirq_create_model(const char* name);
    void cuirq_set_model_data(const char* name, const char* json_data);
    // ... etc
}
```

### 4. Codegen Bridge (Future - Type Safety)

Compile-time generation for type-safe bindings:

```clojure
(ns cuirq.qt.codegen
  (:require [clojure.java.io :as io]))

(defmacro def-qt-interface
  "Defines a typed Qt interface. At compile time, generates:
   - Java class with native methods
   - C++ implementation with Q_PROPERTY/Q_INVOKABLE
   - Clojure bridge implementation

   Example:
     (def-qt-interface Counter
       :properties
       {:count {:type :int :default 0}
        :label {:type :string :default \"\"}}

       :signals
       {:incremented [:new-value]
        :reset []}

       :methods
       {:increment {:args [] :return :void}
        :set-value {:args [:int] :return :void}})"
  [name & {:keys [properties signals methods]}]
  (let [java-class (generate-java-class name properties signals methods)
        cpp-impl (generate-cpp-impl name properties signals methods)
        bridge-impl (generate-bridge-impl name properties signals methods)]

    ;; Write generated files
    (spit (io/file "generated" "java" (str name ".java")) java-class)
    (spit (io/file "generated" "cpp" (str (->snake_case name) ".cpp")) cpp-impl)
    (spit (io/file "generated" "cpp" (str (->snake_case name) ".h"))
          (generate-cpp-header name properties signals methods))

    ;; Return Clojure implementation
    bridge-impl))

;; Generated Java (example output — Panama FFM downcalls)
(comment
  ;; Counter.java
  "package qml.generated;

   import java.lang.foreign.*;
   import java.lang.invoke.MethodHandle;

   public class Counter implements AutoCloseable {
       private static final MethodHandle GET_COUNT;
       private static final MethodHandle SET_COUNT;
       // ... other downcall handles

       static {
           SymbolLookup lookup = SymbolLookup.loaderLookup();
           Linker linker = Linker.nativeLinker();
           GET_COUNT = linker.downcallHandle(
               lookup.find(\"counter_get_count\").orElseThrow(),
               FunctionDescriptor.of(ValueLayout.JAVA_INT));
           // ... etc
       }

       public int getCount() { ... }
       public void setCount(int value) { ... }
       public void increment() { ... }

       @Override
       public void close() { ... }
   }")

;; Generated C++ (example output)
(comment
  ;; counter.h
  "#pragma once
   #include <QObject>

   class Counter : public QObject {
       Q_OBJECT
       Q_PROPERTY(int count READ count WRITE setCount NOTIFY countChanged)
       Q_PROPERTY(QString label READ label WRITE setLabel NOTIFY labelChanged)

   public:
       explicit Counter(QObject* parent = nullptr);
       ~Counter();

       int count() const { return m_count; }
       void setCount(int value);

       QString label() const { return m_label; }
       void setLabel(const QString& value);

       Q_INVOKABLE void increment();
       Q_INVOKABLE void setValue(int value);

   signals:
       void countChanged();
       void labelChanged();
       void incremented(int newValue);
       void reset();

   private:
       int m_count = 0;
       QString m_label;
   };"))

;; Usage in application
(comment
  (def-qt-interface AppState
    :properties
    {:user-name {:type :string}
     :items {:type [:list {:id :int :text :string :done :bool}]}
     :loading {:type :bool :default false}}

    :signals
    {:item-clicked [:id]
     :refresh-requested []}

    :methods
    {:add-item {:args [:string] :return :int}
     :remove-item {:args [:int] :return :void}
     :toggle-item {:args [:int] :return :void}})

  ;; Creates typed bridge
  (def app-state (create-app-state-bridge engine))

  ;; Type-safe access
  (.setUserName app-state "Alice")           ; Compile-time checked
  (.addItem app-state "Buy milk")            ; Returns int
  (.onItemClicked app-state (fn [id] ...)))  ; Handler registered
```

### 5. High-Level API (cuirq.qt)

> Note: The codegen examples above use JNI in generated C++ code for illustration.
> Actual implementation would use Panama FFM upcalls/downcalls instead.

User-facing API that abstracts bridge implementation:

```clojure
(ns cuirq.qt
  (:require [cuirq.qt.protocol :as proto]
            [cuirq.qt.message-bridge :as msg]))

;; Current bridge instance (can be swapped)
(defonce ^:private *bridge* (atom nil))

(defn init!
  "Initialize Qt bridge.
   Options:
     :impl - :message (default), :direct, or custom bridge instance
     :config - implementation-specific config"
  [& {:keys [impl config] :or {impl :message}}]
  (let [bridge (case impl
                 :message (msg/create-bridge)
                 :direct (throw (ex-info "Direct bridge not yet implemented" {}))
                 ;; Custom instance
                 (if (satisfies? proto/QtBridge impl)
                   impl
                   (throw (ex-info "Invalid bridge implementation" {:impl impl}))))]
    (proto/initialize! bridge config)
    (reset! *bridge* bridge)))

(defn shutdown! []
  (when-let [bridge @*bridge*]
    (proto/shutdown! bridge)
    (reset! *bridge* nil)))

;; Delegating functions
(defn set-property! [name value]
  (proto/set-property! @*bridge* name value))

(defn get-property [name]
  (proto/get-property @*bridge* name))

(defn on-signal! [signal-name handler]
  (proto/on-signal! @*bridge* signal-name handler))

(defn emit! [signal-name & args]
  (proto/emit! @*bridge* signal-name args))

(defn create-model! [model-name roles]
  (proto/create-model! @*bridge* model-name roles))

(defn set-model-data! [model-name data]
  (proto/set-model-data! @*bridge* model-name data))

(defn load-qml! [path]
  (proto/load-qml! @*bridge* path))

(defn reload-qml! []
  (proto/reload-qml! @*bridge*))

;; Convenience macros
(defmacro with-qt
  "Execute body with Qt initialized."
  [opts & body]
  `(try
     (init! ~@opts)
     ~@body
     (finally
       (shutdown!))))
```

## Migration Path

### Phase 1: Panama Foundation (done)

- [x] GraalVM 25 as default JVM in `flake.nix`
- [x] `--enable-native-access=ALL-UNNAMED` in JVM args
- [x] `java/qml/PanamaBridge.java` with FFM downcalls and upcall stubs
- [x] C++ exports plain `extern "C"` functions (no JNI boilerplate)
- [x] Clojure API wraps PanamaBridge static methods
- [x] Counter and file-manager examples working

### Phase 2: Thread Safety & Zero-Copy

**Qt Thread Dispatch (see ADR-003):**
- [ ] `cuirq_invoke_on_qt_thread` C function
- [ ] `QtThread.invoke()` Java dispatcher
- [ ] `cuirq.qt/invoke!` Clojure wrapper
- [ ] Wrap all Qt-touching calls through dispatcher

**Zero-Copy Data Transfer:**
- [ ] Shared memory region for large model data
- [ ] Binary layouts for common structures
- [ ] `cuirq.qt.buffer` namespace for binary serialization

**Virtual List Model:**
- [ ] `VirtualListModel` in C++ for large datasets
- [ ] Lazy data source protocol in Clojure
- [ ] Range requests (visible items only)

### Phase 3: Type Safety & Codegen

**Optional compile-time generation:**
- [ ] `def-qt-interface` macro for typed bindings
- [ ] Generate Java FFM code from specs
- [ ] Generate C++ headers from specs
- [ ] Integrate with `bb build` task

## Consequences

### Positive

1. **Flexibility** - Swap implementations without API changes
2. **Progressive optimization** - Start simple, optimize later
3. **Testability** - Easy to mock bridge in tests
4. **Future-proof** - Can add codegen without breaking existing code

### Negative

1. **Indirection** - Protocol adds slight overhead
2. **Codegen complexity** - C++/Java generation is non-trivial (future phase)

### Mitigation

1. Protocol dispatch is negligible vs. Panama FFM overhead
2. Codegen is optional, most apps won't need it

## References

- [JEP 454: Foreign Function & Memory API](https://openjdk.org/jeps/454)
- [QtJambi Architecture](https://github.com/OmixVisualization/qtjambi)
- [React Native Bridge](https://reactnative.dev/docs/native-modules-intro)
- [Qt Property System](https://doc.qt.io/qt-6/properties.html)
