import QtQuick
import QtQuick.Controls

Rectangle {
    id: fileList
    color: "#FFFFFF"

    function iconSource(type) {
        switch (type) {
            case "folder":   return "icons/folder.svg"
            case "document": return "icons/document.svg"
            case "image":    return "icons/image.svg"
            case "audio":    return "icons/audio.svg"
            case "video":    return "icons/video.svg"
            case "code":     return "icons/code.svg"
            case "archive":  return "icons/archive.svg"
            default:         return "icons/file.svg"
        }
    }

    ListView {
        id: listView
        anchors.fill: parent
        anchors.margins: 8
        clip: true
        spacing: 1

        model: files

        delegate: Rectangle {
            id: listItem
            width: listView.width
            height: 40
            radius: 6
            color: listMouse.containsMouse ? "#F1F5F9" : "transparent"

            Behavior on color { ColorAnimation { duration: 150 } }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: sizeText.left
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                // Icon
                Image {
                    source: fileList.iconSource(model.fileType)
                    width: 24
                    height: 24
                    sourceSize.width: 24
                    sourceSize.height: 24
                    anchors.verticalCenter: parent.verticalCenter
                }

                // File name
                Text {
                    text: model.name
                    font.pixelSize: 13
                    color: "#334155"
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 36
                }
            }

            // File size
            Text {
                id: sizeText
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: model.isDir ? "" : model.size
                font.pixelSize: 12
                color: "#94A3B8"
            }

            MouseArea {
                id: listMouse
                anchors.fill: parent
                hoverEnabled: true
                onDoubleClicked: {
                    if (model.isDir) {
                        signalForwarder.emitSignal("navigate", [model.path])
                    }
                }
            }
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
            visible: listView.count === 0
        }
    }
}
