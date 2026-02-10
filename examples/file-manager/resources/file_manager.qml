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
    property string sortField: "name"
    property bool sortAscending: true
    property int millerActiveCount: 0
    property var millerColumns: []

    function applyState(key, value) {
        if (key === "currentPath")
            root.currentPath = value;
        else if (key === "canGoBack")
            root.canGoBack = (value === "true");
        else if (key === "canGoForward")
            root.canGoForward = (value === "true");
        else if (key === "itemCount")
            root.itemCount = parseInt(value) || 0;
        else if (key === "breadcrumbs") {
            try {
                root.breadcrumbs = JSON.parse(value);
            } catch (e) {
                root.breadcrumbs = [];
            }
        } else if (key === "sortField")
            root.sortField = value;
        else if (key === "sortAscending")
            root.sortAscending = (value === "true");
        else if (key === "millerActiveCount")
            root.millerActiveCount = parseInt(value) || 0;
        else if (key === "millerColumns") {
            try {
                root.millerColumns = JSON.parse(value);
            } catch (e) {
                root.millerColumns = [];
            }
        }
    }

    Connections {
        target: stateNotifier
        function onPropChanged(key, value) {
            root.applyState(key, value);
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

            // Content area — extends behind toolbar and status bar
            Rectangle {
                id: contentArea
                anchors.fill: parent
                clip: true
                color: theme.background
                Behavior on color {
                    ColorAnimation {
                        duration: theme.animDuration
                    }
                }

                FileGrid {
                    id: gridView
                    anchors.fill: parent
                    visible: root.viewMode === "grid"
                    opacity: 0
                    transform: Translate {
                        id: gridTranslate
                        y: theme.animViewOffset
                    }
                }

                FileList {
                    id: listView
                    anchors.fill: parent
                    sortField: root.sortField
                    sortAscending: root.sortAscending
                    visible: root.viewMode === "list"
                    opacity: 0
                    transform: Translate {
                        id: listTranslate
                        y: theme.animViewOffset
                    }
                }

                FileColumns {
                    id: columnsView
                    anchors.fill: parent
                    activeColumnCount: root.millerActiveCount
                    columnsInfo: root.millerColumns
                    visible: root.viewMode === "columns"
                    opacity: 0
                    transform: Translate {
                        id: columnsTranslate
                        y: theme.animViewOffset
                    }
                }

                ParallelAnimation {
                    id: gridFadeIn
                    NumberAnimation {
                        target: gridView
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: theme.animViewDuration
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: gridTranslate
                        property: "y"
                        from: theme.animViewOffset
                        to: 0
                        duration: theme.animViewDuration
                        easing.type: Easing.OutQuad
                    }
                }

                ParallelAnimation {
                    id: listFadeIn
                    NumberAnimation {
                        target: listView
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: theme.animViewDuration
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: listTranslate
                        property: "y"
                        from: theme.animViewOffset
                        to: 0
                        duration: theme.animViewDuration
                        easing.type: Easing.OutQuad
                    }
                }

                ParallelAnimation {
                    id: columnsFadeIn
                    NumberAnimation {
                        target: columnsView
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: theme.animViewDuration
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: columnsTranslate
                        property: "y"
                        from: theme.animViewOffset
                        to: 0
                        duration: theme.animViewDuration
                        easing.type: Easing.OutQuad
                    }
                }

                Connections {
                    target: root
                    function onViewModeChanged() {
                        if (root.viewMode === "grid")
                            gridFadeIn.restart();
                        else if (root.viewMode === "list")
                            listFadeIn.restart();
                        else if (root.viewMode === "columns")
                            columnsFadeIn.restart();
                        signalForwarder.emitSignal("viewModeChanged", [root.viewMode]);
                    }
                    function onCurrentPathChanged() {
                        if (root.viewMode === "grid")
                            gridFadeIn.restart();
                        else if (root.viewMode === "list")
                            listFadeIn.restart();
                        // columns: no fade-in on path change — columns manage their own content
                    }
                }

                Component.onCompleted: gridFadeIn.start()
            }

            BlurPanel {
                id: toolbarBlur
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: toolbar.height
                z: 1
                sourceItem: contentArea
                overlayColor: theme.toolbarOverlay
            }

            BlurPanel {
                id: listHeaderBlur
                anchors.left: parent.left
                anchors.right: parent.right
                y: theme.toolbarHeight
                height: theme.listHeaderHeight
                z: 1
                visible: root.viewMode === "list"
                sourceItem: contentArea
            }

            // List header controls — on top of blur
            Item {
                id: listHeaderControls
                anchors.left: parent.left
                anchors.right: parent.right
                y: theme.toolbarHeight
                height: theme.listHeaderHeight
                z: 2
                visible: root.viewMode === "list"

                Row {
                    anchors.fill: parent

                    ColumnHeader {
                        label: "Name"
                        field: "name"
                        width: parent.width - listView.colRightWidth - theme.listPadding
                    }
                    ColumnHeader {
                        label: "Size"
                        field: "sizeBytes"
                        width: listView.colSizeWidth
                    }
                    ColumnHeader {
                        label: "Date Modified"
                        field: "modified"
                        width: listView.colDateWidth
                    }
                    ColumnHeader {
                        label: "Type"
                        field: "fileType"
                        width: listView.colTypeWidth
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: theme.separator
                }
            }

            // Toolbar controls — on top of everything
            Toolbar {
                id: toolbar
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                z: 3
                canGoBack: root.canGoBack
                canGoForward: root.canGoForward
                breadcrumbs: root.breadcrumbs
                viewMode: root.viewMode
                onViewModeRequested: mode => root.viewMode = mode
                onThemeCycled: {
                    let next = theme.themeMode === "system" ? "light" : theme.themeMode === "light" ? "dark" : "system";
                    theme.themeMode = next;
                    signalForwarder.emitSignal("themeChanged", [next]);
                }
            }

            BlurPanel {
                id: statusBarBlur
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: statusBar.height
                z: 1
                sourceItem: contentArea
            }

            StatusBar {
                id: statusBar
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                z: 2
                itemCount: root.itemCount
                currentPath: root.currentPath
            }
        }
    }

    component ColumnHeader: Item {
        id: colHeader
        property string label
        property string field
        property bool active: root.sortField === field

        height: parent.height

        Rectangle {
            anchors.fill: parent
            color: headerMouse.containsMouse ? theme.surfaceHover : theme.surfaceHoverOff
            Behavior on color {
                ColorAnimation {
                    duration: theme.animHoverDuration
                }
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 12
            spacing: 4

            Text {
                text: colHeader.label
                font.pixelSize: 11
                font.weight: colHeader.active ? Font.DemiBold : Font.Normal
                color: colHeader.active ? theme.textPrimary : theme.textSecondary
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: root.sortAscending ? "\u25B2" : "\u25BC"
                font.pixelSize: 8
                color: theme.textSecondary
                visible: colHeader.active
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: headerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.sortField === colHeader.field) {
                    root.sortAscending = !root.sortAscending;
                } else {
                    root.sortField = colHeader.field;
                    root.sortAscending = true;
                }
                signalForwarder.emitSignal("sortChanged", [root.sortField, root.sortAscending ? "true" : "false"]);
            }
        }
    }
}
