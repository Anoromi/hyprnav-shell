import QtQuick
import ".."

// A flat control surface with the bar's hover and press language: hover
// lifts it 1 px onto an Emulsion wash, press sinks it back and shrinks it a
// little, all in 120 ms. `active` holds the full Emulsion fill (and an
// optional Pencil edge with `outlined`).
Rectangle {
    id: p
    property bool active: false
    property bool outlined: false
    property bool interactive: true
    property alias hovered: area.containsMouse
    property alias pressed: area.pressed
    property alias acceptedButtons: area.acceptedButtons
    property alias cursorShape: area.cursorShape
    signal clicked(var mouse)
    signal wheel(var wheel)
    radius: Theme.rControl
    color: active ? Theme.emulsion : (area.containsMouse && interactive ? Theme.hover : "transparent")
    border.width: outlined ? 1 : 0
    border.color: active ? Theme.pencil : Theme.emulsion
    scale: area.pressed && interactive ? 0.96 : 1
    transform: Translate { y: area.containsMouse && !area.pressed && p.interactive ? -1 : 0; Behavior on y { NumberAnimation { duration: Theme.tHover; easing.type: Easing.OutCubic } } }
    Behavior on color { ColorAnimation { duration: Theme.tHover } }
    Behavior on border.color { ColorAnimation { duration: Theme.tHover } }
    Behavior on scale { NumberAnimation { duration: Theme.tHover; easing.type: Easing.OutCubic } }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: p.interactive
        onClicked: m => p.clicked(m)
        onWheel: w => p.wheel(w)
    }
}
