import QtQuick
import QtQuick.Controls

Rectangle {
    id: fileGrid
    property bool darkMode: false
    color: darkMode ? "#1E293B" : "#FFFFFF"
    Behavior on color { ColorAnimation { duration: 200 } }

    GridView {
        id: gridView
        anchors.fill: parent
        anchors.topMargin: 12
        anchors.leftMargin: 20
        anchors.rightMargin: 20
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
            darkMode: fileGrid.darkMode
        }

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Text {
            anchors.centerIn: parent
            text: "This folder is empty"
            font.pixelSize: 16
            color: "#94A3B8"
            visible: gridView.count === 0
        }
    }
}
