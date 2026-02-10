#include "fs_watcher.h"

#include <CoreServices/CoreServices.h>
#include <iostream>

static void fsEventsCallback(ConstFSEventStreamRef /*streamRef*/,
                             void* info,
                             size_t numEvents,
                             void* eventPaths,
                             const FSEventStreamEventFlags* /*eventFlags*/,
                             const FSEventStreamEventId* /*eventIds*/)
{
    auto* watcher = static_cast<DirectoryWatcher*>(info);
    char** paths = static_cast<char**>(eventPaths);

    // Determine which watched directory each event belongs to
    for (size_t i = 0; i < numEvents; i++) {
        QString eventPath = QString::fromUtf8(paths[i]);
        // FSEvents reports the exact changed path; find which watched dir it's under
        watcher->restartDebounce(eventPath);
    }
}

DirectoryWatcher::DirectoryWatcher(QObject* parent)
    : QObject(parent)
    , m_debounceTimer(new QTimer(this))
    , m_stream(nullptr)
    , m_callback(nullptr)
{
    m_debounceTimer->setSingleShot(true);

    connect(m_debounceTimer, &QTimer::timeout, this, [this]() {
        if (!m_callback) return;
        // Fire directoryChanged for each pending path
        QSet<QString> pending;
        pending.swap(m_pendingChanges);
        for (const QString& path : pending) {
            QByteArray pathBytes = path.toUtf8();
            QByteArray jsonArgs = "[\"" + pathBytes + "\"]";
            m_callback("directoryChanged", jsonArgs.constData());
        }
    });
}

DirectoryWatcher::~DirectoryWatcher()
{
    stopWatching();
}

void DirectoryWatcher::restartDebounce(const QString& changedPath)
{
    // Find which watched directory this event path belongs to
    for (const QString& watched : m_watchedPaths) {
        if (changedPath.startsWith(watched)) {
            m_pendingChanges.insert(watched);
            break;
        }
    }
    m_debounceTimer->start(150);
}

void DirectoryWatcher::startWatching(const QString& path)
{
    startWatching(QStringList{path});
}

void DirectoryWatcher::startWatching(const QStringList& paths)
{
    if (paths.isEmpty()) {
        stopWatching();
        return;
    }

    // Sort for comparison and deepest-first matching
    QStringList sorted = paths;
    std::sort(sorted.begin(), sorted.end(),
              [](const QString& a, const QString& b) { return a.length() > b.length(); });

    // Skip if already watching the same paths
    if (m_stream && sorted == m_watchedPaths) return;

    stopWatching();
    m_watchedPaths = sorted;

    // Build CFArray of paths
    QVector<CFStringRef> cfStrings;
    cfStrings.reserve(paths.size());
    for (const QString& p : paths) {
        cfStrings.append(CFStringCreateWithCString(kCFAllocatorDefault,
                                                    p.toUtf8().constData(),
                                                    kCFStringEncodingUTF8));
    }

    CFArrayRef pathsToWatch = CFArrayCreate(kCFAllocatorDefault,
                                            (const void**)cfStrings.data(),
                                            cfStrings.size(), nullptr);

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

    for (CFStringRef s : cfStrings) CFRelease(s);
    CFRelease(pathsToWatch);

    if (!stream) {
        std::cerr << "[CPP] ERROR: Failed to create FSEventStream" << std::endl;
        return;
    }

    FSEventStreamSetDispatchQueue(stream, dispatch_get_main_queue());
    FSEventStreamStart(stream);

    m_stream = stream;
    std::cout << "[CPP] Watching " << paths.size() << " directories" << std::endl;
}

void DirectoryWatcher::stopWatching()
{
    if (m_stream) {
        auto stream = static_cast<FSEventStreamRef>(m_stream);
        FSEventStreamStop(stream);
        FSEventStreamInvalidate(stream);
        FSEventStreamRelease(stream);
        m_stream = nullptr;
    }
    m_debounceTimer->stop();
    m_watchedPaths.clear();
    m_pendingChanges.clear();
}

void DirectoryWatcher::setSignalCallback(cuirq::signal_callback_t callback)
{
    m_callback = callback;
}

// MOC output for Q_OBJECT class defined in header
#include "moc_fs_watcher.cpp"
