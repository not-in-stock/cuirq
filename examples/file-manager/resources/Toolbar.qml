import QtQuick
import QtQuick.Layouts

Rectangle {
    id: toolbar

    property bool canGoBack: false
    property bool canGoForward: false
    property var breadcrumbs: []
    property string viewMode: "grid"
    property bool darkMode: false

    signal viewModeRequested(string mode)
    signal themeToggled()

    height: 48
    color: darkMode ? "#1E293B" : "#FFFFFF"
    Behavior on color { ColorAnimation { duration: 200 } }

    // Bottom border
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: darkMode ? "#334155" : "#E2E8F0"
        Behavior on color { ColorAnimation { duration: 200 } }
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
            color: backMouse.containsMouse && toolbar.canGoBack ? (darkMode ? "#334155" : "#F1F5F9") : "transparent"

            Image {
                anchors.centerIn: parent
                source: "icons/arrow-left.svg"
                width: 18; height: 18
                sourceSize.width: 18; sourceSize.height: 18
                opacity: toolbar.canGoBack ? 1.0 : 0.3
            }

            MouseArea {
                id: backMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: toolbar.canGoBack ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: { if (toolbar.canGoBack) signalForwarder.emitSignal("goBack", []) }
            }
        }

        // Forward button
        Rectangle {
            width: 32
            height: 32
            radius: 6
            color: fwdMouse.containsMouse && toolbar.canGoForward ? (darkMode ? "#334155" : "#F1F5F9") : "transparent"

            Image {
                anchors.centerIn: parent
                source: "icons/arrow-right.svg"
                width: 18; height: 18
                sourceSize.width: 18; sourceSize.height: 18
                opacity: toolbar.canGoForward ? 1.0 : 0.3
            }

            MouseArea {
                id: fwdMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: toolbar.canGoForward ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: { if (toolbar.canGoForward) signalForwarder.emitSignal("goForward", []) }
            }
        }

        // Breadcrumbs
        Row {
            Layout.fillWidth: true
            spacing: 2
            clip: true
            Layout.leftMargin: 8

            Repeater {
                model: toolbar.breadcrumbs.length

                Row {
                    required property int index
                    spacing: 2

                    Text {
                        text: "/"
                        font.pixelSize: 14
                        color: darkMode ? "#475569" : "#CBD5E1"
                        anchors.verticalCenter: parent.verticalCenter
                        visible: index > 0
                    }

                    Rectangle {
                        width: crumbText.width + 12
                        height: 28
                        radius: 6
                        anchors.verticalCenter: parent.verticalCenter
                        color: crumbMouse.containsMouse ? (darkMode ? "#334155" : "#F1F5F9") : "transparent"

                        Text {
                            id: crumbText
                            anchors.centerIn: parent
                            text: toolbar.breadcrumbs[index].name
                            font.pixelSize: 13
                            font.bold: index === toolbar.breadcrumbs.length - 1
                            color: index === toolbar.breadcrumbs.length - 1
                                ? (darkMode ? "#F8FAFC" : "#0F172A")
                                : (darkMode ? "#94A3B8" : "#64748B")
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

        // Separator
        Rectangle {
            width: 1; height: 24
            color: darkMode ? "#334155" : "#E2E8F0"
            Layout.leftMargin: 4; Layout.rightMargin: 4
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        // View mode toggle
        Row {
            spacing: 2

            Rectangle {
                width: 32; height: 32; radius: 6
                color: toolbar.viewMode === "grid"
                    ? (darkMode ? "#334155" : "#E2E8F0")
                    : (gridMouse.containsMouse ? (darkMode ? "#334155" : "#F1F5F9") : "transparent")

                Image {
                    anchors.centerIn: parent
                    source: "icons/grid-view.svg"
                    width: 18; height: 18; sourceSize.width: 18; sourceSize.height: 18
                    opacity: toolbar.viewMode === "grid" ? 1.0 : 0.5
                }

                MouseArea {
                    id: gridMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toolbar.viewModeRequested("grid")
                }
            }

            Rectangle {
                width: 32; height: 32; radius: 6
                color: toolbar.viewMode === "list"
                    ? (darkMode ? "#334155" : "#E2E8F0")
                    : (listMouse.containsMouse ? (darkMode ? "#334155" : "#F1F5F9") : "transparent")

                Image {
                    anchors.centerIn: parent
                    source: "icons/list-view.svg"
                    width: 18; height: 18; sourceSize.width: 18; sourceSize.height: 18
                    opacity: toolbar.viewMode === "list" ? 1.0 : 0.5
                }

                MouseArea {
                    id: listMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toolbar.viewModeRequested("list")
                }
            }
        }

        // Theme toggle
        Rectangle {
            width: 32; height: 32; radius: 6
            color: themeMouse.containsMouse ? (darkMode ? "#334155" : "#F1F5F9") : "transparent"
            Layout.leftMargin: 4

            Image {
                anchors.centerIn: parent
                source: darkMode ? "icons/sun.svg" : "icons/moon.svg"
                width: 18; height: 18; sourceSize.width: 18; sourceSize.height: 18
            }

            MouseArea {
                id: themeMouse; anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: toolbar.themeToggled()
            }
        }
    }
}
