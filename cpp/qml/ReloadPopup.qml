import QtQuick

Item {
    id: root
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: 12

    width: popup.isError ? 320 : successRow.implicitWidth + 28
    height: popup.isError ? Math.min(errorColumn.implicitHeight + 24, 400) : 36

    // Animation-driven — no declarative bindings on opacity/y
    opacity: 0
    transform: Translate { id: slideTranslate; y: 12 }
    visible: opacity > 0

    ParallelAnimation {
        id: appearAnim
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { target: slideTranslate; property: "y"; to: 0; duration: 200; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: disappearAnim
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 150; easing.type: Easing.InCubic }
        NumberAnimation { target: slideTranslate; property: "y"; to: -12; duration: 150; easing.type: Easing.InCubic }
    }

    Connections {
        target: popup
        function onShowAnimationRequested() {
            disappearAnim.stop();
            slideTranslate.y = 8;
            appearAnim.restart();
        }
        function onHideAnimationRequested() {
            appearAnim.stop();
            disappearAnim.restart();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: popup.isError ? "#E53E3E" : "#38A169"
        opacity: 0.95
        clip: true

        // — Success state —
        Row {
            id: successRow
            spacing: 7
            anchors.centerIn: parent
            visible: !popup.isError

            Canvas {
                width: 12; height: 12
                anchors.verticalCenter: parent.verticalCenter
                onPaint: {
                    var ctx = getContext("2d");
                    var cx = width / 2, cy = height / 2, r = 4.5;
                    ctx.clearRect(0, 0, width, height);
                    ctx.strokeStyle = "white";
                    ctx.lineWidth = 1.5;
                    ctx.lineCap = "round";
                    var gap = Math.PI / 4;
                    var end1 = Math.PI / 2 - gap / 2;
                    var end2 = Math.PI * 3 / 2 - gap / 2;
                    // Top arc
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, -Math.PI / 2 + gap / 2, end1);
                    ctx.stroke();
                    // Bottom arc
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, Math.PI / 2 + gap / 2, end2);
                    ctx.stroke();
                    // Arrowheads along tangent
                    function arrow(angle) {
                        var ax = cx + r * Math.cos(angle);
                        var ay = cy + r * Math.sin(angle);
                        var tx = -Math.sin(angle);
                        var ty = Math.cos(angle);
                        var nx = Math.cos(angle);
                        var ny = Math.sin(angle);
                        var s = 1.2;
                        ctx.beginPath();
                        ctx.moveTo(ax - s*tx + s*0.5*nx, ay - s*ty + s*0.5*ny);
                        ctx.lineTo(ax, ay);
                        ctx.lineTo(ax - s*tx - s*0.5*nx, ay - s*ty - s*0.5*ny);
                        ctx.stroke();
                    }
                    arrow(end1);
                    arrow(end2);
                }

                RotationAnimation on rotation {
                    from: 0; to: 360
                    duration: 700
                    loops: 2
                    running: root.opacity > 0 && !popup.isError
                }
            }

            Text {
                text: "Reloaded"
                color: "white"
                font.pixelSize: 13
                font.family: "SF Mono, Menlo, monospace"
            }
        }

        // — Error state —
        Flickable {
            anchors.fill: parent
            anchors.margins: 12
            contentHeight: errorColumn.implicitHeight
            clip: true
            visible: popup.isError

            Column {
                id: errorColumn
                width: parent.width
                spacing: 8

                // Copy button
                Rectangle {
                    width: copyRow.implicitWidth + 12
                    height: copyRow.implicitHeight + 6
                    radius: 3
                    color: Qt.rgba(1,1,1,0.1)
                    anchors.right: parent.right
                    opacity: copyMouse.pressed ? 0.4 : copyMouse.containsMouse ? 0.95 : 0.7
                    Behavior on opacity { NumberAnimation { duration: 100 } }

                    Row {
                        id: copyRow
                        anchors.centerIn: parent
                        spacing: 4

                        // Copy icon (Phosphor style)
                        Canvas {
                            width: 11; height: 11
                            anchors.verticalCenter: parent.verticalCenter
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                ctx.strokeStyle = "white";
                                ctx.lineWidth = 1.2;
                                ctx.lineCap = "round";
                                ctx.lineJoin = "round";
                                var r = 1;
                                // Front rect (bottom-left)
                                var x = 0.5, y = 3, w = 7, h = 7;
                                ctx.beginPath();
                                ctx.moveTo(x + r, y);
                                ctx.arcTo(x + w, y, x + w, y + r, r);
                                ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
                                ctx.arcTo(x, y + h, x, y + h - r, r);
                                ctx.arcTo(x, y, x + r, y, r);
                                ctx.closePath();
                                ctx.stroke();
                                // Back corner (top-right, open path)
                                ctx.beginPath();
                                ctx.moveTo(3.5, 3);
                                ctx.lineTo(3.5, 0.5 + r);
                                ctx.arcTo(3.5, 0.5, 3.5 + r, 0.5, r);
                                ctx.lineTo(10.5 - r, 0.5);
                                ctx.arcTo(10.5, 0.5, 10.5, 0.5 + r, r);
                                ctx.lineTo(10.5, 7);
                                ctx.lineTo(7.5, 7);
                                ctx.stroke();
                            }
                        }

                        Text {
                            text: "Copy"
                            color: "white"
                            font.pixelSize: 11
                            font.family: "SF Mono, Menlo, monospace"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: copyMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.copyToClipboard()
                    }
                }

                Repeater {
                    model: popup.errorText ? popup.errorText.split("\n") : []

                    Item {
                        required property string modelData
                        required property int index
                        width: errorColumn.width
                        height: errText.implicitHeight + 10

                        // Accent bar (left side)
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 3
                            color: Qt.rgba(1, 1, 1, 0.5)
                            topLeftRadius: 4
                            bottomLeftRadius: 4
                            topRightRadius: 0
                            bottomRightRadius: 0
                        }

                        // Background (right side)
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 3
                            color: Qt.rgba(1, 1, 1, 0.15)
                            topLeftRadius: 0
                            bottomLeftRadius: 0
                            topRightRadius: 4
                            bottomRightRadius: 4
                        }

                        Text {
                            id: errText
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 5
                            anchors.topMargin: 5
                            anchors.bottomMargin: 5
                            text: parent.modelData
                            color: "white"
                            font.pixelSize: 13
                            font.family: "SF Mono, Menlo, monospace"
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
    }
}
