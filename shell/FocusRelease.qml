import QtQuick

// Runs a callback once the window has handed its keyboard focus back to the
// compositor. A layer surface's keyboard interactivity changes on its next
// commit, which Qt makes with the next frame; `run()` waits for that frame
// (or 50 ms, if nothing draws) before calling back.
//
// Why: the switcher and grid release their Exclusive keyboard focus when they
// activate a workspace. If Hyprland processes that release after the
// workspace switch, it gives the focus back to the window that had it before
// the overlay opened, on the old workspace, and the switch is undone.
Item {
    id: gate
    property var pending: null
    function run(cb) { pending = cb; fallback.restart(); }
    function fire() {
        const cb = pending; pending = null; fallback.stop();
        if (cb) cb();
    }
    Timer { id: fallback; interval: 50; onTriggered: gate.fire() }
    Connections {
        target: gate.pending ? gate.Window.window : null
        function onFrameSwapped() { gate.fire(); }
    }
}
