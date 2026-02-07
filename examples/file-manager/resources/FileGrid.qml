import QtQuick
import QtQuick.Controls

Rectangle {
    id: fileGrid
    color: Theme.background
    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

    GridView {
        id: gridView
        anchors.fill: parent
        topMargin: 48
        leftMargin: 20
        cellWidth: 150
        cellHeight: 150
        clip: true

        model: files

        delegate: FileItem {
            fileName: model.name
            filePath: model.path
            isDir: model.isDir
            fileSize: model.size
            fileType: model.fileType
        }

        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animItemDuration }
            NumberAnimation { property: "scale"; from: Theme.animItemScale; to: 1; duration: Theme.animItemDuration }
        }
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.animItemDuration }
            NumberAnimation { property: "scale"; to: Theme.animItemScale; duration: Theme.animItemDuration }
        }
        displaced: Transition {
            NumberAnimation { properties: "x,y"; duration: Theme.animItemDuration; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.centerIn: parent
            text: "This folder is empty"
            font.pixelSize: 16
            color: Theme.textSecondary
            visible: gridView.count === 0
        }
    }

    OverlayScrollBar {
        flickable: gridView
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 48
        anchors.bottom: parent.bottom
    }
}
