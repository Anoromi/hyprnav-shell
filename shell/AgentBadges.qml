pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
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

    property var agents: []        // from hyprnav agents_list
    property var clients: []       // from hyprctl -j clients, mapped on this screen's active workspace

    // Poll the registry while any agent exists; cheap when none do.
    Timer {
        interval: 1000; repeat: true; running: true
        onTriggered: Services.Hyprnav.request("agents_list", {}, res => { if (res) win.agents = res; })
    }
    // Window geometry from the compositor, refreshed with the agents.
    onAgentsChanged: if (agents.length > 0) clientsProc.running = true; else clients = []
    Process {
        id: clientsProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector { onStreamFinished: { try { win.clients = JSON.parse(text); } catch (e) {} } }
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
            const c = clients.find(c => "0x" + c.address.replace(/^0x/, "") === addr && c.mapped && c.workspace && c.workspace.id === activeWs);
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
            // Client coordinates are global; subtract this monitor's origin and scale.
            x: (c.at[0] - (win.monitor ? win.monitor.x : 0)) / (win.monitor ? win.monitor.scale : 1) + c.size[0] / (win.monitor ? win.monitor.scale : 1) - width - 10
            y: (c.at[1] - (win.monitor ? win.monitor.y : 0)) / (win.monitor ? win.monitor.scale : 1) + 10
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
            readonly property real sc: win.monitor ? win.monitor.scale : 1
            x: (c.at[0] - (win.monitor ? win.monitor.x : 0)) / sc - 2
            y: (c.at[1] - (win.monitor ? win.monitor.y : 0)) / sc - 2
            width: c.size[0] / sc + 4
            height: c.size[1] / sc + 4
            color: "transparent"
            radius: 6
            border.color: Theme.pencil
            border.width: 2
            opacity: 0.9
        }
    }
}
