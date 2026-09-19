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
    property bool connected: false
    property var grid: null          // GridSnapshot
    property var switcher: null      // SwitcherSnapshot
    property var status: null        // StatusSnapshot
    property string lastError: ""

    signal gridUpdated()
    signal switcherUpdated()

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
        _pump();
    }

    Timer {
        id: timeout
        interval: 3000
        onTriggered: {
            lastError = "request timed out";
            const req = root._inflight; root._inflight = null;
            sock.connected = false;
            if (req && req.cb) req.cb(null, { code: "timeout", message: "hyprnav daemon did not answer" });
            root._pump();
        }
    }

    Socket {
        id: sock
        path: root.socketPath
        parser: SplitParser { splitMarker: "\n"; onRead: data => root._handleLine(data) }
        onConnectionStateChanged: {
            if (connected && root._inflight) { sock.write(root._inflight.line); sock.flush(); }
            else if (!connected && root._inflight) {
                // Closed before answering: fail this request, move on.
                timeout.stop();
                const req = root._inflight; root._inflight = null;
                root.lastError = "daemon closed the connection";
                if (req && req.cb) req.cb(null, { code: "closed", message: root.lastError });
                root._pump();
            }
        }
        onError: err => { root.lastError = "socket: " + err; }
    }
    onSocketPathChanged: if (socketPath !== "") { connected = true; refreshAll(); }

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

    readonly property string lockedEnv: status && status.locked_environment_id ? status.locked_environment_id : ""

    // Rows derived from the grid snapshot, for the grid overlay and the bar.
    readonly property var rows: {
        if (!grid) return [];
        const byRow = {};
        const order = [];
        for (const c of grid.items) {
            if (!(c.row_index in byRow)) { byRow[c.row_index] = { rowIndex: c.row_index, envId: c.environment_id, title: c.environment_title, displayId: c.environment_display_id, locked: c.environment_locked, cells: [] }; order.push(c.row_index); }
            byRow[c.row_index].cells.push(c);
        }
        order.sort((a, b) => a - b);
        return order.map(r => { byRow[r].cells.sort((a, b) => a.column_index - b.column_index); return byRow[r]; });
    }

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
            if (n === "workspace" || n === "workspacev2" || n === "openwindow" || n === "closewindow" || n === "activewindow" || n === "movewindow" || n === "focusedmon" || n === "createworkspace" || n === "destroyworkspace")
                refreshDebounce.restart();
        }
    }
}
