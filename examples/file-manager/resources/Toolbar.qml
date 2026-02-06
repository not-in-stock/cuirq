import QtQuick
import QtQuick.Layouts

Rectangle {
    id: toolbar

    property bool canGoBack: false
    property bool canGoForward: false
    property var breadcrumbs: []
    property string viewMode: "grid"

    signal viewModeRequested(string mode)

    height: 48
    color: "#FFFFFF"

    // Bottom border
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: "#E2E8F0"
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 4

        // Back button
        Rectangle {
            width: 32
            height: 32
            radius: 6
            color: backMouse.containsMouse && toolbar.canGoBack ? "#F1F5F9" : "transparent"

            Text {
                anchors.centerIn: parent
                text: "\u25C0"
                font.pixelSize: 14
                color: toolbar.canGoBack ? "#334155" : "#CBD5E1"
            }

            MouseArea {
                id: backMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: toolbar.canGoBack ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (toolbar.canGoBack)
                        signalForwarder.emitSignal("goBack", [])
                }
            }
        }

        // Forward button
        Rectangle {
            width: 32
            height: 32
            radius: 6
            color: fwdMouse.containsMouse && toolbar.canGoForward ? "#F1F5F9" : "transparent"

            Text {
                anchors.centerIn: parent
                text: "\u25B6"
                font.pixelSize: 14
                color: toolbar.canGoForward ? "#334155" : "#CBD5E1"
            }

            MouseArea {
                id: fwdMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: toolbar.canGoForward ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (toolbar.canGoForward)
                        signalForwarder.emitSignal("goForward", [])
                }
            }
        }

        // Separator
        Rectangle {
            width: 1
            height: 24
            color: "#E2E8F0"
            Layout.leftMargin: 4
            Layout.rightMargin: 4
        }

        // View mode toggle
        Row {
            spacing: 2

            Rectangle {
                width: 30
                height: 28
                radius: 5
                color: toolbar.viewMode === "grid" ? "#E2E8F0" : (gridMouse.containsMouse ? "#F1F5F9" : "transparent")

                Text {
                    anchors.centerIn: parent
                    text: "\u25A6"
                    font.pixelSize: 14
                    color: toolbar.viewMode === "grid" ? "#334155" : "#94A3B8"
                }

                MouseArea {
                    id: gridMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toolbar.viewModeRequested("grid")
                }
            }

            Rectangle {
                width: 30
                height: 28
                radius: 5
                color: toolbar.viewMode === "list" ? "#E2E8F0" : (listMouse.containsMouse ? "#F1F5F9" : "transparent")

                Text {
                    anchors.centerIn: parent
                    text: "\u2630"
                    font.pixelSize: 14
                    color: toolbar.viewMode === "list" ? "#334155" : "#94A3B8"
                }

                MouseArea {
                    id: listMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toolbar.viewModeRequested("list")
                }
            }
        }

        // Separator
        Rectangle {
            width: 1
            height: 24
            color: "#E2E8F0"
            Layout.leftMargin: 4
            Layout.rightMargin: 4
        }

        // Breadcrumbs
        Row {
            Layout.fillWidth: true
            spacing: 4
            clip: true

            Repeater {
                model: toolbar.breadcrumbs.length

                Row {
                    required property int index
                    spacing: 4

                    Text {
                        text: index > 0 ? "/" : ""
                        font.pixelSize: 13
                        color: "#CBD5E1"
                        anchors.verticalCenter: parent.verticalCenter
                        visible: index > 0
                    }

                    Rectangle {
                        width: crumbText.width + 12
                        height: 26
                        radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: crumbMouse.containsMouse ? "#F1F5F9" : "transparent"

                        Text {
                            id: crumbText
                            anchors.centerIn: parent
                            text: toolbar.breadcrumbs[index].name
                            font.pixelSize: 13
                            font.bold: index === toolbar.breadcrumbs.length - 1
                            color: index === toolbar.breadcrumbs.length - 1 ? "#0F172A" : "#64748B"
                        }

                        MouseArea {
                            id: crumbMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: signalForwarder.emitSignal("navigate", [toolbar.breadcrumbs[index].path])
                        }
                    }
                }
            }
        }
    }
}
