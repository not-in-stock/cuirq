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

    // Column header
    component ColumnHeader: Item {
        id: colHeader
        property string label
        property string field
        property bool active: fileList.sortField === field

        height: parent.height

        Rectangle {
            anchors.fill: parent
            color: headerMouse.containsMouse ? theme.surfaceHover : theme.surfaceHoverOff
            Behavior on color { ColorAnimation { duration: theme.animHoverDuration } }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 12
            spacing: 4

            Text {
                text: colHeader.label
                font.pixelSize: 11
                font.weight: colHeader.active ? Font.DemiBold : Font.Normal
                color: colHeader.active ? theme.textPrimary : theme.textSecondary
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: fileList.sortAscending ? "\u25B2" : "\u25BC"
                font.pixelSize: 8
                color: theme.textSecondary
                visible: colHeader.active
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: headerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (fileList.sortField === colHeader.field) {
                    fileList.sortAscending = !fileList.sortAscending
                } else {
                    fileList.sortField = colHeader.field
                    fileList.sortAscending = true
                }
                signalForwarder.emitSignal("sortChanged", [fileList.sortField, fileList.sortAscending ? "true" : "false"])
            }
        }
    }

    Row {
        id: listHeader
        x: 0
        y: theme.toolbarHeight
        width: parent.width
        height: 28
        z: 1

        ColumnHeader { label: "Name";          field: "name";      width: parent.width - fileList.colRightWidth - theme.listPadding }
        ColumnHeader { label: "Size";          field: "sizeBytes"; width: fileList.colSizeWidth }
        ColumnHeader { label: "Date Modified"; field: "modified";  width: fileList.colDateWidth }
        ColumnHeader { label: "Type";          field: "fileType";  width: fileList.colTypeWidth }
    }

    // Header bottom separator
    Rectangle {
        x: 0
        y: listHeader.y + listHeader.height - 1
        width: parent.width
        height: 1
        z: 1
        color: theme.separator
    }

    ListView {
        id: listView
        anchors.fill: parent
        topMargin: theme.toolbarHeight + listHeader.height + theme.listPadding
        bottomMargin: theme.listPadding
        leftMargin: theme.listPadding
        rightMargin: theme.listPadding
        clip: true
        spacing: theme.listItemSpacing

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
                text: {
                    if (model.modified <= 0) return ""
                    let d = new Date(model.modified)
                    return d.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
                }
                font.pixelSize: 12
                color: theme.textTertiary
            }

            // Type column
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width - fileList.colTypeWidth
                width: fileList.colTypeWidth
                leftPadding: 12
                text: model.isDir ? "Folder" : (model.extension ? model.extension.toUpperCase() : "")
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

    OverlayScrollBar {
        flickable: listView
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: theme.toolbarHeight
        anchors.bottom: parent.bottom
    }
}
