import QtQuick
import QtQuick.Controls

Rectangle {
    id: fileGrid
    color: Theme.background
    Behavior on color {
        ColorAnimation {
            duration: Theme.animDuration
        }
    }

    readonly property real _availableWidth: Math.max(Theme.gridMinCellWidth, gridView.width)
    readonly property int _columns: Math.max(1, Math.floor(_availableWidth / Theme.gridMinCellWidth))

    GridView {
        id: gridView
        y: Theme.toolbarHeight
        width: parent.width
        height: parent.height - Theme.toolbarHeight - Theme.statusBarHeight
        topMargin: 10
        cellWidth: fileGrid._availableWidth / fileGrid._columns
        cellHeight: Theme.gridCellHeight
        displayMarginBeginning: Theme.toolbarHeight
        displayMarginEnd: Theme.statusBarHeight
        clip: false
        ScrollBar.vertical: OverlayScrollBar {}
        MouseWheelBooster {
            flickable: gridView
        }

        model: files

        delegate: Item {
            width: gridView.cellWidth
            height: gridView.cellHeight

            FileItem {
                anchors.horizontalCenter: parent.horizontalCenter
                fileName: model.name
                filePath: model.path
                isDir: model.isDir
                fileSize: model.size
                fileType: model.fileType
            }
        }

        add: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.animItemDuration
            }
            NumberAnimation {
                property: "scale"
                from: Theme.animItemScale
                to: 1
                duration: Theme.animItemDuration
            }
        }
        remove: Transition {
            NumberAnimation {
                property: "opacity"
                to: 0
                duration: Theme.animItemDuration
            }
            NumberAnimation {
                property: "scale"
                to: Theme.animItemScale
                duration: Theme.animItemDuration
            }
        }
        displaced: Transition {
            NumberAnimation {
                properties: "x,y"
                duration: Theme.animItemDuration
                easing.type: Easing.OutCubic
            }
        }

        Text {
            anchors.centerIn: parent
            text: "This folder is empty"
            font.pixelSize: 16
            color: Theme.textSecondary
            visible: gridView.count === 0
        }
    }
}
