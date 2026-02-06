import QtQuick
import QtQuick.Controls

Rectangle {
    id: fileGrid
    color: Theme.background
    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

    GridView {
        id: gridView
        anchors.fill: parent
        anchors.topMargin: 0
        anchors.leftMargin: 20
        anchors.rightMargin: 0
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

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Text {
            anchors.centerIn: parent
            text: "This folder is empty"
            font.pixelSize: 16
            color: Theme.textSecondary
            visible: gridView.count === 0
        }
    }
}
