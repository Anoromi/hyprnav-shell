pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../tabs/model.js" as Model
import "../tabs/mru.js" as Mru

// Tabs of every running browser, for the grid's tab column and the Ctrl+Tab
// switcher. Each browser's extension starts a native-messaging host (in
// mynix: browser-tabs-host.py) that serves the browser's tabs on a Unix
// socket and announces itself with a descriptor next to it:
//
//   $HNS_TABS_DIR/<id>.json   { id, browser, browserPid, hostPid, socket }
//
// Each line from a socket is a full JSON snapshot, each line to it a command.
// Snapshot: { windows: [{ id, focused, activeTitle }],
//             tabs: [{ id, windowId, index, title, url, icon, active, audible,
//                      pinned, hidden, lastAccessed }],
//             icons: { <tab.icon>: <image URL> }, caps?: ["navigate"], legacy? }
// Commands: activate {tabId}, create {url} | {search}, close {tabId}, refresh,
//           legacy-ack, and with "navigate" in caps navigate {tabId, url}
//
// Essentials, pinned tabs and groups belong to the shell, not to a browser
// (see tabs/model.js), and live in $HNS_TABS_STATE.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HNS_TABS_DIR")
        || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/browser-tabs")
    readonly property string statePath: Quickshell.env("HNS_TABS_STATE")
        || ((Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/hyprnav-shell/tabs.json")

    // Merged snapshot (see Model.merge); null while no browser is connected.
    property var snapshot: null
    readonly property bool available: snapshot !== null
    property var model: Model.emptyModel()
    property bool modelLoaded: false

    // Source id -> { id, browser, browserPid, snapshot } for connected ones.
    property var _raw: ({})
    property var _links: ({})          // source id -> its Source object

    readonly property bool perf: Quickshell.env("HNS_PERF") === "1"
    function _rebuild() {
        const t0 = perf ? Date.now() : 0;
        const sources = Object.values(_raw).filter(s => s.snapshot);
        if (sources.length === 0) { snapshot = null; _stampFront(); return; }
        let merged = Model.merge(model, sources);
        // Relinking needs the model loaded, or it would claim tabs for an
        // empty model and save that over the real one.
        let changed = false;
        if (modelLoaded && _opening && Model.claimOpened(model, _opening, merged.tabs)) { _opening = null; changed = true; }
        if (modelLoaded && Model.relink(model, merged.tabs, merged.icons)) changed = true;
        if (changed) { merged = Model.merge(model, sources); _save(); }
        const t1 = perf ? Date.now() : 0;
        snapshot = merged;
        if (perf) console.info("[perf] tabs snapshot applied: " + (Date.now() - t1) + " ms (merge " + (t1 - t0) + " ms)");
        _stampFront();
    }
    function _update(info, msg) {
        const prev = _raw[info.id]?.snapshot ?? null;
        if (modelLoaded && Model.dropClosed(model, info.id, prev, msg)) _save();
        if (msg.legacy && !info.legacyAcked && modelLoaded) {
            if (!model.legacyImported) { Model.importLegacy(model, msg.legacy, info.browser); _save(); }
            info.legacyAcked = true;
            sendTo(info.id, { type: "legacy-ack" });
        }
        const next = Object.assign({}, _raw);
        next[info.id] = { id: info.id, browser: info.browser, browserPid: info.browserPid, snapshot: msg };
        _raw = next;
        _rebuild();
    }
    function _drop(id) {
        if (!_raw[id]) return;
        const next = Object.assign({}, _raw);
        delete next[id];
        _raw = next;
        _rebuild();
    }

    function sendTo(sourceId, command) { _links[sourceId]?.send(command); }

    // Try now rather than at the next backoff step: the grid calls this when
    // it opens, so a browser started meanwhile shows up at once.
    function poke() { for (const id in _links) _links[id].poke(); }

    function tab(key) { return (snapshot?.tabs ?? []).find(t => t.id === key) ?? null; }
    function windowOf(key) { return (snapshot?.windows ?? []).find(w => w.id === key) ?? null; }
    function sourceOf(browser) {
        // The browser's source with the window focused last, else any.
        const ids = Object.keys(_raw).filter(id => _raw[id].browser === browser && _raw[id].snapshot);
        const front = frontTab();
        if (front && ids.includes(front.source)) return front.source;
        return ids[0] ?? null;
    }

    // Hyprland's windows, from Quickshell's toplevel cache: the title is
    // live, pid and class come from the last refresh, which a new window
    // triggers.
    function clients() {
        const out = [];
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject;
            if (!o || !o.address) continue;
            out.push({ address: o.address, pid: o.pid, class: o.class, title: t.title ?? o.title ?? "", focusHistoryID: o.focusHistoryID });
        }
        return out;
    }
    function activeClient() {
        const top = Hyprland.activeToplevel;
        if (!top) return null;
        const a = String(top.address);
        const address = a.startsWith("0x") ? a : "0x" + a;
        const c = clients().find(x => x.address === address);
        return c ? Object.assign({}, c, { title: top.title ?? c.title }) : null;
    }
    function isBrowserClass(cls) {
        for (const b in Model.CLASSES) if (Model.CLASSES[b].includes(cls)) return true;
        return false;
    }
    // The browser window Hyprland has in front, as a merged window, or null.
    function frontWindow() {
        if (!snapshot) return null;
        const sources = Object.values(_raw).filter(s => s.snapshot);
        return Model.windowForClient(activeClient(), sources, snapshot.windows);
    }
    function activeTabOf(windowKey) { return (snapshot?.tabs ?? []).find(t => t.windowId === windowKey && t.active) ?? null; }
    // The tab in front: the front browser window's active tab, else the one
    // looked at last.
    function frontTab() {
        const w = frontWindow();
        if (w) return activeTabOf(w.id);
        return mruTabs()[0] ?? null;
    }

    // MRU stamps (see tabs/mru.js): the tab in front of a focused browser
    // window, each time that changes.
    property var stamps: ({})
    property string _stamped: ""
    function _stampFront() {
        const w = snapshot ? frontWindow() : null;
        const t = w ? activeTabOf(w.id) : null;
        const key = t ? t.id : "";
        if (key === _stamped) return;
        _stamped = key;
        if (key) stamps = Mru.stamp(stamps, key, Date.now(), snapshot.tabs);
    }
    function recency(t) { return Mru.recency(t, stamps); }
    function stamp(key) { if (snapshot) { stamps = Mru.stamp(stamps, key, Date.now(), snapshot.tabs); _stamped = key; } }
    function mruTabs() {
        if (!snapshot) return [];
        const w = frontWindow();
        const current = w ? activeTabOf(w.id) : null;
        return Mru.order(snapshot.tabs, stamps, current ? current.id : null);
    }
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { root._previewFocus = null; root._stampFront(); }
        function onRawEvent(ev) {
            if (ev.name === "openwindow") Hyprland.refreshToplevels();
            else if (ev.name === "windowtitlev2") root._stampFront();
        }
    }

    // Open what a grid item stands for. The browser cannot raise its own
    // window on Wayland, so the window comes forward through Hyprland first,
    // then the extension switches the tab.
    function open(item) {
        if (!item) return;
        if (item.kind === "tab") activate(item.tabId);
        else if (item.kind === "essential" || item.kind === "entry") openEntry(item.id);
        else if (item.kind === "new") create(item.text || "", null);
    }
    function activate(key) {
        const t = tab(key);
        if (!t) return;
        stamp(t.id);
        withWindow(t.windowId, () => sendTo(t.source, { type: "activate", tabId: t.rawId }));
    }
    // An essential, pinned tab or group member shows its own tab when it
    // has one, else opens its home page in the browser it was saved from (or
    // the one in front) and takes the new tab: the first one that source
    // shows next (see claimOpened).
    property var _opening: null        // { entry, source, known }
    Timer { id: openingTimer; interval: 10000; onTriggered: root._opening = null }
    function openEntry(id) {
        const e = Model.findEntry(model, id);
        if (!e) return;
        const live = e.tabKey ? tab(e.tabKey) : null;
        if (live && live.entry === id) { activate(live.id); return; }
        if (_opening && _opening.entry === id) return;
        const source = create(e.url, e.browser);
        if (!source) return;
        const known = {};
        for (const t of snapshot.tabs) if (t.source === source) known[t.id] = true;
        _opening = { entry: id, source: source, known: known };
        openingTimer.restart();
    }
    // A new tab in `browser` (or the one in front) for typed text. Returns
    // the source asked, or null with no browser to ask.
    function create(text, browser) {
        const front = frontTab();
        const source = (browser ? sourceOf(browser) : null) ?? front?.source ?? Object.keys(_raw).find(id => _raw[id].snapshot) ?? null;
        if (!source) return null;
        const target = Model.interpretInput(text);
        const command = target.kind === "search" ? { type: "create", search: target.text }
            : { type: "create", url: target.kind === "url" ? target.url : "" };
        const w = (snapshot?.windows ?? []).filter(x => x.source === source);
        const win = (front && front.source === source ? windowOf(front.windowId) : null) ?? w.find(x => x.focused) ?? w[0] ?? null;
        withWindow(win ? win.id : null, () => sendTo(source, command));
        return source;
    }
    function close(key) { const t = tab(key); if (t) sendTo(t.source, { type: "close", tabId: t.rawId }); }
    function can(sourceId, cap) { return (_raw[sourceId]?.snapshot?.caps ?? []).includes(cap); }

    // An entry's own tab, while it has one.
    function entryTab(e) {
        const live = e && e.tabKey ? tab(e.tabKey) : null;
        return live && live.entry === e.id ? live : null;
    }
    // Where its tab is now becomes the entry's home.
    function replaceUrl(id) {
        const e = Model.findEntry(model, id);
        if (e && Model.replaceUrl(model, id, entryTab(e), snapshot?.icons)) _changed();
    }
    // Its tab back to the home page: in place where the extension can
    // navigate, else (an older one, loaded before the browser restarted) a
    // fresh tab on the home page takes the old one's place.
    function reset(id) {
        const e = Model.findEntry(model, id);
        const live = entryTab(e);
        const how = Model.resetAction(e, live, live ? can(live.source, "navigate") : false);
        if (how === "navigate") sendTo(live.source, { type: "navigate", tabId: live.rawId, url: e.url });
        else if (how === "reopen") {
            e.tabKey = null; e.tabUrl = e.url;
            openEntry(id);
            close(live.id);
            _changed();
        }
    }

    // Show a tab behind the open grid: its window comes forward and switches
    // to it. Only entries that already have a tab preview.
    function preview(item) {
        if (!item) return;
        const t = item.tabId ? tab(item.tabId) : null;
        if (!t) return;
        withWindow(t.windowId, () => sendTo(t.source, { type: "activate", tabId: t.rawId }), true);
    }
    // Undo previews: the tab that was showing, then the window that had the
    // focus before the grid opened.
    function restore(key, address) {
        const t = key ? tab(key) : null;
        _previewFocus = null;
        if (t) sendTo(t.source, { type: "activate", tabId: t.rawId });
        if (address) dispatch("hl.dsp.focus({ window = \"" + address + "\" })");
    }

    // Focus the Hyprland window showing a merged browser window, unless it
    // is already in front, then run `then`.
    //
    // While the grid holds the keyboard, Hyprland keeps reporting the window
    // from before as active, so previews remember the window they brought
    // forward and do not focus it again for every tab: `_previewFocus` is
    // { address, from } until the active window changes or previews end.
    property var _previewFocus: null
    function forgetPreviewFocus() { _previewFocus = null; }
    function withWindow(windowKey, then, previewing) {
        const w = windowKey ? windowOf(windowKey) : null;
        const src = w ? _raw[w.source] : null;
        const target = src ? Model.resolveWindow(clients(), src, w) : null;
        const active = activeClient();
        const from = active ? active.address : "";
        const shown = previewing && _previewFocus && target
            && _previewFocus.address === target.address && _previewFocus.from === from;
        if (!previewing) _previewFocus = null;
        if (target && from !== target.address && !shown) {
            dispatch("hl.dsp.focus({ window = \"address:" + target.address + "\" })");
            if (previewing) _previewFocus = { address: target.address, from: from };
        }
        if (then) then();
    }
    // Over Quickshell's own Hyprland socket: a hyprctl process costs 20-60 ms
    // before the window comes forward.
    function dispatch(lua) { Hyprland.dispatch(lua); }

    // The browser in front has no host to talk to: hand it its own Ctrl+Tab.
    // Returns whether that was the case.
    function passNativeTab(reverse) {
        const c = activeClient();
        if (!c || !isBrowserClass(c.class) || frontWindow()) return false;
        dispatch("hl.dsp.send_shortcut({ mods = \"" + (reverse ? "CTRL SHIFT" : "CTRL") + "\", key = \"Tab\", window = \"address:" + c.address + "\" })");
        return true;
    }

    // Copy the front browser tab's web address (Ctrl+Shift+C).
    function copyUrl() {
        const w = frontWindow();
        const t = w ? activeTabOf(w.id) : null;
        if (t && /^https?:\/\//i.test(t.url)) Quickshell.execDetached(["wl-copy", "--", t.url]);
    }

    // Essentials, pinned tabs and groups (see tabs/model.js), changed here
    // and saved.
    // Pinning returns the new entry's id, for the selection to follow it.
    function pin(key) {
        const t = tab(key);
        if (!t) return "";
        Model.pin(model, t); _changed();
        return model.essentials.find(e => e.tabKey === key)?.id ?? "";
    }
    function pinFront() { const t = frontTab(); if (t) { Model.pin(model, t); _changed(); } }
    function pinTab(key) {
        const t = tab(key);
        if (!t) return "";
        Model.pinTab(model, t); _changed();
        return model.pinned.find(e => e.tabKey === key)?.id ?? "";
    }
    // Unpin, or take out of its group: the only way an entry goes.
    function removeEntry(id) { if (Model.removeEntry(model, id)) _changed(); }
    // To a group by name, or to the Pinned rows with a null name.
    function moveEntry(id, name) { if (Model.moveEntry(model, id, name)) _changed(); }
    function renameEssential(id, title) {
        const e = model.essentials.find(x => x.id === id);
        if (e && title.trim()) { e.title = title.trim(); _changed(); }
    }
    function assign(key, name) { const t = tab(key); if (t) { Model.assign(model, t, name); _changed(); } }
    function renameGroup(id, name) {
        const g = model.groups.find(x => x.id === id);
        if (g && name.trim()) { g.name = name.trim(); _changed(); }
    }
    function deleteGroup(id) { model.groups = model.groups.filter(g => g.id !== id); _changed(); }
    function _changed() { _save(); _rebuild(); }

    function _save() { if (modelLoaded) saveTimer.restart(); }
    Timer { id: saveTimer; interval: 300; onTriggered: stateFile.setText(JSON.stringify(root.model, null, 1) + "\n") }
    FileView {
        id: stateFile
        path: root.statePath
        printErrors: false
        onLoaded: { root.model = Model.normalize(root._parse(text())); root.modelLoaded = true; root._rebuild(); }
        // No file yet: start empty; the first change writes it.
        onLoadFailed: { root.model = Model.emptyModel(); root.modelLoaded = true; root._rebuild(); }
    }
    function _parse(text) { try { return JSON.parse(text); } catch (e) { console.warn("browser tabs: bad state file", e); return null; } }

    // One Source per descriptor in the directory; it goes when its file does.
    FolderListModel {
        id: folder
        nameFilters: ["*.json"]
        showDirs: false
        showHidden: false
    }
    Instantiator {
        model: folder
        delegate: Source {}
    }
    Process {
        id: mkdirs
        running: true
        command: ["mkdir", "-p", "-m", "0700", root.dir, root.statePath.replace(/\/[^/]*$/, "")]
        onExited: folder.folder = "file://" + root.dir
    }

    component Source: Item {
        id: src
        required property string filePath
        property var info: null        // { id, browser, browserPid, socket, legacyAcked }
        property var sock: null
        property int delay: 1000

        function send(command) {
            if (!sock || !sock.connected) return;
            sock.write(JSON.stringify(command) + "\n");
            sock.flush();
        }
        function poke() { if (info && !(sock && sock.connected)) connect(); }

        // A Socket that failed to connect never tries again, however
        // `connected` is set afterwards, and its error never reaches QML.
        // Every attempt therefore gets a fresh one. A descriptor whose host
        // died uncleanly backs off to every 30 s until the host's next run
        // sweeps it.
        function connect() {
            if (sock) sock.destroy();
            // A new host run may still hold the legacy model: ack it again.
            info.legacyAcked = false;
            sock = socketComponent.createObject(src, { path: info.socket });
            sock.connected = true;
            retry.interval = delay;
            retry.restart();
            delay = Math.min(delay * 2, 30000);
        }
        FileView {
            path: src.filePath
            printErrors: false
            onLoaded: {
                // A descriptor never changes; a second load must not reconnect.
                if (src.info) return;
                const d = root._parse(text());
                if (!d || !d.id || !d.socket) return;
                src.info = { id: String(d.id), browser: String(d.browser || ""), browserPid: Number(d.browserPid) || 0, socket: String(d.socket), legacyAcked: false };
                const links = Object.assign({}, root._links);
                links[src.info.id] = src;
                root._links = links;
                src.connect();
            }
        }
        Component.onDestruction: {
            if (!info) return;
            const links = Object.assign({}, root._links);
            delete links[info.id];
            root._links = links;
            root._drop(info.id);
        }
        Component {
            id: socketComponent
            Socket {
                id: transport
                property string last: ""
                parser: SplitParser {
                    splitMarker: "\n"
                    onRead: data => {
                        // A page loading sends snapshots that often repeat
                        // the last one word for word: nothing to redo.
                        if (data === transport.last) return;
                        transport.last = data;
                        let msg = null;
                        try { msg = JSON.parse(data); } catch (e) { return; }
                        if (msg && msg.type === "snapshot" && src.sock === transport) root._update(src.info, msg);
                    }
                }
                onConnectionStateChanged: {
                    if (src.sock !== transport) return;
                    if (connected) { src.delay = 1000; retry.stop(); }
                    else { root._drop(src.info.id); retry.interval = 1000; retry.restart(); }
                }
            }
        }
        Timer {
            id: retry
            onTriggered: if (!(src.sock && src.sock.connected)) src.connect()
        }
    }
}
