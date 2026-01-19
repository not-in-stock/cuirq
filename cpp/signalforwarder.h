#ifndef SIGNALFORWARDER_H
#define SIGNALFORWARDER_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <jni.h>
#include <memory>
#include <unordered_map>
#include <string>

/**
 * SignalForwarder - QObject that forwards Qt signals to JVM callbacks.
 *
 * This class acts as a bridge between QML signals and Java/Clojure handlers.
 *
 * Architecture:
 *   QML signal → Q_INVOKABLE slot → JNI call → Java callback → Clojure function
 *
 * Thread safety:
 *   - Qt signals run on main thread
 *   - JNI calls are thread-safe (we get JNIEnv from JavaVM)
 *   - GlobalRefs prevent GC from collecting Java objects
 *
 * Memory management:
 *   - Handlers stored as JNI GlobalRef (persists across JNI calls)
 *   - Must call DeleteGlobalRef when handler is removed
 *   - JavaVM* cached for getting JNIEnv in callbacks
 */
class SignalForwarder : public QObject {
    Q_OBJECT

public:
    explicit SignalForwarder(JavaVM* jvm, QObject* parent = nullptr);
    ~SignalForwarder() override;

    /**
     * Register a signal handler.
     *
     * Creates a JNI GlobalRef to the handler object so it won't be GC'd.
     *
     * @param signalName Name of the signal (e.g., "buttonClicked")
     * @param env JNI environment pointer
     * @param handler Java object implementing SignalHandler interface
     * @return true if registration succeeded
     */
    bool registerHandler(const QString& signalName, JNIEnv* env, jobject handler);

    /**
     * Unregister a signal handler.
     *
     * Deletes the GlobalRef to allow Java object to be GC'd.
     *
     * @param signalName Name of the signal to unregister
     * @param env JNI environment pointer
     */
    void unregisterHandler(const QString& signalName, JNIEnv* env);

    /**
     * Emit a signal with string arguments.
     *
     * This is called from QML or Qt C++ code.
     * The signal is forwarded to the registered Java handler if one exists.
     *
     * Q_INVOKABLE makes this callable from QML.
     *
     * @param signalName Name of the signal being emitted
     * @param args Arguments to pass to the handler (as QVariantList)
     */
    Q_INVOKABLE void emitSignal(const QString& signalName, const QVariantList& args = QVariantList());

private:
    /**
     * Call a Java handler method.
     *
     * This is the core JNI callback mechanism.
     *
     * Steps:
     *   1. Get JNIEnv for current thread
     *   2. Convert C++ arguments to Java String[]
     *   3. Find and call handler.handle(String[] args)
     *   4. Check for JNI exceptions
     *
     * @param signalName Name of the signal
     * @param args Arguments as QStringList
     */
    void callJavaHandler(const QString& signalName, const QStringList& args);

    /**
     * Convert QVariantList to QStringList.
     *
     * QML often passes QVariant arguments; we convert everything to strings
     * for simplicity in Phase 1. Phase 2 could support typed arguments.
     *
     * @param variants Input variants
     * @return Converted strings
     */
    QStringList variantsToStrings(const QVariantList& variants);

    // JavaVM pointer - needed to get JNIEnv in Qt callbacks
    // JavaVM is thread-safe and persistent; JNIEnv is thread-local
    JavaVM* m_jvm;

    // Map of signal name → Java handler (GlobalRef)
    // GlobalRef keeps Java objects alive across JNI calls
    std::unordered_map<std::string, jobject> m_handlers;

    // Cached method IDs for performance
    // Method lookup is expensive; cache once and reuse
    jclass m_handlerClass;      // qml.Bridge$SignalHandler
    jmethodID m_handleMethod;   // handle(String[])
};

#endif // SIGNALFORWARDER_H
