import QtQuick

Rectangle {
    id: fileItem

    property string fileName: ""
    property string filePath: ""
    property bool isDir: false
    property string fileSize: ""
    property string fileType: "other"
    property bool isSelected: false

    signal clicked()

    width: 100
    height: 110
    radius: 8
    color: isSelected ? Theme.selection : (mouseArea.containsMouse ? Theme.surfaceHover : Theme.surfaceHoverOff)

    Behavior on color {
        ColorAnimation {
            duration: Theme.animHoverDuration
        }
    }

    function iconSource(type) {
        switch (type) {
        case "folder":
            return "icons/folder.svg";
        case "document":
            return "icons/document.svg";
        case "image":
            return "icons/image.svg";
        case "audio":
            return "icons/audio.svg";
        case "video":
            return "icons/video.svg";
        case "code":
            return "icons/code.svg";
        case "archive":
            return "icons/archive.svg";
        default:
            return "icons/file.svg";
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 10
        spacing: 6

        Image {
            source: fileItem.iconSource(fileItem.fileType)
            width: 40
            height: 40
            sourceSize.width: 40
            sourceSize.height: 40
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: fileItem.fileName
            font.pixelSize: 12
            color: Theme.textPrimary
            width: 90
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
        onClicked: fileItem.clicked()
        onDoubleClicked: {
            if (fileItem.isDir) {
                signalForwarder.emitSignal("navigate", [fileItem.filePath]);
            }
        }
    }
}
