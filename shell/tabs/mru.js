.pragma library

// Most-recently-used order over the merged tabs of every browser, for
// Ctrl+Tab. A tab counts as used only while it is in front: the shell stamps
// it when its window gains the Hyprland focus, when the focused window shows
// a new tab, or when the shell activates it. A browser's own lastAccessed
// moves for switches in a window nobody looks at, and Zen reports every
// window's selected tab as accessed right now, so it only orders the tabs
// the shell has not seen in front since `since` (its start), below all of
// those it has.

function recency(tab, stamps, since) {
    var stamped = stamps && stamps[tab.id];
    if (stamped) return stamped;
    return Math.min(tab.lastAccessed || 0, since || 0);
}

// Most recent first; the tab in front leads whatever the clocks say, so the
// first Ctrl+Tab always lands on the one before it.
function order(tabs, stamps, current, since) {
    var out = tabs.slice().sort(function (a, b) {
        return recency(b, stamps, since) - recency(a, stamps, since) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
    });
    for (var i = 0; i < out.length; i++) {
        if (out[i].id === current) {
            var front = out.splice(i, 1)[0];
            out.unshift(front);
            break;
        }
    }
    return out;
}

// Stamps for live tabs only, so closed ones do not pile up.
function stamp(stamps, key, now, tabs) {
    var out = {};
    var live = {};
    for (var i = 0; i < tabs.length; i++) live[tabs[i].id] = true;
    for (var k in stamps) if (live[k]) out[k] = stamps[k];
    if (key) out[key] = now;
    return out;
}
