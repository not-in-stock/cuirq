import QtQuick

Transition {
    ParallelAnimation {
        NumberAnimation {
            property: "height"
            from: 0
            duration: theme.animExpandHeight
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: theme.animExpandFade
            easing.type: Easing.OutQuad
        }
    }
}
