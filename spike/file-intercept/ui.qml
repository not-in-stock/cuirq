import QtQuick
import QtQuick.Controls

ApplicationWindow {
    visible: true
    width: 400
    height: 300
    title: "Third time"

    Column {
        anchors.centerIn: parent
        spacing: 10
        Label {
            text: "Three"
            font.pixelSize: 48
            color: "green"
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Label {
            text: "reloads done"
            font.pixelSize: 18
            color: "gray"
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
