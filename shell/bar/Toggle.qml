import QtQuick
import ".."

Rectangle {
    id: t
    property bool on: false
    signal toggled()
    width: 40; height: 22; radius: 11
    color: on ? Theme.pencil : Theme.emulsion
    Behavior on color { ColorAnimation { duration: Theme.tFast } }
    Rectangle {
        width: 16; height: 16; radius: 8
        y: 3
        x: t.on ? t.width - width - 3 : 3
        color: t.on ? Theme.darkroom : Theme.fixer
        Behavior on x { NumberAnimation { duration: Theme.tScrim; easing.type: Easing.OutCubic } }
    }
    MouseArea { anchors.fill: parent; onClicked: t.toggled() }
}
