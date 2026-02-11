import QtQuick

Transition {
    ParallelAnimation {
        NumberAnimation {
            property: "height"
            to: 0
            duration: Theme.animExpandHeight
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            property: "opacity"
            to: 0
            duration: Theme.animExpandFade
            easing.type: Easing.InQuad
        }
    }
}
