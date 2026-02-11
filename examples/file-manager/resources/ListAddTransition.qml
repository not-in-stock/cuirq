import QtQuick

Transition {
    ParallelAnimation {
        NumberAnimation {
            property: "height"
            from: 0
            duration: Theme.animExpandHeight
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.animExpandFade
            easing.type: Easing.OutQuad
        }
    }
}
