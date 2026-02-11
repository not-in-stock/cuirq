import QtQuick
import QtQuick.Controls

Rectangle {
    id: root

    property var columnModel
    property int columnIndex: 0
    property string columnPath: ""
    property string columnName: ""
    property string selectedChildPath: ""

    onColumnPathChanged: listView.contentY = -listView.topMargin

    width: Theme.millerColumnWidth
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
        color: Theme.separator
        Behavior on color {
            ColorAnimation {
                duration: Theme.animDuration
            }
        }
    }

    ListView {
        id: listView
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        topMargin: Theme.toolbarHeight
        displayMarginBeginning: Theme.toolbarHeight

        model: root.columnModel

        ScrollBar.vertical: OverlayScrollBar {
            topPadding: Theme.toolbarHeight
        }

        delegate: Rectangle {
            id: delegateItem
            width: listView.width
            height: Theme.millerItemHeight

            readonly property bool isSelected: model.path === root.selectedChildPath
            readonly property bool isHovered: delegateMouse.containsMouse

            color: isSelected ? Theme.millerSelection : (isHovered ? Theme.surfaceHover : Theme.surfaceHoverOff)

            Behavior on color {
                ColorAnimation {
                    duration: Theme.animHoverDuration
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
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 18 - 6 - (model.isDir ? 14 : 0) - 12
                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.animDuration
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

        add: ListAddTransition {}
        remove: ListRemoveTransition {}
        displaced: ListDisplacedTransition {}

        // Empty state
        Text {
            anchors.centerIn: parent
            text: "Empty"
            font.pixelSize: 12
            color: Theme.textTertiary
            visible: listView.count === 0
        }
    }
}
