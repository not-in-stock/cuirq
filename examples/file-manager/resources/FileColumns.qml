import QtQuick
import QtQuick.Controls

Rectangle {
    id: fileColumns
    color: Theme.background
    Behavior on color {
        ColorAnimation {
            duration: Theme.animDuration
        }
    }

    property var columnModels: [mc0, mc1, mc2, mc3, mc4, mc5, mc6, mc7,
                                mc8, mc9, mc10, mc11, mc12, mc13, mc14, mc15]
    property int activeColumnCount: 0
    property var columnsInfo: []
    property int selectedIndex: -1

    // Deferred removal: how many excess columns to remove after scroll animation
    property int _pendingRemoves: 0

    ListModel {
        id: columnsListModel
    }

    ListView {
        id: columnsListView
        width: parent.width
        height: parent.height - Theme.statusBarHeight
        orientation: ListView.Horizontal
        model: columnsListModel
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.horizontal: OverlayScrollBar {
            orientation: Qt.Horizontal
        }

        delegate: MillerColumn {
            required property int index
            required property string name
            required property string path
            required property string selectedPath

            height: columnsListView.height
            columnModel: fileColumns.columnModels[index % 16]
            columnIndex: index
            columnName: name
            columnPath: path
            selectedChildPath: selectedPath
            focusedIndex: (index === fileColumns.activeColumnCount - 1) ? fileColumns.selectedIndex : -1
        }

        add: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Theme.animViewDuration
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    property: "scale"
                    from: 0.92
                    to: 1
                    duration: Theme.animViewDuration
                    easing.type: Easing.OutQuad
                }
            }
        }

        NumberAnimation {
            id: scrollAnim
            target: columnsListView
            property: "contentX"
            duration: Theme.animViewDuration
            easing.type: Easing.OutQuad
            onFinished: {
                // Remove deferred columns — they're now off-screen
                while (fileColumns._pendingRemoves > 0) {
                    columnsListModel.remove(columnsListModel.count - 1);
                    fileColumns._pendingRemoves--;
                }
            }
        }
    }

    onColumnsInfoChanged: {
        let newInfo = columnsInfo;
        if (!newInfo) newInfo = [];
        let oldCount = columnsListModel.count;

        if (newInfo.length < oldCount) {
            // === Backward navigation: defer removal until scroll finishes ===

            // Update existing columns in place
            for (let i = 0; i < newInfo.length; i++)
                columnsListModel.set(i, newInfo[i]);

            // Clear selectedPath on excess columns so they don't show stale highlights
            for (let i = newInfo.length; i < oldCount; i++)
                columnsListModel.setProperty(i, "selectedPath", "");

            let target = Math.max(0, newInfo.length * Theme.millerColumnWidth - columnsListView.width);
            if (target !== columnsListView.contentX) {
                // Animate scroll — columns slide off-screen, then get removed
                _pendingRemoves = oldCount - newInfo.length;
                scrollAnim.from = columnsListView.contentX;
                scrollAnim.to = target;
                scrollAnim.restart();
            } else {
                // No scroll needed — remove immediately
                while (columnsListModel.count > newInfo.length)
                    columnsListModel.remove(columnsListModel.count - 1);
            }
        } else {
            // === Forward navigation or same count: normal flow ===

            // Flush any pending removes first
            while (_pendingRemoves > 0) {
                columnsListModel.remove(columnsListModel.count - 1);
                _pendingRemoves--;
            }

            // Update existing columns in place
            for (let i = 0; i < Math.min(oldCount, newInfo.length); i++)
                columnsListModel.set(i, newInfo[i]);

            // Append new columns — triggers add transitions
            for (let i = oldCount; i < newInfo.length; i++)
                columnsListModel.append(newInfo[i]);

            let target = Math.max(0, newInfo.length * Theme.millerColumnWidth - columnsListView.width);
            if (target !== columnsListView.contentX) {
                scrollAnim.from = columnsListView.contentX;
                scrollAnim.to = target;
                scrollAnim.restart();
            }
        }
    }

    // Empty state
    Text {
        anchors.centerIn: parent
        text: "This folder is empty"
        font.pixelSize: 16
        color: Theme.textSecondary
        visible: columnsListModel.count === 0
    }
}
