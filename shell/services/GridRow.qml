import QtQuick

// One roll of the grid: a leaf environment and every frame it resolves,
// its ancestors' shared frames included. Like GridCell this
// outlives individual snapshots, so the row Repeater keeps its delegates and
// only the changed properties propagate.
QtObject {
    property int rowIndex: 0
    property string envId: ""
    property string title: ""
    property string displayId: ""
    // Some level of the chain is locked; `lockedEnvId` says which.
    property bool locked: false
    property string lockedEnvId: ""
    // Environment ids root to leaf, and the ancestor labels shown after the
    // title ("Proj", "main"): never raw ids.
    property var chainIds: []
    property var chainLabels: []
    property var breadcrumb: []
    // GridCell objects, in column order. Replaced only when the set of slots
    // changes, never on a plain data update.
    property var cells: []
}
