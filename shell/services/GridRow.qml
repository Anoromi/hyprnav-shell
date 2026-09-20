import QtQuick

// One roll of the grid: an environment and its frames. Like GridCell this
// outlives individual snapshots, so the row Repeater keeps its delegates and
// only the changed properties propagate.
QtObject {
    property int rowIndex: 0
    property string envId: ""
    property string title: ""
    property string displayId: ""
    property bool locked: false
    // GridCell objects, in column order. Replaced only when the set of slots
    // changes, never on a plain data update.
    property var cells: []
}
