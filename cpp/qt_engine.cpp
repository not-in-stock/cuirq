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
#include <iostream>
#include <vector>

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
static StateObject* g_state = nullptr;
static QHash<QString, JvmListModel*> g_models;

// Command-line arguments storage (must persist for QGuiApplication lifetime)
static std::vector<char*> g_argv_storage;
static int g_argc = 0;

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

    // Reactive state
    g_state = new StateObject(g_engine);
    g_engine->rootContext()->setContextProperty("state", g_state);
    std::cout << "[CPP] StateObject created and exposed as 'state'" << std::endl;

    return true;
}

void shutdown() {
    std::cout << "[CPP] Shutting down Qt engine..." << std::endl;

    g_models.clear();

    delete g_engine;
    g_engine = nullptr;
    g_signalForwarder = nullptr; // owned by engine
    g_qmlWatcher = nullptr;     // owned by engine
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

    std::cout << "[CPP] Loading QML from: " << path << std::endl;
    QUrl qmlUrl = QUrl::fromLocalFile(QString::fromUtf8(path));
    g_engine->load(qmlUrl);

    if (g_engine->rootObjects().isEmpty()) {
        std::cerr << "[CPP] ERROR: Failed to load QML file: " << path << std::endl;
        return false;
    }

    std::cout << "[CPP] QML loaded successfully" << std::endl;

    if (g_qmlWatcher) {
        g_qmlWatcher->watchFile(QString::fromUtf8(path));
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

} // namespace cuirq
