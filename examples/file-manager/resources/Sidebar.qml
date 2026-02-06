import QtQuick
import QtQuick.Layouts

Rectangle {
    id: sidebar

    property string currentPath: ""

    width: 200
    color: "#FFFFFF"

    // Right border
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: "#E2E8F0"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4

        Text {
            text: "Favorites"
            font.pixelSize: 11
            font.bold: true
            color: "#94A3B8"
            Layout.leftMargin: 8
            Layout.bottomMargin: 4
        }

        Repeater {
            model: ListModel {
                ListElement { label: "Home";      icon: "\uD83C\uDFE0"; key: "home" }
                ListElement { label: "Desktop";   icon: "\uD83D\uDDA5"; key: "desktop" }
                ListElement { label: "Documents"; icon: "\uD83D\uDCC4"; key: "documents" }
                ListElement { label: "Downloads"; icon: "\uD83D\uDCE5"; key: "downloads" }
                ListElement { label: "Pictures";  icon: "\uD83D\uDDBC"; key: "pictures" }
                ListElement { label: "Music";     icon: "\uD83C\uDFB5"; key: "music" }
            }

            Rectangle {
                required property int index
                required property string label
                required property string icon
                required property string key

                Layout.fillWidth: true
                height: 36
                radius: 8
                color: sidebarMouse.containsMouse ? "#F1F5F9" : "transparent"

                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    spacing: 8

                    Text {
                        text: icon
                        font.pixelSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: label
                        font.pixelSize: 13
                        color: "#334155"
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
