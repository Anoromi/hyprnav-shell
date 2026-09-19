pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Internal panel backlight through sysfs. Reading always works; writing needs
// a udev rule or a helper, so failures are reported instead of hidden.
Singleton {
    id: root
    property string device: ""
    property int max: 1
    property int current: 0
    readonly property real level: max > 0 ? current / max : 0
    readonly property bool available: device !== ""
    property string error: ""

    Process {
        id: find
        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -e \"$d/brightness\" ] && echo \"$d\" && break; done"]
        running: true
        stdout: StdioCollector { onStreamFinished: { root.device = text.trim(); if (root.device) { maxFile.reload(); curFile.reload(); } } }
    }
    FileView { id: maxFile; path: root.device ? root.device + "/max_brightness" : ""; onLoaded: root.max = parseInt(text()) || 1 }
    FileView { id: curFile; path: root.device ? root.device + "/brightness" : ""; watchChanges: true; onLoaded: root.current = parseInt(text()) || 0; onFileChanged: reload() }

    Process {
        id: writer
        stderr: StdioCollector { onStreamFinished: root.error = text.trim() !== "" ? "Cannot change brightness: no write permission on sysfs" : "" }
        onExited: code => { if (code === 0) root.error = ""; curFile.reload(); }
    }
    function setLevel(v) {
        if (!available) return;
        const n = Math.round(Math.max(0.02, Math.min(1, v)) * max);
        writer.command = ["sh", "-c", "printf %s " + n + " > " + device + "/brightness"];
        writer.running = true;
    }
}
