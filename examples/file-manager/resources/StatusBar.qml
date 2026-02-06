import QtQuick
import QtQuick.Layouts

Rectangle {
    id: statusBar

    property int itemCount: 0
    property string currentPath: ""

    height: 32
    color: Theme.background
    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Theme.border
        Behavior on color { ColorAnimation { duration: Theme.animDuration } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 16

        Text {
            text: statusBar.itemCount + " items"
            font.pixelSize: 12
            color: Theme.textSecondary
        }

        Item { Layout.fillWidth: true }

        Text {
            text: statusBar.currentPath
            font.pixelSize: 12
            color: Theme.textTertiary
            elide: Text.ElideMiddle
            Layout.maximumWidth: 400
        }
    }
}
