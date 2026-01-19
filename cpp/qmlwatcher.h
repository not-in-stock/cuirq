#ifndef QMLWATCHER_H
#define QMLWATCHER_H

#include <QObject>
#include <QFileSystemWatcher>
#include <QQmlApplicationEngine>
#include <QString>
#include <QMap>

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
    ~QmlWatcher() override;

    // Watch a QML file for changes
    void watchFile(const QString& filePath);

    // Stop watching a file
    void unwatchFile(const QString& filePath);

    // Enable/disable automatic reload
    void setAutoReload(bool enabled);
    bool isAutoReloadEnabled() const { return m_autoReload; }

private slots:
    void onFileChanged(const QString& path);

private:
    QQmlApplicationEngine* m_engine;
    QFileSystemWatcher* m_watcher;
    bool m_autoReload;
    QString m_currentQmlPath;
    QMap<QString, QVariant> m_savedProperties; // For preserving state during reload

    void reloadQml(const QString& path);
    void saveContextProperties();
    void restoreContextProperties();
};

#endif // QMLWATCHER_H
