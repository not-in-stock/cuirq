import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property string windowTitle: "cuirq File Manager"
    property int windowWidth: 1024
    property int windowHeight: 700

    property string currentPath: ""
    property bool canGoBack: false
    property bool canGoForward: false
    property int itemCount: 0
    property var breadcrumbs: []
    property string viewMode: "grid"

    Connections {
        target: stateNotifier
        function onPropChanged(key, value) {
            if (key === "currentPath") root.currentPath = value
            else if (key === "canGoBack") root.canGoBack = (value === "true")
            else if (key === "canGoForward") root.canGoForward = (value === "true")
            else if (key === "itemCount") root.itemCount = parseInt(value) || 0
            else if (key === "breadcrumbs") {
                try {
                    root.breadcrumbs = JSON.parse(value)
                } catch (e) {
                    root.breadcrumbs = []
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Sidebar {
            Layout.fillHeight: true
            currentPath: root.currentPath
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Content area — extends behind toolbar, stops above status bar
            Rectangle {
                id: contentArea
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: statusBar.top
                clip: true
                color: Theme.background
                Behavior on color { ColorAnimation { duration: Theme.animDuration } }

                FileGrid {
                    id: gridView
                    anchors.fill: parent
                    visible: root.viewMode === "grid"
                    opacity: 0
                    transform: Translate { id: gridTranslate; y: Theme.animViewOffset }
                }

                FileList {
                    id: listView
                    anchors.fill: parent
                    visible: root.viewMode === "list"
                    opacity: 0
                    transform: Translate { id: listTranslate; y: Theme.animViewOffset }
                }

                ParallelAnimation {
                    id: gridFadeIn
                    NumberAnimation { target: gridView; property: "opacity"; from: 0; to: 1; duration: Theme.animViewDuration; easing.type: Easing.OutQuad }
                    NumberAnimation { target: gridTranslate; property: "y"; from: Theme.animViewOffset; to: 0; duration: Theme.animViewDuration; easing.type: Easing.OutQuad }
                }

                ParallelAnimation {
                    id: listFadeIn
                    NumberAnimation { target: listView; property: "opacity"; from: 0; to: 1; duration: Theme.animViewDuration; easing.type: Easing.OutQuad }
                    NumberAnimation { target: listTranslate; property: "y"; from: Theme.animViewOffset; to: 0; duration: Theme.animViewDuration; easing.type: Easing.OutQuad }
                }

                Connections {
                    target: root
                    function onViewModeChanged() {
                        if (root.viewMode === "grid") gridFadeIn.restart()
                        else listFadeIn.restart()
                    }
                    function onCurrentPathChanged() {
                        if (root.viewMode === "grid") gridFadeIn.restart()
                        else listFadeIn.restart()
                    }
                }

                Component.onCompleted: gridFadeIn.start()
            }

            // Toolbar blur background — captures content behind toolbar and blurs it
            Item {
                id: toolbarBlur
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: toolbar.height
                z: 1
                clip: true

                ShaderEffectSource {
                    id: toolbarBlurSource
                    // Full contentArea size — no sourceRect, avoids scaling artifacts
                    width: contentArea.width
                    height: contentArea.height
                    sourceItem: contentArea
                    visible: false
                }

                FastBlur {
                    width: contentArea.width
                    height: contentArea.height
                    source: toolbarBlurSource
                    radius: 64
                    cached: true
                    transparentBorder: false
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.darkMode ? Qt.rgba(0.08, 0.1, 0.16, 0.80)
                                          : Qt.rgba(1, 1, 1, 0.65)
                    Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                }
            }

            // Toolbar controls — on top of blur
            Toolbar {
                id: toolbar
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                z: 2
                canGoBack: root.canGoBack
                canGoForward: root.canGoForward
                breadcrumbs: root.breadcrumbs
                viewMode: root.viewMode
                onViewModeRequested: (mode) => root.viewMode = mode
                onThemeCycled: {
                    let next = Theme.themeMode === "system" ? "light"
                             : Theme.themeMode === "light"  ? "dark"
                             : "system"
                    Theme.themeMode = next
                    signalForwarder.emitSignal("themeChanged", [next])
                }
            }

            StatusBar {
                id: statusBar
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                itemCount: root.itemCount
                currentPath: root.currentPath
            }
        }
    }
}
