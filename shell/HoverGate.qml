import QtQuick

// Hover-to-select that waits for the pointer to move.
//
// When an overlay opens, the pointer is wherever it was. The compositor sends
// the new surface a pointer enter at that spot, and Qt turns it into hover
// events (MouseArea `entered`, `containsMouse`) without the pointer having
// moved at all. Selecting on those would let the cell that happens to sit
// under a resting pointer take the selection from the one the overlay opened
// on. So hover stays inert after `reset()` until the pointer has travelled
// more than `threshold` px, in window coordinates, from the first position
// seen after the open. Cells that slide under a resting pointer (a scroll,
// a roll gaining a line) do not move it in window coordinates either, so
// they never arm the gate.
//
// Feed it from every hover-enabled MouseArea with `moved(item, x, y)`; call
// `reset()` before the overlay takes input.
QtObject {
    property real threshold: 8
    property bool armed: false
    property bool _seen: false
    property real _x: 0
    property real _y: 0
    function reset() { armed = false; _seen = false; }
    function moved(item, x, y) {
        if (armed) return;
        const p = item.mapToItem(null, x, y);
        if (!_seen) { _seen = true; _x = p.x; _y = p.y; return; }
        if (Math.hypot(p.x - _x, p.y - _y) > threshold) armed = true;
    }
}
