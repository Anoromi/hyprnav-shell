.pragma library

// Browser tabs from every connected browser, merged, plus the shell's own
// Essentials, pinned tabs and groups over them. Plain functions so node can
// test them.
//
// A source is one running browser's host (see services/BrowserTabs.qml):
// { id: "zen-4242", browser: "zen", browserPid, snapshot }. Its tab and
// window ids are only unique inside it, so merged ones are "<source>/<id>"
// strings and keep the browser's own as `rawId`.
//
// The model: { essentials: [entry], pinned: [entry],
//              groups: [{ id, name, members: [entry] }],
//              nextId, legacyImported }
// entry:     { id, title, url, icon, browser, tabKey, tabUrl }
//
// Every entry is the shell's, Arc style: its home `url`, title and icon stay
// until it is removed (unpinned, or taken out of its group), whether or not
// a tab shows it. `tabKey` is the tab it opened (null: none open), `tabUrl`
// where that tab was last, for finding it again after a restart: tab keys
// die with the browser, URLs survive. An entry only takes a tab it opened
// itself or had before the restart; other tabs on its site stay loose tabs.
// Essentials show as icons, pinned tabs and group members as rows.

// Hyprland classes per browser, for when its window's pid is not the one
// that started the host.
var CLASSES = {
    island: ["island-browser"],
    chromium: ["chromium", "chromium-browser"],
    zen: ["zen-beta", "zen"]
};

function emptyModel() {
    return { essentials: [], pinned: [], groups: [], nextId: 1, legacyImported: false };
}

function str(value) { return typeof value === "string" ? value : ""; }

function newId(model, prefix) {
    var id = prefix + model.nextId;
    model.nextId += 1;
    return id;
}

function entryOf(model, e, prefix) {
    return { id: e.id !== undefined && e.id !== null ? String(e.id) : newId(model, prefix),
             title: String(e.title || e.url), url: e.url, icon: str(e.icon), browser: str(e.browser),
             tabKey: typeof e.tabKey === "string" ? e.tabKey : null, tabUrl: str(e.tabUrl) };
}

function hasUrl(e) { return e && typeof e.url === "string"; }

function normalize(stored) {
    var model = emptyModel();
    if (!stored || typeof stored !== "object") return model;
    model.nextId = typeof stored.nextId === "number" && stored.nextId > 0 ? stored.nextId : 1;
    model.legacyImported = stored.legacyImported === true;
    function list(x) { return (Array.isArray(x) ? x : []).filter(hasUrl); }
    model.essentials = list(stored.essentials).map(function (e) { return entryOf(model, e, "e"); });
    model.pinned = list(stored.pinned).map(function (e) { return entryOf(model, e, "p"); });
    model.groups = (Array.isArray(stored.groups) ? stored.groups : [])
        .filter(function (g) { return g && typeof g.name === "string"; })
        .map(function (g) {
            return { id: String(g.id), name: g.name,
                     members: list(g.members).map(function (m) {
                         if (m.id !== undefined) return entryOf(model, m, "m");
                         // A member from before groups kept their tabs: just
                         // { browser, url, tabKey }. One with no tab waited
                         // for a tab on its URL; it still finds one.
                         return entryOf(model, { title: m.url, url: m.url, browser: m.browser,
                                                 tabKey: typeof m.tabKey === "string" ? m.tabKey : "legacy",
                                                 tabUrl: m.url }, "m");
                     }) };
        })
        .filter(function (g) { return g.members.length > 0; });
    return model;
}

// Every entry, in the order they claim tabs.
function entries(model) {
    var all = model.essentials.concat(model.pinned);
    model.groups.forEach(function (g) { all = all.concat(g.members); });
    return all;
}

function findEntry(model, id) {
    var all = entries(model);
    for (var i = 0; i < all.length; i++) if (all[i].id === id) return all[i];
    return null;
}

// The Island Productivity extension kept Essentials and groups itself; its
// successor hands them over once. Their tab ids are the old browser's, so
// everything relinks by URL: a key no tab has stands for a lost tab.
function importLegacy(model, legacy, browser) {
    var old = legacy && typeof legacy === "object" ? legacy : {};
    (Array.isArray(old.essentials) ? old.essentials : []).forEach(function (e) {
        if (!hasUrl(e)) return;
        model.essentials.push({ id: newId(model, "e"), title: String(e.title || e.url), url: e.url,
                                icon: str(e.icon), browser: browser, tabKey: "legacy", tabUrl: "" });
    });
    (Array.isArray(old.groups) ? old.groups : []).forEach(function (g) {
        if (!g || typeof g.name !== "string") return;
        var members = (Array.isArray(g.members) ? g.members : [])
            .filter(function (m) { return hasUrl(m) && m.url !== ""; })
            .map(function (m) {
                return { id: newId(model, "m"), title: m.url, url: m.url, icon: "", browser: browser,
                         tabKey: "legacy", tabUrl: m.url };
            });
        if (members.length > 0) model.groups.push({ id: newId(model, "g"), name: g.name, members: members });
    });
    model.legacyImported = true;
}

// A page without its query and fragment, for matching a tab to a URL.
function pageOf(url) {
    return (url || "").replace(/[?#].*$/, "").replace(/\/+$/, "");
}

// Re-attach entries whose tab went with its window or browser to one on the
// page their tab was on, or on their home page. Live tabs keep their entry
// however far they navigate; the entry notes where the tab is and the
// site's icon, so it still shows with no tab, and a title it lacks. Returns
// whether anything changed.
function relink(model, tabs, icons) {
    var changed = false;
    var live = {}, claimed = {};
    var known = icons || {};
    for (var i = 0; i < tabs.length; i++) live[tabs[i].id] = tabs[i];
    var all = entries(model);
    all.forEach(function (e) { if (e.tabKey !== null && live[e.tabKey]) claimed[e.tabKey] = true; });
    all.forEach(function (e) {
        if (e.tabKey === null) return;
        var tab = live[e.tabKey] || null;
        for (var k = 0; !tab && k < tabs.length; k++) {
            var t = tabs[k];
            if (!claimed[t.id] && t.browser === e.browser && t.url !== ""
                && (pageOf(t.url) === pageOf(e.tabUrl) || pageOf(t.url) === pageOf(e.url))) tab = t;
        }
        if (!tab) return;
        claimed[tab.id] = true;
        if (e.tabKey !== tab.id) { e.tabKey = tab.id; changed = true; }
        if (tab.url && e.tabUrl !== tab.url) { e.tabUrl = tab.url; changed = true; }
        if ((!e.title || e.title === e.url) && tab.title && e.title !== tab.title) { e.title = tab.title; changed = true; }
        var icon = known[tab.icon];
        if (icon && /^(data:|https?:)/.test(icon) && e.icon !== icon) { e.icon = icon; changed = true; }
    });
    return changed;
}

// The tab an entry asked its browser for: the first new one in that
// source. `opening`: { entry, source, known: { <tab key>: true } }, the
// tabs the source had when asked. Returns whether it was found.
function claimOpened(model, opening, tabs) {
    var e = findEntry(model, opening.entry);
    if (!e) return false;
    for (var i = 0; i < tabs.length; i++) {
        var t = tabs[i];
        if (t.source === opening.source && !opening.known[t.id]) {
            entries(model).forEach(function (x) { if (x.tabKey === t.id) x.tabKey = null; });
            e.tabKey = t.id;
            e.tabUrl = t.url;
            return true;
        }
    }
    return false;
}

// Tabs closed one by one leave their entry with no tab; tabs that went with
// their window, or with the whole browser, stay and relink when they come
// back. `before` and `after` are one source's own snapshots.
function dropClosed(model, sourceId, before, after) {
    if (!before) return false;
    var live = {}, windows = {};
    (after.tabs || []).forEach(function (t) { live[t.id] = true; });
    (after.windows || []).forEach(function (w) { windows[w.id] = true; });
    var changed = false;
    var all = entries(model);
    (before.tabs || []).forEach(function (t) {
        if (live[t.id] || !windows[t.windowId]) return;
        var key = sourceId + "/" + t.id;
        all.forEach(function (e) { if (e.tabKey === key) { e.tabKey = null; changed = true; } });
    });
    return changed;
}

// Groups go with their last member.
function prune(model) {
    model.groups = model.groups.filter(function (g) { return g.members.length > 0; });
}

// Take an entry out of wherever it is. Returns it, or null.
function removeEntry(model, id) {
    var found = null;
    function keep(e) { if (e.id === id) { found = e; return false; } return true; }
    model.essentials = model.essentials.filter(keep);
    model.pinned = model.pinned.filter(keep);
    model.groups.forEach(function (g) { g.members = g.members.filter(keep); });
    prune(model);
    return found;
}

// A tab moving somewhere new leaves the pinned tab or group member it was,
// and its essential, which stays with no tab.
function take(model, tabKey) {
    model.essentials.forEach(function (e) { if (e.tabKey === tabKey) e.tabKey = null; });
    model.pinned = model.pinned.filter(function (e) { return e.tabKey !== tabKey; });
    model.groups.forEach(function (g) { g.members = g.members.filter(function (e) { return e.tabKey !== tabKey; }); });
    prune(model);
}

function entryFor(model, tab, prefix) {
    return { id: newId(model, prefix), title: tab.title || tab.url || "", url: tab.url || "", icon: tab.icon || "",
             browser: tab.browser, tabKey: tab.id, tabUrl: tab.url || "" };
}

// To Essentials.
function pin(model, tab) {
    if (model.essentials.some(function (e) { return e.tabKey === tab.id; })) return;
    take(model, tab.id);
    model.essentials.push(entryFor(model, tab, "e"));
}

// To the Pinned rows.
function pinTab(model, tab) {
    if (model.pinned.some(function (e) { return e.tabKey === tab.id; })) return;
    take(model, tab.id);
    model.pinned.push(entryFor(model, tab, "p"));
}

function groupNamed(model, name) {
    var wanted = (name || "").trim();
    if (!wanted) return null;
    for (var i = 0; i < model.groups.length; i++) {
        if (model.groups[i].name.toLowerCase() === wanted.toLowerCase()) return model.groups[i];
    }
    var group = { id: newId(model, "g"), name: wanted, members: [] };
    model.groups.push(group);
    return group;
}

function assign(model, tab, name) {
    if (!(name || "").trim()) return;
    take(model, tab.id);
    groupNamed(model, name).members.push(entryFor(model, tab, "m"));
}

// A pinned tab or group member to another group, or with no name to the
// Pinned rows, keeping what it is.
function moveEntry(model, id, name) {
    var e = findEntry(model, id);
    if (!e || model.essentials.indexOf(e) >= 0) return false;
    if (name !== null && !(name || "").trim()) return false;
    removeEntry(model, id);
    if (name === null) model.pinned.push(e);
    else groupNamed(model, name).members.push(e);
    return true;
}

// Every source's tabs and windows under merged keys, with the model laid
// over them in the shape grid/tabs.js builds the column from: each entry
// with `tabId`, its live tab or null, and each tab with the `entry` that
// shows it (and its `essential` or `group`), or null for a loose tab.
function merge(model, sources) {
    var tabs = [], windows = [], icons = {}, browsers = [];
    sources.forEach(function (s) {
        var snap = s.snapshot || {};
        if (browsers.indexOf(s.browser) < 0) browsers.push(s.browser);
        var ic = snap.icons || {};
        for (var k in ic) if (ic[k] && !icons[k]) icons[k] = ic[k];
        (snap.windows || []).forEach(function (w) {
            windows.push({ id: s.id + "/" + w.id, rawId: w.id, source: s.id, browser: s.browser,
                           focused: !!w.focused, activeTitle: w.activeTitle || "" });
        });
        (snap.tabs || []).forEach(function (t) {
            tabs.push({ id: s.id + "/" + t.id, rawId: t.id, source: s.id, browser: s.browser,
                        windowId: s.id + "/" + t.windowId, index: t.index || 0, title: t.title || "",
                        url: t.url || "", icon: t.icon || "", active: !!t.active, audible: !!t.audible,
                        pinned: !!t.pinned, hidden: !!t.hidden, lastAccessed: t.lastAccessed || 0,
                        essential: null, entry: null, group: null });
        });
    });
    var byId = {};
    tabs.forEach(function (t) { byId[t.id] = t; });
    // One tab, one entry: the first to claim it.
    function shown(e, mark) {
        var t = e.tabKey !== null ? byId[e.tabKey] || null : null;
        if (t && t.entry) t = null;
        if (t) { t.entry = e.id; mark(t); }
        // The live tab's own icon beats the one saved at pin time.
        var icon = t && t.icon && icons[t.icon] ? t.icon : e.icon;
        if (icon && !icons[icon] && /^(data:|https?:)/.test(icon)) icons[icon] = icon;
        return { id: e.id, title: e.title, url: e.url, browser: e.browser, tabId: t ? t.id : null, icon: icon };
    }
    var essentials = model.essentials.map(function (e) { return shown(e, function (t) { t.essential = e.id; }); });
    var pinned = model.pinned.map(function (e) { return shown(e, function () {}); });
    var groups = model.groups.map(function (g) {
        return { id: g.id, name: g.name,
                 members: g.members.map(function (m) { return shown(m, function (t) { t.group = g.id; }); }) };
    });
    return { windows: windows, tabs: tabs, essentials: essentials, pinned: pinned, groups: groups, icons: icons, browsers: browsers };
}

function titleMatches(windowTitle, activeTitle) {
    return activeTitle !== "" && (windowTitle === activeTitle || windowTitle.indexOf(activeTitle) === 0);
}

function byFocus(a, b) { return (a.focusHistoryID === undefined ? 1e9 : a.focusHistoryID) - (b.focusHistoryID === undefined ? 1e9 : b.focusHistoryID); }

// The browser's Hyprland windows: those of the process that started the
// host, else, for a launcher that forked, any of the browser's class.
function browserClients(clients, source) {
    var own = clients.filter(function (c) { return c.pid === source.browserPid; });
    if (own.length > 0) return own;
    var classes = CLASSES[source.browser] || [];
    return clients.filter(function (c) { return classes.indexOf(c.class) >= 0; });
}

// The Hyprland window showing a browser window. A browser window's title is
// its active tab's, plus the browser's name. `clients`: [{ address, pid,
// class, title, focusHistoryID }]. Ties go to the window focused last.
function resolveWindow(clients, source, win) {
    var own = browserClients(clients, source).slice().sort(byFocus);
    if (own.length === 0) return null;
    var title = win ? win.activeTitle || "" : "";
    var exact = own.filter(function (c) { return c.title === title; });
    if (exact.length > 0) return exact[0];
    var prefix = own.filter(function (c) { return titleMatches(c.title, title); });
    return prefix[0] || own[0];
}

// The other way: which source and browser window a Hyprland window is.
// The longest matching active title wins (one tab's title can start
// another's), then the browser's focused window.
function windowForClient(client, sources, windows) {
    if (!client) return null;
    var mine = sources.filter(function (s) { return browserClients([client], s).length > 0; });
    if (mine.length === 0) return null;
    // A pid match beats a class match when both browsers share a class.
    var exactPid = mine.filter(function (s) { return s.browserPid === client.pid; });
    if (exactPid.length > 0) mine = exactPid;
    var ids = {};
    mine.forEach(function (s) { ids[s.id] = true; });
    var candidates = windows.filter(function (w) { return ids[w.source]; });
    var best = null;
    candidates.forEach(function (w) {
        if (titleMatches(client.title || "", w.activeTitle) && (!best || w.activeTitle.length > best.activeTitle.length)) best = w;
    });
    if (best) return best;
    if (candidates.length === 1) return candidates[0];
    return candidates.filter(function (w) { return w.focused; })[0] || null;
}

// What to open for typed text: a URL as is, a bare domain over https, and
// anything else as a search.
function interpretInput(text) {
    var value = (text || "").trim();
    if (!value) return { kind: "blank" };
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(value)) return { kind: "url", url: value };
    if (!/\s/.test(value) && /^[^/]+\.[a-z]{2,}(:\d+)?(\/.*)?$/i.test(value)) return { kind: "url", url: "https://" + value };
    if (/^localhost(:\d+)?(\/.*)?$/i.test(value)) return { kind: "url", url: "http://" + value };
    return { kind: "search", text: value };
}
