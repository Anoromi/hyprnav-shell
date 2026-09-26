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
// run down it, the environment title reads along it. The bottom stacks, from
// the top: launcher and clipboard, tray, the notification bell, the system
// cluster (opens quick settings), the clock.
PanelWindow {
    id: bar
    required property var modelData
    screen: modelData
    property var quickSettings: null
    property var center: null               // this screen's notification centre, if enabled

    anchors { top: true; left: true; bottom: true }
    implicitWidth: 44
    color: Theme.sheet
    WlrLayershell.namespace: "hyprnav-shell-bar"
    WlrLayershell.layer: WlrLayer.Top

    // Each screen's bar follows the workspace shown on that screen.
    readonly property var monitor: Hyprland.monitors.values.find(m => m.name === screen.name) ?? null
    readonly property var focusedWs: monitor && monitor.activeWorkspace ? monitor.activeWorkspace : Hyprland.focusedWorkspace
    readonly property var cell: focusedWs ? Services.Hyprnav.cellForWorkspace(focusedWs.id) : Services.Hyprnav.activeCell
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
        if (battery.state === UPowerDeviceState.FullyCharged) return "󰂅";
        const p = battery.percentage;
        if (p > 0.95) return "󰁹";
        if (p < 0.05) return "󰂎";
        return String.fromCodePoint(0xF0079 + Math.max(1, Math.min(9, Math.round(p * 10))));
    }
    readonly property bool batteryLow: battery && battery.isPresent && battery.percentage < 0.15
        && battery.state !== UPowerDeviceState.Charging && battery.state !== UPowerDeviceState.FullyCharged

    // One hover label for every button in the column, beside the bar.
    property string tipText: ""
    property real tipY: 0
    function tip(item, text) { tipY = item.mapToItem(null, 0, item.height / 2).y; tipText = text; }
    function untip() { tipText = ""; }
    PopupWindow {
        anchor.window: bar
        anchor.rect.x: bar.width + 6
        anchor.rect.y: bar.tipY - height / 2
        implicitWidth: tipLabel.implicitWidth + 16
        implicitHeight: tipLabel.implicitHeight + 10
        visible: bar.tipText !== ""
        color: "transparent"
        Rectangle {
            anchors.fill: parent; radius: 4
            color: Theme.darkroom; border.color: Theme.emulsion
            Text { id: tipLabel; anchors.centerIn: parent; text: bar.tipText; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs12 }
        }
    }

    component BarButton: Rectangle {
        id: btn
        property string glyph: ""
        property string label: ""
        property bool active: false
        property color glyphColor: active ? Theme.pencil : Theme.paper
        signal clicked()
        anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
        width: 32; height: 28; radius: 4
        color: active || btnMouse.containsMouse ? Theme.emulsion : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.tFast } }
        Glyph { anchors.centerIn: parent; text: btn.glyph; size: 17; color: btn.glyphColor }
        MouseArea {
            id: btnMouse; anchors.fill: parent; hoverEnabled: true
            onClicked: btn.clicked()
            onContainsMouseChanged: containsMouse ? bar.tip(btn, btn.label) : bar.untip(btn.label)
        }
    }
    TrayMenu { id: trayMenu; bar: bar }

    component Hair: Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 16; height: 1; color: Theme.emulsion }

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
            model: bar.roll.map(c => c.snapshot).filter(c => c !== bar.cell && !c.unnumbered && !(bar.cell && c.slot_index === bar.cell.slot_index))
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
        anchors.bottom: bottomStack.top; anchors.bottomMargin: Theme.s16
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

    // Bottom stack, above the clock.
    Column {
        id: bottomStack
        anchors.bottom: clock.top; anchors.bottomMargin: Theme.s12
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.s8

        // Launcher and clipboard history, both vicinae views.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.s4
            BarButton { glyph: "󰀻"; label: "Launcher"; onClicked: Quickshell.execDetached(["vicinae", "toggle"]) }
            BarButton { glyph: "󰅌"; label: "Clipboard history"; onClicked: Quickshell.execDetached(["vicinae", "cmd", "launch", "clipboard:history"]) }
        }

        Hair { visible: SystemTray.items.values.length > 0 }

        // Tray: left click activates (or opens the menu for menu-only items),
        // right click opens the menu beside the bar, middle click is the
        // secondary action, the wheel scrolls the item.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            Repeater {
                model: SystemTray.items
                Rectangle {
                    id: trayItem
                    required property var modelData
                    readonly property string label: modelData.tooltipTitle || modelData.title || modelData.id
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 32; height: 26; radius: 4
                    color: trayMouse.containsMouse ? Theme.emulsion : "transparent"
                    IconImage { anchors.centerIn: parent; implicitSize: 16; source: trayItem.modelData.icon }
                    Rectangle {
                        visible: trayItem.modelData.status === Status.NeedsAttention
                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 3
                        width: 6; height: 6; radius: 3; color: Theme.pencil
                    }
                    function openMenu() {
                        const p = trayItem.mapToItem(null, 0, 0);
                        trayMenu.open(trayItem.modelData, p.y);
                    }
                    MouseArea {
                        id: trayMouse
                        anchors.fill: parent; hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: m => {
                            const it = trayItem.modelData;
                            bar.untip(trayItem.label);
                            if (m.button === Qt.MiddleButton) it.secondaryActivate();
                            else if (m.button === Qt.RightButton || it.onlyMenu) { if (it.hasMenu) trayItem.openMenu(); }
                            else it.activate();
                        }
                        onWheel: w => {
                            const horizontal = w.angleDelta.y === 0;
                            trayItem.modelData.scroll(horizontal ? w.angleDelta.x : w.angleDelta.y, horizontal);
                        }
                        onContainsMouseChanged: containsMouse ? bar.tip(trayItem, trayItem.label) : bar.untip(trayItem.label)
                    }
                }
            }
        }

        Hair {}

        // Notification bell: count of unseen notifications, crossed out while
        // do not disturb is on. Opens the notification centre.
        BarButton {
            id: bell
            visible: bar.center !== null
            glyph: Services.Notifs.dnd ? "󰂛" : (Services.Notifs.unread > 0 ? "󰂞" : "󰂚")
            label: Services.Notifs.dnd ? "Do not disturb" : (Services.Notifs.unread > 0 ? Services.Notifs.unread + " new" : "Notifications")
            active: bar.center !== null && bar.center.shown
            glyphColor: active || Services.Notifs.unread > 0 ? Theme.pencil : (Services.Notifs.dnd ? Theme.fixer : Theme.paper)
            onClicked: if (bar.center) bar.center.toggle()
            Text {
                visible: Services.Notifs.unread > 0 && !bell.active
                anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: 1; anchors.topMargin: -2
                text: Services.Notifs.unread > 9 ? "9+" : Services.Notifs.unread
                color: Theme.pencil; font.family: Theme.mono; font.pixelSize: 10; font.weight: Font.Bold
            }
        }

        // System cluster, one click target: opens quick settings.
        Rectangle {
            id: cluster
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
                Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: bar.wifiGlyph(); size: 17; color: bar.wifiNet ? Theme.paper : Theme.fixer }
                Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: bar.btConnected > 0 ? "󰂱" : "󰂯"; size: 17; color: bar.btAdapter && bar.btAdapter.enabled ? Theme.paper : Theme.fixer }
                Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: Services.Audio.icon(); size: 17 }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: bar.battery && bar.battery.isPresent
                    spacing: 0
                    Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: bar.batteryGlyph(); size: 17; rotation: 90; color: bar.batteryLow ? Theme.warn : Theme.paper }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: bar.battery ? Math.round(bar.battery.percentage * 100) : ""; color: bar.batteryLow ? Theme.warn : Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs12 }
                }
            }
            MouseArea {
                id: clusterMouse; anchors.fill: parent; hoverEnabled: true
                onClicked: if (bar.quickSettings) bar.quickSettings.toggle()
                onContainsMouseChanged: containsMouse ? bar.tip(cluster, bar.clusterLabel()) : bar.untip(bar.clusterLabel())
            }
        }
    }
    function clusterLabel() {
        const parts = [wifiNet ? wifiNet.name : (Networking.wifiEnabled ? "Wi-Fi disconnected" : "Wi-Fi off")];
        if (battery && battery.isPresent) parts.push(Math.round(battery.percentage * 100) + "%");
        return parts.join(", ");
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
