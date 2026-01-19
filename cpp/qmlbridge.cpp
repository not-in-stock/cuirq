#include "qmlbridge.h"
#include "signalforwarder.h"
#include "jvmlistmodel.h"
#include "qmlwatcher.h"
#include "stateobject.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QString>
#include <QUrl>
#include <QHash>
#include <iostream>
#include <vector>
#include <memory>

// Global state for Qt objects
// Rationale: Qt requires these to live for the lifetime of the application
// Using raw pointers because Qt uses parent-child ownership model
static QGuiApplication* g_app = nullptr;
static QQmlApplicationEngine* g_engine = nullptr;
static SignalForwarder* g_signalForwarder = nullptr;
static QmlWatcher* g_qmlWatcher = nullptr;
static StateObject* g_state = nullptr;

// List models registry
// Maps model name to JvmListModel instance
static QHash<QString, JvmListModel*> g_models;

// JavaVM pointer - needed for JNI callbacks from Qt
// JavaVM is thread-safe and persistent (unlike JNIEnv which is thread-local)
static JavaVM* g_jvm = nullptr;

// Command-line arguments storage
// Must persist because QGuiApplication stores pointers to argv
static std::vector<char*> g_argv_storage;
static int g_argc = 0;

/**
 * Helper: Convert Java String to C++ std::string.
 *
 * Uses GetStringUTFChars for UTF-8 encoding (handles Unicode correctly).
 * RAII pattern: ReleaseStringUTFChars called automatically.
 */
std::string jstringToStdString(JNIEnv* env, jstring jstr) {
    if (jstr == nullptr) {
        return "";
    }

    // Get UTF-8 encoded C string from Java string
    const char* chars = env->GetStringUTFChars(jstr, nullptr);
    if (chars == nullptr) {
        // Exception already thrown by JVM
        return "";
    }

    // Copy to std::string (so we can safely release JNI resources)
    std::string result(chars);

    // Release JNI resources
    env->ReleaseStringUTFChars(jstr, chars);

    return result;
}

extern "C" {

/**
 * Initialize Qt application.
 *
 * Creates QGuiApplication and QQmlApplicationEngine.
 * Must be called before any other Qt operations.
 */
JNIEXPORT void JNICALL Java_qml_Bridge_initialize
  (JNIEnv* env, jclass /* cls */, jobjectArray args)
{
    std::cout << "[CPP] Initializing Qt application..." << std::endl;

    // Get and cache JavaVM pointer for callbacks
    // JavaVM is thread-safe and persists across JNI calls
    if (env->GetJavaVM(&g_jvm) != JNI_OK) {
        std::cerr << "[CPP] ERROR: Failed to get JavaVM pointer!" << std::endl;
        return;
    }
    std::cout << "[CPP] JavaVM pointer cached" << std::endl;

    // Convert Java String[] to argc/argv format required by Qt
    g_argc = env->GetArrayLength(args);

    // Allocate storage for argv (must persist for lifetime of QGuiApplication)
    g_argv_storage.clear();
    g_argv_storage.reserve(g_argc);

    for (int i = 0; i < g_argc; i++) {
        jstring jarg = (jstring)env->GetObjectArrayElement(args, i);
        std::string arg = jstringToStdString(env, jarg);

        // Allocate persistent C string (leaked intentionally - Qt keeps pointers)
        char* arg_cstr = new char[arg.length() + 1];
        std::strcpy(arg_cstr, arg.c_str());
        g_argv_storage.push_back(arg_cstr);

        env->DeleteLocalRef(jarg);
    }

    // Create Qt application
    // Note: QGuiApplication constructor expects (int& argc, char** argv)
    // We pass g_argc by value since we don't need Qt to modify it
    g_app = new QGuiApplication(g_argc, g_argv_storage.data());

    std::cout << "[CPP] QGuiApplication created" << std::endl;

    // Create QML engine
    g_engine = new QQmlApplicationEngine();

    std::cout << "[CPP] QQmlApplicationEngine created" << std::endl;

    // Create SignalForwarder (for QML → JVM callbacks)
    g_signalForwarder = new SignalForwarder(g_jvm);

    // Expose SignalForwarder to QML as global object "signalForwarder"
    // This allows QML to call: signalForwarder.emitSignal("name", ["args"])
    QQmlContext* rootContext = g_engine->rootContext();
    rootContext->setContextProperty("signalForwarder", g_signalForwarder);

    std::cout << "[CPP] SignalForwarder exposed to QML" << std::endl;

    // Create QmlWatcher for hot-reload (dev mode only)
    g_qmlWatcher = new QmlWatcher(g_engine, g_engine);
    std::cout << "[CPP] QmlWatcher created (hot-reload enabled)" << std::endl;

    // Create StateObject for reactive state management
    g_state = new StateObject(g_engine);
    rootContext->setContextProperty("state", g_state);
    std::cout << "[CPP] StateObject created and exposed as 'state'" << std::endl;
}

/**
 * Load QML file into the engine.
 *
 * Supports both file paths and qrc:/ resource URLs.
 * Returns false if loading fails (check Qt console for errors).
 */
JNIEXPORT jboolean JNICALL Java_qml_Bridge_loadQml
  (JNIEnv* env, jclass /* cls */, jstring path)
{
    if (g_engine == nullptr) {
        std::cerr << "[CPP] ERROR: Engine not initialized. Call initialize() first." << std::endl;
        return JNI_FALSE;
    }

    std::string qmlPath = jstringToStdString(env, path);
    std::cout << "[CPP] Loading QML from: " << qmlPath << std::endl;

    // Convert to QUrl (handles both file paths and qrc:/ URLs)
    QUrl qmlUrl = QUrl::fromLocalFile(QString::fromStdString(qmlPath));

    // Load QML file
    g_engine->load(qmlUrl);

    // Check if loading succeeded
    // QQmlApplicationEngine creates root objects if QML loaded successfully
    if (g_engine->rootObjects().isEmpty()) {
        std::cerr << "[CPP] ERROR: Failed to load QML file: " << qmlPath << std::endl;
        return JNI_FALSE;
    }

    std::cout << "[CPP] QML loaded successfully" << std::endl;

    // Start watching the QML file for changes (dev mode)
    if (g_qmlWatcher) {
        g_qmlWatcher->watchFile(QString::fromStdString(qmlPath));
    }

    return JNI_TRUE;
}

/**
 * Set context property accessible from QML.
 *
 * Must be called BEFORE loadQml() to take effect.
 * Context properties are exposed as global variables in QML.
 *
 * Example:
 *   setContextProperty("userName", "Alice")
 *   In QML: Text { text: userName }
 */
JNIEXPORT void JNICALL Java_qml_Bridge_setContextProperty
  (JNIEnv* env, jclass /* cls */, jstring name, jstring value)
{
    if (g_engine == nullptr) {
        std::cerr << "[CPP] ERROR: Engine not initialized. Call initialize() first." << std::endl;
        return;
    }

    std::string propName = jstringToStdString(env, name);
    std::string propValue = jstringToStdString(env, value);

    std::cout << "[CPP] Setting state property: " << propName << " = \"" << propValue << "\"" << std::endl;

    // Set property in StateObject (will emit signal and update QML)
    g_state->setProp(QString::fromStdString(propName), QString::fromStdString(propValue));
}

/**
 * Run Qt event loop (blocking).
 *
 * This function blocks until:
 * - quit() is called
 * - User closes the window
 * - Qt.quit() is called from QML
 *
 * Returns exit code (0 = success).
 */
JNIEXPORT jint JNICALL Java_qml_Bridge_exec
  (JNIEnv* /* env */, jclass /* cls */)
{
    if (g_app == nullptr) {
        std::cerr << "[CPP] ERROR: Application not initialized. Call initialize() first." << std::endl;
        return -1;
    }

    std::cout << "[CPP] Starting Qt event loop..." << std::endl;

    // Run event loop (blocks until quit)
    int exitCode = g_app->exec();

    std::cout << "[CPP] Qt event loop exited with code: " << exitCode << std::endl;

    return exitCode;
}

/**
 * Quit Qt event loop.
 *
 * Non-blocking: posts quit event to event loop.
 * exec() will return after processing pending events.
 */
JNIEXPORT void JNICALL Java_qml_Bridge_quit
  (JNIEnv* /* env */, jclass /* cls */)
{
    if (g_app == nullptr) {
        std::cerr << "[CPP] ERROR: Application not initialized." << std::endl;
        return;
    }

    std::cout << "[CPP] Requesting Qt event loop to quit..." << std::endl;

    // Queue quit event
    QGuiApplication::quit();
}

/**
 * Register signal handler.
 *
 * Registers a Java callback that will be invoked when QML emits a signal.
 *
 * Flow:
 *   1. QML calls: signalForwarder.emitSignal("buttonClicked", ["arg1"])
 *   2. SignalForwarder::emitSignal receives the call
 *   3. SignalForwarder finds registered handler and calls it via JNI
 *   4. Java handler.handle(String[] args) is invoked
 *   5. Clojure function receives the callback
 */
JNIEXPORT void JNICALL Java_qml_Bridge_registerSignalHandler
  (JNIEnv* env, jclass /* cls */, jstring signalName, jobject handler)
{
    if (g_signalForwarder == nullptr) {
        std::cerr << "[CPP] ERROR: SignalForwarder not initialized. Call initialize() first." << std::endl;
        return;
    }

    if (handler == nullptr) {
        std::cerr << "[CPP] ERROR: Cannot register null handler" << std::endl;
        return;
    }

    QString signal = QString::fromStdString(jstringToStdString(env, signalName));

    // Register the handler in SignalForwarder
    // This creates a GlobalRef to prevent GC
    bool success = g_signalForwarder->registerHandler(signal, env, handler);

    if (success) {
        std::cout << "[CPP] Signal handler registered successfully: "
                  << signal.toStdString() << std::endl;
    } else {
        std::cerr << "[CPP] ERROR: Failed to register signal handler: "
                  << signal.toStdString() << std::endl;
    }
}

/**
 * Create a new list model and register it as a context property.
 */
JNIEXPORT void JNICALL Java_qml_Bridge_createModel
  (JNIEnv* env, jclass /* cls */, jstring modelName)
{
    QString name = QString::fromStdString(jstringToStdString(env, modelName));
    std::cout << "[CPP] Creating list model: " << name.toStdString() << std::endl;

    if (!g_engine) {
        std::cerr << "[CPP] ERROR: Qt not initialized!" << std::endl;
        return;
    }

    // Check if model already exists
    if (g_models.contains(name)) {
        std::cout << "[CPP] Model already exists: " << name.toStdString() << std::endl;
        return;
    }

    // Create model (Qt will manage memory via parent-child relationship)
    JvmListModel* model = new JvmListModel(g_engine);
    g_models.insert(name, model);

    // Register as context property
    g_engine->rootContext()->setContextProperty(name, model);

    std::cout << "[CPP] Model created and registered: " << name.toStdString() << std::endl;
}

/**
 * Set list model data from JSON string.
 */
JNIEXPORT void JNICALL Java_qml_Bridge_setModelData
  (JNIEnv* env, jclass /* cls */, jstring modelName, jstring jsonData)
{
    QString name = QString::fromStdString(jstringToStdString(env, modelName));
    QString json = QString::fromStdString(jstringToStdString(env, jsonData));

    std::cout << "[CPP] Setting model data: " << name.toStdString() << std::endl;

    // Find model
    JvmListModel* model = g_models.value(name, nullptr);
    if (!model) {
        std::cerr << "[CPP] ERROR: Model not found: " << name.toStdString() << std::endl;
        return;
    }

    // Set data
    model->setJsonData(json);
}

/**
 * Clear all items from a list model.
 */
JNIEXPORT void JNICALL Java_qml_Bridge_clearModel
  (JNIEnv* env, jclass /* cls */, jstring modelName)
{
    QString name = QString::fromStdString(jstringToStdString(env, modelName));
    std::cout << "[CPP] Clearing model: " << name.toStdString() << std::endl;

    JvmListModel* model = g_models.value(name, nullptr);
    if (!model) {
        std::cerr << "[CPP] ERROR: Model not found: " << name.toStdString() << std::endl;
        return;
    }

    model->clear();
}

/**
 * Get number of items in a list model.
 */
JNIEXPORT jint JNICALL Java_qml_Bridge_getModelCount
  (JNIEnv* env, jclass /* cls */, jstring modelName)
{
    QString name = QString::fromStdString(jstringToStdString(env, modelName));

    JvmListModel* model = g_models.value(name, nullptr);
    if (!model) {
        std::cerr << "[CPP] ERROR: Model not found: " << name.toStdString() << std::endl;
        return 0;
    }

    return model->count();
}

/**
 * Enable or disable automatic QML hot-reload.
 */
JNIEXPORT void JNICALL Java_qml_Bridge_setAutoReload
  (JNIEnv* /* env */, jclass /* cls */, jboolean enabled)
{
    if (g_qmlWatcher) {
        g_qmlWatcher->setAutoReload(enabled);
        std::cout << "[CPP] Auto-reload " << (enabled ? "enabled" : "disabled") << std::endl;
    } else {
        std::cout << "[CPP] QmlWatcher not available (production mode?)" << std::endl;
    }
}

/**
 * Check if auto-reload is enabled.
 */
JNIEXPORT jboolean JNICALL Java_qml_Bridge_isAutoReloadEnabled
  (JNIEnv* /* env */, jclass /* cls */)
{
    if (g_qmlWatcher) {
        return g_qmlWatcher->isAutoReloadEnabled() ? JNI_TRUE : JNI_FALSE;
    }
    return JNI_FALSE;
}

} // extern "C"
