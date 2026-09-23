pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Client for the hyprnav daemon: one JSON request per line on a Unix socket,
// one JSON response line back. Requests are queued and sent one at a time.
Singleton {
    id: root

    property string socketPath: ""
    property string eventsSocketPath: ""
    property bool connected: false
    property var grid: null          // GridSnapshot
    property var switcher: null      // SwitcherSnapshot
    property var status: null        // StatusSnapshot
    property string lastError: ""

    signal gridUpdated()
    signal switcherUpdated()

    // Push events from the daemon's events.sock. `agents` carries the full
    // registry, `slots` is a bare marker meaning "re-read the grid snapshot".
    property var agents: []
    signal agentsEvent(var agents)
    signal slotsEvent()

    property var _queue: []
    property var _inflight: null

    function request(op, params, cb) {
        const body = Object.assign({ op: op }, params || {});
        _queue.push({ line: JSON.stringify(body) + "\n", cb: cb || null });
        _pump();
    }

    // The daemon serves one connection at a time, so each request opens its
    // own short connection, exactly like the Rust CLI client does. Holding a
    // connection open would block every other hyprnav client.
    function _pump() {
        if (_inflight || _queue.length === 0 || socketPath === "" || sock.connected) return;
        _inflight = _queue.shift();
        sock.connected = true;
        timeout.restart();
    }

    function _handleLine(line) {
        timeout.stop();
        const req = _inflight;
        _inflight = null;
        sock.connected = false;
        let parsed = null;
        try { parsed = JSON.parse(line); } catch (e) { lastError = "bad json: " + line.slice(0, 120); }
        if (req && req.cb) {
            if (parsed && parsed.ok) req.cb(parsed.result, null);
            else req.cb(null, parsed && parsed.error ? parsed.error : { code: "unknown", message: line });
        }
        if (parsed && !parsed.ok && parsed.error) lastError = parsed.error.code + ": " + parsed.error.message;
        Qt.callLater(_pump);
    }

    Timer {
        id: timeout
        interval: 3000
        onTriggered: {
            lastError = "request timed out";
            const req = root._inflight; root._inflight = null;
            sock.connected = false;
            if (req && req.cb) req.cb(null, { code: "timeout", message: "hyprnav daemon did not answer" });
            Qt.callLater(root._pump);
        }
    }

    Socket {
        id: sock
        path: root.socketPath
        parser: SplitParser { splitMarker: "\n"; onRead: data => root._handleLine(data) }
        onConnectionStateChanged: {
            if (connected && root._inflight) { sock.write(root._inflight.line); sock.flush(); }
            else if (!connected) {
                if (root._inflight) {
                    // Closed before answering: fail this request, move on.
                    timeout.stop();
                    const req = root._inflight; root._inflight = null;
                    root.lastError = "daemon closed the connection";
                    if (req && req.cb) req.cb(null, { code: "closed", message: root.lastError });
                }
                Qt.callLater(root._pump);
            }
        }
        onError: err => { root.lastError = "socket: " + err; }
    }
    onSocketPathChanged: if (socketPath !== "") {
        connected = true;
        eventsSocketPath = socketPath.replace(/hyprnav\.sock$/, "events.sock");
        refreshAll();
    }

    // Event stream. Unlike the request socket this one is multi-client and
    // write-only on the daemon side, so holding it open blocks nobody.
    function _handleEvent(line) {
        let ev = null;
        try { ev = JSON.parse(line); } catch (e) { return; }
        if (!ev || !ev.event) return;
        if (ev.event === "agents") {
            root.agents = ev.agents || [];
            root.agentsEvent(root.agents);
        } else if (ev.event === "slots") {
            root.slotsEvent();
            refreshDebounce.restart();
        }
    }

    Socket {
        id: eventsSock
        path: root.eventsSocketPath
        parser: SplitParser { splitMarker: "\n"; onRead: data => root._handleEvent(data) }
        onConnectionStateChanged: if (!connected && root.eventsSocketPath !== "") eventsRetry.restart()
        // A missing socket (daemon not up yet, or restarted) surfaces as an
        // error rather than a state change, so retry from here too.
        onError: err => { root.lastError = "events socket: " + err; eventsRetry.restart(); }
    }
    // The daemon may restart under us; keep trying.
    Timer {
        id: eventsRetry
        interval: 2000
        onTriggered: if (!eventsSock.connected && root.eventsSocketPath !== "") eventsSock.connected = true
    }
    onEventsSocketPathChanged: if (eventsSocketPath !== "") eventsSock.connected = true

    // Locate the daemon socket: $XDG_RUNTIME_DIR/hx/<fnv1a64(instance)>/hyprnav.sock
    Process {
        id: finder
        command: ["sh", "-c", "ls -t \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}\"/hx/*/hyprnav.sock 2>/dev/null | head -n1"]
        running: true
        stdout: StdioCollector { onStreamFinished: {
            const p = text.trim();
            if (p !== "") root.socketPath = p; else { root.lastError = "hyprnav daemon socket not found"; findRetry.start(); }
        } }
    }
    Timer { id: findRetry; interval: 2000; onTriggered: finder.running = true }

    // Public API
    function refreshAll() { refreshStatus(); refreshGrid(); }
    function refreshGrid(cb) {
        request("ui_snapshot_grid", { cwd: null }, (res, err) => { if (res) { grid = res; gridUpdated(); } if (cb) cb(res, err); });
    }
    function refreshSwitcher(reverse, cb) {
        request("ui_snapshot_switcher", { reverse: !!reverse }, (res, err) => { if (res) { switcher = res; switcherUpdated(); } if (cb) cb(res, err); });
    }
    function refreshStatus() { request("status_get", { cwd: null }, res => { if (res) status = res; }); }
    function gotoSlot(env, slot, cb) { request("workspace_goto", { env: env, slot: slot }, (r, e) => { refreshDebounce.restart(); if (cb) cb(r, e); }); }
    function gotoPhysical(ws, cb) { request("workspace_goto_physical", { workspace_id: ws }, (r, e) => { refreshDebounce.restart(); if (cb) cb(r, e); }); }
    function lock(env, cb) { request("lock_set", { env: env }, (r, e) => { refreshAll(); if (cb) cb(r, e); }); }
    function unlock(cb) { request("lock_clear", {}, (r, e) => { refreshAll(); if (cb) cb(r, e); }); }

    // Slot and environment mutations used by the grid palette.
    function slotTempCreate(env, name, cb) { request("slot_temp_create", { env: env, cwd: null, name: name || null, owner: "grid", client: null, launch_argv: null }, (r, e) => { refreshAll(); if (cb) cb(r, e); }); }
    function slotRemove(env, slot, cb) { request("slot_remove", { env: env, slot: slot, name: null }, (r, e) => { refreshAll(); if (cb) cb(r, e); }); }
    function slotRename(env, slot, name, cb) { request(name ? "slot_name_set" : "slot_name_clear", name ? { env: env, slot: slot, name: name } : { env: env, slot: slot }, (r, e) => { refreshAll(); if (cb) cb(r, e); }); }
    function slotCommandSet(env, slot, argv, cb) { request("slot_command_set", { env: env, slot: slot, argv: argv, display_name: null }, (r, e) => { refreshAll(); if (cb) cb(r, e); }); }
    function slotCommandClear(env, slot, cb) { request("slot_command_clear", { env: env, slot: slot }, (r, e) => { refreshAll(); if (cb) cb(r, e); }); }
    function envTitleSet(env, title, cb) { request("env_title_set", { env: env, title: title }, (r, e) => { refreshAll(); if (cb) cb(r, e); }); }
    function envDelete(env, cb) { request("env_delete", { env: env }, (r, e) => { refreshAll(); if (cb) cb(r, e); }); }
    function stickRelease(workspaceId, cb) {
        request("stick_list", {}, (res, err) => {
            if (!res) { if (cb) cb(null, err); return; }
            const hits = (res.persisted || []).filter(s => s.workspace_id === workspaceId);
            let left = hits.length; if (left === 0) { refreshAll(); if (cb) cb({ released: 0 }, null); return; }
            for (const h of hits) request("stick_release", { stick_id: h.stick_id }, () => { if (--left === 0) { refreshAll(); if (cb) cb({ released: hits.length }, null); } });
        });
    }
    // Split a command line on spaces, honouring double quotes.
    function splitArgv(text) {
        const out = []; let cur = ""; let q = false;
        for (const ch of text) { if (ch === '"') q = !q; else if (ch === " " && !q) { if (cur) out.push(cur); cur = ""; } else cur += ch; }
        if (cur) out.push(cur); return out;
    }

    readonly property string lockedEnv: status && status.locked_environment_id ? status.locked_environment_id : ""

    // Rows derived from the grid snapshot, for the grid overlay and the bar.
    //
    // These are long-lived GridRow/GridCell objects rather than plain JSON, and
    // `rows` is only reassigned when the set of rows or slots actually changes.
    // A Repeater fed a fresh array resets its whole delegate model, which in the
    // grid means every cell, thumbnail and screencopy capture is destroyed and
    // rebuilt; with a live snapshot field such as an agent's `last_action` or a
    // temporary slot's `empty_for_ms` that happened once a second and made the
    // thumbnails blink. Updating `snapshot` in place leaves delegates alone.
    property var rows: []
    property var _cellsByKey: ({})
    property var _rowsByIndex: ({})
    property Component _cellComponent: Component { GridCell {} }
    property Component _rowComponent: Component { GridRow {} }

    function _cellKey(c) { return c.row_index + "/" + c.slot_index + "/" + c.physical_workspace_id; }

    function _syncRows() {
        const byRow = {};
        const order = [];
        for (const c of (grid ? grid.items : [])) {
            if (!(c.row_index in byRow)) { byRow[c.row_index] = []; order.push(c.row_index); }
            byRow[c.row_index].push(c);
        }
        order.sort((a, b) => a - b);

        const keptRows = {}, keptCells = {};
        const nextRows = [];
        // Rows and cells are tracked apart on purpose: a window opening in one
        // frame replaces that row's cells, and reassigning `rows` as well would
        // rebuild every other roll's thumbnails for nothing.
        let rowSetChanged = order.length !== rows.length;

        for (const idx of order) {
            const items = byRow[idx].sort((a, b) => a.column_index - b.column_index);
            const head = items[0];
            let row = _rowsByIndex[idx];
            if (!row) { row = _rowComponent.createObject(root); rowSetChanged = true; }
            keptRows[idx] = row;
            row.rowIndex = idx;
            row.envId = head.environment_id;
            row.title = head.environment_title;
            row.displayId = head.environment_display_id;
            row.locked = head.environment_locked;

            const keys = items.map(_cellKey);
            let sameCells = keys.length === row.cells.length;
            if (sameCells) for (let i = 0; i < keys.length; i++) if (row.cells[i].key !== keys[i]) { sameCells = false; break; }
            if (sameCells) {
                for (let i = 0; i < items.length; i++) { row.cells[i].snapshot = items[i]; keptCells[keys[i]] = row.cells[i]; }
            } else {
                const cells = [];
                for (let i = 0; i < items.length; i++) {
                    let cell = _cellsByKey[keys[i]];
                    if (!cell) { cell = _cellComponent.createObject(root, { key: keys[i] }); }
                    cell.snapshot = items[i];
                    keptCells[keys[i]] = cell;
                    cells.push(cell);
                }
                row.cells = cells;
            }
            nextRows.push(row);
        }

        for (const k in _cellsByKey) if (!(k in keptCells)) _cellsByKey[k].destroy();
        for (const i in _rowsByIndex) if (!(i in keptRows)) _rowsByIndex[i].destroy();
        _cellsByKey = keptCells;
        _rowsByIndex = keptRows;

        if (!rowSetChanged) for (let i = 0; i < nextRows.length; i++) if (nextRows[i] !== rows[i]) { rowSetChanged = true; break; }
        if (rowSetChanged) rows = nextRows;
    }
    onGridChanged: _syncRows()

    // Live agent registry keyed by the workspace each agent works in. Beats
    // arrive on the event socket already; a cell reads its agent from here
    // instead of making the grid re-request the whole snapshot every second.
    readonly property var agentsByWorkspace: {
        const m = {};
        for (const a of agents) if (a.workspace_id !== null && a.workspace_id !== undefined) m[a.workspace_id] = a;
        return m;
    }
    function agentFor(workspaceId) { return agentsByWorkspace[workspaceId] ?? null; }

    // The cell whose workspace is currently focused, if any.
    readonly property var activeCell: {
        if (!grid) return null;
        for (const c of grid.items) if (c.active) return c;
        return null;
    }

    // Refresh after compositor changes, debounced.
    Timer { id: refreshDebounce; interval: 80; onTriggered: root.refreshAll() }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            const n = ev.name;
            if (n === "workspace" || n === "workspacev2" || n === "openwindow" || n === "closewindow" || n === "activewindow" || n === "movewindow" || n === "movewindowv2" || n === "focusedmon" || n === "createworkspace" || n === "destroyworkspace")
                refreshDebounce.restart();
        }
    }
}
