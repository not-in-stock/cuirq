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

### 1. Separate nREPL into dev-only entry point [Done]

**Problem**: `file-manager/core.clj` and `counter/core.clj` hardcode nREPL/CIDER imports and `start-server` calls. nREPL uses `eval`, reflection, and dynamic class loading — incompatible with native-image.

**Action**:
- Extract nREPL setup into `file-manager/dev.clj` (and `counter/dev.clj`) with its own `-main` that wraps the core `-main`
- Core `-main` becomes nREPL-free — the native-image entry point
- `deps.edn` aliases: `:dev` includes nREPL deps, `:run` does not
- `bb dev` uses dev entry point, `bb run` uses core entry point (no behavior change for either)

**Complexity**: Low
**Priority**: Blocker — native-image will fail to compile with nREPL on classpath

**Done**: nREPL/CIDER removed from core namespaces and `:deps`. Dev wrappers created at `counter/dev.clj` (port 7888) and `file_manager/dev.clj` (port 7889). nREPL deps moved to `:dev` `:extra-deps` in both example `deps.edn` and root `deps.edn`. `bb dev` uses `-M:dev:bridge`.

### 2. Defer Panama FFM initialization to runtime

**Problem**: `PanamaBridge` and `QtThread` initialize `MethodHandle` downcalls, `SymbolLookup`, and upcall stubs in `static {}` blocks. Native-image cannot serialize native addresses into the image heap.

**Action**:
- Mark both classes `--initialize-at-run-time=qml.PanamaBridge,qml.QtThread` in native-image config
- `System.loadLibrary("qmlbridge")` must also happen at runtime (already the case since it's in `static {}`)
- No lazy holder pattern needed — `--initialize-at-run-time` on the class itself is sufficient

**Validated by spike**: `--initialize-at-run-time=spike.Bridge` confirmed working — static init with `System.loadLibrary` + `SymbolLookup.loaderLookup()` + `Arena.ofAuto()` all deferred correctly.

**Complexity**: Low
**Priority**: Blocker

### 3. Register FFM descriptors for native-image

**Problem**: GraalVM native-image needs to know all `FunctionDescriptor` signatures at build time to generate the supporting code for downcalls and upcalls.

**Action**:
- Use the GraalVM Tracing Agent: run the application on standard JVM with `-agentlib:native-image-agent=config-output-dir=native-config/` to auto-generate config with all FFM descriptors
- Commit the generated config to `native-config/` and pass `-H:ConfigurationFileDirectories=native-config` to native-image
- Verify upcall stubs (signal callback in `PanamaBridge`, task callback in `QtThread`) are captured

**Validated by spike**: Tracing agent automatically captured 2 downcalls + 1 upcall from a single run. No manual descriptor registration needed.

**Complexity**: Low (downgraded from Medium — agent works reliably)
**Priority**: Blocker

### 4. Add reflection configuration for Clojure runtime

**Problem**: Clojure itself uses reflection for protocol dispatch, multimethod resolution, and `defrecord`/`deftype` interop. `clojure.data.json` uses `extend-type` with protocol dispatch.

**Action**:
- Use `com.github.clj-easy/graal-build-time` library with `--features=clj_easy.graal_build_time.InitClojureClasses` — automatically registers all Clojure packages for build-time initialization
- Supplement with Tracing Agent output for reflection metadata
- Add `(set! *warn-on-reflection* true)` in all source files (currently missing from example namespaces: `dirs.clj`, `tree.clj`, `file-manager/core.clj`)

**Validated by spike**: `graal-build-time` auto-detected and registered packages `clojure`, `clj_easy.graal_build_time`, `spike` for build-time init. No manual `graal-config` or `--initialize-at-build-time` listing needed.

**Complexity**: Low (downgraded from Medium — graal-build-time automates this)
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
    -H:+UnlockExperimentalVMOptions \
    --enable-native-access=ALL-UNNAMED \
    --features=clj_easy.graal_build_time.InitClojureClasses \
    --initialize-at-run-time=qml.PanamaBridge,qml.QtThread \
    -H:ConfigurationFileDirectories=native-config/ \
    -Djava.library.path=build/lib \
    -o cuirq-file-manager \
    file_manager.core
  ```
- Handle macOS-specific: `-XstartOnFirstThread` equivalent (needs investigation)
- Bundle `libqmlbridge.dylib` alongside the binary

**Complexity**: Medium — platform-specific issues expected
**Priority**: Blocker

### 7. Spike: minimal Panama + Clojure native-image [Works]

**Status**: Complete — see `spike/native-image/`

Built a standalone spike with a tiny C library (not Qt) to isolate Panama/GraalVM concerns:
- `spike_add(int, int)` — downcall with return value
- `spike_invoke(callback, ctx)` — upcall trampoline with `ConcurrentHashMap<Long, Runnable>` task map
- Clojure `gen-class` entry point calling both

**Results**:
- JVM run: all tests pass
- Native binary (21.5 MB, built in ~50s): identical output, all tests pass
- Tracing agent auto-captured 2 downcalls + 1 upcall
- `graal-build-time` auto-registered all Clojure packages for build-time init
- `--initialize-at-run-time` correctly defers `System.loadLibrary` + `SymbolLookup.loaderLookup()` + `Arena.ofAuto()`

**Key dependencies for native-image build**:
- `com.github.clj-easy/graal-build-time {:mvn/version "1.0.5"}`
- `-H:+ForeignAPISupport -H:+UnlockExperimentalVMOptions --enable-native-access=ALL-UNNAMED`

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
- ~~**Clojure + Panama + GraalVM** is an uncommon combination — limited community experience~~ **De-risked by spike**: the triple works, tooling (`graal-build-time`, tracing agent) handles most complexity
- macOS `-XstartOnFirstThread` behavior in native-image is uncharted
- Qt's own thread model interacting with SubstrateVM's thread implementation — potential surprises
- `clojure.data.json` or other transitive deps may have hidden reflection — tracing agent should capture this but may need multiple exercise runs

## References

- [FFM API in GraalVM Native Image (JDK 25)](https://www.graalvm.org/jdk25/reference-manual/native-image/native-code-interoperability/ffm-api/)
- [GraalVM 25 Release Notes](https://www.graalvm.org/release-notes/JDK_25/)
- [clj-easy/graal-config](https://github.com/clj-easy/graal-config) — community Clojure reflection configs
- [Clojure + GraalVM Native Image patterns](https://softwarepatternslexicon.com/patterns-clojure/20/17/)
- [GraalVM FFM support tracking issue](https://github.com/oracle/graal/issues/8113)
