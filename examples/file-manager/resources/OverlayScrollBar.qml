import QtQuick
import QtQuick.Controls

ScrollBar {
    id: root

    required property Flickable flickable

    orientation: Qt.Vertical
    policy: ScrollBar.AlwaysOn
    visible: size < 1

    size: flickable.contentHeight > 0
          ? flickable.height / flickable.contentHeight
          : 0
    padding: 2

    property bool _show: false
    property bool _engaged: active || flickable.movingVertically
    property bool _windowActive: Window.window?.active ?? true

    Binding on position {
        value: root.flickable.contentHeight > 0
               ? (root.flickable.contentY - root.flickable.originY) / root.flickable.contentHeight
               : 0
        when: !root.pressed
    }

    onPositionChanged: {
        if (pressed) {
            flickable.contentY = position * flickable.contentHeight + flickable.originY
        }
    }

    on_EngagedChanged: {
        if (_engaged) {
            hideTimer.stop()
            _show = true
        } else {
            hideTimer.restart()
        }
    }

    on_WindowActiveChanged: {
        if (!_windowActive && !_engaged) {
            hideTimer.stop()
            _show = false
        }
    }

    Timer {
        id: hideTimer
        interval: theme.scrollbarFadeDelay
        onTriggered: root._show = false
    }

    contentItem: Rectangle {
        implicitWidth: theme.scrollbarWidth
        radius: theme.scrollbarRadius
        color: theme.scrollbarColor
        opacity: root._show ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: theme.scrollbarFadeDuration }
        }
    }

    background: Item {}
}
