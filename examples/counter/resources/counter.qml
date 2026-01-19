import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    visible: true
    width: 500
    height: 400
    title: "REPL Hot-Reload Demo"

    // Local properties that update when state changes
    property string currentMessage: state.message || "No message"
    property int currentCount: parseInt(state.count) || 0

    // Listen for state changes from QQmlPropertyMap
    Connections {
        target: state
        function onValueChanged(key, value) {
            console.log("QML: State changed:", key, "=", value)
            if (key === "message") {
                currentMessage = value || "No message"
            } else if (key === "count") {
                currentCount = parseInt(value) || 0
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#FFee00" }
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
                        text: currentMessage
                        font.pixelSize: 20
                        color: "#333"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "Count: " + currentCount
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
