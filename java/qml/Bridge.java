package qml;

/**
 * JNI Bridge between JVM and Qt QML.
 *
 * This class provides native methods that are implemented in C++
 * to interact with Qt's QML engine.
 */
public class Bridge {
    static {
        // Load native library (libqmlbridge.dylib on macOS, libqmlbridge.so on Linux)
        System.loadLibrary("qmlbridge");
    }

    /**
     * Initialize Qt application with command-line arguments.
     * Must be called before any other Qt operations.
     *
     * @param args Command-line arguments (typically empty for GUI apps)
     */
    public static native void initialize(String[] args);

    /**
     * Load a QML file into the engine.
     *
     * @param path Absolute or relative path to .qml file
     * @return true if loading succeeded, false otherwise
     */
    public static native boolean loadQml(String path);

    /**
     * Set a context property that will be available in QML as a global variable.
     *
     * Example: setContextProperty("userName", "Alice")
     * In QML: Text { text: userName }
     *
     * @param name Property name (must be valid JavaScript identifier)
     * @param value Property value (string representation)
     */
    public static native void setContextProperty(String name, String value);

    /**
     * Run Qt event loop (blocking call).
     * Returns when quit() is called or window is closed.
     *
     * @return Exit code (0 = success)
     */
    public static native int exec();

    /**
     * Request Qt event loop to quit.
     * Non-blocking - queues quit event.
     */
    public static native void quit();

    /**
     * Register a callback for QML signals.
     *
     * Note: Signal handling implementation is Phase 2 feature.
     * For now, just focus on basic QML loading.
     *
     * @param signalName Name of the signal to listen for
     * @param handler Callback that receives signal arguments
     */
    public static native void registerSignalHandler(String signalName, SignalHandler handler);

    /**
     * Create a list model and register it as a context property.
     *
     * @param modelName Name of the model (will be available in QML)
     */
    public static native void createModel(String modelName);

    /**
     * Set list model data from JSON string.
     *
     * @param modelName Name of the model
     * @param jsonData JSON array of objects, e.g. [{"name":"A","count":1}]
     */
    public static native void setModelData(String modelName, String jsonData);

    /**
     * Clear all items from a list model.
     *
     * @param modelName Name of the model
     */
    public static native void clearModel(String modelName);

    /**
     * Get number of items in a list model.
     *
     * @param modelName Name of the model
     * @return Number of items
     */
    public static native int getModelCount(String modelName);

    /**
     * Enable or disable automatic QML hot-reload (dev mode).
     *
     * @param enabled true to enable auto-reload, false to disable
     */
    public static native void setAutoReload(boolean enabled);

    /**
     * Check if automatic QML hot-reload is enabled.
     *
     * @return true if auto-reload is enabled
     */
    public static native boolean isAutoReloadEnabled();

    /**
     * Functional interface for signal callbacks from QML.
     */
    @FunctionalInterface
    public interface SignalHandler {
        /**
         * Handle a signal from QML.
         *
         * @param args Signal arguments as strings
         */
        void handle(String[] args);
    }
}
