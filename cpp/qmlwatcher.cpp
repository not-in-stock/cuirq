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
    qDebug() << "[CPP] QmlWatcher: RELOADING CONTENT";
    qDebug() << "[CPP] QmlWatcher: ========================================";

    QQmlContext* ctx = m_engine->rootContext();
    QUrl contentUrl = QUrl::fromLocalFile(path);

    // Step 1: Unload content (set Loader source to empty)
    qDebug() << "[CPP] QmlWatcher: [1/3] Unloading content...";
    ctx->setContextProperty("_cuirq_content_url", QUrl());

    // Step 2: Clear cache + reload on next event loop tick
    // (Loader must process the empty URL before we set the new one)
    QTimer::singleShot(0, this, [this, contentUrl]() {
        qDebug() << "[CPP] QmlWatcher: [2/3] Clearing component cache...";
        m_engine->clearComponentCache();

        qDebug() << "[CPP] QmlWatcher: [3/3] Loading content:" << contentUrl.toString();
        m_engine->rootContext()->setContextProperty("_cuirq_content_url", contentUrl);

        qDebug() << "[CPP] QmlWatcher: RELOAD COMPLETE (window preserved)";
    });
}

void QmlWatcher::saveContextProperties()
{
}

void QmlWatcher::restoreContextProperties()
{
}
