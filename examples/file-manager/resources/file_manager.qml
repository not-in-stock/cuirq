import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

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

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Toolbar {
            Layout.fillWidth: true
            canGoBack: root.canGoBack
            canGoForward: root.canGoForward
            breadcrumbs: root.breadcrumbs
            viewMode: root.viewMode
            onViewModeRequested: (mode) => root.viewMode = mode
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Sidebar {
                Layout.fillHeight: true
                currentPath: root.currentPath
            }

            // Animated view container
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                color: "#FFFFFF"

                FileGrid {
                    id: gridView
                    anchors.fill: parent
                    visible: root.viewMode === "grid"
                    opacity: 0
                    transform: Translate { id: gridTranslate; y: 4 }
                }

                FileList {
                    id: listView
                    anchors.fill: parent
                    visible: root.viewMode === "list"
                    opacity: 0
                    transform: Translate { id: listTranslate; y: 4 }
                }

                // Fade-in + slide-up animation (matches original mockup: 150ms ease-out)
                ParallelAnimation {
                    id: gridFadeIn
                    NumberAnimation { target: gridView; property: "opacity"; from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad }
                    NumberAnimation { target: gridTranslate; property: "y"; from: 4; to: 0; duration: 250; easing.type: Easing.OutQuad }
                }

                ParallelAnimation {
                    id: listFadeIn
                    NumberAnimation { target: listView; property: "opacity"; from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad }
                    NumberAnimation { target: listTranslate; property: "y"; from: 4; to: 0; duration: 250; easing.type: Easing.OutQuad }
                }

                Connections {
                    target: root
                    function onViewModeChanged() {
                        if (root.viewMode === "grid") gridFadeIn.restart()
                        else listFadeIn.restart()
                    }
                }

                // Initial fade-in
                Component.onCompleted: gridFadeIn.start()
            }
        }

        StatusBar {
            Layout.fillWidth: true
            itemCount: root.itemCount
            currentPath: root.currentPath
        }
    }
}
