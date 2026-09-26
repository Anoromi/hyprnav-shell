pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../services" as Services
import ".."

// Most-recently-used workspace switcher. One row of frames, a pencil ring
// on the chosen one, the environment title of the chosen frame below.
//
// Speed: the layer surface is created once and stays mapped (transparent,
// empty input region, no keyboard) like the bar's sheets, so opening only
// flips opacity, input and keyboard focus. It opens from the cached MRU
// snapshot the service keeps warm and reconciles with a fresh one when that
// arrives; the daemon takes 50-120 ms to build one. See TESTING.md,
// "Switcher and grid speed".
//
// Hold-to-switch: Super+Tab (global shortcut `switcher-open`) opens with the
// next MRU entry selected, more Tabs step, and the Super release
// (`switcher-commit`) activates. `hold` marks an open that a release commits.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    property bool open: false
    property int selected: 0
    property string phase: "closed"   // closed | open | activating | cancelling
    property bool hold: false          // opened by the held shortcut: its release activates
    property bool waitingOpen: false   // no cached snapshot yet, the daemon's is on its way
    property bool commitPending: false // released before that snapshot arrived
    property bool userMoved: false     // stepped since opening: a late snapshot keeps the choice
    property int request: 0            // drops snapshots answering an older open
    readonly property bool shown: phase === "open" || phase === "activating"
    readonly property var rawItems: Services.Hyprnav.switcher ? Services.Hyprnav.switcher.items : []
    // Temporary workspaces live at the end of their own environment's grid row
    // and nowhere else, so they stay out of the MRU list: neither a card nor a
    // stop in the cycling order, and Alt-Tab can never land on one. The daemon
    // already drops them from the switcher snapshot; this keeps an older daemon
    // honest too.
    readonly property var items: rawItems.filter(it => !win.isTemporary(it))

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprnav-shell-switcher"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // Closed: an empty input region, so the mapped surface never takes a click.
    mask: open ? null : nowhere
    Region { id: nowhere }
    Component.onCompleted: Services.Hyprnav.keepSwitcherWarm = true

    function key(it) { return it ? it.workspace_id + "/" + it.slot_index : ""; }
    // Where the ring starts: the daemon's choice when the snapshot was built
    // for this direction, else the next (or, backwards, the last) MRU entry.
    function initialIndex(res, reverse, kept) {
        if (kept.length === 0) return 0;
        if (res._reverse === !!reverse) {
            const wanted = res.items[Math.max(0, Math.min(res.initial_index, res.items.length - 1))];
            const i = kept.findIndex(it => win.key(it) === win.key(wanted));
            if (i >= 0) return i;
        }
        return reverse ? kept.length - 1 : Math.min(1, kept.length - 1);
    }
    function present(res, reverse) {
        const kept = res.items.filter(it => !win.isTemporary(it));
        if (kept.length === 0) return false;
        selected = initialIndex(res, reverse, kept);
        perf.arm("open");
        phase = "open"; open = true;
        keys.forceActiveFocus();
        return true;
    }
    function show(reverse, held) {
        if (phase === "open") { step(reverse ? -1 : 1); return; }
        if (perf.enabled) console.info("[perf] switcher show() at " + Date.now());
        finish.stop();
        const id = ++request;
        userMoved = false; commitPending = false;
        hold = !!held;
        const cached = Services.Hyprnav.switcher;
        waitingOpen = !(cached && present(cached, reverse));
        Services.Hyprnav.refreshSwitcher(reverse, res => {
            if (id !== win.request || !res) return;
            if (perf.enabled) console.info("[perf] switcher snapshot at " + Date.now());
            if (win.waitingOpen) {
                win.waitingOpen = false;
                if (!win.present(res, reverse)) return;
                if (win.commitPending) { win.commitPending = false; win.activate(); }
                return;
            }
            if (win.phase !== "open") return;
            const kept = res.items.filter(it => !win.isTemporary(it));
            if (!win.userMoved) { win.selected = win.initialIndex(res, reverse, kept); return; }
            const i = kept.findIndex(it => win.key(it) === win.heldKey);
            win.selected = i >= 0 ? i : Math.min(win.selected, Math.max(0, kept.length - 1));
        });
    }
    property string heldKey: ""
    function step(dir) {
        if (items.length === 0) return;
        selected = (selected + dir + items.length) % items.length;
        userMoved = true; heldKey = key(items[selected]);
    }
    // The held shortcut's release: activate what the ring is on. A release
    // with the switcher closed, or opened some other way, does nothing.
    function commit() {
        if (!hold) return;
        if (phase === "open") activate();
        else if (waitingOpen) commitPending = true;
    }
    function activate() {
        if (phase !== "open") return;
        const it = items[selected];
        if (!it) { cancel(); return; }
        ++request;
        phase = "activating";
        const done = (r, e) => {
            if (e) console.warn("switcher: goto failed", JSON.stringify(e));
            else if (perf.enabled) console.info("[perf] switcher goto done at " + Date.now());
        };
        if (perf.enabled) console.info("[perf] switcher activate " + win.key(it) + " at " + Date.now());
        close();
        // Hand the keyboard back first, then switch. When Hyprland takes the
        // focus back from this layer after the switch has landed, it refocuses
        // the window that had it before, on the old workspace, and undoes the
        // switch (seen about half the time in the lab).
        afterRelease.run(() => {
            if (it.environment_id) Services.Hyprnav.gotoSlot(it.environment_id, it.slot_index, done);
            else Services.Hyprnav.gotoPhysical(it.workspace_id, done);
        });
    }
    function cancel() {
        ++request;
        if (waitingOpen) { waitingOpen = false; commitPending = false; }
        if (phase !== "open") return;
        phase = "cancelling";
        close();
    }
    // Keyboard and input go back at once; the content fades out in tSnap.
    function close() {
        open = false; hold = false;
        finish.interval = Theme.tSnap;
        finish.restart();
    }
    Timer { id: finish; onTriggered: win.phase = "closed" }
    PerfProbe { id: perf; label: "switcher" }
    FocusRelease { id: afterRelease }
    // A background refresh can reorder the list under an open switcher; keep
    // the ring on the frame the user chose.
    Connections {
        target: Services.Hyprnav
        function onSwitcherUpdated() {
            if (win.phase !== "open") return;
            if (win.userMoved) { const i = win.items.findIndex(it => win.key(it) === win.heldKey); if (i >= 0) { win.selected = i; return; } }
            win.selected = Math.min(win.selected, Math.max(0, win.items.length - 1));
        }
    }

    // Enrich each item with environment and slot from the grid snapshot.
    function cellFor(it) {
        const g = Services.Hyprnav.grid; if (!g || !it) return null;
        let best = null;
        for (const c of g.items) if (c.physical_workspace_id === it.workspace_id) { if (!best || c.environment_locked) best = c; }
        return best;
    }
    readonly property var selectedCell: cellFor(items[selected])

    // A card is temporary when the grid cell on its workspace is one of the
    // unnumbered, environment-owned slots. Without a grid snapshot nothing is
    // dropped here and the daemon's own filter carries it.
    function isTemporary(it) {
        const c = cellFor(it);
        return c !== null && (c.unnumbered === true || c.temporary === true);
    }

    // Geometry
    readonly property int inset: 160
    readonly property int gap: Theme.s24
    readonly property int maxCard: 300
    readonly property int cardW: items.length === 0 ? maxCard : Math.min(maxCard, Math.floor((width - inset * 2 - gap * (items.length - 1)) / items.length))
    readonly property int cardH: Math.round(cardW * 10 / 16)
    readonly property int rowY: Math.round((height - cardH) / 2) - 30

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: ev => {
            if (ev.key === Qt.Key_Tab || ev.key === Qt.Key_Right || ev.key === Qt.Key_Down) { win.step(1); ev.accepted = true; }
            else if (ev.key === Qt.Key_Backtab || ev.key === Qt.Key_Left || ev.key === Qt.Key_Up) { win.step(-1); ev.accepted = true; }
            else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { win.activate(); ev.accepted = true; }
            else if (ev.key === Qt.Key_Escape) { win.cancel(); ev.accepted = true; }
            else if (ev.key >= Qt.Key_1 && ev.key <= Qt.Key_9) {
                const n = ev.key - Qt.Key_1; if (n < win.items.length) { win.selected = n; win.activate(); } ev.accepted = true;
            }
        }
        MouseArea { anchors.fill: parent; enabled: win.open; onClicked: win.cancel() }
    }

    // Everything drawn: one short fade in and out, nothing moves.
    Item {
        id: content
        anchors.fill: parent
        opacity: win.open ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.tSnap } }
        onOpacityChanged: if (opacity === 1 && perf.enabled) console.info("[perf] switcher opaque at " + Date.now())

        Rectangle { anchors.fill: parent; color: Theme.scrim }

        // Frames
        Repeater {
            model: win.items
            delegate: Item {
                id: card
                required property var modelData
                required property int index
                readonly property bool isSelected: index === win.selected
                readonly property var cell: win.cellFor(modelData)
                x: win.inset + index * (win.cardW + win.gap)
                y: win.rowY
                width: win.cardW
                height: win.cardH + 34

                Rectangle {
                    id: frame
                    width: win.cardW; height: win.cardH
                    radius: Theme.rFrame
                    color: Theme.sheet
                    border.width: 1
                    border.color: Qt.rgba(Theme.paper.r, Theme.paper.g, Theme.paper.b, 0.35)
                    WorkspaceThumb {
                        anchors.fill: parent; anchors.margins: 3
                        workspaceId: card.modelData.workspace_id
                        fallbackClass: card.modelData.app_class
                        live: win.phase !== "closed"
                    }
                    Glyph {
                        anchors.right: parent.right; anchors.top: parent.top
                        anchors.rightMargin: 8; anchors.topMargin: 6
                        visible: card.cell !== null && card.cell.stuck === true
                        text: "󰐃"
                        size: 14
                        color: Theme.pencil
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: win.open
                        hoverEnabled: true
                        onEntered: { win.selected = card.index; win.userMoved = true; win.heldKey = win.key(card.modelData); }
                        onClicked: win.activate()
                    }
                }
                Row {
                    anchors.top: frame.bottom; anchors.topMargin: Theme.s8
                    anchors.left: frame.left
                    spacing: Theme.s8
                    Text {
                        text: card.cell ? (card.cell.unnumbered ? "" : card.cell.slot_index) : (card.index + 1)
                        visible: text !== ""
                        color: card.isSelected ? Theme.pencil : Theme.fixer
                        font.family: Theme.mono; font.pixelSize: Theme.fs15; font.weight: Font.Medium
                    }
                    Text {
                        width: win.cardW - 24
                        text: card.cell ? card.cell.slot_display_name : card.modelData.workspace_name
                        elide: Text.ElideRight
                        color: card.isSelected ? Theme.paper : Theme.fixer
                        font.family: Theme.sans; font.pixelSize: Theme.fs15
                        font.weight: card.isSelected ? Font.Medium : Font.Normal
                    }
                }
            }
        }

        // The ring: one item, a short slide between frames.
        Rectangle {
            id: ring
            visible: win.items.length > 0
            readonly property int pad: 7
            x: win.inset + win.selected * (win.cardW + win.gap) - pad
            y: win.rowY - pad
            width: win.cardW + pad * 2
            height: win.cardH + pad * 2
            radius: Theme.rFrame + pad
            color: "transparent"
            border.color: Theme.pencil
            border.width: Theme.ringWidth
            // No slide while hidden, so an open never shows the ring travelling.
            Behavior on x { enabled: win.open && content.opacity === 1; NumberAnimation { duration: Theme.tSnap; easing.type: Easing.OutCubic } }
        }

        // Environment title of the selected frame
        Item {
            x: win.inset
            y: win.rowY + win.cardH + 34 + Theme.s32
            width: win.width - win.inset * 2
            height: 40
            Text {
                id: envTitle
                text: win.selectedCell ? win.selectedCell.environment_title : (win.items[win.selected] ? win.items[win.selected].workspace_name : "")
                color: Theme.paper
                font.family: Theme.casual; font.pixelSize: Theme.fs22; font.weight: Font.Medium
            }
            Text {
                anchors.left: envTitle.right; anchors.leftMargin: Theme.s16
                anchors.baseline: envTitle.baseline
                visible: win.selectedCell && win.selectedCell.environment_locked
                text: "locked"
                color: Theme.pencil
                font.family: Theme.sans; font.pixelSize: Theme.fs13
            }
        }
    }
}
