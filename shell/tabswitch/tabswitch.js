.pragma library

// Selection rules of the Ctrl+Tab switcher. Index 0 is the tab in front.

// Where a cycle starts: forwards on the tab before the current one,
// backwards on the oldest.
function start(count, reverse) {
    if (count <= 1) return 0;
    return reverse ? count - 1 : 1;
}

function step(selected, dir, count) {
    if (count <= 0) return 0;
    return ((selected + dir) % count + count) % count;
}
