#ifndef FS_WATCHER_H
#define FS_WATCHER_H

#include <QObject>
#include <QString>
#include <QTimer>

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
    void stopWatching();
    void setSignalCallback(cuirq::signal_callback_t callback);

    void restartDebounce();

private:
    QTimer* m_debounceTimer;
#ifdef Q_OS_MACOS
    void* m_stream; // FSEventStreamRef (opaque)
#else
    QFileSystemWatcher* m_fsWatcher;
#endif
    QString m_watchedPath;
    cuirq::signal_callback_t m_callback;
};

#endif // FS_WATCHER_H
