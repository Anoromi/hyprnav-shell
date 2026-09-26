import QtQuick

// A Nerd Font glyph that cross-fades when its text changes (tile icons that
// flip state) and eases its colour.
Item {
    id: g
    property string text: ""
    property int size: 15
    property color color: Theme.paper
    property bool flip: false
    implicitWidth: Math.max(a.implicitWidth, b.implicitWidth)
    implicitHeight: Math.max(a.implicitHeight, b.implicitHeight)
    onTextChanged: {
        if (!g.flip && a.text === text || g.flip && b.text === text) return;
        if (g.flip) a.text = text; else b.text = text;
        g.flip = !g.flip;
    }
    Component.onCompleted: a.text = text
    Glyph {
        id: a
        anchors.centerIn: parent; size: g.size; color: g.color
        opacity: g.flip ? 0 : 1; scale: g.flip ? 0.8 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
        Behavior on scale { NumberAnimation { duration: Theme.tOpen; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.tHover } }
    }
    Glyph {
        id: b
        anchors.centerIn: parent; size: g.size; color: g.color
        opacity: g.flip ? 1 : 0; scale: g.flip ? 1 : 0.8
        Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
        Behavior on scale { NumberAnimation { duration: Theme.tOpen; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.tHover } }
    }
}
