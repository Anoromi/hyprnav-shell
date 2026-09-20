import QtQuick

// One frame of the grid, kept alive across snapshots.
//
// The daemon answers `ui_snapshot_grid` with a fresh JSON tree every time, so
// handing those raw arrays to a Repeater resets the delegate model on every
// refresh and destroys every cell, thumbnail and screencopy capture with it.
// Instead the service keeps one of these per slot, identified by `key`, and
// only swaps `snapshot` underneath it. Delegates survive; their bindings
// re-evaluate.
QtObject {
    // Stable identity of the slot: row, slot index and physical workspace.
    property string key: ""
    // The raw snapshot item from `ui_snapshot_grid`.
    property var snapshot: null
}
