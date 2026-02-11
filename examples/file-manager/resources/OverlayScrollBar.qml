import QtQuick
import QtQuick.Controls

ScrollBar {
    id: root

    orientation: Qt.Vertical
    policy: ScrollBar.AsNeeded
    minimumSize: 0.06
    padding: 2

    property bool _show: false
    property bool _engaged: size < 1 && (active || (parent instanceof Flickable && (orientation === Qt.Vertical ? parent.movingVertically : parent.movingHorizontally)))
    property bool _windowActive: Window.window ? Window.window.active : true

    on_EngagedChanged: {
        if (_engaged) {
            hideTimer.stop();
            _show = true;
        } else {
            hideTimer.interval = hovered ? theme.scrollbarFadeDelay : theme.scrollbarFadeDelay / 3;
            hideTimer.restart();
        }
    }

    onHoveredChanged: {
        if (!hovered && !_engaged && _show) {
            hideTimer.interval = theme.scrollbarFadeDelay / 3;
            hideTimer.restart();
        }
    }

    on_WindowActiveChanged: {
        if (!_windowActive && !_engaged) {
            hideTimer.stop();
            _show = false;
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
            NumberAnimation {
                duration: theme.scrollbarFadeDuration
            }
        }
    }

    background: Item {}
}
