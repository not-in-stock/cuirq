import QtQuick

Transition {
    NumberAnimation {
        properties: "x,y"
        duration: Theme.animExpandHeight
        easing.type: Easing.OutCubic
    }
}
