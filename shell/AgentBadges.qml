pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "services" as Services

// Marks windows an agent is currently driving: a small pencil tag at the
// window's top-right corner on the visible workspace, with the agent's label
// and state. Click-through; the mask is empty so input passes to the window.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprnav-shell-agent-badges"
    visible: badges.count > 0

    // The daemon pushes the whole registry on every change; no polling.
    readonly property var agents: Services.Hyprnav.agents

    // Quickshell's toplevel cache gives us the first frame without a process.
    // Hyprland does not emit a raw event for every pixel move, so query current
    // geometry while a driven window is visible.
    readonly property var clients: {
        const out = [];
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject;
            if (o && o.address) out.push(o);
        }
        return out;
    }

    // Only the set of driven windows matters here, not the beat itself: a
    // refresh is a `hyprctl clients` round trip that replaces every toplevel's
    // cached IPC object, so doing it once a second would churn the window
    // geometry every other view reads.
    property string drivenAddresses: ""
    Connections {
        target: Services.Hyprnav
        function onAgentsEvent(agents) {
            const next = agents.map(a => a.current_target ?? "").sort().join(",");
            if (next === win.drivenAddresses) return;
            win.drivenAddresses = next;
            Hyprland.refreshToplevels();
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            switch (ev.name) {
            case "openwindow": case "closewindow": case "movewindow": case "movewindowv2":
            case "changefloatingmode": case "fullscreen": case "workspace": case "workspacev2":
            case "focusedmon": case "monitoradded":
                Hyprland.refreshToplevels();
                break;
            }
        }
    }

    property var polledClients: []
    Timer {
        interval: 150
        repeat: true
        running: win.visibleTargets.length > 0
        onTriggered: if (!geometryProbe.running) geometryProbe.running = true
    }
    Process {
        id: geometryProbe
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.polledClients = JSON.parse(text); }
                catch (e) { console.log("badge geometry query failed", e); }
            }
        }
    }

    readonly property var monitor: Hyprland.monitors.values.find(m => m.name === win.screen.name) ?? null
    readonly property int activeWs: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1

    // One badge per driven window on the active workspace of this screen.
    readonly property var visibleTargets: {
        const out = [];
        const recent = Date.now() - 20000;
        for (const a of agents) {
            if (a.state === "finished") continue;
            const addr = a.current_target; if (!addr) continue;
            if (a.last_beat_ms < recent && a.state !== "waiting_for_user") continue;
            const matches = c => "0x" + c.address.replace(/^0x/, "") === addr && c.mapped && c.workspace && c.workspace.id === activeWs;
            const c = polledClients.find(matches) ?? clients.find(matches);
            if (!c) continue;
            out.push({ agent: a, client: c });
        }
        return out;
    }

    Repeater {
        id: badges
        model: win.visibleTargets
        delegate: Item {
            required property var modelData
            readonly property var c: modelData.client
            readonly property var a: modelData.agent
            // Hyprland reports client and monitor positions in the global
            // layout space, already scaled; only the monitor origin differs.
            x: c.at[0] - (win.monitor ? win.monitor.x : 0) + c.size[0] - width - 10
            y: c.at[1] - (win.monitor ? win.monitor.y : 0) + 10
            width: tag.implicitWidth + 24
            height: 30
            Rectangle {
                anchors.fill: parent
                radius: 6
                color: Theme.pencil
                border.color: Theme.darkroom
                border.width: 1
                Row {
                    id: tag
                    anchors.centerIn: parent
                    spacing: 8
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10; height: 10; radius: 5
                        color: a.state === "waiting_for_user" ? Theme.warn : Theme.darkroom
                        SequentialAnimation on opacity {
                            running: a.state === "working"; loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 500 } NumberAnimation { to: 1; duration: 500 }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: a.label + (a.state === "waiting_for_user" ? "  needs you" : a.state === "idle" ? "  idle" : a.last_action ? "  " + a.last_action : "")
                        color: Theme.darkroom
                        font.family: Theme.sans; font.pixelSize: Theme.fs13; font.weight: Font.Medium
                    }
                }
            }
        }
    }
    // Window outline for every driven window
    Repeater {
        model: win.visibleTargets
        delegate: Rectangle {
            required property var modelData
            readonly property var c: modelData.client
            x: c.at[0] - (win.monitor ? win.monitor.x : 0) - 2
            y: c.at[1] - (win.monitor ? win.monitor.y : 0) - 2
            width: c.size[0] + 4
            height: c.size[1] + 4
            color: "transparent"
            radius: 6
            border.color: Theme.pencil
            border.width: 2
            opacity: 0.9
        }
    }
}
