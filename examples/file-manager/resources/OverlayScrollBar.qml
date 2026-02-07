import QtQuick
import QtQuick.Controls

ScrollBar {
    id: root

    policy: ScrollBar.AlwaysOn
    visible: size < 1

    padding: 2

    property bool _show: false
    property bool _windowActive: Window.window?.active ?? true

    onActiveChanged: {
        if (active) {
            hideTimer.stop()
            _show = true
        } else {
            hideTimer.restart()
        }
    }

    on_WindowActiveChanged: {
        if (!_windowActive && !active) {
            hideTimer.stop()
            _show = false
        }
    }

    Timer {
        id: hideTimer
        interval: Theme.scrollbarFadeDelay
        onTriggered: root._show = false
    }

    contentItem: Rectangle {
        implicitWidth: Theme.scrollbarWidth
        radius: Theme.scrollbarRadius
        color: Theme.scrollbarColor
        opacity: root._show ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.scrollbarFadeDuration }
        }
    }

    background: Item {}
}
