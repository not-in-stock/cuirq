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

    function applyState(key, value) {
        if (key === "currentPath") root.currentPath = value
        else if (key === "canGoBack") root.canGoBack = (value === "true")
        else if (key === "canGoForward") root.canGoForward = (value === "true")
        else if (key === "itemCount") root.itemCount = parseInt(value) || 0
        else if (key === "breadcrumbs") {
            try { root.breadcrumbs = JSON.parse(value) }
            catch (e) { root.breadcrumbs = [] }
        }
    }

    Connections {
        target: stateNotifier
        function onPropChanged(key, value) { root.applyState(key, value) }
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
                color: theme.background
                Behavior on color { ColorAnimation { duration: theme.animDuration } }

                FileGrid {
                    id: gridView
                    anchors.fill: parent
                    visible: root.viewMode === "grid"
                    opacity: 0
                    transform: Translate { id: gridTranslate; y: theme.animViewOffset }
                }

                FileList {
                    id: listView
                    anchors.fill: parent
                    visible: root.viewMode === "list"
                    opacity: 0
                    transform: Translate { id: listTranslate; y: theme.animViewOffset }
                }

                ParallelAnimation {
                    id: gridFadeIn
                    NumberAnimation { target: gridView; property: "opacity"; from: 0; to: 1; duration: theme.animViewDuration; easing.type: Easing.OutQuad }
                    NumberAnimation { target: gridTranslate; property: "y"; from: theme.animViewOffset; to: 0; duration: theme.animViewDuration; easing.type: Easing.OutQuad }
                }

                ParallelAnimation {
                    id: listFadeIn
                    NumberAnimation { target: listView; property: "opacity"; from: 0; to: 1; duration: theme.animViewDuration; easing.type: Easing.OutQuad }
                    NumberAnimation { target: listTranslate; property: "y"; from: theme.animViewOffset; to: 0; duration: theme.animViewDuration; easing.type: Easing.OutQuad }
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
                    color: theme.toolbarOverlay
                    Behavior on color { ColorAnimation { duration: theme.animDuration } }
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
                    let next = theme.themeMode === "system" ? "light"
                             : theme.themeMode === "light"  ? "dark"
                             : "system"
                    theme.themeMode = next
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
