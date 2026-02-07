#ifndef QMLWATCHER_H
#define QMLWATCHER_H

#include <QObject>
#include <QFileSystemWatcher>
#include <QQmlApplicationEngine>
#include <QString>
#include <QMap>
#include <QTimer>

class StateObject;

/**
 * QmlWatcher - Watches QML files and triggers automatic reload on changes.
 *
 * Inspired by QuickShell's approach to live development.
 * This class is designed to be compile-time excluded in production builds.
 */
class QmlWatcher : public QObject
{
    Q_OBJECT

public:
    explicit QmlWatcher(QQmlApplicationEngine* engine, QObject *parent = nullptr);
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
    QQmlApplicationEngine* m_engine;
    QFileSystemWatcher* m_watcher;
    QTimer* m_debounce;
    StateObject* m_state;
    QObject* m_themeObject;
    bool m_autoReload;
    QString m_currentQmlPath;

    void reloadContent();
    void loadTheme(const QString& contentDir);
};

#endif // QMLWATCHER_H
