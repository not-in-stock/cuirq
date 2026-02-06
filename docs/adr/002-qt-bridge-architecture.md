# ADR-002: Qt Bridge Architecture

## Status
Proposed

## Context

cuirq needs a bridge between Clojure (JVM) and Qt/QML (C++). Unlike reagent which wraps React's reactive API directly, we have a fundamental boundary between two runtimes.

### Current Architecture

```
Clojure ←→ [JSON] ←→ Java Bridge ←→ [JNI] ←→ C++ Bridge ←→ Qt/QML Engine
```

Current implementation uses message passing:
- All data serialized to JSON
- Single communication channel
- No direct Qt API access from Clojure
- Simple but limited

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

Implement a **layered bridge architecture** with protocol abstraction, prioritizing **Panama FFM API** over JNI.

### Technology Choice: Panama over JNI

**Decision**: Use Java Foreign Function & Memory API (Panama, JEP 454) as the primary native interop mechanism.

**Rationale**:
- Framework has no existing users → no migration burden
- Panama is cleaner, safer, and more maintainable than JNI
- Zero-copy memory access built-in
- GraalVM 25 supports Panama FFM out of the box
- Less C++ boilerplate to maintain

**Layers** (in priority order):
1. **cuirq.qt.panama** - Primary implementation using FFM API
2. **cuirq.qt.jni** - Legacy fallback for older JVMs
3. **cuirq.qt.codegen** - Compile-time code generation (future)

All layers implement the same protocol, allowing transparent switching.

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
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│ MessageBridge │   │ DirectBridge  │   │ CodegenBridge │
│   (default)   │   │   (future)    │   │   (future)    │
│               │   │               │   │               │
│ JSON + queue  │   │ JNI calls     │   │ Generated     │
│ Simple debug  │   │ Zero-copy     │   │ Type-safe     │
└───────────────┘   └───────────────┘   └───────────────┘
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

### 2. Message Bridge (Default Implementation)

Current approach, wrapped in protocol:

```clojure
(ns cuirq.qt.message-bridge
  (:require [cuirq.qt.protocol :as proto]
            [clojure.data.json :as json])
  (:import [qml Bridge]))

(defrecord MessageBridge [^Bridge bridge
                          signal-handlers
                          property-watches]

  proto/QtBridge

  (initialize! [this config]
    (.initialize bridge)
    (doto this
      (setup-signal-dispatch!)
      (setup-property-sync!)))

  (shutdown! [this]
    (.shutdown bridge)
    (reset! signal-handlers {})
    (reset! property-watches {}))

  (set-property! [_ name value]
    (.setContextProperty bridge
                         (clj-name->qml name)
                         (json/write-str value)))

  (get-property [_ name]
    (-> (.getContextProperty bridge (clj-name->qml name))
        json/read-str
        keywordize-keys))

  (watch-property! [this name callback]
    (swap! property-watches assoc name callback)
    #(swap! property-watches dissoc name))

  (on-signal! [this signal-name handler]
    (swap! signal-handlers assoc signal-name handler)
    #(swap! signal-handlers dissoc signal-name))

  (off-signal! [this signal-name]
    (swap! signal-handlers dissoc signal-name))

  (emit! [_ signal-name args]
    (.emitSignal bridge
                 (clj-name->qml signal-name)
                 (json/write-str args)))

  (create-model! [_ model-name roles]
    (.createListModel bridge
                      (name model-name)
                      (into-array String (map name roles))))

  (set-model-data! [_ model-name data]
    (.setModelData bridge
                   (name model-name)
                   (json/write-str data)))

  (append-model! [_ model-name items]
    (.appendModelData bridge
                      (name model-name)
                      (json/write-str items)))

  (update-model! [_ model-name index item]
    (.updateModelItem bridge
                      (name model-name)
                      index
                      (json/write-str item)))

  (remove-model! [_ model-name index count]
    (.removeModelItems bridge (name model-name) index count))

  (clear-model! [_ model-name]
    (.clearModel bridge (name model-name)))

  (load-qml! [_ path]
    (.loadQml bridge path))

  (reload-qml! [this]
    (.reloadQml bridge)))

;; Helper functions
(defn- clj-name->qml [kw-or-str]
  (-> (name kw-or-str)
      (clojure.string/replace #"-" "_")
      csk/->camelCase))

(defn- setup-signal-dispatch! [{:keys [bridge signal-handlers]}]
  (.setSignalCallback bridge
    (reify qml.SignalCallback
      (onSignal [_ name args]
        (when-let [handler (get @signal-handlers (keyword name))]
          (handler (json/read-str args :key-fn keyword)))))))

;; Constructor
(defn create-bridge []
  (map->MessageBridge
    {:bridge (Bridge.)
     :signal-handlers (atom {})
     :property-watches (atom {})}))
```

### 3. Panama Bridge (Primary - GraalVM 25+)

Primary implementation using Foreign Function & Memory API:

```java
// java/qml/PanamaBridge.java
package qml;

import java.lang.foreign.*;
import java.lang.invoke.MethodHandle;

public class PanamaBridge implements AutoCloseable {
    private static final Linker LINKER = Linker.nativeLinker();
    private static final Arena ARENA = Arena.ofShared();

    // Load native library
    private static final SymbolLookup LOOKUP;
    static {
        System.loadLibrary("cuirq_qt");
        LOOKUP = SymbolLookup.loaderLookup();
    }

    // Function descriptors for C functions
    private static final FunctionDescriptor SET_PROPERTY_DESC =
        FunctionDescriptor.ofVoid(ADDRESS, ADDRESS, ADDRESS);  // (engine*, name, value)

    private static final FunctionDescriptor EMIT_SIGNAL_DESC =
        FunctionDescriptor.ofVoid(ADDRESS, ADDRESS, ADDRESS);  // (engine*, signal, args)

    private static final FunctionDescriptor CREATE_MODEL_DESC =
        FunctionDescriptor.of(ADDRESS, ADDRESS, ADDRESS, ADDRESS);  // engine*, name, roles -> model*

    // Method handles (downcalls to C++)
    private final MethodHandle setProperty;
    private final MethodHandle emitSignal;
    private final MethodHandle createModel;
    private final MethodHandle setModelData;

    // Engine pointer
    private final MemorySegment engine;

    public PanamaBridge() {
        // Initialize downcall handles
        this.setProperty = LINKER.downcallHandle(
            LOOKUP.find("qt_set_property").orElseThrow(),
            SET_PROPERTY_DESC
        );
        this.emitSignal = LINKER.downcallHandle(
            LOOKUP.find("qt_emit_signal").orElseThrow(),
            EMIT_SIGNAL_DESC
        );
        this.createModel = LINKER.downcallHandle(
            LOOKUP.find("qt_create_model").orElseThrow(),
            CREATE_MODEL_DESC
        );
        this.setModelData = LINKER.downcallHandle(
            LOOKUP.find("qt_set_model_data").orElseThrow(),
            FunctionDescriptor.ofVoid(ADDRESS, ADDRESS, JAVA_INT)
        );

        // Create Qt engine
        MethodHandle createEngine = LINKER.downcallHandle(
            LOOKUP.find("qt_create_engine").orElseThrow(),
            FunctionDescriptor.of(ADDRESS)
        );
        try {
            this.engine = (MemorySegment) createEngine.invokeExact();
        } catch (Throwable t) {
            throw new RuntimeException("Failed to create Qt engine", t);
        }
    }

    public void setProperty(String name, String jsonValue) {
        try (Arena local = Arena.ofConfined()) {
            MemorySegment nameStr = local.allocateFrom(name);
            MemorySegment valueStr = local.allocateFrom(jsonValue);
            setProperty.invokeExact(engine, nameStr, valueStr);
        } catch (Throwable t) {
            throw new RuntimeException("setProperty failed", t);
        }
    }

    public void emitSignal(String signal, String jsonArgs) {
        try (Arena local = Arena.ofConfined()) {
            MemorySegment signalStr = local.allocateFrom(signal);
            MemorySegment argsStr = local.allocateFrom(jsonArgs);
            emitSignal.invokeExact(engine, signalStr, argsStr);
        } catch (Throwable t) {
            throw new RuntimeException("emitSignal failed", t);
        }
    }

    // Zero-copy model data using shared buffer
    public void setModelDataDirect(String modelName, MemorySegment buffer, int itemCount) {
        try (Arena local = Arena.ofConfined()) {
            MemorySegment nameStr = local.allocateFrom(modelName);
            // Pass buffer pointer directly - no copy!
            setModelData.invokeExact(engine, nameStr, buffer, itemCount);
        } catch (Throwable t) {
            throw new RuntimeException("setModelData failed", t);
        }
    }

    @Override
    public void close() {
        // Cleanup engine
        try {
            MethodHandle destroyEngine = LINKER.downcallHandle(
                LOOKUP.find("qt_destroy_engine").orElseThrow(),
                FunctionDescriptor.ofVoid(ADDRESS)
            );
            destroyEngine.invokeExact(engine);
        } catch (Throwable t) {
            // Log but don't throw
        }
    }
}
```

```cpp
// cpp/panama_bridge.cpp
// Simple C API - no JNI boilerplate!

extern "C" {

void* qt_create_engine() {
    // Initialize Qt application if needed
    static int argc = 1;
    static char* argv[] = {(char*)"cuirq"};
    static QGuiApplication app(argc, argv);

    QQmlApplicationEngine* engine = new QQmlApplicationEngine();
    return engine;
}

void qt_destroy_engine(void* engine) {
    delete static_cast<QQmlApplicationEngine*>(engine);
}

void qt_set_property(void* engine, const char* name, const char* jsonValue) {
    auto* e = static_cast<QQmlApplicationEngine*>(engine);
    QJsonDocument doc = QJsonDocument::fromJson(jsonValue);
    e->rootContext()->setContextProperty(name, doc.toVariant());
}

void qt_emit_signal(void* engine, const char* signal, const char* jsonArgs) {
    // Signal dispatch implementation
}

void qt_set_model_data(void* engine, const char* modelName,
                       void* buffer, int itemCount) {
    // Direct buffer access - zero copy!
    auto* data = static_cast<ItemData*>(buffer);
    // Update model directly from buffer
}

}  // extern "C"
```

```clojure
;; clj/src/cuirq/qt/panama.clj
(ns cuirq.qt.panama
  (:require [cuirq.qt.protocol :as proto]
            [clojure.data.json :as json])
  (:import [qml PanamaBridge]
           [java.lang.foreign Arena MemorySegment]))

(defrecord PanamaBridgeImpl [^PanamaBridge bridge
                             ^Arena shared-arena
                             signal-handlers]

  proto/QtBridge

  (set-property! [_ name value]
    (.setProperty bridge
                  (clj-name->qml name)
                  (json/write-str value)))

  (emit! [_ signal-name args]
    (.emitSignal bridge
                 (clj-name->qml signal-name)
                 (json/write-str args)))

  ;; Zero-copy for large data
  (set-model-data! [this model-name data]
    (if (> (count data) 100)
      ;; Large dataset: use direct buffer
      (let [buffer (write-items-to-buffer! shared-arena data)]
        (.setModelDataDirect bridge (name model-name) buffer (count data)))
      ;; Small dataset: JSON is fine
      (.setModelData bridge (name model-name) (json/write-str data))))

  ;; ... rest of protocol

  java.lang.AutoCloseable
  (close [_]
    (.close bridge)
    (.close shared-arena)))

(defn create-bridge []
  (map->PanamaBridgeImpl
    {:bridge (PanamaBridge.)
     :shared-arena (Arena/ofShared)
     :signal-handlers (atom {})}))
```

### 4. JNI Bridge (Legacy Fallback)

For JVMs < 25 or when Panama is unavailable:

```clojure
(ns cuirq.qt.jni
  (:require [cuirq.qt.protocol :as proto]
            [clojure.data.json :as json])
  (:import [qml JniBridge]))

;; Traditional JNI implementation
;; Requires separate .cpp file with JNI_OnLoad, etc.
(defrecord JniBridgeImpl [^JniBridge bridge signal-handlers]

  proto/QtBridge

  (set-property! [_ name value]
    (.setContextProperty bridge
                         (clj-name->qml name)
                         (json/write-str value)))

  (emit! [_ signal-name args]
    (.emitSignal bridge
                 (clj-name->qml signal-name)
                 (json/write-str args)))

  ;; ... standard JNI implementation
  )

(defn create-bridge []
  (map->JniBridgeImpl
    {:bridge (JniBridge.)
     :signal-handlers (atom {})}))
```

### 5. Codegen Bridge (Future - Type Safety)

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

;; Generated Java (example output)
(comment
  ;; Counter.java
  "package qml.generated;

   public class Counter {
       private long nativeHandle;

       public native void initialize();
       public native void destroy();

       // Properties
       public native int getCount();
       public native void setCount(int value);
       public native String getLabel();
       public native void setLabel(String value);

       // Methods
       public native void increment();
       public native void setValue(int value);

       // Signal emission
       public native void emitIncremented(int newValue);
       public native void emitReset();

       // Signal handlers (called from C++)
       public void onIncremented(int newValue) {
           // Dispatch to Clojure
       }
   }")

;; Generated C++ (example output)
(comment
  ;; counter.h
  "#pragma once
   #include <QObject>
   #include <jni.h>

   class Counter : public QObject {
       Q_OBJECT
       Q_PROPERTY(int count READ count WRITE setCount NOTIFY countChanged)
       Q_PROPERTY(QString label READ label WRITE setLabel NOTIFY labelChanged)

   public:
       explicit Counter(JNIEnv* env, jobject javaObj);
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
       JNIEnv* m_env;
       jobject m_javaObj;
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

### Phase 1: GraalVM 25 + Panama Foundation

**Environment Setup:**
- [ ] Update `flake.nix` to use `graalvm-oracle_25` as default JVM
- [ ] Remove Temurin 21, keep only GraalVM 25
- [ ] Add `--enable-native-access=ALL-UNNAMED` to JVM args
- [ ] Update `bb.edn` tasks for new JVM flags

**Panama Bridge Implementation:**
- [ ] Create `java/qml/PanamaBridge.java` with FFM API
- [ ] Define C function signatures using `FunctionDescriptor`
- [ ] Implement `MethodHandle` downcalls for Qt functions
- [ ] Create `MemoryLayout` structs for data transfer

**C++ Side:**
- [ ] Simplify C++ to export plain C functions (no JNI boilerplate)
- [ ] Remove `JNIEnv*` and `jobject` from signatures
- [ ] Keep Qt/QML integration as-is

**Clojure Integration:**
- [ ] Create `cuirq.qt.panama` namespace
- [ ] Implement `QtBridge` protocol using Panama
- [ ] Test with counter example

### Phase 2: Zero-Copy Data Transfer

**DirectByteBuffer Integration:**
- [ ] Implement shared memory region for model data
- [ ] Define binary layouts for common structures (file items, list items)
- [ ] Create `cuirq.qt.buffer` namespace for binary serialization

**Virtual List Model:**
- [ ] Implement `VirtualListModel` in C++ for large datasets
- [ ] Create lazy data source protocol in Clojure
- [ ] Support range requests (visible items only)
- [ ] Test with file manager example (100k+ items)

### Phase 3: Type Safety & Codegen

**Optional compile-time generation:**
- [ ] `def-qt-interface` macro for typed bindings
- [ ] Generate Java FFM code from specs
- [ ] Generate C++ headers from specs
- [ ] Integrate with `bb build` task

### Legacy Support

**JNI Fallback (for older JVMs):**
- Keep `cuirq.qt.jni` namespace
- Auto-detect JVM version at runtime
- Fall back to JNI if Panama unavailable

```clojure
;; Runtime bridge selection
(defn create-bridge []
  (if (panama-available?)
    (panama/create-bridge)
    (do
      (log/warn "Panama FFM not available, falling back to JNI")
      (jni/create-bridge))))
```

## Consequences

### Positive

1. **Flexibility** - Swap implementations without API changes
2. **Progressive optimization** - Start simple, optimize later
3. **Testability** - Easy to mock bridge in tests
4. **Future-proof** - Can add codegen without breaking existing code

### Negative

1. **Indirection** - Protocol adds slight overhead
2. **Complexity** - Multiple implementations to maintain
3. **Codegen complexity** - C++/Java generation is non-trivial

### Mitigation

1. Protocol dispatch is negligible vs. JNI overhead
2. Start with one implementation, add others when needed
3. Codegen is optional, most apps won't need it

## References

- [QtJambi Architecture](https://github.com/OmixVisualization/qtjambi)
- [React Native Bridge](https://reactnative.dev/docs/native-modules-intro)
- [JNI Best Practices](https://developer.android.com/training/articles/perf-jni)
- [Qt Property System](https://doc.qt.io/qt-6/properties.html)
