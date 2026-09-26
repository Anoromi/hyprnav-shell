import QtQuick
import ".."

// Thin track, Pencil fill, Paper thumb. While dragging, the thumb follows the
// pointer from a local value (the service's value arrives a round trip
// later, via PipeWire or the backlight file) and grows; `shownValue` is what
// a value label next to the slider should print.
Item {
    id: s
    property real value: 0
    signal moved(real v)
    readonly property bool dragging: ma.pressed
    property real local: 0
    property bool holding: false            // keep the local value until the service catches up
    readonly property real shownValue: dragging || holding ? local : value
    implicitHeight: 24

    Timer { id: release; interval: 400; onTriggered: s.holding = false }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 4; radius: 2
        color: Theme.emulsion
        Rectangle {
            width: parent.width * s.shownValue; height: parent.height; radius: 2; color: s.enabled ? Theme.pencil : Theme.fixer
            // Outside changes (keys, wpctl, the OSD) glide; a drag is followed 1:1.
            Behavior on width { enabled: !s.dragging && !s.holding; NumberAnimation { duration: Theme.tHover; easing.type: Easing.OutCubic } }
        }
    }
    Rectangle {
        id: thumb
        x: Math.max(0, Math.min(parent.width - width, parent.width * s.shownValue - width / 2))
        anchors.verticalCenter: parent.verticalCenter
        width: 14; height: 14; radius: 7
        color: Theme.paper
        border.color: s.dragging ? Theme.pencil : Theme.darkroom
        Behavior on x { enabled: !s.dragging && !s.holding; NumberAnimation { duration: Theme.tHover; easing.type: Easing.OutCubic } }
        scale: s.dragging ? 1.35 : (ma.containsMouse ? 1.15 : 1)
        Behavior on scale { NumberAnimation { duration: Theme.tHover; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.topMargin: -4; anchors.bottomMargin: -4
        enabled: s.enabled
        hoverEnabled: true
        preventStealing: true
        function upd(mx) {
            const v = Math.max(0, Math.min(1, mx / width));
            if (v === s.local && s.dragging) return;
            s.local = v; s.moved(v);
        }
        onPressed: e => { s.local = s.value; s.holding = true; release.stop(); upd(e.x); }
        onPositionChanged: e => { if (pressed) upd(e.x); }
        onReleased: release.restart()
    }
}
