.pragma library

// Most-recently-used order over the merged tabs of every browser, for
// Ctrl+Tab. Browsers only update a tab's lastAccessed for their own
// switches, so the shell stamps a tab when it becomes the one in front: its
// window gains the Hyprland focus, or the focused window shows a new tab.
// A tab's recency is the later of the two.

function recency(tab, stamps) {
    return Math.max(tab.lastAccessed || 0, (stamps && stamps[tab.id]) || 0);
}

// Most recent first; the tab in front leads whatever the clocks say, so the
// first Ctrl+Tab always lands on the one before it.
function order(tabs, stamps, current) {
    var out = tabs.slice().sort(function (a, b) {
        return recency(b, stamps) - recency(a, stamps) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
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
