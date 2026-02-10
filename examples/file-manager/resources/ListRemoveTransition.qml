import QtQuick

Transition {
    ParallelAnimation {
        NumberAnimation {
            property: "height"
            to: 0
            duration: theme.animExpandHeight
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            property: "opacity"
            to: 0
            duration: theme.animExpandFade
            easing.type: Easing.InQuad
        }
    }
}
