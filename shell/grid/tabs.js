.pragma library

// The grid's browser-tab column: jump hints and the sections it shows,
// computed from a BrowserTabs snapshot (see tabs/model.js merge()). Tab ids
// are "<source>/<id>" strings. Plain functions so node can test them.

// Dvorak home row: the keys under the fingers.
var ALPHABET = "aoeuidhtns";

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

// Essentials first (as icons), then "New tab", then each group's open tabs
// and every other tab, each most recently used first. A string `query`, even
// an empty one, means a search: it keeps only what matches and lists "New
// tab" last, where the search draws it, turning it into opening the query
// once there is one. A null or missing `query` is the plain column.
// `frozen` maps tab ids to the last-used times to sort by instead of the live
// ones: previews switch tabs while the grid is open, and the list must not
// reshuffle under the pointer. `selectables` is that same
// order flattened; each item carries its `index` there and its `hint`.
function build(snapshot, query, frozen) {
    var essentials = [], sections = [], selectables = [];
    if (!snapshot) return { essentials: essentials, sections: sections, selectables: selectables };
    var tabs = (snapshot.tabs || []).map(function (t) {
        if (!frozen || frozen[t.id] === undefined) return t;
        var copy = {};
        for (var k in t) copy[k] = t[k];
        copy.lastAccessed = frozen[t.id];
        return copy;
    });
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
    function tabItem(tab, groupId) {
        return {
            kind: "tab", key: "t:" + tab.id, tabId: tab.id, windowId: tab.windowId,
            title: tab.title || hostOf(tab.url) || tab.url, url: tab.url, host: hostOf(tab.url),
            icon: icon(tab.icon), active: tab.active, here: tab.id === hereTab,
            audible: tab.audible, groupId: groupId, lastAccessed: tab.lastAccessed || 0,
            browser: tab.browser || "", badge: badge(tab.browser)
        };
    }

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

    var groups = snapshot.groups || [];
    for (var g = 0; g < groups.length; g++) {
        var items = [];
        var ids = groups[g].tabIds || [];
        for (var i = 0; i < ids.length; i++) {
            var gt = byId[ids[i]];
            if (gt && matches(query, gt.title, gt.url)) items.push(tabItem(gt, groups[g].id));
        }
        // Most recently used first, like the rest.
        items.sort(function (a, b) { return b.lastAccessed - a.lastAccessed; });
        if (items.length > 0) sections.push({ key: "g:" + groups[g].id, title: groups[g].name, groupId: groups[g].id, items: items });
    }
    var loose = tabs.filter(function (x) { return !x.essential && !x.group && matches(query, x.title, x.url); })
        .sort(function (a, b) { return (b.lastAccessed || 0) - (a.lastAccessed || 0) || (a.windowId < b.windowId ? -1 : a.windowId > b.windowId ? 1 : 0) || a.index - b.index; });
    if (loose.length > 0) {
        sections.push({ key: "loose", title: "Tabs", groupId: null, items: loose.map(function (x) { return tabItem(x, null); }) });
    }

    selectables = searching ? essentials.slice() : essentials.concat([newTab]);
    for (var s = 0; s < sections.length; s++) selectables = selectables.concat(sections[s].items);
    if (searching) selectables.push(newTab);
    var labels = hintLabels(selectables.length);
    for (var n = 0; n < selectables.length; n++) {
        selectables[n].index = n;
        selectables[n].hint = labels[n] || "";
    }
    return { essentials: essentials, newTab: newTab, sections: sections, selectables: selectables };
}

// Where a search puts the selection: the first match once something is
// typed; before that the tab showing ("here"), else the first tab.
function searchStart(selectables, query) {
    if ((query || "").trim() !== "") return 0;
    var first = -1;
    for (var i = 0; i < selectables.length; i++) {
        if (selectables[i].here) return i;
        if (first < 0 && selectables[i].kind === "tab") first = i;
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
