import QtQuick
import ".."

// Soft top and bottom edges and a thin position hair for a list in a sheet,
// the grid's pattern (Grid.qml) at sheet scale: the fades show only where
// the content continues out of sight, the hair on the right edge shows while
// the list moves and fades once it has been still for a moment. No
// scrollbar. Lay it over the Flickable (anchors.fill); it takes the wheel,
// and the list's keys go through key(ev) for Up/Down/PageUp/PageDown/Home/End.
Item {
    id: edges
    required property Flickable flick
    property color fadeColor: Theme.sheet
    property int step: Theme.rowH + Theme.listGap
    readonly property bool overflows: flick.contentHeight > flick.height + 0.5
    readonly property bool canScrollUp: overflows && !flick.atYBeginning
    readonly property bool canScrollDown: overflows && !flick.atYEnd
    property bool indicatorShown: false
    property bool quiet: false              // set while the owner moves the list itself

    function bounded(y) {
        const top = flick.originY - flick.topMargin;
        const bottom = flick.originY + flick.contentHeight + flick.bottomMargin - flick.height;
        return Math.max(top, Math.min(Math.max(top, bottom), y));
    }
    // Wheel clicks and keys glide (Theme.tHover); touchpad pixels follow 1:1.
    function scrollTo(y, animated) {
        flick.cancelFlick();
        glide.stop();
        const to = bounded(y);
        if (animated && !Theme.reducedMotion && Math.abs(to - flick.contentY) > 0.5) { glide.from = flick.contentY; glide.to = to; glide.start(); }
        else flick.contentY = to;
    }
    function scrollBy(dy, animated) { scrollTo((glide.running ? glide.to : flick.contentY) + dy, animated); }
    function key(ev) {
        switch (ev.key) {
        case Qt.Key_Up: scrollBy(-step, true); break;
        case Qt.Key_Down: scrollBy(step, true); break;
        case Qt.Key_PageUp: scrollBy(-(flick.height - step), true); break;
        case Qt.Key_PageDown: scrollBy(flick.height - step, true); break;
        case Qt.Key_Home: scrollTo(-Infinity, true); break;
        case Qt.Key_End: scrollTo(Infinity, true); break;
        default: return;
        }
        ev.accepted = true;
    }

    // Only a real scroll shows the hair: rows arriving below leave contentY
    // alone, so a filling list stays quiet.
    Connections {
        target: edges.flick
        function onContentYChanged() { if (edges.overflows && !edges.quiet) { edges.indicatorShown = true; idle.restart(); } }
    }
    Timer { id: idle; interval: 800; onTriggered: edges.indicatorShown = false }
    NumberAnimation { id: glide; target: edges.flick; property: "contentY"; duration: Theme.tHover; easing.type: Easing.OutCubic }

    // The wheel, over the whole list and ahead of its rows (whose MouseAreas
    // would otherwise take it): one click moves a row and a half. Presses and
    // hover pass through to the rows; drag stays the Flickable's own.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: w => {
            if (!edges.overflows) return;
            if (w.pixelDelta.y !== 0) edges.scrollBy(-w.pixelDelta.y, false);
            else edges.scrollBy(-w.angleDelta.y / 120 * edges.step * 1.5, true);
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: Theme.listFadeH
        gradient: Gradient {
            GradientStop { position: 0; color: edges.fadeColor }
            GradientStop { position: 1; color: Qt.rgba(edges.fadeColor.r, edges.fadeColor.g, edges.fadeColor.b, 0) }
        }
        opacity: edges.canScrollUp ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.tSnap } }
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Theme.listFadeH
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(edges.fadeColor.r, edges.fadeColor.g, edges.fadeColor.b, 0) }
            GradientStop { position: 1; color: edges.fadeColor }
        }
        opacity: edges.canScrollDown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.tSnap } }
    }
    Rectangle {
        visible: edges.overflows
        x: parent.width - width
        width: 3; radius: 1.5
        height: Math.max(24, parent.height * edges.flick.visibleArea.heightRatio)
        y: Math.max(0, Math.min(parent.height - height, parent.height * edges.flick.visibleArea.yPosition))
        color: Theme.fixer
        opacity: edges.indicatorShown ? 0.9 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
    }
}
