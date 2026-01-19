#include "qmlwatcher.h"
#include <QDebug>
#include <QUrl>
#include <QQmlContext>
#include <QTimer>

QmlWatcher::QmlWatcher(QQmlApplicationEngine* engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
    , m_watcher(new QFileSystemWatcher(this))
    , m_autoReload(true)
{
    qDebug() << "[CPP] QmlWatcher created";

    // Connect file change signal
    connect(m_watcher, &QFileSystemWatcher::fileChanged,
            this, &QmlWatcher::onFileChanged);
}

QmlWatcher::~QmlWatcher()
{
    qDebug() << "[CPP] QmlWatcher destroyed";
}

void QmlWatcher::watchFile(const QString& filePath)
{
    qDebug() << "[CPP] QmlWatcher: Starting to watch" << filePath;

    if (m_watcher->files().contains(filePath)) {
        qDebug() << "[CPP] QmlWatcher: Already watching" << filePath;
        return;
    }

    if (!m_watcher->addPath(filePath)) {
        qWarning() << "[CPP] QmlWatcher: Failed to watch" << filePath;
        return;
    }

    m_currentQmlPath = filePath;
    qDebug() << "[CPP] QmlWatcher: Now watching" << filePath;
}

void QmlWatcher::unwatchFile(const QString& filePath)
{
    qDebug() << "[CPP] QmlWatcher: Stopping watch on" << filePath;
    m_watcher->removePath(filePath);
}

void QmlWatcher::setAutoReload(bool enabled)
{
    m_autoReload = enabled;
    qDebug() << "[CPP] QmlWatcher: Auto-reload" << (enabled ? "enabled" : "disabled");
}

void QmlWatcher::onFileChanged(const QString& path)
{
    qDebug() << "[CPP] QmlWatcher: File changed:" << path;

    if (!m_autoReload) {
        qDebug() << "[CPP] QmlWatcher: Auto-reload disabled, ignoring change";
        return;
    }

    // QFileSystemWatcher sometimes stops watching after a change
    // Re-add the path to continue watching
    if (!m_watcher->files().contains(path)) {
        qDebug() << "[CPP] QmlWatcher: Re-adding watch for" << path;
        m_watcher->addPath(path);
    }

    // Delay reload slightly to avoid multiple rapid changes
    // (e.g., editor saving multiple times)
    QTimer::singleShot(100, this, [this, path]() {
        reloadQml(path);
    });
}

void QmlWatcher::reloadQml(const QString& path)
{
    if (!m_engine) {
        qWarning() << "[CPP] QmlWatcher: No engine available for reload";
        return;
    }

    qDebug() << "[CPP] QmlWatcher: ========================================";
    qDebug() << "[CPP] QmlWatcher: RELOADING QML";
    qDebug() << "[CPP] QmlWatcher: ========================================";

    // Step 1: Save current context properties (to preserve state)
    qDebug() << "[CPP] QmlWatcher: [1/5] Saving context properties...";
    saveContextProperties();

    // Step 2: Delete old root objects (to close existing windows)
    qDebug() << "[CPP] QmlWatcher: [2/5] Closing old windows...";
    QList<QObject*> oldRoots = m_engine->rootObjects();
    for (QObject* obj : oldRoots) {
        qDebug() << "[CPP] QmlWatcher: Deleting old root object:" << obj;
        obj->deleteLater();
    }

    // Step 3: Clear component cache
    qDebug() << "[CPP] QmlWatcher: [3/5] Clearing component cache...";
    m_engine->clearComponentCache();

    // Step 4: Reload QML
    qDebug() << "[CPP] QmlWatcher: [4/5] Reloading QML from:" << path;
    m_engine->load(QUrl::fromLocalFile(path));

    if (m_engine->rootObjects().isEmpty()) {
        qWarning() << "[CPP] QmlWatcher: Failed to reload QML!";
        qWarning() << "[CPP] QmlWatcher: Check QML file for syntax errors";
        return;
    }

    // Step 5: Restore context properties (they persist automatically in Qt)
    qDebug() << "[CPP] QmlWatcher: [5/5] Context properties restored";
    restoreContextProperties();

    qDebug() << "[CPP] QmlWatcher: ========================================";
    qDebug() << "[CPP] QmlWatcher: RELOAD COMPLETE";
    qDebug() << "[CPP] QmlWatcher: ========================================";
}

void QmlWatcher::saveContextProperties()
{
    // Note: QQmlContext doesn't provide a way to enumerate all properties
    // So we can't automatically save them. Instead, the application should
    // use the Bridge API to set properties, and they will be preserved
    // through the reload because we don't destroy the engine.

    // For now, this is a placeholder. In practice, context properties
    // set via setContextProperty() persist across load() calls.
    qDebug() << "[CPP] QmlWatcher: Context properties preserved (Qt handles this)";
}

void QmlWatcher::restoreContextProperties()
{
    // Context properties are automatically preserved by Qt
    // when we call load() without destroying the engine.
    qDebug() << "[CPP] QmlWatcher: Context properties restored automatically";
}
