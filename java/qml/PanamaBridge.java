package qml;

import java.lang.foreign.*;
import java.lang.invoke.*;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Panama FFM bridge between JVM and Qt QML.
 *
 * Uses Foreign Function & Memory API (JEP 454).
 * All native calls go through MethodHandle downcalls to extern "C" functions.
 * Signal callbacks use upcall stubs (C function pointers → Java methods).
 */
public class PanamaBridge implements AutoCloseable {

    private static final Linker LINKER = Linker.nativeLinker();
    private static final SymbolLookup LOOKUP;

    // Downcall method handles
    private static final MethodHandle INITIALIZE;
    private static final MethodHandle SHUTDOWN;
    private static final MethodHandle EXEC;
    private static final MethodHandle QUIT;
    private static final MethodHandle LOAD_QML;
    private static final MethodHandle SET_PROPERTY;
    private static final MethodHandle SET_SIGNAL_CALLBACK;
    private static final MethodHandle REGISTER_SIGNAL;
    private static final MethodHandle CREATE_MODEL;
    private static final MethodHandle SET_MODEL_DATA;
    private static final MethodHandle UPDATE_MODEL_DATA;
    private static final MethodHandle CLEAR_MODEL;
    private static final MethodHandle GET_MODEL_COUNT;
    private static final MethodHandle SET_APP_NAME;
    private static final MethodHandle SET_AUTO_RELOAD;
    private static final MethodHandle IS_AUTO_RELOAD_ENABLED;
    private static final MethodHandle HIDE_TITLEBAR;
    private static final MethodHandle ENABLE_SIDEBAR_VIBRANCY;
    private static final MethodHandle ENABLE_TOOLBAR_VIBRANCY;
    private static final MethodHandle SET_VIBRANCY_APPEARANCE;
    private static final MethodHandle SET_VIBRANCY_ALWAYS_ACTIVE;
    private static final MethodHandle SORT_MODEL;
    private static final MethodHandle START_DIRECTORY_WATCH;
    private static final MethodHandle STOP_DIRECTORY_WATCH;

    // Upcall state for signal callbacks
    private static Arena signalArena;
    private static MemorySegment signalCallbackStub;

    // Signal handlers: signal name → handler function
    private static final Map<String, SignalHandler> handlers = new ConcurrentHashMap<>();

    /**
     * Functional interface for signal callbacks from QML.
     */
    @FunctionalInterface
    public interface SignalHandler {
        void handle(String name, String jsonArgs);
    }

    static {
        // Load native library
        System.loadLibrary("qmlbridge");

        // Look up symbols from loaded library
        LOOKUP = SymbolLookup.loaderLookup();

        // Downcall descriptors
        INITIALIZE = downcall("cuirq_initialize",
                FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        SHUTDOWN = downcall("cuirq_shutdown",
                FunctionDescriptor.ofVoid());
        EXEC = downcall("cuirq_exec",
                FunctionDescriptor.of(ValueLayout.JAVA_INT));
        QUIT = downcall("cuirq_quit",
                FunctionDescriptor.ofVoid());
        LOAD_QML = downcall("cuirq_load_qml",
                FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN, ValueLayout.ADDRESS));
        SET_PROPERTY = downcall("cuirq_set_property",
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        SET_SIGNAL_CALLBACK = downcall("cuirq_set_signal_callback",
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        REGISTER_SIGNAL = downcall("cuirq_register_signal",
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        CREATE_MODEL = downcall("cuirq_create_model",
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        SET_MODEL_DATA = downcall("cuirq_set_model_data",
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        UPDATE_MODEL_DATA = downcall("cuirq_update_model_data",
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
        CLEAR_MODEL = downcall("cuirq_clear_model",
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        GET_MODEL_COUNT = downcall("cuirq_get_model_count",
                FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS));
        SET_APP_NAME = downcall("cuirq_set_app_name",
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        SET_AUTO_RELOAD = downcall("cuirq_set_auto_reload",
                FunctionDescriptor.ofVoid(ValueLayout.JAVA_BOOLEAN));
        IS_AUTO_RELOAD_ENABLED = downcall("cuirq_is_auto_reload_enabled",
                FunctionDescriptor.of(ValueLayout.JAVA_BOOLEAN));
        HIDE_TITLEBAR = downcall("cuirq_hide_titlebar",
                FunctionDescriptor.ofVoid());
        ENABLE_SIDEBAR_VIBRANCY = downcall("cuirq_enable_sidebar_vibrancy",
                FunctionDescriptor.ofVoid(ValueLayout.JAVA_INT));
        ENABLE_TOOLBAR_VIBRANCY = downcall("cuirq_enable_toolbar_vibrancy",
                FunctionDescriptor.ofVoid(ValueLayout.JAVA_INT, ValueLayout.JAVA_INT));
        SET_VIBRANCY_APPEARANCE = downcall("cuirq_set_vibrancy_appearance",
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        SET_VIBRANCY_ALWAYS_ACTIVE = downcall("cuirq_set_vibrancy_always_active",
                FunctionDescriptor.ofVoid(ValueLayout.JAVA_BOOLEAN));
        SORT_MODEL = downcall("cuirq_sort_model",
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_BOOLEAN));
        START_DIRECTORY_WATCH = downcall("cuirq_start_directory_watch",
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS));
        STOP_DIRECTORY_WATCH = downcall("cuirq_stop_directory_watch",
                FunctionDescriptor.ofVoid());
    }

    private static MethodHandle downcall(String name, FunctionDescriptor descriptor) {
        MemorySegment symbol = LOOKUP.find(name)
                .orElseThrow(() -> new UnsatisfiedLinkError("Symbol not found: " + name));
        return LINKER.downcallHandle(symbol, descriptor);
    }

    // ---- Signal upcall machinery ----

    /**
     * Called from C++ via function pointer when a QML signal fires.
     * Dispatches to the registered Java handler by signal name.
     */
    private static void onSignal(MemorySegment namePtr, MemorySegment argsPtr) {
        // Upcall pointers arrive as zero-length segments; reinterpret so getString can scan for '\0'
        String name = namePtr.reinterpret(Long.MAX_VALUE).getString(0);
        String args = argsPtr.reinterpret(Long.MAX_VALUE).getString(0);

        SignalHandler handler = handlers.get(name);
        if (handler != null) {
            try {
                handler.handle(name, args);
            } catch (Throwable t) {
                System.err.println("[Panama] Error in signal handler for " + name + ": " + t.getMessage());
                t.printStackTrace();
            }
        }
    }

    private static void ensureSignalCallback() {
        if (signalCallbackStub != null) return;

        signalArena = Arena.ofAuto();

        // Create upcall stub: void(*)(const char*, const char*)
        try {
            MethodHandle onSignalHandle = MethodHandles.lookup().findStatic(
                    PanamaBridge.class, "onSignal",
                    MethodType.methodType(void.class, MemorySegment.class, MemorySegment.class));

            FunctionDescriptor callbackDescriptor = FunctionDescriptor.ofVoid(
                    ValueLayout.ADDRESS, ValueLayout.ADDRESS);

            signalCallbackStub = LINKER.upcallStub(onSignalHandle, callbackDescriptor, signalArena);

            // Register the upcall stub with C++
            SET_SIGNAL_CALLBACK.invokeExact(signalCallbackStub);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to create signal upcall stub", t);
        }
    }

    // ---- Public API ----

    public static void initialize(String[] args) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment argv = arena.allocate(ValueLayout.ADDRESS, args.length);
            for (int i = 0; i < args.length; i++) {
                MemorySegment argStr = arena.allocateFrom(args[i]);
                argv.setAtIndex(ValueLayout.ADDRESS, i, argStr);
            }
            boolean ok = (boolean) INITIALIZE.invokeExact(args.length, argv);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to initialize Qt", t);
        }
    }

    public static void shutdown() {
        try {
            SHUTDOWN.invokeExact();
        } catch (Throwable t) {
            throw new RuntimeException("Failed to shutdown Qt", t);
        }
    }

    public static boolean loadQml(String path) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment pathStr = arena.allocateFrom(path);
            return (boolean) LOAD_QML.invokeExact(pathStr);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to load QML", t);
        }
    }

    public static void setContextProperty(String name, String value) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment nameStr = arena.allocateFrom(name);
            MemorySegment valueStr = arena.allocateFrom(value);
            SET_PROPERTY.invokeExact(nameStr, valueStr);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to set property", t);
        }
    }

    public static int exec() {
        try {
            return (int) EXEC.invokeExact();
        } catch (Throwable t) {
            throw new RuntimeException("Failed to run Qt event loop", t);
        }
    }

    public static void quit() {
        try {
            QUIT.invokeExact();
        } catch (Throwable t) {
            throw new RuntimeException("Failed to quit Qt", t);
        }
    }

    public static void registerSignalHandler(String signalName, SignalHandler handler) {
        ensureSignalCallback();
        handlers.put(signalName, handler);

        try (Arena arena = Arena.ofConfined()) {
            MemorySegment nameStr = arena.allocateFrom(signalName);
            REGISTER_SIGNAL.invokeExact(nameStr);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to register signal", t);
        }
    }

    public static void createModel(String modelName) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment nameStr = arena.allocateFrom(modelName);
            CREATE_MODEL.invokeExact(nameStr);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to create model", t);
        }
    }

    public static void setModelData(String modelName, String jsonData) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment nameStr = arena.allocateFrom(modelName);
            MemorySegment dataStr = arena.allocateFrom(jsonData);
            SET_MODEL_DATA.invokeExact(nameStr, dataStr);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to set model data", t);
        }
    }

    public static void updateModelData(String modelName, String jsonData, String keyField) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment nameStr = arena.allocateFrom(modelName);
            MemorySegment dataStr = arena.allocateFrom(jsonData);
            MemorySegment keyStr = arena.allocateFrom(keyField);
            UPDATE_MODEL_DATA.invokeExact(nameStr, dataStr, keyStr);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to update model data", t);
        }
    }

    public static void clearModel(String modelName) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment nameStr = arena.allocateFrom(modelName);
            CLEAR_MODEL.invokeExact(nameStr);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to clear model", t);
        }
    }

    public static int getModelCount(String modelName) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment nameStr = arena.allocateFrom(modelName);
            return (int) GET_MODEL_COUNT.invokeExact(nameStr);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to get model count", t);
        }
    }

    public static void sortModel(String modelName, String role, boolean ascending) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment nameStr = arena.allocateFrom(modelName);
            MemorySegment roleStr = arena.allocateFrom(role);
            SORT_MODEL.invokeExact(nameStr, roleStr, ascending);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to sort model", t);
        }
    }

    public static void setAppName(String name) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment nameStr = arena.allocateFrom(name);
            SET_APP_NAME.invokeExact(nameStr);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to set app name", t);
        }
    }

    public static void setAutoReload(boolean enabled) {
        try {
            SET_AUTO_RELOAD.invokeExact(enabled);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to set auto-reload", t);
        }
    }

    public static boolean isAutoReloadEnabled() {
        try {
            return (boolean) IS_AUTO_RELOAD_ENABLED.invokeExact();
        } catch (Throwable t) {
            throw new RuntimeException("Failed to check auto-reload", t);
        }
    }

    public static void hideTitlebar() {
        try {
            HIDE_TITLEBAR.invokeExact();
        } catch (Throwable t) {
            throw new RuntimeException("Failed to hide titlebar", t);
        }
    }

    public static void enableSidebarVibrancy(int width) {
        try {
            ENABLE_SIDEBAR_VIBRANCY.invokeExact(width);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to enable sidebar vibrancy", t);
        }
    }

    public static void enableToolbarVibrancy(int sidebarWidth, int toolbarHeight) {
        try {
            ENABLE_TOOLBAR_VIBRANCY.invokeExact(sidebarWidth, toolbarHeight);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to enable toolbar vibrancy", t);
        }
    }

    public static void startDirectoryWatch(String path) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment pathStr = arena.allocateFrom(path);
            START_DIRECTORY_WATCH.invokeExact(pathStr);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to start directory watch", t);
        }
    }

    public static void stopDirectoryWatch() {
        try {
            STOP_DIRECTORY_WATCH.invokeExact();
        } catch (Throwable t) {
            throw new RuntimeException("Failed to stop directory watch", t);
        }
    }

    public static void setVibrancyAppearance(String mode) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment modeStr = arena.allocateFrom(mode);
            SET_VIBRANCY_APPEARANCE.invokeExact(modeStr);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to set vibrancy appearance", t);
        }
    }

    public static void setVibrancyAlwaysActive(boolean always) {
        try {
            SET_VIBRANCY_ALWAYS_ACTIVE.invokeExact(always);
        } catch (Throwable t) {
            throw new RuntimeException("Failed to set vibrancy always active", t);
        }
    }

    @Override
    public void close() {
        shutdown();
    }
}
