import QtQuick
import QtQuick.Controls

Rectangle {
    id: fileList
    color: theme.background
    Behavior on color { ColorAnimation { duration: theme.animDuration } }

    property string sortField: "name"
    property bool sortAscending: true

    // Column widths — shared between header and delegate
    readonly property int colSizeWidth: 80
    readonly property int colDateWidth: 120
    readonly property int colTypeWidth: 80
    readonly property int colRightWidth: colSizeWidth + colDateWidth + colTypeWidth

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
        y: theme.toolbarHeight + theme.listHeaderHeight
        width: parent.width
        height: parent.height - theme.toolbarHeight - theme.listHeaderHeight - theme.statusBarHeight
        topMargin: theme.listPadding
        bottomMargin: theme.listPadding
        leftMargin: theme.listPadding
        rightMargin: theme.listPadding
        clip: false
        displayMarginBeginning: theme.toolbarHeight + theme.listHeaderHeight
        displayMarginEnd: theme.statusBarHeight
        spacing: theme.listItemSpacing
        ScrollBar.vertical: OverlayScrollBar {}

        model: files

        delegate: Rectangle {
            id: listItem
            width: listView.width - listView.leftMargin - listView.rightMargin
            height: theme.listItemHeight
            radius: 6
            color: listMouse.containsMouse ? theme.surfaceHover : theme.surfaceHoverOff

            Behavior on color { ColorAnimation { duration: theme.animHoverDuration } }

            // Name column (icon + name)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 12
                width: parent.width - fileList.colRightWidth - 12
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
                    color: theme.textPrimary
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 36
                }
            }

            // Size column
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width - fileList.colRightWidth
                width: fileList.colSizeWidth
                leftPadding: 12
                text: model.isDir ? "" : model.size
                font.pixelSize: 12
                color: theme.textTertiary
            }

            // Date column
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width - fileList.colDateWidth - fileList.colTypeWidth
                width: fileList.colDateWidth
                leftPadding: 12
                text: model.modifiedFormatted
                font.pixelSize: 12
                color: theme.textTertiary
            }

            // Type column
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width - fileList.colTypeWidth
                width: fileList.colTypeWidth
                leftPadding: 12
                text: model.typeLabel
                font.pixelSize: 12
                color: theme.textTertiary
                elide: Text.ElideRight
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
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: theme.animItemDuration }
            NumberAnimation { property: "scale"; from: theme.animItemScale; to: 1; duration: theme.animItemDuration }
        }
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: theme.animItemDuration }
            NumberAnimation { property: "scale"; to: theme.animItemScale; duration: theme.animItemDuration }
        }
        displaced: Transition {
            NumberAnimation { properties: "x,y"; duration: theme.animItemDuration; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.centerIn: parent
            text: "This folder is empty"
            font.pixelSize: 16
            color: theme.textSecondary
            visible: listView.count === 0
        }
    }
}
