#include "qmlwatcher.h"
#include "stateobject.h"
#include <QDebug>
#include <QUrl>
#include <QQmlComponent>
#include <QQmlContext>
#include <QTimer>
#include <QFile>
#include <QFileInfo>
#include <QDir>

QmlWatcher::QmlWatcher(QQmlApplicationEngine* engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
    , m_watcher(new QFileSystemWatcher(this))
    , m_debounce(new QTimer(this))
    , m_state(nullptr)
    , m_themeObject(nullptr)
    , m_autoReload(true)
{
    qDebug() << "[CPP] QmlWatcher created";

    m_debounce->setSingleShot(true);
    m_debounce->setInterval(150);
    connect(m_debounce, &QTimer::timeout, this, &QmlWatcher::reloadContent);

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

    // Create initial Theme context property (replaces pragma Singleton)
    if (!m_themeObject) {
        loadTheme(dir);
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

void QmlWatcher::loadTheme(const QString& contentDir)
{
    QString themePath = contentDir + "/Theme.qml";
    if (!QFileInfo::exists(themePath)) return;

    // Read file manually to bypass any URL-based caching
    QFile file(themePath);
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "[CPP] QmlWatcher: Cannot open Theme.qml";
        return;
    }
    QByteArray data = file.readAll();
    file.close();

    QQmlComponent comp(m_engine);
    comp.setData(data, QUrl::fromLocalFile(themePath));
    if (!comp.isReady()) {
        qWarning() << "[CPP] QmlWatcher: Theme.qml errors:" << comp.errors();
        return;
    }

    QObject* newTheme = comp.create();
    if (!newTheme) {
        qWarning() << "[CPP] QmlWatcher: Failed to instantiate Theme";
        return;
    }

    delete m_themeObject;
    m_themeObject = newTheme;
    m_themeObject->setParent(m_engine);
    m_engine->rootContext()->setContextProperty("theme", m_themeObject);
    qDebug() << "[CPP] QmlWatcher: Theme reloaded from" << themePath;
}

void QmlWatcher::setAutoReload(bool enabled)
{
    m_autoReload = enabled;
    qDebug() << "[CPP] QmlWatcher: Auto-reload" << (enabled ? "enabled" : "disabled");
}

void QmlWatcher::onFileChanged(const QString& path)
{
    if (!m_autoReload) return;
    if (!path.endsWith(".qml")) return;

    qDebug() << "[CPP] QmlWatcher: File changed:" << path;

    // QFileSystemWatcher sometimes stops watching after a change — re-add
    if (!m_watcher->files().contains(path)) {
        m_watcher->addPath(path);
    }

    m_debounce->start();
}

void QmlWatcher::onDirectoryChanged(const QString& path)
{
    if (!m_autoReload) return;

    // Rescan for new/deleted .qml files; ignore editor temp files (.#, #...#, ~)
    QDir dir(path);
    QSet<QString> currentQml;
    for (const QString& entry : dir.entryList({"*.qml"}, QDir::Files)) {
        currentQml.insert(dir.absoluteFilePath(entry));
    }

    QSet<QString> watchedQml;
    for (const QString& f : m_watcher->files()) {
        if (f.startsWith(path) && f.endsWith(".qml")) {
            watchedQml.insert(f);
        }
    }

    // Watch new .qml files
    bool changed = false;
    for (const QString& f : currentQml) {
        if (!watchedQml.contains(f)) {
            m_watcher->addPath(f);
            qDebug() << "[CPP] QmlWatcher: New file:" << QFileInfo(f).fileName();
            changed = true;
        }
    }
    // Unwatch deleted .qml files
    for (const QString& f : watchedQml) {
        if (!currentQml.contains(f)) {
            m_watcher->removePath(f);
            qDebug() << "[CPP] QmlWatcher: Removed file:" << QFileInfo(f).fileName();
            changed = true;
        }
    }

    if (changed) {
        m_debounce->start();
    }
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
    QString contentDir = QFileInfo(m_currentQmlPath).absolutePath();
    QTimer::singleShot(0, this, [this, contentUrl, contentDir]() {
        m_engine->clearComponentCache();

        // Recreate Theme from updated file (context property, not singleton)
        loadTheme(contentDir);

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
