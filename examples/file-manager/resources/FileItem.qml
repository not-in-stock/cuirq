import QtQuick

Rectangle {
    id: fileItem

    property string fileName: ""
    property string filePath: ""
    property bool isDir: false
    property string fileSize: ""
    property string fileType: "other"

    width: 130
    height: 140
    radius: 10
    color: mouseArea.containsMouse ? Theme.surfaceHover : Theme.surfaceHoverOff

    Behavior on color { ColorAnimation { duration: Theme.animHoverDuration } }

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

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 16
        spacing: 8

        Image {
            source: fileItem.iconSource(fileItem.fileType)
            width: 48; height: 48
            sourceSize.width: 48; sourceSize.height: 48
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: fileItem.fileName
            font.pixelSize: 12
            color: Theme.textPrimary
            width: 118
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
            elide: Text.ElideMiddle
            maximumLineCount: 2
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }

        Text {
            text: fileItem.fileSize
            font.pixelSize: 11
            color: Theme.textTertiary
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
