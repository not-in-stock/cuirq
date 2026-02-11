#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQuickWindow>
#include <QQuickStyle>
#include <QFileSystemWatcher>
#include <QFileInfo>
#include <QTimer>
#include <QDebug>

#include "qml_file_override.h"

int main(int argc, char* argv[]) {
    QQuickStyle::setStyle("Basic");
    QGuiApplication app(argc, argv);

    // File override must be created before any QML loading
    QmlFileOverride fileOverride;

    QQmlApplicationEngine engine;

    QString qmlPath = QFileInfo("ui.qml").absoluteFilePath();
    QUrl qmlUrl = QUrl::fromLocalFile(qmlPath);

    // Track root object ourselves (QQmlComponent-based reload)
    QObject* rootObject = nullptr;

    auto loadQml = [&]() {
        QQmlComponent component(&engine, qmlUrl);
        if (component.isError()) {
            for (const auto& error : component.errors())
                qWarning() << error.toString();
            return;
        }
        rootObject = component.create();
        if (!rootObject) {
            qWarning() << "Failed to create root object";
            return;
        }
        // Show the window
        if (auto* window = qobject_cast<QQuickWindow*>(rootObject))
            window->show();
    };

    qDebug() << "Loading:" << qmlPath;
    loadQml();

    if (!rootObject) {
        qCritical() << "Failed to load QML";
        return -1;
    }

    // Watch for changes
    QFileSystemWatcher watcher;
    watcher.addPath(qmlPath);

    QTimer debounce;
    debounce.setSingleShot(true);
    debounce.setInterval(150);

    QObject::connect(&watcher, &QFileSystemWatcher::fileChanged,
                     &debounce, [&debounce, &watcher](const QString& path) {
        // Re-add path — some editors replace the file (FSEvents stops tracking)
        if (!watcher.files().contains(path))
            watcher.addPath(path);
        debounce.start();
    });

    QObject::connect(&debounce, &QTimer::timeout, [&]() {
        qDebug() << "Reloading...";

        // 1. Read new contents into override
        fileOverride.updateFile(qmlPath);

        // 2. Clear QML cache
        engine.clearComponentCache();

        // 3. Create new tree BEFORE destroying old one (avoid flicker)
        QObject* oldRoot = rootObject;
        rootObject = nullptr;

        // Remember old window geometry
        QRect oldGeometry;
        if (auto* oldWindow = qobject_cast<QQuickWindow*>(oldRoot))
            oldGeometry = oldWindow->geometry();

        loadQml();

        // Restore geometry and show new window before destroying old
        if (auto* newWindow = qobject_cast<QQuickWindow*>(rootObject)) {
            if (!oldGeometry.isNull())
                newWindow->setGeometry(oldGeometry);
        }

        // 4. Now destroy old tree
        delete oldRoot;

        if (rootObject) {
            qDebug() << "Reload complete.";
        } else {
            qWarning() << "Reload produced no root objects (QML error?)";
        }
    });

    return app.exec();
}
