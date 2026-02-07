#ifndef FS_WATCHER_H
#define FS_WATCHER_H

#include <QObject>
#include <QString>
#include <QTimer>

#include "qt_engine.h"

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
    void* m_stream; // FSEventStreamRef (opaque)
    QString m_watchedPath;
    cuirq::signal_callback_t m_callback;
};

#endif // FS_WATCHER_H
