import QtQuick

Rectangle {
    id: fileItem

    property string fileName: ""
    property string filePath: ""
    property bool isDir: false
    property string fileSize: ""
    property string fileType: "other"

    width: 130
    height: 130
    radius: 10
    color: mouseArea.containsMouse ? "#F1F5F9" : "transparent"

    Behavior on color { ColorAnimation { duration: 150 } }

    Column {
        anchors.centerIn: parent
        spacing: 8

        // Icon circle
        Rectangle {
            width: 56
            height: 56
            radius: 28
            anchors.horizontalCenter: parent.horizontalCenter
            color: {
                switch (fileItem.fileType) {
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
                font.pixelSize: 24
                text: {
                    switch (fileItem.fileType) {
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
            text: fileItem.fileName
            font.pixelSize: 12
            color: "#334155"
            width: 110
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }

        // File size (only for files)
        Text {
            text: fileItem.isDir ? "" : fileItem.fileSize
            font.pixelSize: 10
            color: "#94A3B8"
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !fileItem.isDir
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onDoubleClicked: {
            if (fileItem.isDir) {
                signalForwarder.emitSignal("navigate", [fileItem.filePath])
            }
        }
    }
}
