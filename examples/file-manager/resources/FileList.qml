import QtQuick
import QtQuick.Controls

Rectangle {
    id: fileList
    color: Theme.background
    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

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
        topMargin: Theme.toolbarHeight + Theme.listPadding
        bottomMargin: Theme.listPadding
        leftMargin: Theme.listPadding
        rightMargin: Theme.listPadding
        clip: true
        spacing: Theme.listItemSpacing

        model: files

        delegate: Rectangle {
            id: listItem
            width: listView.width - listView.leftMargin - listView.rightMargin
            height: Theme.listItemHeight
            radius: 6
            color: listMouse.containsMouse ? Theme.surfaceHover : Theme.surfaceHoverOff

            Behavior on color { ColorAnimation { duration: Theme.animHoverDuration } }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: sizeText.left
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Image {
                    source: fileList.iconSource(model.fileType)
                    width: 24; height: 24
                    sourceSize.width: 24; sourceSize.height: 24
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: model.name
                    font.pixelSize: 13
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 36
                }
            }

            Text {
                id: sizeText
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: model.isDir ? "" : model.size
                font.pixelSize: 12
                color: Theme.textTertiary
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
            visible: listView.count === 0
        }
    }

    OverlayScrollBar {
        flickable: listView
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Theme.toolbarHeight
        anchors.bottom: parent.bottom
    }
}
