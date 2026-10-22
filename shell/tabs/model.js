.pragma library

// Browser tabs from every connected browser, merged, plus the shell's own
// Essentials and groups over them. Plain functions so node can test them.
//
// A source is one running browser's host (see services/BrowserTabs.qml):
// { id: "zen-4242", browser: "zen", browserPid, snapshot }. Its tab and
// window ids are only unique inside it, so merged ones are "<source>/<id>"
// strings and keep the browser's own as `rawId`.
//
// The model: { essentials: [{ id, title, url, icon, browser, tabKey }],
//              groups: [{ id, name, members: [{ browser, url, tabKey }] }],
//              nextId, legacyImported }
// Tab keys die with the browser; URLs survive, so members and essentials
// find their tab again by browser and URL after a restart.

// Hyprland classes per browser, for when its window's pid is not the one
// that started the host.
var CLASSES = {
    island: ["island-browser"],
    chromium: ["chromium", "chromium-browser"],
    zen: ["zen-beta", "zen"]
};

function emptyModel() {
    return { essentials: [], groups: [], nextId: 1, legacyImported: false };
}

function str(value) { return typeof value === "string" ? value : ""; }

function normalize(stored) {
    var model = emptyModel();
    if (!stored || typeof stored !== "object") return model;
    model.nextId = typeof stored.nextId === "number" && stored.nextId > 0 ? stored.nextId : 1;
    model.legacyImported = stored.legacyImported === true;
    model.essentials = (Array.isArray(stored.essentials) ? stored.essentials : [])
        .filter(function (e) { return e && typeof e.url === "string"; })
        .map(function (e) {
            return { id: String(e.id), title: String(e.title || e.url), url: e.url, icon: str(e.icon),
                     browser: str(e.browser), tabKey: typeof e.tabKey === "string" ? e.tabKey : null };
        });
    model.groups = (Array.isArray(stored.groups) ? stored.groups : [])
        .filter(function (g) { return g && typeof g.name === "string"; })
        .map(function (g) {
            return { id: String(g.id), name: g.name,
                     members: (Array.isArray(g.members) ? g.members : [])
                         .filter(function (m) { return m && typeof m.url === "string"; })
                         .map(function (m) { return { browser: str(m.browser), url: m.url, tabKey: typeof m.tabKey === "string" ? m.tabKey : null }; }) };
        });
    return model;
}

function newId(model, prefix) {
    var id = prefix + model.nextId;
    model.nextId += 1;
    return id;
}

// The Island Productivity extension kept Essentials and groups itself; its
// successor hands them over once. Their tab ids are the old browser's, so
// everything relinks by URL.
function importLegacy(model, legacy, browser) {
    var old = legacy && typeof legacy === "object" ? legacy : {};
    (Array.isArray(old.essentials) ? old.essentials : []).forEach(function (e) {
        if (!e || typeof e.url !== "string") return;
        model.essentials.push({ id: newId(model, "e"), title: String(e.title || e.url), url: e.url,
                                icon: str(e.icon), browser: browser, tabKey: null });
    });
    (Array.isArray(old.groups) ? old.groups : []).forEach(function (g) {
        if (!g || typeof g.name !== "string") return;
        var members = (Array.isArray(g.members) ? g.members : [])
            .filter(function (m) { return m && typeof m.url === "string" && m.url !== ""; })
            .map(function (m) { return { browser: browser, url: m.url, tabKey: null }; });
        model.groups.push({ id: newId(model, "g"), name: g.name, members: members });
    });
    model.legacyImported = true;
}

function hostOf(url) {
    var m = /^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i.exec(url || "");
    return m ? m[1] : "";
}

// An essential owns at most one tab, in the browser it was pinned from: the
// one it opened while that tab is still on the essential's site, otherwise
// an unclaimed tab on that site.
function essentialTab(essential, tabs, claimed) {
    var host = hostOf(essential.url);
    if (!host) return null;
    for (var i = 0; i < tabs.length; i++) {
        if (tabs[i].id === essential.tabKey && hostOf(tabs[i].url) === host) return tabs[i];
    }
    for (var j = 0; j < tabs.length; j++) {
        var t = tabs[j];
        if (!claimed[t.id] && t.browser === essential.browser && hostOf(t.url) === host) return t;
    }
    return null;
}

// Re-attach members whose tab is gone to an unclaimed tab with the same
// browser and URL, and follow essentials to their adopted tab. Returns
// whether anything changed.
function relink(model, tabs) {
    var changed = false;
    var live = {}, claimed = {};
    for (var i = 0; i < tabs.length; i++) live[tabs[i].id] = true;
    model.groups.forEach(function (g) {
        g.members.forEach(function (m) { if (m.tabKey !== null && live[m.tabKey]) claimed[m.tabKey] = true; });
    });
    model.groups.forEach(function (g) {
        g.members.forEach(function (m) {
            if (m.tabKey !== null && live[m.tabKey]) return;
            for (var k = 0; k < tabs.length; k++) {
                var t = tabs[k];
                if (!claimed[t.id] && t.browser === m.browser && t.url === m.url) {
                    m.tabKey = t.id; claimed[t.id] = true; changed = true;
                    return;
                }
            }
        });
    });
    model.essentials.forEach(function (e) {
        var tab = essentialTab(e, tabs, claimed);
        if (tab) {
            claimed[tab.id] = true;
            if (e.tabKey !== tab.id) { e.tabKey = tab.id; changed = true; }
        }
        // A missing tab keeps its key: the next one on the site is adopted
        // above, and nothing else can take a dead key.
    });
    return changed;
}

function removeMember(model, tabKey) {
    var changed = false;
    model.groups.forEach(function (g) {
        var kept = g.members.filter(function (m) { return m.tabKey !== tabKey; });
        if (kept.length !== g.members.length) { g.members = kept; changed = true; }
    });
    return changed;
}

// Tabs closed one by one leave their group; tabs that went with their
// window, or with the whole browser, stay and relink when they come back.
// `before` and `after` are one source's own snapshots.
function dropClosed(model, sourceId, before, after) {
    if (!before) return false;
    var live = {}, windows = {};
    (after.tabs || []).forEach(function (t) { live[t.id] = true; });
    (after.windows || []).forEach(function (w) { windows[w.id] = true; });
    var changed = false;
    (before.tabs || []).forEach(function (t) {
        if (!live[t.id] && windows[t.windowId] && removeMember(model, sourceId + "/" + t.id)) changed = true;
    });
    return changed;
}

function pin(model, tab) {
    if (model.essentials.some(function (e) { return e.tabKey === tab.id; })) return;
    removeMember(model, tab.id);
    model.essentials.push({ id: newId(model, "e"), title: tab.title || tab.url, url: tab.url,
                            icon: tab.icon || "", browser: tab.browser, tabKey: tab.id });
}

function assign(model, tab, name) {
    var wanted = (name || "").trim();
    if (!wanted) return;
    model.essentials.forEach(function (e) { if (e.tabKey === tab.id) e.tabKey = null; });
    removeMember(model, tab.id);
    var group = null;
    for (var i = 0; i < model.groups.length; i++) {
        if (model.groups[i].name.toLowerCase() === wanted.toLowerCase()) group = model.groups[i];
    }
    if (!group) {
        group = { id: newId(model, "g"), name: wanted, members: [] };
        model.groups.push(group);
    }
    group.members.push({ browser: tab.browser, url: tab.url || "", tabKey: tab.id });
}

// Every source's tabs and windows under merged keys, with the model laid
// over them in the shape grid/tabs.js builds the column from.
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
                        essential: null, group: null });
        });
    });
    var byId = {};
    tabs.forEach(function (t) { byId[t.id] = t; });
    var essentials = model.essentials.map(function (e) {
        var live = e.tabKey !== null && byId[e.tabKey] ? e.tabKey : null;
        if (live) byId[live].essential = e.id;
        // The live tab's own icon beats the one saved at pin time.
        return { id: e.id, title: e.title, url: e.url, browser: e.browser, tabId: live,
                 icon: live && byId[live].icon && icons[byId[live].icon] ? byId[live].icon : e.icon };
    });
    var groups = model.groups.map(function (g) {
        var ids = [];
        g.members.forEach(function (m) {
            var t = m.tabKey !== null ? byId[m.tabKey] : null;
            if (t && !t.essential && !t.group) { t.group = g.id; ids.push(t.id); }
        });
        return { id: g.id, name: g.name, tabIds: ids };
    });
    // A saved icon is a data or web URL itself; make it resolvable like the rest.
    essentials.forEach(function (e) { if (e.icon && !icons[e.icon] && /^(data:|https?:)/.test(e.icon)) icons[e.icon] = e.icon; });
    return { windows: windows, tabs: tabs, essentials: essentials, groups: groups, icons: icons, browsers: browsers };
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
