import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    // Window properties — shell.qml reads these
    property string windowTitle: "cuirq Counter!!!"
    property int windowWidth: 500
    property int windowHeight: 400

    property string currentMessage: state.message || "No message"
    property int currentCount: parseInt(state.count) || 0

    Connections {
        target: stateNotifier
        function onPropChanged(key, value) {
            console.log("[QML] propChanged:", key, "=", value)
            if (key === "message") root.currentMessage = value || "No message"
            else if (key === "count") root.currentCount = parseInt(value) || 0
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#007eea" }
            GradientStop { position: 1.0; color: "#764ba2" }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 30

            Text {
                text: "Hot-Reload Demo"
                font.pixelSize: 32
                font.bold: true
                color: "white"
                Layout.alignment: Qt.AlignHCenter
            }

            Rectangle {
                width: 300
                height: 150
                color: "white"
                opacity: 0.9
                radius: 15
                Layout.alignment: Qt.AlignHCenter

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 15

                    Text {
                        text: root.currentMessage
                        font.pixelSize: 20
                        color: "#333"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "Count: " + root.currentCount
                        font.pixelSize: 36
                        font.bold: true
                        color: "#667eea"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            Text {
                text: "Edit this file and save to see changes!"
                font.pixelSize: 14
                color: "#e0e0e0"
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "Use REPL to update state: (update-state! :count inc)"
                font.pixelSize: 12
                color: "#c0c0c0"
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
