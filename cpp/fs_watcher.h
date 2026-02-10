#ifndef FS_WATCHER_H
#define FS_WATCHER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QSet>

#include "qt_engine.h"

#ifndef Q_OS_MACOS
class QFileSystemWatcher;
#endif

class DirectoryWatcher : public QObject {
    Q_OBJECT

public:
    explicit DirectoryWatcher(QObject* parent = nullptr);
    ~DirectoryWatcher() override;

    void startWatching(const QString& path);
    void startWatching(const QStringList& paths);
    void stopWatching();
    void setSignalCallback(cuirq::signal_callback_t callback);

    void restartDebounce(const QString& changedPath);

private:
    QTimer* m_debounceTimer;
#ifdef Q_OS_MACOS
    void* m_stream; // FSEventStreamRef (opaque)
#else
    QFileSystemWatcher* m_fsWatcher;
#endif
    QStringList m_watchedPaths;
    QSet<QString> m_pendingChanges;
    cuirq::signal_callback_t m_callback;
};

#endif // FS_WATCHER_H
