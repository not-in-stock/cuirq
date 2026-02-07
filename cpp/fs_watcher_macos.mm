#include "fs_watcher.h"

#include <CoreServices/CoreServices.h>
#include <iostream>

static void fsEventsCallback(ConstFSEventStreamRef /*streamRef*/,
                             void* info,
                             size_t /*numEvents*/,
                             void* /*eventPaths*/,
                             const FSEventStreamEventFlags* /*eventFlags*/,
                             const FSEventStreamEventId* /*eventIds*/)
{
    auto* watcher = static_cast<DirectoryWatcher*>(info);
    // Restart debounce timer — we're on the main queue
    watcher->restartDebounce();
}

DirectoryWatcher::DirectoryWatcher(QObject* parent)
    : QObject(parent)
    , m_debounceTimer(new QTimer(this))
    , m_stream(nullptr)
    , m_callback(nullptr)
{
    m_debounceTimer->setSingleShot(true);

    connect(m_debounceTimer, &QTimer::timeout, this, [this]() {
        if (m_callback && !m_watchedPath.isEmpty()) {
            QByteArray pathBytes = m_watchedPath.toUtf8();
            // JSON array with the path
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

    CFStringRef cfPath = CFStringCreateWithCString(kCFAllocatorDefault,
                                                    path.toUtf8().constData(),
                                                    kCFStringEncodingUTF8);
    CFArrayRef pathsToWatch = CFArrayCreate(kCFAllocatorDefault,
                                            (const void**)&cfPath, 1, nullptr);

    FSEventStreamContext context = {0, this, nullptr, nullptr, nullptr};

    FSEventStreamRef stream = FSEventStreamCreate(
        kCFAllocatorDefault,
        &fsEventsCallback,
        &context,
        pathsToWatch,
        kFSEventStreamEventIdSinceNow,
        0.0, // latency — we debounce ourselves
        kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents
    );

    CFRelease(cfPath);
    CFRelease(pathsToWatch);

    if (!stream) {
        std::cerr << "[CPP] ERROR: Failed to create FSEventStream for: "
                  << path.toStdString() << std::endl;
        return;
    }

    FSEventStreamSetDispatchQueue(stream, dispatch_get_main_queue());
    FSEventStreamStart(stream);

    m_stream = stream;
    std::cout << "[CPP] Watching directory: " << path.toStdString() << std::endl;
}

void DirectoryWatcher::stopWatching()
{
    if (m_stream) {
        auto stream = static_cast<FSEventStreamRef>(m_stream);
        FSEventStreamStop(stream);
        FSEventStreamInvalidate(stream);
        FSEventStreamRelease(stream);
        m_stream = nullptr;
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
