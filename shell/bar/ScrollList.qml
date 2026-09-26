import QtQuick
import ".."

// A list in a sheet: a box of fixed height (set it from the Theme scale, e.g.
// Theme.wifiListH) whatever the number of rows, so the sheet never changes
// size as rows arrive. Rows scroll inside it by wheel, touchpad, drag, or
// keys while it has focus; ScrollEdges draws the fades and position hair.
// While the model is empty `placeholder` sits quietly in the same box.
//
// Feed it a ScriptModel: it diffs the new array against the old one, so
// rows that stay keep their delegates and a row added below the view leaves
// the scroll position where it is. Once scrolled, the top visible row is
// also held in place when rows arrive or reorder above it (a scan sorts
// saved and strong networks first); new rows open up below it.
Item {
    id: box
    property alias model: view.model
    property alias delegate: view.delegate
    property alias view: view
    property alias edges: edges
    property int step: Theme.rowH + Theme.listGap
    property string placeholder: ""
    property real bottomInset: 0            // room kept free for an overlay at the bottom

    property var anchorData: null           // model value of the top visible row, once scrolled
    property real anchorOffset: 0
    property bool restoring: false
    function noteAnchor() {
        if (view.contentY <= view.originY + 0.5) { anchorData = null; return; }
        const it = view.itemAt(0, view.contentY + 1);
        if (!it) { anchorData = null; return; }
        anchorData = it.modelData;
        anchorOffset = view.contentY - it.y;
    }
    function restoreAnchor() {
        if (anchorData === null || !view.model || !view.model.values) return;
        view.forceLayout();
        const idx = Array.prototype.indexOf.call(view.model.values, anchorData);
        const it = idx >= 0 ? view.itemAtIndex(idx) : null;
        if (!it) { noteAnchor(); return; }
        restoring = true;
        edges.quiet = true;
        edges.scrollTo(it.y + anchorOffset, false);
        edges.quiet = false;
        restoring = false;
    }
    Connections { target: view; function onContentYChanged() { if (!box.restoring) box.noteAnchor(); } }
    Connections { target: view.model; ignoreUnknownSignals: true; function onValuesChanged() { box.restoreAnchor(); } }

    ListView {
        id: view
        anchors.fill: parent
        clip: true
        spacing: Theme.listGap
        bottomMargin: box.bottomInset
        boundsBehavior: Flickable.StopAtBounds
        // Keep every row alive, not only the visible ones: these lists are
        // short (60 rows at most), and a row scrolled away and back should be
        // the same row, not a new one.
        cacheBuffer: 3000
        activeFocusOnTab: true
        Keys.onPressed: ev => edges.key(ev)
    }
    ScrollEdges { id: edges; anchors.fill: view; flick: view; step: box.step }
    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -box.bottomInset / 2
        visible: view.count === 0 && text !== ""
        text: box.placeholder
        color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13
    }
}
