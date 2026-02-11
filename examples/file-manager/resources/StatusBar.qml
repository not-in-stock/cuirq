import QtQuick
import QtQuick.Layouts

Rectangle {
    id: statusBar

    property int itemCount: 0
    property string currentPath: ""

    height: Theme.statusBarHeight
    color: "transparent"

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Theme.border
        Behavior on color {
            ColorAnimation {
                duration: Theme.animDuration
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 16

        Text {
            text: "🔥 HOT RELOAD!!!"
            font.pixelSize: 12
            color: "#E53E3E"
            font.bold: true
        }

        Text {
            text: statusBar.itemCount + " items"
            font.pixelSize: 12
            color: Theme.textSecondary
        }

        Item {
            Layout.fillWidth: true
        }

        Text {
            text: statusBar.currentPath
            font.pixelSize: 12
            color: Theme.textTertiary
            elide: Text.ElideMiddle
            Layout.maximumWidth: 400
        }
    }
}
