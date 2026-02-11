# ADR-004: GraalVM Native Image Packaging

## Status
Proposed

## Context

cuirq currently runs on a standard JVM (GraalVM JDK 25) with Clojure, Panama FFM, and Qt/C++. The startup involves:

1. JVM boot (~200ms)
2. Clojure runtime initialization — loading `clojure.core` and all namespaces
3. Panama downcall/upcall setup
4. Qt application initialization

Packaging as a GraalVM Native Image would eliminate JVM startup, reduce memory footprint, and produce a single distributable binary. However, native-image imposes constraints that conflict with several patterns used in the project.

### Current Architecture

```
Clojure (AOT .class) → Panama FFM → libqmlbridge.dylib → Qt/QML
                ↕
          nREPL (dev only)
```

### Constraints of Native Image

1. **No runtime code generation** — `eval`, dynamic `require`, runtime class loading are unavailable
2. **No runtime reflection** unless pre-registered in configuration files
3. **Panama FFM** — supported in GraalVM 25, but all downcall/upcall descriptors must be registered at build time; native addresses cannot be frozen into the image heap
4. **Static initializers** that create native objects (MethodHandles, MemorySegments, Arenas) cannot run at build time

## Decision

Prepare the codebase for GraalVM Native Image compilation in stages. The goal is a single native binary that bundles the Clojure application with `libqmlbridge` loaded at runtime.

### Architecture After Native Image

```
native-binary (AOT-compiled Clojure + JDK substrate)
    → dlopen("libqmlbridge.dylib") at runtime
    → Panama FFM downcalls/upcalls → Qt/QML
```

nREPL and CIDER are excluded from the native binary entirely. Development workflow remains on the standard JVM.

## Tasks

### 1. Separate nREPL into dev-only entry point

**Problem**: `file-manager/core.clj` and `counter/core.clj` hardcode nREPL/CIDER imports and `start-server` calls. nREPL uses `eval`, reflection, and dynamic class loading — incompatible with native-image.

**Action**:
- Extract nREPL setup into `file-manager/dev.clj` (and `counter/dev.clj`) with its own `-main` that wraps the core `-main`
- Core `-main` becomes nREPL-free — the native-image entry point
- `deps.edn` aliases: `:dev` includes nREPL deps, `:run` does not
- `bb dev` uses dev entry point, `bb run` uses core entry point (no behavior change for either)

**Complexity**: Low
**Priority**: Blocker — native-image will fail to compile with nREPL on classpath

### 2. Defer Panama FFM initialization to runtime

**Problem**: `PanamaBridge` and `QtThread` initialize `MethodHandle` downcalls, `SymbolLookup`, and upcall stubs in `static {}` blocks. Native-image cannot serialize native addresses into the image heap.

**Action**:
- Mark both classes `--initialize-at-run-time=qml.PanamaBridge,qml.QtThread` in native-image config
- Alternatively, use lazy holder pattern:
  ```java
  private static class Handles {
      static final MethodHandle INITIALIZE = downcall(...);
      // ...
  }
  ```
  with `--initialize-at-run-time=qml.PanamaBridge$Handles`
- `System.loadLibrary("qmlbridge")` must also happen at runtime (already the case since it's in `static {}`)

**Complexity**: Low
**Priority**: Blocker

### 3. Register FFM descriptors for native-image

**Problem**: GraalVM native-image needs to know all `FunctionDescriptor` signatures at build time to generate the supporting code for downcalls and upcalls.

**Action**:
- Use the GraalVM Tracing Agent: run the application on standard JVM with `-agentlib:native-image-agent=config-output-dir=native-config/` to auto-generate `reachability-metadata.json` with all FFM descriptors
- Commit the generated config to `native-config/` (or `META-INF/native-image/`)
- Verify upcall stubs (signal callback in `PanamaBridge`, task callback in `QtThread`) are captured

**Complexity**: Medium — agent may miss code paths, manual review needed
**Priority**: Blocker

### 4. Add reflection configuration for Clojure runtime

**Problem**: Clojure itself uses reflection for protocol dispatch, multimethod resolution, and `defrecord`/`deftype` interop. `clojure.data.json` uses `extend-type` with protocol dispatch.

**Action**:
- Start with community-maintained configs from [clj-easy/graal-config](https://github.com/clj-easy/graal-config)
- Supplement with Tracing Agent output from a full application run
- Add `(set! *warn-on-reflection* true)` in all source files (currently missing from example namespaces: `dirs.clj`, `tree.clj`, `file-manager/core.clj`)

**Complexity**: Medium — iterative process, may require multiple agent runs
**Priority**: Blocker

### 5. AOT-compile all Clojure namespaces

**Problem**: Native-image analyzes `.class` files. Clojure namespaces must be AOT-compiled before `native-image` runs.

**Action**:
- Add `bb native-compile` task that runs `(compile 'file-manager.core)` with `:aot :all` transitive compilation
- Verify all transitive namespaces produce `.class` files
- Ensure no top-level side effects (I/O, server starts) execute during AOT — they will run at build time

**Complexity**: Medium
**Priority**: Blocker

### 6. Native-image build configuration

**Action**:
- Create `native-image.properties` or `bb native` task:
  ```
  native-image \
    --no-fallback \
    -H:+ForeignAPISupport \
    --initialize-at-run-time=qml.PanamaBridge,qml.QtThread \
    -H:ConfigurationFileDirectories=native-config/ \
    -Djava.library.path=build/lib \
    -o cuirq-file-manager \
    file_manager.core
  ```
- Handle macOS-specific: `-XstartOnFirstThread` equivalent (native-image may need `-R:+StartOnFirstThread` or similar; needs investigation)
- Bundle `libqmlbridge.dylib` alongside the binary

**Complexity**: Medium — platform-specific issues expected
**Priority**: Blocker

### 7. Spike: minimal Panama + Clojure native-image

**Action**: Before tackling the full application, build a minimal proof-of-concept:
- Single Clojure namespace with one Panama downcall (e.g., `cuirq_initialize` + `cuirq_shutdown`)
- Compile to native-image
- Verify it runs

This validates the Clojure AOT + Panama FFM + GraalVM triple before investing in full migration.

**Complexity**: Low
**Priority**: High — do first to de-risk the approach

## Consequences

### Positive
- Single binary distribution — no JVM installation required for end users
- Fast startup (milliseconds vs seconds)
- Lower memory footprint
- Simpler packaging for macOS `.app` bundle

### Negative
- Two build paths to maintain (JVM for dev, native for release)
- nREPL unavailable in release builds — development and release behavior diverge
- Reflection/FFM configuration is fragile — adding new Panama functions requires regenerating configs
- Build time: native-image compilation is slow (minutes) and memory-hungry (4+ GB)
- Debugging native binaries is harder than JVM

### Risks
- **Clojure + Panama + GraalVM** is an uncommon combination — limited community experience
- macOS `-XstartOnFirstThread` behavior in native-image is uncharted
- Qt's own thread model interacting with SubstrateVM's thread implementation — potential surprises
- `clojure.data.json` or other transitive deps may have hidden reflection that's hard to track down

## References

- [FFM API in GraalVM Native Image (JDK 25)](https://www.graalvm.org/jdk25/reference-manual/native-image/native-code-interoperability/ffm-api/)
- [GraalVM 25 Release Notes](https://www.graalvm.org/release-notes/JDK_25/)
- [clj-easy/graal-config](https://github.com/clj-easy/graal-config) — community Clojure reflection configs
- [Clojure + GraalVM Native Image patterns](https://softwarepatternslexicon.com/patterns-clojure/20/17/)
- [GraalVM FFM support tracking issue](https://github.com/oracle/graal/issues/8113)
