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
    property var _socket: null
    property int _retryDelay: 200

    function request(op, params, cb) {
        const body = Object.assign({ op: op }, params || {});
        _queue.push({ op: op, line: JSON.stringify(body) + "\n", cb: cb || null });
        _pump();
    }

    // The daemon serves one connection at a time, so each request opens its
    // own short connection, exactly like the Rust CLI client does. Holding a
    // connection open would block every other hyprnav client.
    function _pump() {
        if (_inflight || _queue.length === 0 || socketPath === "" || _socket || requestRetry.running) return;
        _inflight = _queue.shift();
        _socket = requestSocket.createObject(root, { path: socketPath });
        _socket.connected = true;
        timeout.restart();
    }

    function _closeSocket() {
        const current = _socket;
        _socket = null;
        if (current) { current.connected = false; current.destroy(); }
    }

    function _handleLine(line) {
        timeout.stop();
        _retryDelay = 200;
        const req = _inflight;
        _inflight = null;
        _closeSocket();
        let parsed = null;
        try { parsed = JSON.parse(line); } catch (e) { lastError = "bad json: " + line.slice(0, 120); }
        if (req && req.cb) {
            if (parsed && parsed.ok) req.cb(parsed.result, null);
            else req.cb(null, parsed && parsed.error ? parsed.error : { code: "unknown", message: line });
        }
        if (parsed && !parsed.ok && parsed.error) lastError = parsed.error.code + ": " + parsed.error.message;
        Qt.callLater(_pump);
    }

    function _recoverRequest(reason) {
        timeout.stop();
        lastError = reason;
        const req = _inflight;
        _inflight = null;
        // Snapshot reads are safe to retry. A mutation may have reached the
        // daemon before the transport failed, so report that error instead.
        if (req && ["status_get", "ui_snapshot_grid", "ui_snapshot_switcher"].includes(req.op)) _queue.unshift(req);
        else if (req && req.cb) req.cb(null, { code: "socket", message: reason });
        _closeSocket();
        requestRetry.interval = _retryDelay;
        requestRetry.restart();
        _retryDelay = Math.min(_retryDelay * 2, 2000);
    }

    Timer {
        id: timeout
        interval: 3000
        onTriggered: {
            root._recoverRequest("request timed out");
        }
    }

    Timer {
        id: requestRetry
        interval: 200
        onTriggered: { requestRetry.stop(); root._pump(); }
    }

    Component {
        id: requestSocket
        Socket {
            id: transport
            parser: SplitParser { splitMarker: "\n"; onRead: data => { if (root._socket === transport) root._handleLine(data); } }
            onConnectionStateChanged: {
                if (root._socket !== transport) return;
                if (connected && root._inflight) { transport.write(root._inflight.line); transport.flush(); }
                else if (!connected && root._inflight) root._recoverRequest("daemon closed the connection");
            }
            onError: err => { if (root._socket === transport) root._recoverRequest("socket: " + err); }
        }
    }
    onSocketPathChanged: if (socketPath !== "") {
        connected = true;
        eventsSocketPath = socketPath.replace(/hyprnav\.sock$/, "events.sock");
        refreshAll();
        if (keepSwitcherWarm) refreshSwitcher(false);
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
    // `_reverse` records the direction the daemon's `initial_index` was
    // chosen for, so a cached snapshot is only trusted for that direction.
    function refreshSwitcher(reverse, cb) {
        request("ui_snapshot_switcher", { reverse: !!reverse }, (res, err) => { if (res) { res._reverse = !!reverse; switcher = res; switcherUpdated(); } if (cb) cb(res, err); });
    }
    // Set by the switcher: keep an MRU snapshot ready so Super+Tab can open
    // from it at once instead of waiting 50-120 ms for the daemon to build one.
    // It is re-read on the same compositor events as the grid, never on a timer.
    property bool keepSwitcherWarm: false
    onKeepSwitcherWarmChanged: if (keepSwitcherWarm && connected) refreshSwitcher(false)
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

    // Short name for each roll, for the bar: the initials of the first two
    // words of the title that are not "and", "of", "the" and the like
    // ("Design Hypernav Workspace UI" is "DH"), or the first two letters of
    // a one-word title ("Sh"). Rolls whose initials collide all get a digit,
    // numbered in environment id order ("DH1", "DH2"), so the same set of
    // rolls always gets the same names.
    readonly property var monograms: {
        const skip = ["a", "an", "and", "the", "of", "for", "to", "in", "on", "with", "at", "by", "or"];
        const codeOf = title => {
            const all = title.split(/[^A-Za-z0-9\u00C0-\uFFFF]+/).filter(w => w.length > 0);
            const words = all.filter(w => !skip.includes(w.toLowerCase()));
            const use = words.length > 0 ? words : all;
            if (use.length >= 2) return (use[0][0] + use[1][0]).toUpperCase();
            if (use.length === 1) return use[0][0].toUpperCase() + (use[0].length > 1 ? use[0][1].toLowerCase() : "");
            return "?";
        };
        const base = {};
        for (const r of rows) base[r.envId] = codeOf(r.title || r.displayId || r.envId || "");
        // Ancestors merged into their descendants' rows can still hold the
        // lock; name them by their own label.
        for (const r of rows) r.chainIds.forEach((id, i) => {
            if (!(id in base) && r.chainLabels[i]) base[id] = codeOf(r.chainLabels[i]);
        });
        const groups = {};
        for (const id in base) (groups[base[id]] = groups[base[id]] || []).push(id);
        const out = {};
        for (const code in groups) {
            const ids = groups[code].sort();
            ids.forEach((id, i) => out[id] = ids.length > 1 ? code + (i + 1) : code);
        }
        return out;
    }
    function monogramFor(envId) { return monograms[envId] ?? ""; }

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

    // The labels of the levels above the one that names the row, root first.
    // When no level names it (the title is the leaf's id), every labelled
    // level above the leaf.
    function _breadcrumb(chain, title) {
        let at = -1;
        for (let i = chain.length - 1; i >= 0; i--) if (chain[i].label && chain[i].label === title) { at = i; break; }
        const upTo = at >= 0 ? at : chain.length - 1;
        return chain.slice(0, upTo).map(l => l.label).filter(l => !!l);
    }

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
            row.lockedEnvId = head.locked_environment_id || "";
            const chain = head.environment_chain || [];
            const ids = chain.map(l => l.id);
            if (JSON.stringify(ids) !== JSON.stringify(row.chainIds)) row.chainIds = ids;
            const labels = chain.map(l => l.label || "");
            if (JSON.stringify(labels) !== JSON.stringify(row.chainLabels)) row.chainLabels = labels;
            const crumbs = _breadcrumb(chain, head.environment_title);
            if (JSON.stringify(crumbs) !== JSON.stringify(row.breadcrumb)) row.breadcrumb = crumbs;

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

    // The cell showing a given physical workspace, for a bar on a screen that
    // is not focused: the focused one when that workspace is focused, else
    // its own (not inherited) frame, else any frame that shows it.
    function cellForWorkspace(ws) {
        if (!grid || ws === null || ws === undefined) return null;
        let own = null, any = null;
        for (const c of grid.items) {
            if (c.physical_workspace_id !== ws) continue;
            if (c.active) return c;
            if (!(c.shared ?? c.inherited) && !own) own = c;
            if (!any) any = c;
        }
        return own ?? any;
    }

    // Refresh after compositor changes, debounced.
    Timer { id: refreshDebounce; interval: 80; onTriggered: { root.refreshAll(); if (root.keepSwitcherWarm) root.refreshSwitcher(false); } }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            const n = ev.name;
            if (n === "workspace" || n === "workspacev2" || n === "openwindow" || n === "closewindow" || n === "activewindow" || n === "movewindow" || n === "movewindowv2" || n === "focusedmon" || n === "createworkspace" || n === "destroyworkspace")
                refreshDebounce.restart();
        }
    }
}
