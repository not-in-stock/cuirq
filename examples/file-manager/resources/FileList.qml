import QtQuick
import QtQuick.Controls

Rectangle {
    id: fileList
    color: theme.background
    Behavior on color {
        ColorAnimation {
            duration: theme.animDuration
        }
    }

    property string sortField: "name"
    property bool sortAscending: true

    // Column widths — shared between header and delegate
    readonly property int colSizeWidth: 80
    readonly property int colDateWidth: 120
    readonly property int colTypeWidth: 80
    readonly property int colRightWidth: colSizeWidth + colDateWidth + colTypeWidth

    // Tree indentation
    readonly property int iconSize: 24
    readonly property int indentStep: iconSize / 2
    readonly property int arrowWidth: 12
    readonly property int arrowSpacing: 0
    readonly property int rowLeftPadding: 6
    readonly property int iconPaddingLeft: 4
    readonly property int iconPaddingRight: 8

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
        MouseWheelBooster {
            flickable: listView
        }

        model: files

        delegate: Rectangle {
            id: listItem
            width: listView.width - listView.leftMargin - listView.rightMargin
            height: theme.listItemHeight
            radius: 6
            clip: true
            color: listMouse.containsMouse ? theme.surfaceHover : theme.surfaceHoverOff

            Behavior on color {
                ColorAnimation {
                    duration: theme.animHoverDuration
                }
            }

            readonly property int depth: model.depth || 0
            readonly property int indentWidth: depth * fileList.indentStep

            // Name column (indent + arrow + icon + name)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: fileList.rowLeftPadding
                width: parent.width - fileList.colRightWidth - fileList.rowLeftPadding
                spacing: 0

                // Depth indentation
                Item {
                    width: listItem.indentWidth
                    height: 1
                }

                // Expand/collapse chevron
                Item {
                    id: arrowItem
                    width: model.isDir ? fileList.arrowWidth + fileList.arrowSpacing : 0
                    height: parent.height
                    visible: model.isDir
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        id: chevron
                        source: "icons/arrow-right.svg"
                        width: 12
                        height: 12
                        sourceSize.width: 12
                        sourceSize.height: 12
                        anchors.centerIn: parent
                        rotation: model.expanded ? 90 : 0
                        Behavior on rotation {
                            NumberAnimation {
                                duration: theme.animExpandHeight
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }

                Item {
                    width: model.isDir ? 0 : fileList.arrowWidth + fileList.arrowSpacing
                    height: 1
                }

                // Spacing before icon
                Item {
                    width: fileList.iconPaddingLeft
                    height: 1
                }

                Image {
                    source: fileList.iconSource(model.fileType)
                    width: fileList.iconSize
                    height: fileList.iconSize
                    sourceSize.width: fileList.iconSize
                    sourceSize.height: fileList.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    width: fileList.iconPaddingRight
                    height: 1
                }

                Text {
                    text: model.name
                    font.pixelSize: 13
                    color: theme.textPrimary
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - listItem.indentWidth - fileList.arrowWidth - fileList.arrowSpacing - fileList.iconSize - fileList.iconPaddingRight * 2
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
                        signalForwarder.emitSignal("navigate", [model.path]);
                    }
                }
            }

            // Expand/collapse click area — on top of listMouse
            MouseArea {
                visible: model.isDir
                x: fileList.rowLeftPadding + listItem.indentWidth - 4
                width: fileList.arrowWidth + fileList.arrowSpacing + 8
                height: parent.height
                onClicked: signalForwarder.emitSignal("toggleExpand", [model.path])
            }
        }

        add: ListAddTransition {}
        remove: ListRemoveTransition {}
        displaced: ListDisplacedTransition {}

        Text {
            anchors.centerIn: parent
            text: "This folder is empty"
            font.pixelSize: 16
            color: theme.textSecondary
            visible: listView.count === 0
        }
    }
}
