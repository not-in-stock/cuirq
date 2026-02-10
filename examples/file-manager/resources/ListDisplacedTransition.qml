import QtQuick

Transition {
    NumberAnimation {
        properties: "x,y"
        duration: theme.animExpandHeight
        easing.type: Easing.OutCubic
    }
}
