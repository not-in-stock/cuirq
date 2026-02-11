#ifndef QMLWATCHER_H
#define QMLWATCHER_H

#include <QObject>
#include <QFileSystemWatcher>
#include <QString>
#include <QSet>
#include <QTimer>

class StateObject;

/**
 * QmlWatcher - Watches QML files and triggers engine-per-reload on changes.
 *
 * On file change: destroys old engine, creates fresh one via setupEngine(),
 * re-loads root QML. Accepts brief flicker (window destroyed + recreated).
 *
 * Compile-time excluded in production builds (CUIRQ_DEV_RELOAD).
 */
class QmlWatcher : public QObject
{
    Q_OBJECT

public:
    explicit QmlWatcher(QObject *parent = nullptr);
    void setStateObject(StateObject* state);
    ~QmlWatcher() override;

    // Watch a QML file and its directory for changes
    void watchFile(const QString& filePath);

    // Stop watching a file
    void unwatchFile(const QString& filePath);

    // Enable/disable automatic reload
    void setAutoReload(bool enabled);
    bool isAutoReloadEnabled() const { return m_autoReload; }

private slots:
    void onFileChanged(const QString& path);
    void onDirectoryChanged(const QString& path);

private:
    QFileSystemWatcher* m_watcher;
    QTimer* m_debounce;
    StateObject* m_state;
    bool m_autoReload;
    QString m_currentQmlPath;
    QString m_contentDir;
    QSet<QString> m_deletedFiles;

    void reloadContent();
};

#endif // QMLWATCHER_H
