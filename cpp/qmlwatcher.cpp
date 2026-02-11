#include "qmlwatcher.h"
#include "stateobject.h"
#include "reload_popup.h"
#include <QDebug>
#include <QUrl>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QTimer>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QQuickWindow>
#include <QQuickItem>

// These are defined in qt_engine.cpp and accessed during reload
extern QQuickWindow* g_window;
extern QQuickItem* g_rootItem;
extern QQmlEngine* g_engine;
extern ReloadPopup* g_reloadPopup;
void setupEngine();

QmlWatcher::QmlWatcher(QObject *parent)
    : QObject(parent)
    , m_watcher(new QFileSystemWatcher(this))
    , m_debounce(new QTimer(this))
    , m_state(nullptr)
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
    m_contentDir = QFileInfo(filePath).absolutePath();

    // Watch the file itself
    if (!m_watcher->files().contains(filePath)) {
        if (!m_watcher->addPath(filePath)) {
            qWarning() << "[CPP] QmlWatcher: Failed to watch file" << filePath;
        }
    }

    // Watch all .qml files in the same directory (Theme, components, etc.)
    QDir qmlDir(m_contentDir);
    for (const QString& entry : qmlDir.entryList({"*.qml"}, QDir::Files)) {
        QString fullPath = qmlDir.absoluteFilePath(entry);
        if (!m_watcher->files().contains(fullPath)) {
            if (m_watcher->addPath(fullPath)) {
                qDebug() << "[CPP] QmlWatcher: Watching" << entry;
            }
        }
    }

    // Watch the directory (for new/deleted files)
    if (!m_watcher->directories().contains(m_contentDir)) {
        if (m_watcher->addPath(m_contentDir)) {
            qDebug() << "[CPP] QmlWatcher: Watching directory" << m_contentDir;
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
    if (!m_autoReload) return;
    if (!path.endsWith(".qml")) return;

    // Skip zero-byte files (truncate step of atomic save)
    QFileInfo fi(path);
    if (fi.exists() && fi.size() == 0) {
        qDebug() << "[CPP] QmlWatcher: Skipping empty file (truncate step):" << path;
        if (!m_watcher->files().contains(path))
            m_watcher->addPath(path);
        return;
    }

    // Track disappeared files (editor atomic saves: delete + recreate)
    if (!fi.exists()) {
        qDebug() << "[CPP] QmlWatcher: File disappeared:" << path;
        m_deletedFiles.insert(path);
        return;
    }

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

    // Check for reappeared files (editor atomic saves: delete + recreate)
    QSet<QString> reappeared;
    for (const QString& f : m_deletedFiles) {
        if (QFileInfo::exists(f)) {
            reappeared.insert(f);
            if (!m_watcher->files().contains(f))
                m_watcher->addPath(f);
            qDebug() << "[CPP] QmlWatcher: File reappeared:" << QFileInfo(f).fileName();
        }
    }
    if (!reappeared.isEmpty()) {
        m_deletedFiles.subtract(reappeared);
        m_debounce->start();
        return;
    }

    // Rescan for new/deleted .qml files
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
    if (m_currentQmlPath.isEmpty()) {
        qWarning() << "[CPP] QmlWatcher: No content path for reload";
        return;
    }

    qDebug() << "[CPP] QmlWatcher: Reloading content (proxy window)...";

    // 1. Detach old root from window and destroy old engine
    //    Must delete old engine BEFORE creating new one — Qt's global type
    //    registry can serve cached compilations to a new engine otherwise.
    if (g_rootItem) {
        g_rootItem->setParentItem(nullptr);
        delete g_rootItem;
        g_rootItem = nullptr;
    }
    delete g_engine;
    g_engine = nullptr;

    // 2. Create fresh engine with all context properties
    setupEngine();
    g_engine->addImportPath(m_contentDir);

    // 3. Load QML in new engine
    QQmlComponent component(g_engine, QUrl::fromLocalFile(m_currentQmlPath));
    if (component.isError()) {
        qWarning() << "[CPP] QmlWatcher: Reload failed:";
        for (const auto& err : component.errors())
            qWarning().noquote() << err.toString();
        if (g_reloadPopup)
            g_reloadPopup->showError("Failed to load " + m_currentQmlPath);
        return;
    }

    QObject* obj = component.create();
    auto* newRootItem = qobject_cast<QQuickItem*>(obj);
    if (!newRootItem) {
        qWarning() << "[CPP] QmlWatcher: Root QML must be an Item";
        delete obj;
        return;
    }

    // 4. Attach new root to persistent window
    newRootItem->setParentItem(g_window->contentItem());
    newRootItem->setWidth(g_window->width());
    newRootItem->setHeight(g_window->height());
    g_rootItem = newRootItem;

    // 5. Re-emit state so fresh QML picks up current values
    if (m_state) {
        QTimer::singleShot(0, this, [this]() {
            m_state->reemitAll();
        });
    }

    if (g_reloadPopup) g_reloadPopup->showSuccess();
    qDebug() << "[CPP] QmlWatcher: Reload complete (no flicker)";
}
