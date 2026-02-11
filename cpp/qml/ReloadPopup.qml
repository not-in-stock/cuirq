import QtQuick
import QtQuick.Controls

Window {
    id: root
    width: 320
    height: popup.isError ? Math.min(errorText.implicitHeight + 40, 400) : 36
    flags: Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    visible: false

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: popup.isError ? "#E53E3E" : "#38A169"
        opacity: 0.95

        Flickable {
            anchors.fill: parent
            anchors.margins: 12
            contentHeight: errorText.implicitHeight
            clip: true

            Text {
                id: errorText
                width: parent.width
                text: popup.isError ? popup.errorText : "Reloaded"
                color: "white"
                font.pixelSize: 13
                font.family: "SF Mono, Menlo, monospace"
                wrapMode: Text.Wrap
            }
        }
    }

    Behavior on height {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }
}
