import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: shell
    visible: true
    color: "transparent"

    title: contentLoader.item?.windowTitle ?? "cuirq"
    width: contentLoader.item?.windowWidth ?? 800
    height: contentLoader.item?.windowHeight ?? 600

    Loader {
        id: contentLoader
        anchors.fill: parent
        source: _cuirq_content_url

        onStatusChanged: {
            if (status === Loader.Error) {
                console.log("[Shell] ERROR loading content:", source)
            } else if (status === Loader.Ready) {
                console.log("[Shell] Content loaded:", source)
            }
        }
    }
}
