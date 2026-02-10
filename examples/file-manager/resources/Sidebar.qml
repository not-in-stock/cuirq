import QtQuick
import QtQuick.Layouts
import QtCore

Rectangle {
    id: sidebar

    property string currentPath: ""

    function _toPath(url) {
        return url.toString().replace("file://", "");
    }

    readonly property string _home: _toPath(StandardPaths.writableLocation(StandardPaths.HomeLocation))
    readonly property var _pathMap: ({
            "home": _home,
            "desktop": _home + "/Desktop",
            "documents": _home + "/Documents",
            "downloads": _home + "/Downloads",
            "pictures": _home + "/Pictures",
            "music": _home + "/Music"
        })

    width: theme.sidebarWidth
    color: theme.sidebarBackground
    Behavior on color {
        ColorAnimation {
            duration: theme.animDuration
        }
    }

    // Right border
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: theme.separator
        Behavior on color {
            ColorAnimation {
                duration: theme.animDuration
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: (_cuirq_titlebar_height ?? 0) + 16
        anchors.leftMargin: 12
        anchors.rightMargin: 13
        anchors.bottomMargin: 12
        spacing: 2

        // FAVORITES header
        Text {
            text: "FAVORITES"
            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 0.5
            color: theme.textTertiary
            Layout.leftMargin: 10
            Layout.bottomMargin: 6
        }

        Repeater {
            model: ListModel {
                ListElement {
                    label: "Home"
                    iconFile: "icons/home.svg"
                    key: "home"
                }
                ListElement {
                    label: "Desktop"
                    iconFile: "icons/desktop.svg"
                    key: "desktop"
                }
                ListElement {
                    label: "Documents"
                    iconFile: "icons/documents.svg"
                    key: "documents"
                }
                ListElement {
                    label: "Downloads"
                    iconFile: "icons/downloads.svg"
                    key: "downloads"
                }
                ListElement {
                    label: "Pictures"
                    iconFile: "icons/pictures.svg"
                    key: "pictures"
                }
                ListElement {
                    label: "Music"
                    iconFile: "icons/music.svg"
                    key: "music"
                }
            }

            Rectangle {
                required property int index
                required property string label
                required property string iconFile
                required property string key

                readonly property bool isActive: sidebar.currentPath === (sidebar._pathMap[key] ?? "")

                Layout.fillWidth: true
                height: 36
                radius: 8
                color: isActive || sidebarMouse.containsMouse ? theme.sidebarActive : theme.sidebarActiveOff

                Behavior on color {
                    ColorAnimation {
                        duration: theme.animHoverDuration
                    }
                }
                Behavior on border.color {
                    ColorAnimation {
                        duration: theme.animHoverDuration
                    }
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    spacing: 10

                    Image {
                        source: iconFile
                        width: 20
                        height: 20
                        sourceSize.width: 20
                        sourceSize.height: 20
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: label
                        font.pixelSize: 13
                        color: theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: sidebarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: signalForwarder.emitSignal("sidebarNavigate", [key])
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
