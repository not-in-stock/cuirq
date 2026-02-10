import QtQuick
import QtQuick.Controls

Rectangle {
    id: fileColumns
    color: theme.background
    Behavior on color {
        ColorAnimation {
            duration: theme.animDuration
        }
    }

    property var columnModels: [mc0, mc1, mc2, mc3, mc4, mc5, mc6, mc7]
    property int activeColumnCount: 0
    property var columnsInfo: []

    Flickable {
        id: flickable
        y: theme.toolbarHeight
        width: parent.width
        height: parent.height - theme.toolbarHeight - theme.statusBarHeight
        contentWidth: theme.millerColumnWidth * fileColumns.activeColumnCount
        contentHeight: height
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.horizontal: OverlayScrollBar {
            orientation: Qt.Horizontal
        }

        Row {
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            Repeater {
                model: fileColumns.activeColumnCount

                MillerColumn {
                    required property int index
                    height: flickable.height
                    columnModel: fileColumns.columnModels[index]
                    columnIndex: index
                    columnName: index < fileColumns.columnsInfo.length ? fileColumns.columnsInfo[index].name : ""
                    columnPath: index < fileColumns.columnsInfo.length ? fileColumns.columnsInfo[index].path : ""
                    selectedIndex: index < fileColumns.columnsInfo.length ? fileColumns.columnsInfo[index].selectedIndex : -1
                }
            }
        }

        // Auto-scroll to the rightmost column when new columns appear
        onContentWidthChanged: {
            if (contentWidth > width) {
                scrollAnim.to = contentWidth - width;
                scrollAnim.restart();
            }
        }

        NumberAnimation {
            id: scrollAnim
            target: flickable
            property: "contentX"
            duration: theme.animViewDuration
            easing.type: Easing.OutQuad
        }
    }

    // Empty state
    Text {
        anchors.centerIn: parent
        text: "This folder is empty"
        font.pixelSize: 16
        color: theme.textSecondary
        visible: fileColumns.activeColumnCount === 0
    }
}
