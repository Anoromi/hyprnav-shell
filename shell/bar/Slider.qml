import QtQuick
import ".."

Item {
    id: s
    property real value: 0
    signal moved(real v)
    implicitHeight: 24
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 4; radius: 2
        color: Theme.emulsion
        Rectangle { width: parent.width * s.value; height: parent.height; radius: 2; color: s.enabled ? Theme.pencil : Theme.fixer }
    }
    Rectangle {
        x: Math.max(0, Math.min(parent.width - width, parent.width * s.value - width / 2))
        anchors.verticalCenter: parent.verticalCenter
        width: 14; height: 14; radius: 7
        color: Theme.paper
        border.color: Theme.darkroom
    }
    MouseArea {
        anchors.fill: parent
        enabled: s.enabled
        function upd(mx) { s.moved(Math.max(0, Math.min(1, mx / width))); }
        onPressed: e => upd(e.x)
        onPositionChanged: e => { if (pressed) upd(e.x); }
    }
}
