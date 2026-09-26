pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Internal panel backlight through sysfs. The level follows an inotify watch
// on the brightness file, so a change from brightnessctl, logind or the
// shell's own slider shows up (and drives the OSD) without polling. Writing
// goes through brightnessctl if installed, otherwise logind's SetBrightness
// (no udev rule needed for the active session), otherwise a plain sysfs write.
// HNS_BACKLIGHT points at a directory with `brightness` and `max_brightness`
// to fake a panel in the lab.
Singleton {
    id: root
    readonly property string override: Quickshell.env("HNS_BACKLIGHT") || ""
    property string device: override
    property bool hasBrightnessctl: false
    // Bumps on every change of `current` after the first read; the OSD listens.
    property int changes: 0
    property int max: 1
    property int current: 0
    readonly property real level: max > 0 ? current / max : 0
    readonly property bool available: device !== ""
    property string error: ""

    // One-shot at start: find the panel and whether brightnessctl exists.
    Process {
        id: find
        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -e \"$d/brightness\" ] && echo \"$d\" && break; done; echo; command -v brightnessctl >/dev/null && echo brightnessctl; true"]
        running: true
        stdout: StdioCollector { onStreamFinished: {
            const lines = text.split("\n");
            if (!root.override) root.device = lines[0].trim();
            root.hasBrightnessctl = lines.includes("brightnessctl");
            if (root.device) { maxFile.reload(); curFile.reload(); }
        } }
    }
    property bool _loaded: false
    FileView { id: maxFile; path: root.device ? root.device + "/max_brightness" : ""; onLoaded: root.max = parseInt(text()) || 1 }
    FileView {
        id: curFile
        path: root.device ? root.device + "/brightness" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const v = parseInt(text()) || 0;
            if (root._loaded && v !== root.current) { root.current = v; root.changes++; }
            else root.current = v;
            root._loaded = true;
        }
    }

    Process {
        id: writer
        stderr: StdioCollector { onStreamFinished: root.error = text.trim() !== "" ? "Cannot change brightness: " + text.trim().split("\n")[0] : "" }
        onExited: code => { if (code === 0) root.error = ""; curFile.reload(); }
    }
    function setLevel(v) {
        if (!available) return;
        const n = Math.round(Math.max(0.02, Math.min(1, v)) * max);
        const name = device.split("/").pop();
        if (device.startsWith("/sys/class/backlight/") && hasBrightnessctl)
            writer.command = ["brightnessctl", "-q", "-d", name, "set", String(n)];
        else if (device.startsWith("/sys/class/backlight/"))
            writer.command = ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
                              "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", name, String(n)];
        else
            writer.command = ["sh", "-c", "printf %s " + n + " > " + device + "/brightness"];
        writer.running = true;
    }
}
