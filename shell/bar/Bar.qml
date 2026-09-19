pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../services" as Services
import ".."

// Left edge column, like the edge of a film strip: the roll's frame numbers
// run down it, the environment title reads along it, the system cluster sits
// at the bottom above the clock.
PanelWindow {
    id: bar
    required property var modelData
    screen: modelData
    property var quickSettings: null

    anchors { top: true; left: true; bottom: true }
    implicitWidth: 44
    color: Theme.sheet
    WlrLayershell.namespace: "hyprnav-shell-bar"
    WlrLayershell.layer: WlrLayer.Top

    readonly property var cell: Services.Hyprnav.activeCell
    readonly property var focusedWs: Hyprland.focusedWorkspace
    readonly property var roll: cell ? (Services.Hyprnav.rows.find(r => r.envId === cell.environment_id)?.cells ?? []) : []

    readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wifiNet: wifiDev ? (wifiDev.networks.values.find(n => n.connected) ?? null) : null
    readonly property var battery: UPower.displayDevice
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property int btConnected: btAdapter ? btAdapter.devices.values.filter(d => d.connected).length : 0

    function wifiGlyph() {
        if (!Networking.wifiEnabled) return "󰖪";
        if (!wifiNet) return "󰤮";
        const s = wifiNet.signalStrength;
        if (s > 0.8) return "󰤨"; if (s > 0.55) return "󰤥"; if (s > 0.3) return "󰤢"; return "󰤟";
    }
    function batteryGlyph() {
        if (!battery || !battery.isPresent) return "󰁹";
        if (battery.state === UPowerDeviceState.Charging) return "󰂄";
        const p = battery.percentage;
        if (p > 0.95) return "󰁹";
        return String.fromCodePoint(0xF0079 + Math.max(1, Math.min(9, Math.round(p * 10))));
    }

    Rectangle { anchors.right: parent.right; height: parent.height; width: 1; color: Theme.emulsion }

    // Top: current frame, then the rest of the roll running down.
    Column {
        id: top
        anchors.top: parent.top; anchors.topMargin: Theme.s12
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.s4
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 28; height: 28; radius: 3
            color: Theme.pencil
            visible: bar.cell !== null
            Text {
                anchors.centerIn: parent
                text: bar.cell ? bar.cell.slot_index : ""
                color: Theme.darkroom
                font.family: Theme.mono; font.pixelSize: Theme.fs18; font.weight: Font.Bold
            }
            MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellDir, "ipc", "call", "grid", "toggle"]) }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 28; height: 28; radius: 3
            color: Theme.emulsion
            visible: bar.cell === null
            Text { anchors.centerIn: parent; text: bar.focusedWs ? bar.focusedWs.id : ""; color: Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs15 }
        }
        Item { width: 1; height: Theme.s4 }
        Repeater {
            model: bar.roll.filter(c => !c.active && !c.unnumbered)
            Rectangle {
                id: pip
                required property var modelData
                anchors.horizontalCenter: parent.horizontalCenter
                width: 28; height: 24; radius: 3
                color: pipMouse.containsMouse ? Theme.emulsion : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.tFast } }
                Text {
                    anchors.centerIn: parent
                    text: pip.modelData.slot_index
                    color: pip.modelData.window_count > 0 ? Theme.paper : Theme.fixer
                    font.family: Theme.mono; font.pixelSize: Theme.fs15
                }
                // Pin: a spawned process tree is stuck to this frame.
                Glyph { anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: -3; anchors.topMargin: -5; visible: pip.modelData.stuck === true; text: "󰐃"; size: 12; color: Theme.pencil }
                MouseArea { id: pipMouse; anchors.fill: parent; hoverEnabled: true; onClicked: Services.Hyprnav.gotoSlot(pip.modelData.environment_id, pip.modelData.slot_index) }
            }
        }
    }

    // Middle: environment title along the edge, reading bottom to top.
    Item {
        anchors.top: top.bottom; anchors.topMargin: Theme.s16
        anchors.bottom: cluster.top; anchors.bottomMargin: Theme.s16
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        clip: true
        Text {
            id: envTitle
            anchors.centerIn: parent
            rotation: -90
            width: parent.height
            text: (bar.cell ? bar.cell.environment_title : "No environment") + (bar.cell && bar.cell.environment_locked ? "   locked" : "")
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
            color: bar.cell ? Theme.paper : Theme.fixer
            font.family: Theme.casual; font.pixelSize: Theme.fs15; font.weight: Font.Medium
        }
    }

    // Bottom: system cluster, one click target, then the clock.
    Rectangle {
        id: cluster
        anchors.bottom: clock.top; anchors.bottomMargin: Theme.s12
        anchors.horizontalCenter: parent.horizontalCenter
        width: 32
        height: clusterCol.implicitHeight + Theme.s12
        radius: 4
        color: (bar.quickSettings && bar.quickSettings.shown) || clusterMouse.containsMouse ? Theme.emulsion : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.tFast } }
        Column {
            id: clusterCol
            anchors.centerIn: parent
            spacing: Theme.s8
            Repeater {
                model: SystemTray.items
                IconImage {
                    required property var modelData
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitSize: 16
                    source: modelData.icon
                    MouseArea { anchors.fill: parent; onClicked: modelData.display(bar, 0, 0) }
                }
            }
            Glyph { anchors.horizontalCenter: parent.horizontalCenter; visible: Services.Notifs.unread > 0; text: "󰂚"; size: 15; color: Theme.pencil }
            Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: bar.wifiGlyph(); size: 17; color: bar.wifiNet ? Theme.paper : Theme.fixer }
            Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: bar.btConnected > 0 ? "󰂱" : "󰂯"; size: 17; color: bar.btAdapter && bar.btAdapter.enabled ? Theme.paper : Theme.fixer }
            Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: Services.Audio.icon(); size: 17 }
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: bar.battery && bar.battery.isPresent
                spacing: 0
                Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: bar.batteryGlyph(); size: 17; rotation: 90; color: bar.battery && bar.battery.percentage < 0.15 && bar.battery.state !== UPowerDeviceState.Charging ? Theme.warn : Theme.paper }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: bar.battery ? Math.round(bar.battery.percentage * 100) : ""; color: Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs12 }
            }
        }
        MouseArea { id: clusterMouse; anchors.fill: parent; hoverEnabled: true; onClicked: if (bar.quickSettings) bar.quickSettings.toggle() }
    }

    SystemClock { id: clockSrc; precision: SystemClock.Minutes }
    Column {
        id: clock
        anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.s12
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 0
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDateTime(clockSrc.date, "HH"); color: Theme.paper; font.family: Theme.mono; font.pixelSize: Theme.fs15; font.weight: Font.Medium }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDateTime(clockSrc.date, "mm"); color: Theme.paper; font.family: Theme.mono; font.pixelSize: Theme.fs15; font.weight: Font.Medium }
        Item { width: 1; height: Theme.s4 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDateTime(clockSrc.date, "d"); color: Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs12 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDateTime(clockSrc.date, "MMM"); color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12 }
    }
}
