#ifndef QMLBRIDGE_H
#define QMLBRIDGE_H

#include <jni.h>

// JNI function declarations
// These match the native methods in qml.Bridge Java class
extern "C" {

/**
 * Initialize Qt application.
 *
 * JNI signature: (Ljava/lang/String;)V
 * Java: public static native void initialize(String[] args)
 */
JNIEXPORT void JNICALL Java_qml_Bridge_initialize
  (JNIEnv* env, jclass cls, jobjectArray args);

/**
 * Load QML file.
 *
 * JNI signature: (Ljava/lang/String;)Z
 * Java: public static native boolean loadQml(String path)
 */
JNIEXPORT jboolean JNICALL Java_qml_Bridge_loadQml
  (JNIEnv* env, jclass cls, jstring path);

/**
 * Set state property (reactive, will update QML automatically).
 *
 * JNI signature: (Ljava/lang/String;Ljava/lang/String;)V
 * Java: public static native void setContextProperty(String name, String value)
 */
JNIEXPORT void JNICALL Java_qml_Bridge_setContextProperty
  (JNIEnv* env, jclass cls, jstring name, jstring value);

/**
 * Run Qt event loop (blocking).
 *
 * JNI signature: ()I
 * Java: public static native int exec()
 */
JNIEXPORT jint JNICALL Java_qml_Bridge_exec
  (JNIEnv* env, jclass cls);

/**
 * Quit Qt event loop.
 *
 * JNI signature: ()V
 * Java: public static native void quit()
 */
JNIEXPORT void JNICALL Java_qml_Bridge_quit
  (JNIEnv* env, jclass cls);

/**
 * Register signal handler (Phase 2 feature - stub for now).
 *
 * JNI signature: (Ljava/lang/String;Lqml/Bridge$SignalHandler;)V
 * Java: public static native void registerSignalHandler(String signalName, SignalHandler handler)
 */
JNIEXPORT void JNICALL Java_qml_Bridge_registerSignalHandler
  (JNIEnv* env, jclass cls, jstring signalName, jobject handler);

JNIEXPORT void JNICALL Java_qml_Bridge_createModel
  (JNIEnv* env, jclass cls, jstring modelName);

JNIEXPORT void JNICALL Java_qml_Bridge_setModelData
  (JNIEnv* env, jclass cls, jstring modelName, jstring jsonData);

JNIEXPORT void JNICALL Java_qml_Bridge_clearModel
  (JNIEnv* env, jclass cls, jstring modelName);

JNIEXPORT jint JNICALL Java_qml_Bridge_getModelCount
  (JNIEnv* env, jclass cls, jstring modelName);

JNIEXPORT void JNICALL Java_qml_Bridge_setAutoReload
  (JNIEnv* env, jclass cls, jboolean enabled);

JNIEXPORT jboolean JNICALL Java_qml_Bridge_isAutoReloadEnabled
  (JNIEnv* env, jclass cls);

} // extern "C"

#endif // QMLBRIDGE_H
