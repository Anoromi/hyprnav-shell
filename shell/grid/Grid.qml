pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../services" as Services
import ".."

// Environment grid: one roll per environment, one frame per slot.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    property bool open: false
    property string phase: "closed"   // closed | open | activating | closing
    property int selRow: 0
    property int selCol: 0
    readonly property var rows: Services.Hyprnav.rows
    readonly property var selectedRow: rows[selRow] ?? null
    readonly property var selectedCell: selectedRow ? (selectedRow.cells[selCol] ?? null) : null

    visible: phase !== "closed"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprnav-shell-grid"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function show() {
        if (phase === "open") return;
        Services.Hyprnav.refreshGrid(res => {
            if (!res) return;
            const rs = Services.Hyprnav.rows;
            let r = 0, c = 0;
            const it = res.items[res.initial_index];
            if (it) { r = rs.findIndex(x => x.rowIndex === it.row_index); c = Math.max(0, it.column_index); if (r < 0) r = 0; }
            selRow = r; selCol = Math.min(c, (rs[r]?.cells.length ?? 1) - 1);
            phase = "open"; open = true; keys.forceActiveFocus();
        });
    }
    function toggle() { if (phase === "open") close(); else show(); }
    function close() {
        if (phase !== "open") return;
        phase = "closing"; finish.interval = Theme.tFast; finish.restart();
    }
    function move(dr, dc) {
        if (rows.length === 0) return;
        let r = Math.max(0, Math.min(rows.length - 1, selRow + dr));
        let c = Math.max(0, Math.min(rows[r].cells.length - 1, selCol + dc));
        selRow = r; selCol = c;
    }
    function activate() {
        const cell = selectedCell; if (!cell || phase !== "open") return;
        phase = "activating";
        Services.Hyprnav.gotoSlot(cell.environment_id, cell.slot_index);
        finish.interval = Theme.reducedMotion ? 0 : 140; finish.restart();
    }
    function togglePalette() { if (palette.open) palette.hide(); else palette.show(); }
    function toggleLock() {
        const row = selectedRow; if (!row) return;
        if (row.locked) Services.Hyprnav.unlock(); else Services.Hyprnav.lock(row.envId);
    }
    Timer { id: finish; onTriggered: { win.open = false; win.phase = "closed"; } }

    // Geometry
    readonly property int inset: 160
    readonly property int cellW: 220
    readonly property int cellH: 138
    readonly property int gap: Theme.s16
    readonly property int titleH: 40
    readonly property int nameH: 30
    readonly property int rowGap: Theme.s32
    readonly property int rowH: titleH + cellH + nameH + rowGap
    readonly property int rowsTop: Math.max(80, Math.round((height - rows.length * rowH + rowGap) / 2))
    function cellX(c) { return inset + c * (cellW + gap); }
    function cellY(r) { return rowsTop + r * rowH + titleH; }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: win.phase === "open" || win.phase === "activating" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: win.phase === "closing" ? Theme.tFast : Theme.tScrim; easing.type: Easing.OutCubic } }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: ev => {
            if (ev.key === Qt.Key_P && (ev.modifiers & Qt.ControlModifier)) { if (palette.open) palette.hide(); else palette.show(); ev.accepted = true; return; }
            if (palette.open) return;
            switch (ev.key) {
            case Qt.Key_Right: case Qt.Key_L: win.move(0, 1); break;
            case Qt.Key_Left: case Qt.Key_H: win.move(0, -1); break;
            case Qt.Key_Down: case Qt.Key_J: win.move(1, 0); break;
            case Qt.Key_Up: case Qt.Key_K: win.move(-1, 0); break;
            case Qt.Key_Tab: win.move(0, 1); break;
            case Qt.Key_End: win.move(0, 99); break;
            case Qt.Key_Home: win.move(0, -99); break;
            case Qt.Key_Backtab: win.move(0, -1); break;
            case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: win.activate(); break;
            case Qt.Key_Escape: win.close(); break;
            default:
                if (ev.key >= Qt.Key_1 && ev.key <= Qt.Key_9) {
                    const n = ev.key - Qt.Key_1;
                    const row = win.selectedRow;
                    if (row) { const idx = row.cells.findIndex(c => c.slot_index === n + 1); if (idx >= 0) { win.selCol = idx; win.activate(); } }
                } else return;
            }
            ev.accepted = true;
        }
        MouseArea { anchors.fill: parent; onClicked: win.close() }
    }

    // Rows
    Repeater {
        model: win.rows
        delegate: Item {
            id: rowItem
            required property var modelData
            required property int index
            x: win.inset
            y: win.rowsTop + index * win.rowH + (win.phase === "open" || win.phase === "activating" ? 0 : 6)
            width: win.width - win.inset * 2
            height: win.rowH
            opacity: win.phase === "closed" ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: win.phase === "closing" ? Theme.tFast : Theme.tRise; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: Theme.tRise; easing.type: Easing.OutCubic } }

            Row {
                spacing: Theme.s12
                height: win.titleH
                Text {
                    text: rowItem.modelData.title
                    color: rowItem.index === win.selRow ? Theme.paper : Theme.fixer
                    font.family: Theme.casual; font.pixelSize: Theme.fs22; font.weight: Font.Medium
                    Behavior on color { ColorAnimation { duration: Theme.tFast } }
                }
                Text {
                    visible: rowItem.modelData.locked
                    anchors.baseline: parent.children[0].baseline
                    text: "locked"
                    color: Theme.pencil
                    font.family: Theme.sans; font.pixelSize: Theme.fs13
                }
                Text {
                    visible: rowItem.modelData.displayId.indexOf(".") >= 0
                    anchors.baseline: parent.children[0].baseline
                    text: "inside " + rowItem.modelData.displayId.split(".").slice(0, -1).join(".")
                    color: Theme.fixer
                    font.family: Theme.sans; font.pixelSize: Theme.fs13
                }
            }

            Repeater {
                model: rowItem.modelData.cells
                delegate: Item {
                    id: cellItem
                    required property var modelData
                    required property int index
                    readonly property bool isSelected: rowItem.index === win.selRow && index === win.selCol
                    readonly property bool hasWindows: modelData.window_count > 0
                    readonly property string launchName: {
                        if (modelData.subtitle && modelData.subtitle.indexOf("Workspace") !== 0) return modelData.subtitle;
                        return "";
                    }
                    x: index * (win.cellW + win.gap)
                    y: win.titleH
                    width: win.cellW
                    height: win.cellH + win.nameH
                    opacity: win.phase === "activating" && !isSelected ? 0.4 : 1
                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    Rectangle {
                        id: frame
                        width: win.cellW; height: win.cellH
                        radius: Theme.rFrame
                        color: cellItem.hasWindows ? Theme.sheet : Theme.emulsion
                        border.width: cellItem.modelData.inherited || cellItem.modelData.temporary ? 0 : 1
                        border.color: Qt.rgba(Theme.paper.r, Theme.paper.g, Theme.paper.b, cellItem.hasWindows ? 0.35 : 0.12)
                        Shape {
                            anchors.fill: parent
                            visible: cellItem.modelData.inherited || cellItem.modelData.temporary
                            ShapePath {
                                strokeColor: Qt.rgba(Theme.paper.r, Theme.paper.g, Theme.paper.b, 0.4)
                                strokeWidth: 1
                                fillColor: "transparent"
                                strokeStyle: ShapePath.DashLine
                                dashPattern: [4, 4]
                                startX: 0.5; startY: 0.5
                                PathLine { x: win.cellW - 0.5; y: 0.5 }
                                PathLine { x: win.cellW - 0.5; y: win.cellH - 0.5 }
                                PathLine { x: 0.5; y: win.cellH - 0.5 }
                                PathLine { x: 0.5; y: 0.5 }
                            }
                        }
                        WorkspaceThumb {
                            anchors.fill: parent; anchors.margins: 3
                            workspaceId: cellItem.modelData.physical_workspace_id
                            live: win.visible
                            emptyText: cellItem.hasWindows ? "" : (cellItem.modelData.subtitle && cellItem.modelData.subtitle.indexOf("Workspace") !== 0 ? "Opens " + cellItem.modelData.subtitle : "Empty frame")
                        }
                        // Pin: a spawned process tree is stuck to this frame.
                        Glyph {
                            anchors.right: parent.right; anchors.top: parent.top
                            anchors.rightMargin: 8; anchors.topMargin: 6
                            visible: cellItem.modelData.stuck === true
                            text: "󰐃"
                            size: 14
                            color: Theme.pencil
                        }
                        // Frame number, film-edge style. Temporary slots have no
                        // number: they carry their name in Casual instead.
                        Rectangle {
                            x: 6; y: 6
                            width: num.implicitWidth + 10; height: 20
                            radius: 2
                            color: cellItem.isSelected ? Theme.pencil : Theme.darkroom
                            Behavior on color { ColorAnimation { duration: Theme.tFast } }
                            Text {
                                id: num
                                anchors.centerIn: parent
                                text: cellItem.modelData.unnumbered ? cellItem.modelData.workspace_name : cellItem.modelData.slot_index
                                color: cellItem.isSelected ? Theme.darkroom : Theme.paper
                                font.family: cellItem.modelData.unnumbered ? Theme.casual : Theme.mono
                                font.pixelSize: Theme.fs13; font.weight: Font.Medium
                            }
                        }
                        // Temporary slot empty timer
                        Row {
                            anchors.left: parent.left; anchors.bottom: parent.bottom
                            anchors.leftMargin: 6; anchors.bottomMargin: 6
                            spacing: 4
                            visible: cellItem.modelData.temporary === true && cellItem.modelData.empty_for_ms !== null && cellItem.modelData.empty_for_ms !== undefined
                            Glyph { text: "󰔟"; size: 12; color: Theme.fixer }
                            Text {
                                text: "empty " + Math.round((cellItem.modelData.empty_for_ms || 0) / 1000) + " s, gone at 30"
                                color: Theme.fixer
                                font.family: Theme.sans; font.pixelSize: Theme.fs12
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: { win.selRow = rowItem.index; win.selCol = cellItem.index; }
                            onClicked: win.activate()
                        }
                    }
                    Row {
                        anchors.top: frame.bottom; anchors.topMargin: 7
                        spacing: Theme.s8
                        Text {
                            width: win.cellW - (cellItem.modelData.active ? 50 : 0)
                            text: cellItem.modelData.unnumbered ? ("temporary" + (cellItem.modelData.owner ? ", by " + cellItem.modelData.owner : "")) : cellItem.modelData.slot_display_name
                            elide: Text.ElideRight
                            color: cellItem.isSelected ? Theme.paper : Theme.fixer
                            font.family: Theme.sans; font.pixelSize: Theme.fs13
                            font.weight: cellItem.isSelected ? Font.Medium : Font.Normal
                            Behavior on color { ColorAnimation { duration: Theme.tFast } }
                        }
                        Text {
                            visible: cellItem.modelData.active
                            text: "here"
                            color: Theme.pencil
                            font.family: Theme.sans; font.pixelSize: Theme.fs13
                        }
                    }
                }
            }
        }
    }

    // The ring
    Rectangle {
        id: ring
        visible: win.selectedCell !== null && win.phase !== "closed"
        readonly property int pad: 6
        x: win.cellX(win.selCol) - pad
        y: win.cellY(win.selRow) - pad
        width: win.cellW + pad * 2
        height: win.cellH + pad * 2
        radius: Theme.rFrame + pad
        color: "transparent"
        border.color: Theme.pencil
        border.width: win.phase === "activating" ? Theme.ringWidth + 2 : Theme.ringWidth
        scale: win.phase === "open" || win.phase === "activating" ? 1 : 0.92
        opacity: win.phase === "open" || win.phase === "activating" ? 1 : 0
        Behavior on x { enabled: !Theme.reducedMotion; SpringAnimation { spring: 4.2; damping: 0.36; epsilon: 0.2 } }
        Behavior on y { enabled: !Theme.reducedMotion; SpringAnimation { spring: 4.2; damping: 0.36; epsilon: 0.2 } }
        Behavior on border.width { NumberAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: Theme.tRise; easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
    }

    // Command palette
    CommandPalette {
        id: palette
        anchors.centerIn: parent
        actions: win.paletteActions()
        onRun: (action, text) => win.runAction(action, text)
        onOpenChanged: if (!open) keys.forceActiveFocus()
    }
    readonly property var paletteActions: function() {
        const cell = win.selectedCell; const row = win.selectedRow;
        const list = [];
        if (cell) {
            list.push({ id: "open", scope: "frame", title: "Open frame" });
            list.push({ id: "slot-remove", scope: "frame", title: cell.temporary ? "Remove temporary slot" : "Remove slot" });
            list.push({ id: "slot-rename", scope: "frame", title: "Rename slot", needsText: true, prompt: "New name", defaultText: cell.slot_display_name });
            list.push({ id: "slot-command", scope: "frame", title: "Set launch command", needsText: true, prompt: "Command", defaultText: "" });
            list.push({ id: "slot-command-clear", scope: "frame", title: "Clear launch command" });
            if (cell.stuck) list.push({ id: "stick-release", scope: "frame", title: "Release stuck tree" });
            if (cell.window_count > 0) list.push({ id: "close-all", scope: "frame", title: "Close all windows here" });
            if (cell.window_count > 0) list.push({ id: "move-windows", scope: "frame", title: "Move windows to slot…", needsText: true, prompt: "Slot number or name", defaultText: "" });
        }
        if (row) {
            list.push({ id: "temp-new", scope: "roll", title: "New temporary slot" });
            list.push({ id: "temp-run", scope: "roll", title: "New temporary slot and run…", needsText: true, prompt: "Command", defaultText: "" });
            list.push({ id: "env-rename", scope: "roll", title: "Rename environment", needsText: true, prompt: "Title", defaultText: row.title });
            list.push({ id: "lock", scope: "roll", title: row.locked ? "Unlock environment" : "Lock environment" });
            if (row.cells.every(c => c.window_count === 0)) list.push({ id: "env-delete", scope: "roll", title: "Delete environment" });
        }
        list.push({ id: "goto-locked", scope: "everywhere", title: "Go to locked environment" });
        list.push({ id: "refresh", scope: "everywhere", title: "Refresh" });
        return list;
    }
    function windowsOn(workspaceId) {
        return Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.id === workspaceId);
    }
    // Ask the compositor directly which windows sit on a workspace. Quickshell's
    // toplevel cache can lag behind windows the stick manager moved at open.
    function withWindowsOn(workspaceId, cb) {
        const proc = clientsRunner.createObject(win, { command: ["hyprctl", "-j", "clients"], workspaceId: workspaceId, callback: cb });
        proc.running = true;
    }
    Component {
        id: clientsRunner
        Process {
            property int workspaceId: -1
            property var callback: null
            stdout: StdioCollector {
                onStreamFinished: {
                    let list = [];
                    try { list = JSON.parse(text).filter(c => c.workspace && c.workspace.id === workspaceId && c.mapped).map(c => c.address); } catch (e) { console.log("clients parse failed", e); }
                    if (callback) callback(list);
                }
            }
            onExited: destroy()
        }
    }
    // Hyprland wants "address:0x…"; Quickshell reports the hex without the prefix.
    function addr(t) { const a = String(t.address); return "address:" + (a.startsWith("0x") ? a : "0x" + a); }
    // Quickshell's Hyprland.dispatch does not carry Lua dispatcher calls
    // reliably on 0.56; hyprctl does.
    function dispatch(cmd) {
        const proc = hyprctlRunner.createObject(win, { command: ["hyprctl", "dispatch", cmd] });
        proc.running = true;
    }
    Component {
        id: hyprctlRunner
        Process {
            stdout: StdioCollector { onStreamFinished: if (text.trim() !== "ok" && text.trim() !== "") console.log("hyprctl:", text.trim()) }
            stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.log("hyprctl error:", text.trim()) }
            onExited: (code) => { if (code !== 0) console.log("hyprctl exit", code, JSON.stringify(command)); destroy(); }
            stdinEnabled: false
        }
    }
    function runAction(action, text) {
        const cell = win.selectedCell; const row = win.selectedRow;
        switch (action.id) {
        case "open": win.activate(); break;
        case "slot-remove": if (cell) Services.Hyprnav.slotRemove(cell.binding_environment_id || cell.environment_id, cell.slot_index); break;
        case "slot-rename": if (cell) Services.Hyprnav.slotRename(cell.binding_environment_id || cell.environment_id, cell.slot_index, text.trim()); break;
        case "slot-command": if (cell && text.trim()) Services.Hyprnav.slotCommandSet(cell.environment_id, cell.slot_index, Services.Hyprnav.splitArgv(text.trim())); break;
        case "slot-command-clear": if (cell) Services.Hyprnav.slotCommandClear(cell.environment_id, cell.slot_index); break;
        case "stick-release": if (cell) Services.Hyprnav.stickRelease(cell.physical_workspace_id); break;
        case "close-all": if (cell) withWindowsOn(cell.physical_workspace_id, list => { for (const a of list) dispatch("hl.dsp.window.kill({ window = \"address:" + a + "\" })"); }); break;
        case "move-windows": {
            if (!cell || !row) break;
            const q = text.trim().toLowerCase();
            const target = row.cells.find(c => String(c.slot_index) === q || (c.slot_display_name || "").toLowerCase() === q);
            if (!target) break;
            withWindowsOn(cell.physical_workspace_id, list => { for (const a of list) dispatch("hl.dsp.window.move({ window = \"address:" + a + "\", workspace = \"" + target.physical_workspace_id + " silent\" })"); });
            break;
        }
        case "temp-new": if (row) Services.Hyprnav.slotTempCreate(row.envId, null); break;
        case "temp-run": if (row && text.trim()) Services.Hyprnav.slotTempCreate(row.envId, null, (res) => { if (res && res.physical_workspace_id) Quickshell.execDetached(["hyprnav", "spawn", "--no-focus", String(res.physical_workspace_id), "--"].concat(Services.Hyprnav.splitArgv(text.trim()))); }); break;
        case "env-rename": if (row && text.trim()) Services.Hyprnav.envTitleSet(row.envId, text.trim()); break;
        case "lock": win.toggleLock(); break;
        case "env-delete": if (row) Services.Hyprnav.envDelete(row.envId); break;
        case "goto-locked": { const lockedRow = win.rows.findIndex(r => r.locked); if (lockedRow >= 0) { win.selRow = lockedRow; win.selCol = 0; } break; }
        case "refresh": Services.Hyprnav.refreshAll(); break;
        }
    }

    // Key hints, bottom left
    Text {
        x: win.inset
        y: win.height - 60
        text: "Enter opens the frame.  Ctrl+P for actions.  Esc closes.  󰐃 marks a stuck tree."
        color: Theme.fixer
        font.family: Theme.sans; font.pixelSize: Theme.fs13
        opacity: win.phase === "open" ? 0.8 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.tScrim } }
    }
}
