import QtQuick
import Qt5Compat.GraphicalEffects

Item {
    id: root

    required property Item sourceItem
    property color overlayColor: theme.panelOverlay
    property int blurRadius: theme.panelBlurRadius

    clip: true

    ShaderEffectSource {
        id: blurSource
        width: root.sourceItem.width
        height: root.sourceItem.height
        sourceItem: root.sourceItem
        visible: false
    }

    FastBlur {
        width: root.sourceItem.width
        height: root.sourceItem.height
        y: root.sourceItem.y - root.y
        source: blurSource
        radius: root.blurRadius
        cached: true
        transparentBorder: false
    }

    Rectangle {
        anchors.fill: parent
        color: root.overlayColor
        Behavior on color { ColorAnimation { duration: theme.animDuration } }
    }
}
