#include "fs_watcher.h"

#include <QFileSystemWatcher>
#include <iostream>

DirectoryWatcher::DirectoryWatcher(QObject* parent)
    : QObject(parent)
    , m_debounceTimer(new QTimer(this))
    , m_fsWatcher(nullptr)
    , m_callback(nullptr)
{
    m_debounceTimer->setSingleShot(true);

    connect(m_debounceTimer, &QTimer::timeout, this, [this]() {
        if (m_callback && !m_watchedPath.isEmpty()) {
            QByteArray pathBytes = m_watchedPath.toUtf8();
            QByteArray jsonArgs = "[\"" + pathBytes + "\"]";
            m_callback("directoryChanged", jsonArgs.constData());
        }
    });
}

DirectoryWatcher::~DirectoryWatcher()
{
    stopWatching();
}

void DirectoryWatcher::restartDebounce()
{
    m_debounceTimer->start(150);
}

void DirectoryWatcher::startWatching(const QString& path)
{
    stopWatching();

    m_watchedPath = path;
    m_fsWatcher = new QFileSystemWatcher(this);
    m_fsWatcher->addPath(path);

    connect(m_fsWatcher, &QFileSystemWatcher::directoryChanged,
            this, &DirectoryWatcher::restartDebounce);

    std::cout << "[CPP] Watching directory: " << path.toStdString() << std::endl;
}

void DirectoryWatcher::stopWatching()
{
    if (m_fsWatcher) {
        delete m_fsWatcher;
        m_fsWatcher = nullptr;
        std::cout << "[CPP] Stopped watching directory" << std::endl;
    }
    m_debounceTimer->stop();
    m_watchedPath.clear();
}

void DirectoryWatcher::setSignalCallback(cuirq::signal_callback_t callback)
{
    m_callback = callback;
}

// MOC output for Q_OBJECT class defined in header
#include "moc_fs_watcher.cpp"
