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
            hideTimer.interval = hovered ? Theme.scrollbarFadeDelay : Theme.scrollbarFadeDelay / 3;
            hideTimer.restart();
        }
    }

    onHoveredChanged: {
        if (!hovered && !_engaged && _show) {
            hideTimer.interval = Theme.scrollbarFadeDelay / 3;
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
        interval: Theme.scrollbarFadeDelay
        onTriggered: root._show = false
    }

    contentItem: Rectangle {
        implicitWidth: Theme.scrollbarWidth
        radius: Theme.scrollbarRadius
        color: Theme.scrollbarColor
        opacity: root._show ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.scrollbarFadeDuration
            }
        }
    }

    background: Item {}
}
