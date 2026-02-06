import QtQuick
import QtQuick.Controls

Rectangle {
    id: fileGrid
    color: "#F8FAFC"

    GridView {
        id: gridView
        anchors.fill: parent
        anchors.margins: 16
        cellWidth: 140
        cellHeight: 140
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

        // Empty state
        Text {
            anchors.centerIn: parent
            text: "This folder is empty"
            font.pixelSize: 16
            color: "#94A3B8"
            visible: gridView.count === 0
        }
    }
}
