import QtQuick
import QtQuick.Controls

Rectangle {
    id: root

    property var columnModel
    property int columnIndex: 0
    property string columnPath: ""
    property string columnName: ""
    property int selectedIndex: -1

    width: theme.millerColumnWidth
    color: "transparent"

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

    // Right border separator
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: theme.separator
        Behavior on color {
            ColorAnimation {
                duration: theme.animDuration
            }
        }
    }

    // Column header
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: theme.millerItemHeight

        Text {
            anchors.centerIn: parent
            text: root.columnName
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: theme.textSecondary
            elide: Text.ElideMiddle
            width: parent.width - 16
            horizontalAlignment: Text.AlignHCenter
            Behavior on color {
                ColorAnimation {
                    duration: theme.animDuration
                }
            }
        }

        // Bottom separator
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: theme.separator
            Behavior on color {
                ColorAnimation {
                    duration: theme.animDuration
                }
            }
        }
    }

    ListView {
        id: listView
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true

        model: root.columnModel

        ScrollBar.vertical: OverlayScrollBar {}

        delegate: Rectangle {
            id: delegateItem
            width: listView.width
            height: theme.millerItemHeight

            readonly property bool isSelected: index === root.selectedIndex
            readonly property bool isHovered: delegateMouse.containsMouse

            color: isSelected ? theme.millerSelection : (isHovered ? theme.surfaceHover : theme.surfaceHoverOff)

            Behavior on color {
                ColorAnimation {
                    duration: theme.animHoverDuration
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                spacing: 6

                Image {
                    source: root.iconSource(model.fileType)
                    width: 18
                    height: 18
                    sourceSize.width: 18
                    sourceSize.height: 18
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: model.name
                    font.pixelSize: 12
                    color: theme.textPrimary
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 18 - 6 - (model.isDir ? 14 : 0) - 12
                    Behavior on color {
                        ColorAnimation {
                            duration: theme.animDuration
                        }
                    }
                }

                // Chevron for directories
                Image {
                    source: "icons/arrow-right.svg"
                    width: 10
                    height: 10
                    sourceSize.width: 10
                    sourceSize.height: 10
                    visible: model.isDir
                    opacity: 0.5
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                id: delegateMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    signalForwarder.emitSignal("millerSelect", [root.columnIndex, index]);
                }
            }
        }

        // Empty state
        Text {
            anchors.centerIn: parent
            text: "Empty"
            font.pixelSize: 12
            color: theme.textTertiary
            visible: listView.count === 0
        }
    }
}
