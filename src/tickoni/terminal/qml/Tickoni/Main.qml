import QtQuick 2.15
import QtQuick.Controls 2.15

ApplicationWindow {
    width: 640
    height: 480
    visible: true
    title: "tickoni"

    Rectangle {
        anchors.fill: parent
        color: "#f0f0f0"

        Text {
            anchors.centerIn: parent
            text: "tickoni"
            font.pixelSize: 32
            color: "#000000"
        }
    }
}
