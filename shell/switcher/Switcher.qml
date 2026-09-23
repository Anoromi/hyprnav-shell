pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../services" as Services
import ".."

// Most-recently-used workspace switcher. One row of frames, a pencil ring
// that slides between them, the environment title of the chosen frame below.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    property bool open: false
    property int selected: 0
    property string phase: "closed"   // closed | open | activating | cancelling
    readonly property var rawItems: Services.Hyprnav.switcher ? Services.Hyprnav.switcher.items : []
    // Temporary workspaces live at the end of their own environment's grid row
    // and nowhere else, so they stay out of the MRU list: neither a card nor a
    // stop in the cycling order, and Alt-Tab can never land on one. The daemon
    // already drops them from the switcher snapshot; this keeps an older daemon
    // honest too.
    readonly property var items: rawItems.filter(it => !win.isTemporary(it))

    visible: phase !== "closed"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprnav-shell-switcher"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function show(reverse) {
        if (phase === "open") { step(reverse ? -1 : 1); return; }
        Services.Hyprnav.refreshSwitcher(reverse, res => {
            if (!res || res.items.length === 0) return;
            // Re-point the daemon's initial index at the filtered list, so the
            // ring starts on the same workspace it would have without temps.
            const kept = res.items.filter(it => !win.isTemporary(it));
            if (kept.length === 0) return;
            const wanted = res.items[Math.max(0, Math.min(res.initial_index, res.items.length - 1))];
            let index = -1;
            for (let i = 0; i < kept.length; i++) {
                if (kept[i].workspace_id === wanted.workspace_id && kept[i].slot_index === wanted.slot_index) { index = i; break; }
            }
            selected = index >= 0 ? index : Math.max(0, Math.min(res.initial_index, kept.length - 1));
            phase = "open"; open = true;
            keys.forceActiveFocus();
        });
    }
    function step(dir) {
        if (items.length === 0) return;
        selected = (selected + dir + items.length) % items.length;
    }
    function activate() {
        if (phase !== "open") return;
        const it = items[selected];
        if (!it) { cancel(); return; }
        phase = "activating";
        if (it.environment_id) Services.Hyprnav.gotoSlot(it.environment_id, it.slot_index);
        else Services.Hyprnav.gotoPhysical(it.workspace_id);
        finish.interval = Theme.reducedMotion ? 0 : 140;
        finish.restart();
    }
    function cancel() {
        if (phase !== "open") return;
        phase = "cancelling";
        finish.interval = Theme.tFast;
        finish.restart();
    }
    Timer { id: finish; onTriggered: { win.open = false; win.phase = "closed"; } }

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

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: win.phase === "open" || win.phase === "activating" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: win.phase === "cancelling" ? Theme.tFast : Theme.tScrim; easing.type: Easing.OutCubic } }
    }

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
        MouseArea { anchors.fill: parent; onClicked: win.cancel() }
    }

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
            y: win.rowY + (win.phase === "open" || win.phase === "activating" ? 0 : 6)
            width: win.cardW
            height: win.cardH + 34
            opacity: win.phase === "closed" ? 0 : (win.phase === "activating" && !isSelected ? 0.4 : 1)
            Behavior on opacity { NumberAnimation { duration: win.phase === "cancelling" ? Theme.tFast : Theme.tRise; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: Theme.tRise; easing.type: Easing.OutCubic } }

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
                    live: win.visible
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
                    hoverEnabled: true
                    onEntered: win.selected = card.index
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
                    Behavior on color { ColorAnimation { duration: Theme.tFast } }
                }
                Text {
                    width: win.cardW - 24
                    text: card.cell ? card.cell.slot_display_name : card.modelData.workspace_name
                    elide: Text.ElideRight
                    color: card.isSelected ? Theme.paper : Theme.fixer
                    font.family: Theme.sans; font.pixelSize: Theme.fs15
                    font.weight: card.isSelected ? Font.Medium : Font.Normal
                    Behavior on color { ColorAnimation { duration: Theme.tFast } }
                }
            }
        }
    }

    // The ring: one item, slides between frames.
    Rectangle {
        id: ring
        visible: win.items.length > 0 && win.phase !== "closed"
        readonly property int pad: 7
        x: win.inset + win.selected * (win.cardW + win.gap) - pad
        y: win.rowY - pad
        width: win.cardW + pad * 2
        height: win.cardH + pad * 2
        radius: Theme.rFrame + pad
        color: "transparent"
        border.color: Theme.pencil
        border.width: win.phase === "activating" ? Theme.ringWidth + 2 : Theme.ringWidth
        scale: win.phase === "open" || win.phase === "activating" ? 1 : 0.92
        opacity: win.phase === "open" || win.phase === "activating" ? 1 : 0
        Behavior on x { enabled: !Theme.reducedMotion; SpringAnimation { spring: 4.2; damping: 0.36; epsilon: 0.2 } }
        Behavior on border.width { NumberAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: Theme.tRise; easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
    }

    // Environment title of the selected frame
    Item {
        x: win.inset
        y: win.rowY + win.cardH + 34 + Theme.s32
        width: win.width - win.inset * 2
        height: 40
        opacity: win.phase === "open" || win.phase === "activating" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.tScrim } }
        Text {
            id: envTitle
            property string shown: win.selectedCell ? win.selectedCell.environment_title : (win.items[win.selected] ? win.items[win.selected].workspace_name : "")
            text: shown
            color: Theme.paper
            font.family: Theme.casual; font.pixelSize: Theme.fs22; font.weight: Font.Medium
            onShownChanged: fade.restart()
            SequentialAnimation { id: fade
                NumberAnimation { target: envTitle; property: "opacity"; to: 0.55; duration: 40 }
                NumberAnimation { target: envTitle; property: "opacity"; to: 1; duration: Theme.tScrim }
            }
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
