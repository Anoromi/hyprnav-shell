import QtQuick
import Quickshell

// Timing probe for a shell window, active only with HNS_PERF=1. Put one inside
// the window's content. `arm(tag)` starts a measurement; the log line
// "[perf] <label> <tag>: first frame N ms" reports the time from arm() to the
// window's next swapped frame. `track(tag, on)` measures a stretch of
// interaction: frame count, mean and worst interval between swapped frames,
// frames later than 25 ms, and the longest stall of the GUI thread (a 4 ms
// timer that notices when it runs late).
Item {
    id: probe
    property string label: "window"
    readonly property bool enabled: Quickshell.env("HNS_PERF") === "1"
    property string tag: ""
    property real t0: 0
    property bool waiting: false
    property string trackTag: ""
    property real lastSwap: 0
    property var gaps: []
    property real lastTick: 0
    property real worstStall: 0

    function now() { return Date.now(); }
    function arm(t) {
        if (!enabled) return;
        track(t + " first 1.5 s", true);
        tag = t; t0 = now(); waiting = true; settle.restart(); anim.restart(); animGaps = [];
    }
    // Frames during the first 300 ms after open (the open animation): count
    // and worst interval. After that the window only draws on change, so
    // longer intervals are idle time, not dropped frames.
    property var animGaps: []
    Timer { id: anim; interval: 300; onTriggered: {
        const g = probe.animGaps;
        console.info("[perf] " + probe.label + " " + probe.tag + " open animation: frames " + (g.length + 1) + ", worst interval " + (g.length ? Math.max(...g) : 0) + " ms");
    } }
    Timer { id: settle; interval: 1500; onTriggered: probe.track("", false) }
    function track(t, on) {
        if (!enabled) return;
        if (on) { trackTag = t; gaps = []; lastSwap = 0; lastTick = now(); worstStall = 0; stall.restart(); return; }
        if (trackTag === "") return;
        const g = gaps.slice(1);        // the first gap includes idle time before the stretch
        const mean = g.length ? g.reduce((a, b) => a + b, 0) / g.length : 0;
        console.info("[perf] " + label + " " + trackTag + ": frames " + gaps.length
            + ", mean " + mean.toFixed(1) + " ms, worst " + (g.length ? Math.max(...g) : 0)
            + " ms, late(>25ms) " + g.filter(x => x > 25).length + ", gui stall " + worstStall + " ms");
        trackTag = ""; stall.stop();
    }
    Timer {
        id: stall
        interval: 4; repeat: true
        onTriggered: {
            const t = probe.now();
            probe.worstStall = Math.max(probe.worstStall, t - probe.lastTick - interval);
            probe.lastTick = t;
        }
    }
    Connections {
        target: probe.enabled ? probe.Window.window : null
        function onFrameSwapped() {
            const t = probe.now();
            if (probe.waiting) {
                probe.waiting = false;
                console.info("[perf] " + probe.label + " " + probe.tag + ": first frame " + (t - probe.t0) + " ms at " + t + ", gui stall " + probe.worstStall + " ms");
            }
            if (probe.trackTag !== "") {
                if (probe.lastSwap > 0) probe.gaps.push(t - probe.lastSwap);
                if (probe.lastSwap > 0 && anim.running) probe.animGaps.push(t - probe.lastSwap);
                probe.lastSwap = t;
            }
        }
    }
}
