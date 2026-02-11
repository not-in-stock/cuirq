#include "qt_engine.h"
#include "stateobject.h"
#include "jvmlistmodel.h"
#ifdef CUIRQ_DEV_RELOAD
#include "qmlwatcher.h"
#include "reload_popup.h"
#endif

#include <QGuiApplication>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QString>
#include <QQuickStyle>
#include <QUrl>
#include <QHash>
#include <QObject>
#include <QVariantList>
#include <QFileInfo>
#include <QDir>
#include <QTimer>
#include <QThread>
#include <QQuickWindow>
#include <QQuickItem>
#include <QJsonDocument>
#include <QJsonArray>
#include <QQmlError>
#include <iostream>
#include <vector>

#include "fs_watcher.h"
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
QQuickWindow* g_window = nullptr;             // non-static: accessed by qmlwatcher.cpp
QQuickItem* g_rootItem = nullptr;             // non-static: accessed by qmlwatcher.cpp
QQmlEngine* g_engine = nullptr;               // non-static: accessed by qmlwatcher.cpp
static PanamaSignalForwarder* g_signalForwarder = nullptr;
#ifdef CUIRQ_DEV_RELOAD
static QmlWatcher* g_qmlWatcher = nullptr;
ReloadPopup* g_reloadPopup = nullptr;        // non-static: accessed by qmlwatcher.cpp
#endif
static StateNotifier* g_stateNotifier = nullptr;
static StateObject* g_state = nullptr;
static QHash<QString, JvmListModel*> g_models;
static DirectoryWatcher* g_directoryWatcher = nullptr;
static QString g_contentUrl;

// Titlebar height — remembered so new engines get the correct value
static int g_titlebarHeight = 0;

// Command-line arguments storage (must persist for QGuiApplication lifetime)
static std::vector<char*> g_argv_storage;
static int g_argc = 0;

// Create (or recreate) the QML engine with all context properties.
// Long-lived objects are parented to g_app and survive engine destruction.
// Non-static: called by qmlwatcher.cpp during reload.
void setupEngine() {
    g_engine = new QQmlEngine();

    // QML error interception
    g_engine->setOutputWarningsToStandardError(false);
    QObject::connect(g_engine, &QQmlEngine::warnings, [](const QList<QQmlError>& warnings) {
        for (const auto& error : warnings) {
            auto msg = QString("%1:%2:%3: %4")
                .arg(error.url().toLocalFile())
                .arg(error.line()).arg(error.column())
                .arg(error.description());
            qWarning().noquote() << msg;
#ifdef CUIRQ_DEV_RELOAD
            if (g_reloadPopup) g_reloadPopup->appendWarning(msg);
#endif
        }
    });

    auto* ctx = g_engine->rootContext();
    ctx->setContextProperty("signalForwarder", g_signalForwarder);
    ctx->setContextProperty("state", g_state);
    ctx->setContextProperty("stateNotifier", g_stateNotifier);
    ctx->setContextProperty("_cuirq_titlebar_height", g_titlebarHeight);
    for (auto it = g_models.begin(); it != g_models.end(); ++it)
        ctx->setContextProperty(it.key(), it.value());
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

    QQuickStyle::setStyle("Basic");
    QQuickWindow::setDefaultAlphaBuffer(true);
    g_app = new QGuiApplication(g_argc, g_argv_storage.data());
    std::cout << "[CPP] QGuiApplication created" << std::endl;

    // Long-lived objects — parented to g_app so they survive engine recreation
    g_signalForwarder = new PanamaSignalForwarder(g_app);
    std::cout << "[CPP] PanamaSignalForwarder created" << std::endl;

    g_directoryWatcher = new DirectoryWatcher(g_app);
#ifdef Q_OS_MACOS
    std::cout << "[CPP] DirectoryWatcher created (FSEvents)" << std::endl;
#else
    std::cout << "[CPP] DirectoryWatcher created (QFileSystemWatcher)" << std::endl;
#endif

    g_stateNotifier = new StateNotifier(g_app);
    g_state = new StateObject(g_stateNotifier, g_app);
    std::cout << "[CPP] StateObject + StateNotifier created" << std::endl;

#ifdef CUIRQ_DEV_RELOAD
    g_qmlWatcher = new QmlWatcher(g_app);
    g_qmlWatcher->setStateObject(g_state);
    g_reloadPopup = new ReloadPopup(g_app);
    std::cout << "[CPP] QmlWatcher + ReloadPopup created (hot-reload enabled)" << std::endl;
#endif

    // Create the first engine instance
    setupEngine();
    std::cout << "[CPP] QQmlEngine created" << std::endl;

    return true;
}

void invoke_on_qt_thread(qt_callback_t fn, long ctx) {
    if (!g_app) return;
    if (QThread::currentThread() == g_app->thread()) {
        fn(ctx);
    } else {
        QMetaObject::invokeMethod(g_app, [fn, ctx]() {
            fn(ctx);
        }, Qt::QueuedConnection);
    }
}

void invoke_on_qt_thread_sync(qt_callback_t fn, long ctx) {
    if (!g_app) return;
    if (QThread::currentThread() == g_app->thread()) {
        fn(ctx);
    } else {
        QMetaObject::invokeMethod(g_app, [fn, ctx]() {
            fn(ctx);
        }, Qt::BlockingQueuedConnection);
    }
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

    delete g_rootItem;
    g_rootItem = nullptr;

    delete g_engine;
    g_engine = nullptr;

    delete g_window;
    g_window = nullptr;

    // All long-lived objects are parented to g_app — deleted with it
    delete g_app;
    g_app = nullptr;
    g_signalForwarder = nullptr;
#ifdef CUIRQ_DEV_RELOAD
    g_qmlWatcher = nullptr;
    g_reloadPopup = nullptr;
#endif
    g_directoryWatcher = nullptr;
    g_stateNotifier = nullptr;
    g_state = nullptr;

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
    g_contentUrl = contentPath;

    // Add content directory to import path so qmldir singletons are found
    QString contentDir = QFileInfo(contentPath).absolutePath();
    g_engine->addImportPath(contentDir);

#ifdef CUIRQ_DEV_RELOAD
    if (g_qmlWatcher) {
        g_qmlWatcher->watchFile(contentPath);
    }
#endif

    std::cout << "[CPP] Loading QML: " << contentPath.toStdString() << std::endl;

    // Load QML as Item via QQmlComponent
    QQmlComponent component(g_engine, QUrl::fromLocalFile(contentPath));
    if (component.isError()) {
        for (const auto& err : component.errors())
            qWarning().noquote() << err.toString();
        return false;
    }

    QObject* obj = component.create();
    g_rootItem = qobject_cast<QQuickItem*>(obj);
    if (!g_rootItem) {
        std::cerr << "[CPP] ERROR: Root QML must be an Item, not a Window" << std::endl;
        delete obj;
        return false;
    }

    // Create persistent window (first load only)
    if (!g_window) {
        g_window = new QQuickWindow();

        // Read optional window properties from root Item
        QVariant vTitle = g_rootItem->property("windowTitle");
        if (vTitle.isValid()) g_window->setTitle(vTitle.toString());

        QVariant vWidth = g_rootItem->property("windowWidth");
        QVariant vHeight = g_rootItem->property("windowHeight");
        if (vWidth.isValid() && vHeight.isValid())
            g_window->resize(vWidth.toInt(), vHeight.toInt());

        QVariant vColor = g_rootItem->property("windowColor");
        if (vColor.isValid()) g_window->setColor(vColor.value<QColor>());
        else g_window->setColor(Qt::white);

        // Keep root item sized to window — connected once, lambdas read global g_rootItem
        QObject::connect(g_window, &QQuickWindow::widthChanged, g_window, [](int) {
            if (g_rootItem) g_rootItem->setWidth(g_window->width());
        });
        QObject::connect(g_window, &QQuickWindow::heightChanged, g_window, [](int) {
            if (g_rootItem) g_rootItem->setHeight(g_window->height());
        });
    }

    // Parent QML root into window content area
    g_rootItem->setParentItem(g_window->contentItem());
    g_rootItem->setWidth(g_window->width());
    g_rootItem->setHeight(g_window->height());

    g_window->show();
    std::cout << "[CPP] QML loaded successfully" << std::endl;
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
    if (g_directoryWatcher) {
        g_directoryWatcher->setSignalCallback(callback);
    }
    std::cout << "[CPP] Panama signal callback registered" << std::endl;
}

void register_signal_handler(const char* name) {
    // In the Panama model, signal routing is handled Java-side.
    // This function exists so the C++ side can know which signals are expected.
    std::cout << "[CPP] Signal handler registered: " << name << std::endl;
}

void create_model(const char* name) {
    if (!g_app) {
        std::cerr << "[CPP] ERROR: Qt not initialized!" << std::endl;
        return;
    }
    QString qname = QString::fromUtf8(name);
    if (g_models.contains(qname)) {
        std::cout << "[CPP] Model already exists: " << name << std::endl;
        return;
    }
    JvmListModel* model = new JvmListModel(g_app);
    g_models.insert(qname, model);
    if (g_engine)
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

void update_model_data(const char* name, const char* json_data, const char* key_field) {
    QString qname = QString::fromUtf8(name);
    JvmListModel* model = g_models.value(qname, nullptr);
    if (!model) {
        std::cerr << "[CPP] ERROR: Model not found: " << name << std::endl;
        return;
    }
    model->updateJsonData(QString::fromUtf8(json_data), QString::fromUtf8(key_field));
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

void sort_model(const char* name, const char* role, bool ascending) {
    QString qname = QString::fromUtf8(name);
    JvmListModel* model = g_models.value(qname, nullptr);
    if (!model) {
        std::cerr << "[CPP] ERROR: Model not found: " << name << std::endl;
        return;
    }
    model->sortByRole(QString::fromUtf8(role), ascending);
}

void start_directory_watch(const char* path) {
    if (!g_directoryWatcher) {
        std::cerr << "[CPP] ERROR: DirectoryWatcher not initialized." << std::endl;
        return;
    }
    g_directoryWatcher->startWatching(QString::fromUtf8(path));
}

void watch_directories(const char* json_paths) {
    if (!g_directoryWatcher) {
        std::cerr << "[CPP] ERROR: DirectoryWatcher not initialized." << std::endl;
        return;
    }
    QJsonDocument doc = QJsonDocument::fromJson(QByteArray(json_paths));
    QJsonArray arr = doc.array();
    QStringList paths;
    for (const auto& val : arr) {
        paths.append(val.toString());
    }
    g_directoryWatcher->startWatching(paths);
}

void stop_directory_watch() {
    if (g_directoryWatcher) {
        g_directoryWatcher->stopWatching();
    }
}

#ifdef CUIRQ_DEV_RELOAD
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
#endif

void hide_titlebar() {
#ifdef Q_OS_MACOS
    if (!g_window) {
        std::cerr << "[CPP] ERROR: No window for titlebar setup" << std::endl;
        return;
    }
    QTimer::singleShot(0, g_window, []() {
        void* winId = reinterpret_cast<void*>(g_window->winId());
        g_titlebarHeight = hideTitlebar(winId);
        if (g_engine)
            g_engine->rootContext()->setContextProperty("_cuirq_titlebar_height", g_titlebarHeight);
    });
#endif
}

void enable_sidebar_vibrancy(int width) {
#ifdef Q_OS_MACOS
    if (!g_window) return;
    QTimer::singleShot(0, g_window, [width]() {
        void* winId = reinterpret_cast<void*>(g_window->winId());
        setupSidebarVibrancy(winId, width);
    });
#else
    Q_UNUSED(width);
#endif
}

void enable_toolbar_vibrancy(int sidebarWidth, int toolbarHeight) {
#ifdef Q_OS_MACOS
    if (!g_window) return;
    QTimer::singleShot(0, g_window, [sidebarWidth, toolbarHeight]() {
        void* winId = reinterpret_cast<void*>(g_window->winId());
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

void set_vibrancy_always_active(bool always) {
#ifdef Q_OS_MACOS
    setVibrancyAlwaysActive(always);
#else
    Q_UNUSED(always);
#endif
}

} // namespace cuirq
