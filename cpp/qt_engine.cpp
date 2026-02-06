#include "qt_engine.h"
#include "stateobject.h"
#include "jvmlistmodel.h"
#include "qmlwatcher.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QString>
#include <QUrl>
#include <QHash>
#include <QObject>
#include <QVariantList>
#include <QFileInfo>
#include <QDir>
#include <QTimer>
#include <QQuickWindow>
#include <iostream>
#include <vector>
#include <dlfcn.h>

#ifdef Q_OS_MACOS
#include "macos_utils.h"
#endif

// Signal forwarder for Panama FFM.
// Exposes a Q_INVOKABLE emitSignal() to QML, forwards via C function pointer.
class PanamaSignalForwarder : public QObject {
    Q_OBJECT

public:
    explicit PanamaSignalForwarder(QObject* parent = nullptr)
        : QObject(parent), m_callback(nullptr) {}

    void setCallback(cuirq::signal_callback_t callback) {
        m_callback = callback;
    }

    Q_INVOKABLE void emitSignal(const QString& signalName, const QVariantList& args = QVariantList()) {
        if (!m_callback) {
            std::cout << "[CPP] No Panama signal callback registered for: "
                      << signalName.toStdString() << std::endl;
            return;
        }

        // Convert args to JSON array string
        QString jsonArgs = "[";
        for (int i = 0; i < args.size(); ++i) {
            if (i > 0) jsonArgs += ",";
            QString val = args[i].toString();
            // Escape quotes in value
            val.replace("\\", "\\\\");
            val.replace("\"", "\\\"");
            jsonArgs += "\"" + val + "\"";
        }
        jsonArgs += "]";

        QByteArray nameBytes = signalName.toUtf8();
        QByteArray argsBytes = jsonArgs.toUtf8();

        m_callback(nameBytes.constData(), argsBytes.constData());
    }

private:
    cuirq::signal_callback_t m_callback;
};

// Include MOC output for PanamaSignalForwarder (defined in .cpp)
#include "qt_engine.moc"

// Global state for Qt objects
static QGuiApplication* g_app = nullptr;
static QQmlApplicationEngine* g_engine = nullptr;
static PanamaSignalForwarder* g_signalForwarder = nullptr;
static QmlWatcher* g_qmlWatcher = nullptr;
static StateNotifier* g_stateNotifier = nullptr;
static StateObject* g_state = nullptr;
static QHash<QString, JvmListModel*> g_models;
static bool g_shellLoaded = false;
static QString g_contentUrl;

// Command-line arguments storage (must persist for QGuiApplication lifetime)
static std::vector<char*> g_argv_storage;
static int g_argc = 0;

// Find shell.qml relative to libqmlbridge
static QString findShellQmlPath() {
    Dl_info info;
    if (dladdr(reinterpret_cast<void*>(cuirq::initialize), &info) && info.dli_fname) {
        QFileInfo libFile(QString::fromUtf8(info.dli_fname));
        QString projectRoot = libFile.absolutePath() + "/../..";
        QString shellPath = QDir(projectRoot).absoluteFilePath("qml/shell.qml");
        if (QFileInfo::exists(shellPath)) {
            return shellPath;
        }
    }
    return {};
}

namespace cuirq {

bool initialize(int argc, char* argv[]) {
    std::cout << "[CPP] Initializing Qt application (Panama)..." << std::endl;

    // Store argv persistently (QGuiApplication keeps pointers)
    g_argv_storage.clear();
    g_argv_storage.reserve(argc);
    for (int i = 0; i < argc; i++) {
        char* arg_cstr = new char[std::strlen(argv[i]) + 1];
        std::strcpy(arg_cstr, argv[i]);
        g_argv_storage.push_back(arg_cstr);
    }
    g_argc = argc;

    QQuickWindow::setDefaultAlphaBuffer(true);
    g_app = new QGuiApplication(g_argc, g_argv_storage.data());
    std::cout << "[CPP] QGuiApplication created" << std::endl;

    g_engine = new QQmlApplicationEngine();
    std::cout << "[CPP] QQmlApplicationEngine created" << std::endl;

    // Signal forwarder (Panama-style: function pointer callback)
    g_signalForwarder = new PanamaSignalForwarder();
    g_engine->rootContext()->setContextProperty("signalForwarder", g_signalForwarder);
    std::cout << "[CPP] PanamaSignalForwarder exposed to QML" << std::endl;

    // Hot-reload watcher
    g_qmlWatcher = new QmlWatcher(g_engine, g_engine);
    std::cout << "[CPP] QmlWatcher created (hot-reload enabled)" << std::endl;

    // Reactive state + notifier (plain QObject so QML can see its signals)
    g_stateNotifier = new StateNotifier(g_engine);
    g_state = new StateObject(g_stateNotifier, g_engine);
    g_engine->rootContext()->setContextProperty("state", g_state);
    g_engine->rootContext()->setContextProperty("stateNotifier", g_stateNotifier);
    std::cout << "[CPP] StateObject + StateNotifier exposed to QML" << std::endl;

    return true;
}

void set_app_name(const char* name) {
    if (!g_app) return;
    QString appName = QString::fromUtf8(name);
    g_app->setApplicationName(appName);
    g_app->setApplicationDisplayName(appName);
#ifdef Q_OS_MACOS
    // Defer Cocoa menu rename until the event loop is running and the menu exists
    QTimer::singleShot(0, g_app, [appName]() {
        setMacOSAppName(appName.toUtf8().constData());
    });
#endif
}

void shutdown() {
    std::cout << "[CPP] Shutting down Qt engine..." << std::endl;

    g_models.clear();

    delete g_engine;
    g_engine = nullptr;
    g_signalForwarder = nullptr; // owned by engine
    g_qmlWatcher = nullptr;     // owned by engine
    g_stateNotifier = nullptr;  // owned by engine
    g_state = nullptr;          // owned by engine

    delete g_app;
    g_app = nullptr;

    for (char* arg : g_argv_storage) {
        delete[] arg;
    }
    g_argv_storage.clear();
    g_argc = 0;

    std::cout << "[CPP] Qt engine shut down" << std::endl;
}

int exec() {
    if (!g_app) {
        std::cerr << "[CPP] ERROR: Application not initialized." << std::endl;
        return -1;
    }
    std::cout << "[CPP] Starting Qt event loop..." << std::endl;
    int exitCode = g_app->exec();
    std::cout << "[CPP] Qt event loop exited with code: " << exitCode << std::endl;
    return exitCode;
}

void quit() {
    if (!g_app) {
        std::cerr << "[CPP] ERROR: Application not initialized." << std::endl;
        return;
    }
    std::cout << "[CPP] Requesting Qt event loop to quit..." << std::endl;
    QGuiApplication::quit();
}

bool load_qml(const char* path) {
    if (!g_engine) {
        std::cerr << "[CPP] ERROR: Engine not initialized." << std::endl;
        return false;
    }

    QString contentPath = QString::fromUtf8(path);
    QUrl contentUrl = QUrl::fromLocalFile(contentPath);
    g_contentUrl = contentUrl.toString();

    // Add content directory to import path so qmldir singletons are found
    QString contentDir = QFileInfo(contentPath).absolutePath();
    g_engine->addImportPath(contentDir);

    if (!g_shellLoaded) {
        // First load: set content URL and load the shell
        QString shellPath = findShellQmlPath();
        if (shellPath.isEmpty()) {
            std::cerr << "[CPP] ERROR: shell.qml not found" << std::endl;
            return false;
        }

        std::cout << "[CPP] Loading shell from: " << shellPath.toStdString() << std::endl;
        std::cout << "[CPP] Content URL: " << contentPath.toStdString() << std::endl;

        g_engine->rootContext()->setContextProperty("_cuirq_content_url", contentUrl);
        g_engine->load(QUrl::fromLocalFile(shellPath));

        if (g_engine->rootObjects().isEmpty()) {
            std::cerr << "[CPP] ERROR: Failed to load shell.qml" << std::endl;
            return false;
        }

        g_shellLoaded = true;
        std::cout << "[CPP] Shell + content loaded successfully" << std::endl;
    } else {
        // Subsequent loads: just update the content URL (Loader picks it up)
        std::cout << "[CPP] Updating content URL: " << contentPath.toStdString() << std::endl;
        g_engine->rootContext()->setContextProperty("_cuirq_content_url", contentUrl);
    }

    if (g_qmlWatcher) {
        g_qmlWatcher->watchFile(contentPath);
    }

    return true;
}

void set_context_property(const char* name, const char* json_value) {
    if (!g_state) {
        std::cerr << "[CPP] ERROR: Engine not initialized." << std::endl;
        return;
    }
    std::cout << "[CPP] Setting state property: " << name << " = \"" << json_value << "\"" << std::endl;
    g_state->setProp(QString::fromUtf8(name), QString::fromUtf8(json_value));
}

void set_signal_callback(signal_callback_t callback) {
    if (!g_signalForwarder) {
        std::cerr << "[CPP] ERROR: SignalForwarder not initialized." << std::endl;
        return;
    }
    g_signalForwarder->setCallback(callback);
    std::cout << "[CPP] Panama signal callback registered" << std::endl;
}

void register_signal_handler(const char* name) {
    // In the Panama model, signal routing is handled Java-side.
    // This function exists so the C++ side can know which signals are expected.
    std::cout << "[CPP] Signal handler registered: " << name << std::endl;
}

void create_model(const char* name) {
    if (!g_engine) {
        std::cerr << "[CPP] ERROR: Qt not initialized!" << std::endl;
        return;
    }
    QString qname = QString::fromUtf8(name);
    if (g_models.contains(qname)) {
        std::cout << "[CPP] Model already exists: " << name << std::endl;
        return;
    }
    JvmListModel* model = new JvmListModel(g_engine);
    g_models.insert(qname, model);
    g_engine->rootContext()->setContextProperty(qname, model);
    std::cout << "[CPP] Model created and registered: " << name << std::endl;
}

void set_model_data(const char* name, const char* json_data) {
    QString qname = QString::fromUtf8(name);
    JvmListModel* model = g_models.value(qname, nullptr);
    if (!model) {
        std::cerr << "[CPP] ERROR: Model not found: " << name << std::endl;
        return;
    }
    model->setJsonData(QString::fromUtf8(json_data));
}

void clear_model(const char* name) {
    QString qname = QString::fromUtf8(name);
    JvmListModel* model = g_models.value(qname, nullptr);
    if (!model) {
        std::cerr << "[CPP] ERROR: Model not found: " << name << std::endl;
        return;
    }
    model->clear();
}

int get_model_count(const char* name) {
    QString qname = QString::fromUtf8(name);
    JvmListModel* model = g_models.value(qname, nullptr);
    if (!model) {
        std::cerr << "[CPP] ERROR: Model not found: " << name << std::endl;
        return 0;
    }
    return model->count();
}

void set_auto_reload(bool enabled) {
    if (g_qmlWatcher) {
        g_qmlWatcher->setAutoReload(enabled);
        std::cout << "[CPP] Auto-reload " << (enabled ? "enabled" : "disabled") << std::endl;
    }
}

bool is_auto_reload_enabled() {
    if (g_qmlWatcher) {
        return g_qmlWatcher->isAutoReloadEnabled();
    }
    return false;
}

void enable_sidebar_vibrancy(int width) {
#ifdef Q_OS_MACOS
    if (!g_engine || g_engine->rootObjects().isEmpty()) {
        std::cerr << "[CPP] ERROR: No root window for vibrancy setup" << std::endl;
        return;
    }
    QObject* root = g_engine->rootObjects().first();
    QQuickWindow* window = qobject_cast<QQuickWindow*>(root);
    if (!window) {
        std::cerr << "[CPP] ERROR: Root object is not a QQuickWindow" << std::endl;
        return;
    }
    QTimer::singleShot(0, window, [window, width]() {
        void* winId = reinterpret_cast<void*>(window->winId());
        setupSidebarVibrancy(winId, width);
    });
#else
    Q_UNUSED(width);
#endif
}

void enable_toolbar_vibrancy(int sidebarWidth, int toolbarHeight) {
#ifdef Q_OS_MACOS
    if (!g_engine || g_engine->rootObjects().isEmpty()) return;
    QObject* root = g_engine->rootObjects().first();
    QQuickWindow* window = qobject_cast<QQuickWindow*>(root);
    if (!window) return;
    QTimer::singleShot(0, window, [window, sidebarWidth, toolbarHeight]() {
        void* winId = reinterpret_cast<void*>(window->winId());
        setupToolbarVibrancy(winId, sidebarWidth, toolbarHeight);
    });
#else
    Q_UNUSED(sidebarWidth);
    Q_UNUSED(toolbarHeight);
#endif
}

void set_vibrancy_appearance(const char* mode) {
#ifdef Q_OS_MACOS
    setVibrancyAppearance(mode);
#else
    Q_UNUSED(mode);
#endif
}

} // namespace cuirq
