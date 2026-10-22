.pragma library

// The grid's browser-tab column: jump hints and the sections it shows,
// computed from a BrowserTabs snapshot (see tabs/model.js merge()). Tab ids
// are "<source>/<id>" strings. Plain functions so node can test them.

// Dvorak home row, right hand first, index fingers leading: the first
// rows get the comfortable keys.
var ALPHABET = "htnsdueoai";

// Prefix-free labels, Vimium style: as many one-letter labels as fit, and the
// remaining letters lead two-letter ones. With k letters, p prefixes give
// (k - p) + p * k labels. The first items keep the short labels, so
// Essentials, which come first, keep theirs as the tab list grows.
function hintLabels(count, alphabet) {
    var letters = alphabet || ALPHABET;
    var k = letters.length;
    var out = [];
    if (count <= 0 || k === 0) return out;
    if (count <= k) {
        for (var i = 0; i < count; i++) out.push(letters[i]);
        return out;
    }
    var prefixes = Math.min(k, Math.ceil((count - k) / (k - 1)));
    var singles = k - prefixes;
    for (var s = 0; s < singles; s++) out.push(letters[s]);
    for (var p = 0; p < prefixes; p++) {
        for (var c = 0; c < k && out.length < count; c++) out.push(letters[singles + p] + letters[c]);
    }
    return out;
}

function hostOf(url) {
    var m = /^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i.exec(url || "");
    return m ? m[1].replace(/^www\./, "") : "";
}

// Every word of the query, anywhere in the title or the URL.
function matches(query, title, url) {
    var words = (query || "").toLowerCase().split(/\s+/).filter(function (w) { return w !== ""; });
    var hay = ((title || "") + " " + (url || "")).toLowerCase();
    for (var i = 0; i < words.length; i++) if (hay.indexOf(words[i]) < 0) return false;
    return true;
}

// Essentials first (as icons, with the "New tab" tile after them), then the
// Pinned rows, the groups, most recently used first, and every other tab,
// most recently used first. A group is one header row until it is
// expanded: `expanded` maps group ids to true. A string `query`, even an
// empty one, means a search: it keeps only what matches, expands the groups
// with matches once something is typed, and lists "New tab" last, turning
// it into opening the query. A null or missing `query` is the plain column.
// `frozen` maps tab ids to the last-used times to sort by instead of the live
// ones: previews switch tabs while the grid is open, and the list must not
// reshuffle under the pointer. `selectables` is that same
// order flattened; each item carries its `index` there and its `hint`.
//
// Hints: everything outside the groups, and each group's header, share one
// prefix-free set. An expanded group's members continue its header's label
// L: L plus a label over the alphabet without L's first letter. The header
// itself then answers to L typed twice, which collapses it again.
function build(snapshot, query, frozen, expanded) {
    var essentials = [], sections = [], selectables = [];
    if (!snapshot) return { essentials: essentials, sections: sections, selectables: selectables, hereTab: null };
    var tabs = (snapshot.tabs || []).map(function (t) {
        if (!frozen || frozen[t.id] === undefined) return t;
        var copy = {};
        for (var k in t) copy[k] = t[k];
        copy.lastAccessed = frozen[t.id];
        return copy;
    });
    var open = expanded || {};
    // Icons arrive once per site in `icons`, keyed by what each entry names.
    var icons = snapshot.icons || {};
    function icon(key) { return icons[key] || ""; }
    // With more than one browser running, each entry names its own.
    var many = (snapshot.browsers || []).length > 1;
    function badge(browser) { return many ? browser || "" : ""; }
    var byId = {};
    for (var t = 0; t < tabs.length; t++) byId[tabs[t].id] = tabs[t];
    // "here": the tab last looked at, like the grid's "here" frame. Not the
    // focused window's: opening the grid takes the browser's focus away.
    var hereTab = null, hereAt = -1;
    for (var h = 0; h < tabs.length; h++) {
        if (tabs[h].active && (tabs[h].lastAccessed || 0) > hereAt) { hereTab = tabs[h].id; hereAt = tabs[h].lastAccessed || 0; }
    }
    function tabItem(tab) {
        return {
            kind: "tab", key: "t:" + tab.id, tabId: tab.id, windowId: tab.windowId,
            title: tab.title || hostOf(tab.url) || tab.url, url: tab.url, host: hostOf(tab.url),
            icon: icon(tab.icon), active: tab.active, here: tab.id === hereTab, open: true,
            audible: tab.audible, groupId: null, lastAccessed: tab.lastAccessed || 0,
            browser: tab.browser || "", badge: badge(tab.browser)
        };
    }
    // A pinned tab or group member: its live tab's title and place while it
    // has one, its own when closed.
    function entryItem(x, place, groupId) {
        var live = x.tabId !== null && x.tabId !== undefined ? byId[x.tabId] || null : null;
        var url = live ? live.url : x.url;
        return {
            kind: "entry", key: (place === "pinned" ? "p:" : "m:") + x.id, id: x.id, place: place,
            tabId: live ? live.id : null, windowId: live ? live.windowId : null, open: live !== null,
            title: (live && live.title) || x.title || hostOf(x.url) || x.url, url: url, host: hostOf(url),
            icon: icon(x.icon), active: live ? live.active : false, here: live !== null && live.id === hereTab,
            audible: live ? !!live.audible : false, groupId: groupId, lastAccessed: live ? live.lastAccessed || 0 : 0,
            browser: x.browser || "", badge: badge(x.browser)
        };
    }
    function recent(a, b) { return b.lastAccessed - a.lastAccessed || a.order - b.order; }

    var es = (snapshot.essentials || []).filter(function (x) { return matches(query, x.title, x.url); });
    for (var e = 0; e < es.length; e++) {
        essentials.push({
            kind: "essential", key: "e:" + es[e].id, id: es[e].id, title: es[e].title,
            url: es[e].url, icon: icon(es[e].icon), tabId: es[e].tabId,
            open: es[e].tabId !== null && es[e].tabId !== undefined,
            here: hereTab !== null && es[e].tabId === hereTab,
            browser: es[e].browser || "", badge: badge(es[e].browser)
        });
    }
    var searching = query !== null && query !== undefined;
    var q = (query || "").trim();
    var newTab = q === "" ? { kind: "new", key: "new", title: "New tab", text: "" }
        : { kind: "new", key: "new", title: "Open “" + q + "” in a new tab", text: q };

    var pinned = (snapshot.pinned || []).map(function (x) { return entryItem(x, "pinned", null); })
        .filter(function (x) { return matches(query, x.title, x.url); });
    if (pinned.length > 0) sections.push({ key: "pinned", title: "Pinned", items: pinned, groups: [] });

    var groups = [];
    (snapshot.groups || []).forEach(function (g, order) {
        var all = (g.members || []).map(function (m, i) { var it = entryItem(m, "group", g.id); it.order = i; return it; });
        if (all.length === 0) return;
        all.sort(recent);
        // A word of the group's name counts for every member.
        var hits = all.filter(function (x) { return matches(query, x.title + " " + g.name, x.url); });
        if (hits.length === 0) return;
        var shown = (searching && q !== "") || open[g.id] === true;
        var header = {
            kind: "group", key: "g:" + g.id, groupId: g.id, title: g.name, expanded: shown,
            count: all.length, openCount: all.filter(function (x) { return x.open; }).length,
            icons: all.slice(0, 3).map(function (x) { return { icon: x.icon, fallback: x.host || x.title }; }),
            here: !shown && all.some(function (x) { return x.here; }), base: ""
        };
        groups.push({ key: header.key, header: header, expanded: shown, items: shown ? hits : [],
                      lastAccessed: all[0].lastAccessed, order: order });
    });
    groups.sort(recent);
    if (groups.length > 0) sections.push({ key: "groups", title: "", items: [], groups: groups });

    var loose = tabs.filter(function (x) { return !x.entry && !x.essential && !x.group && matches(query, x.title, x.url); })
        .sort(function (a, b) { return (b.lastAccessed || 0) - (a.lastAccessed || 0) || (a.windowId < b.windowId ? -1 : a.windowId > b.windowId ? 1 : 0) || a.index - b.index; })
        .map(tabItem);
    if (loose.length > 0) sections.push({ key: "loose", title: "Tabs", items: loose, groups: [] });

    selectables = searching ? essentials.slice() : essentials.concat([newTab]);
    selectables = selectables.concat(pinned);
    var top = selectables.slice();
    groups.forEach(function (gr) { selectables.push(gr.header); top.push(gr.header); selectables = selectables.concat(gr.items); });
    selectables = selectables.concat(loose);
    top = top.concat(loose);
    if (searching) { selectables.push(newTab); top.push(newTab); }
    var labels = hintLabels(top.length);
    for (var n = 0; n < top.length; n++) top[n].hint = labels[n] || "";
    groups.forEach(function (gr) {
        var base = gr.header.hint;
        gr.header.base = base;
        if (!gr.expanded) return;
        var sub = base ? hintLabels(gr.items.length, ALPHABET.replace(base[0], "")) : [];
        gr.header.hint = base ? base + base : "";
        gr.items.forEach(function (x, i) { x.hint = sub[i] ? base + sub[i] : ""; });
    });
    for (var m = 0; m < selectables.length; m++) selectables[m].index = m;
    return { essentials: essentials, newTab: newTab, sections: sections, selectables: selectables, hereTab: hereTab };
}

// Where a search puts the selection: the first match once something is
// typed (not a group's header: Enter there would only fold it); before that
// the tab showing ("here"), else the first tab.
function searchStart(selectables, query) {
    if ((query || "").trim() !== "") {
        for (var j = 0; j < selectables.length; j++) if (selectables[j].kind !== "group") return j;
        return 0;
    }
    var first = -1;
    for (var i = 0; i < selectables.length; i++) {
        if (selectables[i].here) return i;
        if (first < 0 && (selectables[i].kind === "tab" || selectables[i].kind === "entry")) first = i;
    }
    return Math.max(0, first);
}

// Ctrl+Backspace / Ctrl+W in the query: drop trailing spaces and the word
// before them, as a shell or browser field does.
function deleteWord(query) {
    return (query || "").replace(/\S*\s*$/, "");
}

// What typing `prefix` means: the item whose hint it completes, or whether it
// still starts some hint.
function resolve(selectables, prefix) {
    var partial = false;
    for (var i = 0; i < selectables.length; i++) {
        var h = selectables[i].hint;
        if (!h) continue;
        if (h === prefix) return { exact: selectables[i], partial: false };
        if (h.indexOf(prefix) === 0) partial = true;
    }
    return { exact: null, partial: partial };
}
