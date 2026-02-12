import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    // Window configuration (read by C++ on first load)
    property string windowTitle: "cuirq File Manager"
    property int windowWidth: 1024
    property int windowHeight: 700
    property color windowColor: "transparent"

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
    property int selectedIndex: -1

    // Grid column count (mirrors FileGrid calculation)
    readonly property real _gridAvailableWidth: Math.max(Theme.gridMinCellWidth, root.width - Theme.sidebarWidth)
    readonly property int _gridColumns: Math.max(1, Math.floor(_gridAvailableWidth / Theme.gridMinCellWidth))

    function _qtKeyToString(key, text) {
        switch (key) {
        case Qt.Key_Up:      return "Up";
        case Qt.Key_Down:    return "Down";
        case Qt.Key_Left:    return "Left";
        case Qt.Key_Right:   return "Right";
        case Qt.Key_Return:  return "Return";
        case Qt.Key_Enter:   return "Return";
        case Qt.Key_Escape:  return "Escape";
        case Qt.Key_Tab:     return "Tab";
        case Qt.Key_Backspace: return "Backspace";
        case Qt.Key_Space:   return "Space";
        case Qt.Key_Home:    return "Home";
        case Qt.Key_End:     return "End";
        case Qt.Key_PageUp:  return "PageUp";
        case Qt.Key_PageDown: return "PageDown";
        case Qt.Key_BracketLeft:  return "[";
        case Qt.Key_BracketRight: return "]";
        case Qt.Key_1:       return "1";
        case Qt.Key_2:       return "2";
        case Qt.Key_3:       return "3";
        default:             return text;
        }
    }

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
        } else if (key === "viewMode")
            root.viewMode = value;
        else if (key === "selectedIndex")
            root.selectedIndex = parseInt(value) ?? -1;
    }

    Connections {
        target: stateNotifier
        function onPropChanged(key, value) {
            root.applyState(key, value);
        }
    }

    FocusScope {
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            let hasText = event.text.length > 0 && event.text.charCodeAt(0) > 31;
            let modifiers = [];
            if (event.modifiers & Qt.ControlModifier) modifiers.push("Cmd");
            // Only add Shift for non-printable keys — for letters, case already encodes shift
            if ((event.modifiers & Qt.ShiftModifier) && !hasText) modifiers.push("Shift");
            let keyStr = modifiers.length > 0
                ? modifiers.join("+") + "+" + root._qtKeyToString(event.key, event.text)
                : root._qtKeyToString(event.key, event.text);
            if (keyStr === "") return;
            signalForwarder.emitSignal("keyPress", [keyStr, root._gridColumns]);
            event.accepted = true;
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
                color: Theme.background
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animDuration
                    }
                }

                FileGrid {
                    id: gridView
                    anchors.fill: parent
                    selectedIndex: root.selectedIndex
                    visible: root.viewMode === "grid"
                    opacity: 0
                    transform: Translate {
                        id: gridTranslate
                        y: Theme.animViewOffset
                    }
                }

                FileList {
                    id: listView
                    anchors.fill: parent
                    selectedIndex: root.selectedIndex
                    sortField: root.sortField
                    sortAscending: root.sortAscending
                    visible: root.viewMode === "list"
                    opacity: 0
                    transform: Translate {
                        id: listTranslate
                        y: Theme.animViewOffset
                    }
                }

                FileColumns {
                    id: columnsView
                    anchors.fill: parent
                    activeColumnCount: root.millerActiveCount
                    columnsInfo: root.millerColumns
                    selectedIndex: root.selectedIndex
                    visible: root.viewMode === "columns"
                    opacity: 0
                    transform: Translate {
                        id: columnsTranslate
                        y: Theme.animViewOffset
                    }
                }

                ParallelAnimation {
                    id: gridFadeIn
                    NumberAnimation {
                        target: gridView
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Theme.animViewDuration
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: gridTranslate
                        property: "y"
                        from: Theme.animViewOffset
                        to: 0
                        duration: Theme.animViewDuration
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
                        duration: Theme.animViewDuration
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: listTranslate
                        property: "y"
                        from: Theme.animViewOffset
                        to: 0
                        duration: Theme.animViewDuration
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
                        duration: Theme.animViewDuration
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: columnsTranslate
                        property: "y"
                        from: Theme.animViewOffset
                        to: 0
                        duration: Theme.animViewDuration
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
                overlayColor: Theme.toolbarOverlay
            }

            BlurPanel {
                id: listHeaderBlur
                anchors.left: parent.left
                anchors.right: parent.right
                y: Theme.toolbarHeight
                height: Theme.listHeaderHeight
                z: 1
                visible: root.viewMode === "list"
                sourceItem: contentArea
            }

            // List header controls — on top of blur
            Item {
                id: listHeaderControls
                anchors.left: parent.left
                anchors.right: parent.right
                y: Theme.toolbarHeight
                height: Theme.listHeaderHeight
                z: 2
                visible: root.viewMode === "list"

                Row {
                    anchors.fill: parent

                    ColumnHeader {
                        label: "Name"
                        field: "name"
                        width: parent.width - listView.colRightWidth - Theme.listPadding
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
                    color: Theme.separator
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
                    let next = Theme.themeMode === "system" ? "light" : Theme.themeMode === "light" ? "dark" : "system";
                    Theme.themeMode = next;
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
    }   // FocusScope

    component ColumnHeader: Item {
        id: colHeader
        property string label
        property string field
        property bool active: root.sortField === field

        height: parent.height

        Rectangle {
            anchors.fill: parent
            color: headerMouse.containsMouse ? Theme.surfaceHover : Theme.surfaceHoverOff
            Behavior on color {
                ColorAnimation {
                    duration: Theme.animHoverDuration
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
                color: colHeader.active ? Theme.textPrimary : Theme.textSecondary
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: root.sortAscending ? "\u25B2" : "\u25BC"
                font.pixelSize: 8
                color: Theme.textSecondary
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
