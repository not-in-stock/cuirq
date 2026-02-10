import QtQuick

WheelHandler {
    required property Flickable flickable
    property real speedMultiplier: 9

    enabled: Qt.platform.os === "osx"
    acceptedDevices: PointerDevice.Mouse
    orientation: Qt.Vertical

    onRotationChanged: {
        let dy = rotation * speedMultiplier
        let minY = flickable.originY - flickable.topMargin
        let maxY = flickable.originY + flickable.contentHeight - flickable.height + flickable.bottomMargin
        flickable.contentY = Math.max(minY, Math.min(maxY, flickable.contentY - dy))
        rotation = 0
    }
}
