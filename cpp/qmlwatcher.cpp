#include "qmlwatcher.h"
#include "stateobject.h"
#include <QDebug>
#include <QUrl>
#include <QQmlContext>
#include <QTimer>
#include <QFileInfo>
#include <QDir>

QmlWatcher::QmlWatcher(QQmlApplicationEngine* engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
    , m_watcher(new QFileSystemWatcher(this))
    , m_state(nullptr)
    , m_autoReload(true)
{
    qDebug() << "[CPP] QmlWatcher created";

    connect(m_watcher, &QFileSystemWatcher::fileChanged,
            this, &QmlWatcher::onFileChanged);
    connect(m_watcher, &QFileSystemWatcher::directoryChanged,
            this, &QmlWatcher::onDirectoryChanged);
}

QmlWatcher::~QmlWatcher()
{
    qDebug() << "[CPP] QmlWatcher destroyed";
}

void QmlWatcher::watchFile(const QString& filePath)
{
    qDebug() << "[CPP] QmlWatcher: Starting to watch" << filePath;

    m_currentQmlPath = filePath;

    // Watch the file itself
    if (!m_watcher->files().contains(filePath)) {
        if (!m_watcher->addPath(filePath)) {
            qWarning() << "[CPP] QmlWatcher: Failed to watch file" << filePath;
        }
    }

    // Watch all .qml files in the same directory (Theme, components, etc.)
    QString dir = QFileInfo(filePath).absolutePath();
    QDir qmlDir(dir);
    for (const QString& entry : qmlDir.entryList({"*.qml"}, QDir::Files)) {
        QString fullPath = qmlDir.absoluteFilePath(entry);
        if (!m_watcher->files().contains(fullPath)) {
            if (m_watcher->addPath(fullPath)) {
                qDebug() << "[CPP] QmlWatcher: Watching" << entry;
            }
        }
    }

    // Watch the directory (for new/deleted files)
    if (!m_watcher->directories().contains(dir)) {
        if (m_watcher->addPath(dir)) {
            qDebug() << "[CPP] QmlWatcher: Watching directory" << dir;
        }
    }
}

void QmlWatcher::unwatchFile(const QString& filePath)
{
    qDebug() << "[CPP] QmlWatcher: Stopping watch on" << filePath;
    m_watcher->removePath(filePath);

    QString dir = QFileInfo(filePath).absolutePath();
    if (m_watcher->directories().contains(dir)) {
        m_watcher->removePath(dir);
    }
}

void QmlWatcher::setStateObject(StateObject* state)
{
    m_state = state;
}

void QmlWatcher::setAutoReload(bool enabled)
{
    m_autoReload = enabled;
    qDebug() << "[CPP] QmlWatcher: Auto-reload" << (enabled ? "enabled" : "disabled");
}

void QmlWatcher::onFileChanged(const QString& path)
{
    qDebug() << "[CPP] QmlWatcher: File changed:" << path;

    if (!m_autoReload) return;

    // QFileSystemWatcher sometimes stops watching after a change — re-add
    if (!m_watcher->files().contains(path)) {
        m_watcher->addPath(path);
    }

    QTimer::singleShot(100, this, [this]() {
        reloadContent();
    });
}

void QmlWatcher::onDirectoryChanged(const QString& path)
{
    qDebug() << "[CPP] QmlWatcher: Directory changed:" << path;

    if (!m_autoReload) return;

    QTimer::singleShot(100, this, [this]() {
        reloadContent();
    });
}

void QmlWatcher::reloadContent()
{
    if (!m_engine || m_currentQmlPath.isEmpty()) {
        qWarning() << "[CPP] QmlWatcher: No engine or content path for reload";
        return;
    }

    QQmlContext* ctx = m_engine->rootContext();
    QUrl contentUrl = QUrl::fromLocalFile(m_currentQmlPath);

    qDebug() << "[CPP] QmlWatcher: Reloading content...";

    // Step 1: Unload (Loader source → empty)
    ctx->setContextProperty("_cuirq_content_url", QUrl());

    // Step 2: Clear cache + reload on next tick
    QTimer::singleShot(0, this, [this, contentUrl]() {
        m_engine->clearComponentCache();
        m_engine->rootContext()->setContextProperty("_cuirq_content_url", contentUrl);
        // Step 3: Re-emit state so Connections in fresh QML pick up current values
        if (m_state) {
            QTimer::singleShot(0, this, [this]() {
                m_state->reemitAll();
            });
        }
        qDebug() << "[CPP] QmlWatcher: Reload complete";
    });
}
