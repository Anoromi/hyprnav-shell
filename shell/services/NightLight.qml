pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Night light through hyprsunset, or wlsunset where hyprsunset is missing.
// The tool is looked up once at start and again whenever quick settings
// open (`probe()`); nothing is polled. A filter the shell started runs as a
// child Process; one found running already is stopped by exact process name.
Singleton {
    id: root
    property string tool: ""                // "hyprsunset" | "wlsunset" | ""
    readonly property bool available: tool !== ""
    property bool external: false           // running, but not started by us
    readonly property bool active: runner.running || external
    property int temperature: 4000

    function probe() { if (!detector.running) detector.running = true; }
    function toggle() {
        if (!available) return;
        if (runner.running) { runner.running = false; return; }
        if (external) { Quickshell.execDetached(["pkill", "-x", tool]); external = false; return; }
        runner.command = tool === "hyprsunset"
            ? ["hyprsunset", "-t", String(temperature)]
            // Manual times: sunset at 00:00, sunrise at 23:59, so it stays warm.
            : ["wlsunset", "-t", String(temperature), "-T", "6500", "-s", "00:00", "-S", "23:59", "-d", "1"];
        runner.running = true;
    }

    Process {
        id: detector
        running: true
        command: ["sh", "-c", "t=; for c in hyprsunset wlsunset; do command -v $c >/dev/null && { t=$c; break; }; done; echo \"$t\"; [ -n \"$t\" ] && pgrep -x \"$t\" >/dev/null && echo running; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.tool = lines[0] || "";
                root.external = !runner.running && lines[1] === "running";
            }
        }
    }
    Process { id: runner }
}
