import QtQuick
import QtQuick.Controls

Rectangle {
    id: fileGrid
    color: theme.background
    Behavior on color { ColorAnimation { duration: theme.animDuration } }

    readonly property real _availableWidth: Math.max(theme.gridMinCellWidth, gridView.width)
    readonly property int _columns: Math.max(1, Math.floor(_availableWidth / theme.gridMinCellWidth))

    GridView {
        id: gridView
        anchors.fill: parent
        topMargin: theme.toolbarHeight + 10
        bottomMargin: theme.statusBarHeight
        cellWidth: fileGrid._availableWidth / fileGrid._columns
        cellHeight: theme.gridCellHeight
        clip: true

        model: files

        delegate: Item {
            width: gridView.cellWidth
            height: gridView.cellHeight

            FileItem {
                anchors.horizontalCenter: parent.horizontalCenter
                fileName: model.name
                filePath: model.path
                isDir: model.isDir
                fileSize: model.size
                fileType: model.fileType
            }
        }

        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: theme.animItemDuration }
            NumberAnimation { property: "scale"; from: theme.animItemScale; to: 1; duration: theme.animItemDuration }
        }
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: theme.animItemDuration }
            NumberAnimation { property: "scale"; to: theme.animItemScale; duration: theme.animItemDuration }
        }
        displaced: Transition {
            NumberAnimation { properties: "x,y"; duration: theme.animItemDuration; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.centerIn: parent
            text: "This folder is empty"
            font.pixelSize: 16
            color: theme.textSecondary
            visible: gridView.count === 0
        }
    }

    OverlayScrollBar {
        flickable: gridView
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: theme.toolbarHeight
        anchors.bottom: parent.bottom
        anchors.bottomMargin: theme.statusBarHeight
    }
}
