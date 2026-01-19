#include "signalforwarder.h"
#include <QDebug>
#include <iostream>

/**
 * Constructor.
 *
 * Caches JavaVM pointer and looks up Java method IDs for performance.
 * Method lookup is expensive; doing it once in constructor is faster.
 */
SignalForwarder::SignalForwarder(JavaVM* jvm, QObject* parent)
    : QObject(parent)
    , m_jvm(jvm)
    , m_handlerClass(nullptr)
    , m_handleMethod(nullptr)
{
    std::cout << "[CPP] SignalForwarder created" << std::endl;

    // Get JNIEnv for current thread
    JNIEnv* env = nullptr;
    if (m_jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_8) != JNI_OK) {
        std::cerr << "[CPP] ERROR: Failed to get JNIEnv in SignalForwarder constructor" << std::endl;
        return;
    }

    // Find SignalHandler interface class
    // This is a nested interface: qml.Bridge$SignalHandler
    jclass localClass = env->FindClass("qml/Bridge$SignalHandler");
    if (localClass == nullptr) {
        std::cerr << "[CPP] ERROR: Could not find qml.Bridge$SignalHandler class" << std::endl;
        env->ExceptionDescribe();
        return;
    }

    // Create GlobalRef for the class (so it persists)
    m_handlerClass = reinterpret_cast<jclass>(env->NewGlobalRef(localClass));
    env->DeleteLocalRef(localClass);

    // Find the handle method: void handle(String[])
    // JNI signature: ([Ljava/lang/String;)V
    m_handleMethod = env->GetMethodID(m_handlerClass, "handle", "([Ljava/lang/String;)V");
    if (m_handleMethod == nullptr) {
        std::cerr << "[CPP] ERROR: Could not find handle method on SignalHandler" << std::endl;
        env->ExceptionDescribe();
        return;
    }

    std::cout << "[CPP] SignalForwarder initialized successfully" << std::endl;
}

/**
 * Destructor.
 *
 * Cleans up all GlobalRefs to prevent memory leaks.
 * CRITICAL: Must delete all GlobalRefs or JVM will leak memory.
 */
SignalForwarder::~SignalForwarder()
{
    std::cout << "[CPP] SignalForwarder destructor called" << std::endl;

    // Get JNIEnv for cleanup
    JNIEnv* env = nullptr;
    if (m_jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_8) != JNI_OK) {
        std::cerr << "[CPP] WARNING: Could not get JNIEnv in destructor for cleanup" << std::endl;
        return;
    }

    // Delete all handler GlobalRefs
    for (auto& pair : m_handlers) {
        env->DeleteGlobalRef(pair.second);
    }
    m_handlers.clear();

    // Delete class GlobalRef
    if (m_handlerClass != nullptr) {
        env->DeleteGlobalRef(m_handlerClass);
    }

    std::cout << "[CPP] SignalForwarder cleanup complete" << std::endl;
}

/**
 * Register a signal handler.
 *
 * Creates a GlobalRef so the Java object won't be garbage collected.
 * GlobalRefs persist across JNI calls and threads.
 */
bool SignalForwarder::registerHandler(const QString& signalName, JNIEnv* env, jobject handler)
{
    if (handler == nullptr) {
        std::cerr << "[CPP] ERROR: Cannot register null handler" << std::endl;
        return false;
    }

    std::string sigName = signalName.toStdString();
    std::cout << "[CPP] Registering signal handler: " << sigName << std::endl;

    // If a handler already exists, delete the old GlobalRef first
    auto it = m_handlers.find(sigName);
    if (it != m_handlers.end()) {
        std::cout << "[CPP] Replacing existing handler for: " << sigName << std::endl;
        env->DeleteGlobalRef(it->second);
    }

    // Create GlobalRef to prevent garbage collection
    // CRITICAL: Without GlobalRef, Java object may be GC'd before callback!
    jobject globalHandler = env->NewGlobalRef(handler);
    if (globalHandler == nullptr) {
        std::cerr << "[CPP] ERROR: Failed to create GlobalRef for handler" << std::endl;
        return false;
    }

    // Store the GlobalRef
    m_handlers[sigName] = globalHandler;

    std::cout << "[CPP] Handler registered successfully: " << sigName << std::endl;
    return true;
}

/**
 * Unregister a signal handler.
 *
 * Deletes the GlobalRef, allowing Java object to be garbage collected.
 */
void SignalForwarder::unregisterHandler(const QString& signalName, JNIEnv* env)
{
    std::string sigName = signalName.toStdString();
    auto it = m_handlers.find(sigName);

    if (it == m_handlers.end()) {
        std::cout << "[CPP] No handler registered for: " << sigName << std::endl;
        return;
    }

    std::cout << "[CPP] Unregistering signal handler: " << sigName << std::endl;

    // Delete GlobalRef
    env->DeleteGlobalRef(it->second);
    m_handlers.erase(it);

    std::cout << "[CPP] Handler unregistered: " << sigName << std::endl;
}

/**
 * Emit a signal (called from QML).
 *
 * This is the main entry point from QML side.
 * Q_INVOKABLE makes it callable from JavaScript in QML.
 *
 * Example QML usage:
 *   Button {
 *     onClicked: signalForwarder.emitSignal("buttonClicked", ["arg1", "arg2"])
 *   }
 */
void SignalForwarder::emitSignal(const QString& signalName, const QVariantList& args)
{
    std::cout << "[CPP] Signal emitted: " << signalName.toStdString()
              << " with " << args.size() << " arguments" << std::endl;

    // Convert QVariantList to QStringList for simplicity
    QStringList stringArgs = variantsToStrings(args);

    // Forward to Java handler
    callJavaHandler(signalName, stringArgs);
}

/**
 * Call the Java handler method.
 *
 * This is where the magic happens: Qt → JNI → Java → Clojure
 *
 * Thread safety: Qt signals run on main thread, JNI is thread-safe.
 */
void SignalForwarder::callJavaHandler(const QString& signalName, const QStringList& args)
{
    std::string sigName = signalName.toStdString();

    // Check if handler is registered
    auto it = m_handlers.find(sigName);
    if (it == m_handlers.end()) {
        std::cout << "[CPP] No handler registered for signal: " << sigName << std::endl;
        return;
    }

    // Get JNIEnv for current thread
    // Note: JavaVM is thread-safe; JNIEnv is thread-local
    JNIEnv* env = nullptr;
    jint result = m_jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_8);

    if (result == JNI_EDETACHED) {
        // Thread not attached to JVM - attach it
        // This can happen if Qt calls us from a non-JVM thread
        std::cout << "[CPP] Attaching thread to JVM..." << std::endl;
        result = m_jvm->AttachCurrentThread(reinterpret_cast<void**>(&env), nullptr);
        if (result != JNI_OK) {
            std::cerr << "[CPP] ERROR: Failed to attach thread to JVM" << std::endl;
            return;
        }
    } else if (result != JNI_OK) {
        std::cerr << "[CPP] ERROR: Failed to get JNIEnv" << std::endl;
        return;
    }

    // Convert QStringList to Java String[]
    jclass stringClass = env->FindClass("java/lang/String");
    jobjectArray javaArgs = env->NewObjectArray(args.size(), stringClass, nullptr);

    for (int i = 0; i < args.size(); ++i) {
        jstring jstr = env->NewStringUTF(args[i].toUtf8().constData());
        env->SetObjectArrayElement(javaArgs, i, jstr);
        env->DeleteLocalRef(jstr);  // Clean up local reference
    }

    // Call handler.handle(String[] args)
    std::cout << "[CPP] Calling Java handler for: " << sigName << std::endl;
    env->CallVoidMethod(it->second, m_handleMethod, javaArgs);

    // Check for Java exceptions
    if (env->ExceptionCheck()) {
        std::cerr << "[CPP] ERROR: Exception occurred in Java handler!" << std::endl;
        env->ExceptionDescribe();
        env->ExceptionClear();
    } else {
        std::cout << "[CPP] Java handler completed successfully" << std::endl;
    }

    // Clean up
    env->DeleteLocalRef(javaArgs);
    env->DeleteLocalRef(stringClass);
}

/**
 * Convert QVariantList to QStringList.
 *
 * QML passes arguments as QVariant (dynamic type).
 * We convert everything to strings for simplicity.
 *
 * Future enhancement: Support typed arguments (int, bool, etc.)
 */
QStringList SignalForwarder::variantsToStrings(const QVariantList& variants)
{
    QStringList result;
    result.reserve(variants.size());

    for (const QVariant& variant : variants) {
        // Convert each variant to string
        // Works for most types: int, double, bool, QString, etc.
        result.append(variant.toString());
    }

    return result;
}
