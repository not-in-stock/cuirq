import QtQuick
import QtQuick.Controls

Rectangle {
    id: fileList
    color: "#F8FAFC"

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
                Rectangle {
                    width: 28
                    height: 28
                    radius: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: {
                        switch (model.fileType) {
                            case "folder":   return "#FEF3C7"
                            case "document": return "#DBEAFE"
                            case "image":    return "#D1FAE5"
                            case "audio":    return "#FCE7F3"
                            case "video":    return "#EDE9FE"
                            case "code":     return "#E0E7FF"
                            case "archive":  return "#FEE2E2"
                            default:         return "#F1F5F9"
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        font.pixelSize: 14
                        text: {
                            switch (model.fileType) {
                                case "folder":   return "\uD83D\uDCC1"
                                case "document": return "\uD83D\uDCC4"
                                case "image":    return "\uD83D\uDDBC"
                                case "audio":    return "\uD83C\uDFB5"
                                case "video":    return "\uD83C\uDFAC"
                                case "code":     return "\uD83D\uDCBB"
                                case "archive":  return "\uD83D\uDCE6"
                                default:         return "\uD83D\uDCC3"
                            }
                        }
                    }
                }

                // File name
                Text {
                    text: model.name
                    font.pixelSize: 13
                    color: "#334155"
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 40
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
