import QtQuick

WheelHandler {
    required property Flickable flickable
    property real speedMultiplier: 9

    enabled: Qt.platform.os === "osx"
    acceptedDevices: PointerDevice.Mouse
    orientation: Qt.Vertical

    onRotationChanged: {
        let velocity = rotation * speedMultiplier * 12
        flickable.flick(0, velocity)
        rotation = 0
    }
}
