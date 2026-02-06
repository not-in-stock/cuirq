import QtQuick
import QtQuick.Layouts

Rectangle {
    id: statusBar

    property int itemCount: 0
    property string currentPath: ""
    property bool darkMode: false

    height: 32
    color: darkMode ? "#1E293B" : "#FFFFFF"
    Behavior on color { ColorAnimation { duration: 200 } }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: darkMode ? "#334155" : "#E2E8F0"
        Behavior on color { ColorAnimation { duration: 200 } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 16

        Text {
            text: statusBar.itemCount + " items"
            font.pixelSize: 12
            color: statusBar.darkMode ? "#94A3B8" : "#64748B"
        }

        Item { Layout.fillWidth: true }

        Text {
            text: statusBar.currentPath
            font.pixelSize: 12
            color: statusBar.darkMode ? "#64748B" : "#94A3B8"
            elide: Text.ElideMiddle
            Layout.maximumWidth: 400
        }
    }
}
