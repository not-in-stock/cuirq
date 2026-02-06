import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card

    property string message: "No message!"
    property int count: 0

    width: 300
    height: 150
    color: "white"
    opacity: 0.9
    radius: 15

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 15

        Text {
            text: card.message
            font.pixelSize: 20
            color: "#333"
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "Count: " + card.count
            font.pixelSize: 36
            font.bold: true
            color: "#667eea"
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
