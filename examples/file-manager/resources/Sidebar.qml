import QtQuick
import QtQuick.Layouts

Rectangle {
    id: sidebar

    property string currentPath: ""

    width: 220
    color: Theme.sidebarBackground
    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

    // Right border
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Theme.border
        Behavior on color { ColorAnimation { duration: Theme.animDuration } }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 16
        anchors.leftMargin: 12
        anchors.rightMargin: 13
        anchors.bottomMargin: 12
        spacing: 2

        // FAVORITES header
        Text {
            text: "FAVORITES"
            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 0.5
            color: Theme.textTertiary
            Layout.leftMargin: 10
            Layout.bottomMargin: 6
        }

        Repeater {
            model: ListModel {
                ListElement { label: "Home";      iconFile: "icons/home.svg";      key: "home" }
                ListElement { label: "Desktop";   iconFile: "icons/desktop.svg";   key: "desktop" }
                ListElement { label: "Documents"; iconFile: "icons/documents.svg"; key: "documents" }
                ListElement { label: "Downloads"; iconFile: "icons/downloads.svg"; key: "downloads" }
                ListElement { label: "Pictures";  iconFile: "icons/pictures.svg";  key: "pictures" }
                ListElement { label: "Music";     iconFile: "icons/music.svg";     key: "music" }
            }

            Rectangle {
                required property int index
                required property string label
                required property string iconFile
                required property string key

                Layout.fillWidth: true
                height: 36
                radius: 8
                color: sidebarMouse.containsMouse ? Theme.surfaceActive : "transparent"

                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    spacing: 10

                    Image {
                        source: iconFile
                        width: 20; height: 20
                        sourceSize.width: 20; sourceSize.height: 20
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: label
                        font.pixelSize: 13
                        color: Theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: sidebarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: signalForwarder.emitSignal("sidebarNavigate", [key])
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
