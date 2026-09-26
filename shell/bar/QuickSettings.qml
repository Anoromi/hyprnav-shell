pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Quickshell.Hyprland
import "../services" as Services
import ".."

// One sheet beside the bottom of the bar: quick tiles (night light, do not
// disturb, screenshots), power profile, then network, bluetooth, sound and
// brightness. Opens from the bar cluster or `qs ipc call qs toggle`. The
// notification history lives in the notification centre.
PanelWindow {
    id: qs
    required property var modelData
    screen: modelData
    property bool shown: false
    property string phase: "closed"
    property string section: "wifi"      // wifi | bluetooth | sound

    visible: phase !== "closed"
    anchors { bottom: true; left: true }
    margins { bottom: 8; left: 52 }
    implicitWidth: 400
    implicitHeight: Math.min(720, sheet.implicitHeight)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprnav-shell-quicksettings"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    function toggle() { if (shown) close(); else show(); }
    signal opened()
    function show() { phase = "open"; shown = true; if (bar.wifiDev) bar.wifiDev.scannerEnabled = true; Services.NightLight.probe(); opened(); }
    function close() { if (!shown) return; shown = false; phase = "closing"; finish.restart(); if (bar.wifiDev) bar.wifiDev.scannerEnabled = false; }
    Timer { id: finish; interval: Theme.tScrim; onTriggered: qs.phase = "closed" }

    // Shared lookups
    QtObject {
        id: bar
        readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
        readonly property var networks: wifiDev ? wifiDev.networks.values.slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength)) : []
        readonly property var btAdapter: Bluetooth.defaultAdapter
        readonly property var btDevices: btAdapter ? btAdapter.devices.values.slice().sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired)) : []
        readonly property var battery: UPower.displayDevice
    }
    property var pendingNetwork: null   // network awaiting a password

    function batteryState() {
        const b = bar.battery; if (!b) return "";
        const pct = Math.round(b.percentage * 100) + "%";
        switch (b.state) {
        case UPowerDeviceState.Charging: return "Charging, " + pct;
        case UPowerDeviceState.FullyCharged: return "Plugged in, full";
        case UPowerDeviceState.PendingCharge: return "Plugged in, not charging, " + pct;
        case UPowerDeviceState.Empty: return "Empty";
        default: return "On battery, " + pct;
        }
    }
    function batteryTime() {
        const b = bar.battery; if (!b) return "";
        const fmt = s => Math.floor(s / 3600) + "h " + Math.round((s % 3600) / 60) + "m";
        if (b.state === UPowerDeviceState.Charging && b.timeToFull > 0) return fmt(b.timeToFull) + " to full";
        if (b.state === UPowerDeviceState.Discharging && b.timeToEmpty > 0) return fmt(b.timeToEmpty) + " left";
        return "";
    }

    // Screenshots: the sheet closes first so it is not in the picture. Saved
    // under ~/Pictures/Screenshots and copied to the clipboard.
    property string shotMode: ""
    Timer { id: shotDelay; interval: Theme.tScrim + 150; onTriggered: {
        const out = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const grab = qs.shotMode === "area" ? 'g=$(slurp) || exit 0; grim -g "$g" "$f"' : 'grim ${OUT:+-o "$OUT"} "$f"';
        Quickshell.execDetached({
            command: ["sh", "-c",
                'd="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"; mkdir -p "$d"; f="$d/$(date +%F_%H-%M-%S).png"; ' + grab +
                ' && { wl-copy --type image/png < "$f"; notify-send -a Screenshot -i "$f" "Screenshot saved" "$f"; }'],
            environment: { OUT: out }
        });
    } }

    Rectangle {
        id: sheet
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        implicitHeight: content.implicitHeight + Theme.s24
        radius: Theme.rSheet
        color: Theme.sheet
        border.color: Theme.emulsion
        opacity: qs.shown ? 1 : 0
        x: qs.shown ? 0 : -8
        Behavior on opacity { NumberAnimation { duration: Theme.tScrim; easing.type: Easing.OutCubic } }
        Behavior on x { NumberAnimation { duration: Theme.tScrim; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.s12 }
            spacing: Theme.s12

            // Quick tiles: one click each, state in the tile.
            Row {
                spacing: Theme.s4
                Repeater {
                    model: [
                        { id: "night", glyph: "󰖔", label: "Night light",
                          sub: !Services.NightLight.available ? "Not installed" : Services.NightLight.active ? Services.NightLight.temperature + " K" : "Off",
                          on: Services.NightLight.active, enabled: Services.NightLight.available },
                        { id: "dnd", glyph: Services.Notifs.dnd ? "󰂛" : "󰂚", label: "Do not disturb",
                          sub: Services.Notifs.dnd ? "On" : "Off", on: Services.Notifs.dnd, enabled: Services.Notifs.enabled },
                        { id: "area", glyph: "󰩭", label: "Screenshot", sub: "Area", on: false, enabled: true },
                        { id: "screen", glyph: "󰹑", label: "Screenshot", sub: "Screen", on: false, enabled: true }
                    ]
                    Rectangle {
                        id: tile
                        required property var modelData
                        width: 91; height: 60; radius: 6
                        opacity: modelData.enabled ? 1 : 0.5
                        color: modelData.on || tileMouse.containsMouse ? Theme.emulsion : "transparent"
                        border.color: modelData.on ? Theme.pencil : Theme.emulsion
                        Behavior on color { ColorAnimation { duration: Theme.tFast } }
                        Column {
                            anchors.centerIn: parent; spacing: 1
                            Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.glyph; size: 18; color: tile.modelData.on ? Theme.pencil : Theme.paper }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.label; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs12; fontSizeMode: Text.HorizontalFit; minimumPixelSize: 10; width: 86; horizontalAlignment: Text.AlignHCenter }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.sub; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12 }
                        }
                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent; hoverEnabled: true
                            enabled: tile.modelData.enabled
                            onClicked: {
                                switch (tile.modelData.id) {
                                case "night": Services.NightLight.toggle(); break;
                                case "dnd": Services.Notifs.setDnd(!Services.Notifs.dnd); break;
                                default: qs.shotMode = tile.modelData.id; qs.close(); shotDelay.restart();
                                }
                            }
                        }
                    }
                }
            }

            // Power profile (power-profiles-daemon over D-Bus).
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s4
                Repeater {
                    model: [
                        { p: PowerProfile.PowerSaver, glyph: "󰌪", label: "Saver" },
                        { p: PowerProfile.Balanced, glyph: "󰾅", label: "Balanced" },
                        { p: PowerProfile.Performance, glyph: "󰓅", label: "Performance" }
                    ].filter(m => m.p !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)
                    Rectangle {
                        id: seg
                        required property var modelData
                        readonly property bool on: PowerProfiles.profile === modelData.p
                        Layout.fillWidth: true
                        height: 32; radius: 6
                        color: on || segMouse.containsMouse ? Theme.emulsion : "transparent"
                        border.color: on ? Theme.pencil : Theme.emulsion
                        Behavior on color { ColorAnimation { duration: Theme.tFast } }
                        Row {
                            anchors.centerIn: parent; spacing: 6
                            Glyph { text: seg.modelData.glyph; size: 15; color: seg.on ? Theme.pencil : Theme.paper }
                            Text { text: seg.modelData.label; color: seg.on ? Theme.paper : Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { id: segMouse; anchors.fill: parent; hoverEnabled: true; onClicked: PowerProfiles.profile = seg.modelData.p }
                    }
                }
            }
            Text {
                visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
                text: "Performance limited: " + PerformanceDegradationReason.toString(PowerProfiles.degradationReason)
                color: Theme.warn; font.family: Theme.sans; font.pixelSize: Theme.fs12
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.emulsion }

            // Section tabs, each with its live state
            Row {
                spacing: Theme.s4
                Repeater {
                    model: [
                        { id: "wifi", glyph: "󰖩", label: bar.wifiDev && bar.networks.find(n => n.connected) ? bar.networks.find(n => n.connected).name : "Wi-Fi" },
                        { id: "bluetooth", glyph: "󰂯", label: bar.btAdapter && bar.btAdapter.enabled ? (bar.btDevices.filter(d => d.connected).length + " connected") : "Bluetooth off" },
                        { id: "sound", glyph: Services.Audio.icon(), label: Math.round(Services.Audio.volume * 100) + "%" }
                    ]
                    Rectangle {
                        required property var modelData
                        readonly property bool on: qs.section === modelData.id
                        width: 122; height: 56; radius: 6
                        color: on ? Theme.emulsion : "transparent"
                        border.color: on ? Theme.pencil : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.tFast } }
                        Column {
                            anchors.centerIn: parent; spacing: 2
                            Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.modelData.glyph; size: 18; color: parent.parent.on ? Theme.pencil : Theme.paper }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.modelData.label; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12; elide: Text.ElideRight; width: 114; horizontalAlignment: Text.AlignHCenter }
                        }
                        MouseArea { anchors.fill: parent; onClicked: qs.section = parent.modelData.id }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.emulsion }

            // Wi-Fi
            ColumnLayout {
                visible: qs.section === "wifi"
                Layout.fillWidth: true
                spacing: Theme.s8
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Wi-Fi"; color: Theme.paper; font.family: Theme.casual; font.pixelSize: Theme.fs18; font.weight: Font.Medium; Layout.fillWidth: true }
                    Text { text: bar.wifiDev && bar.wifiDev.scannerEnabled ? "scanning" : ""; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12 }
                    Toggle { on: Networking.wifiEnabled; onToggled: Networking.wifiEnabled = !Networking.wifiEnabled }
                }
                Text { visible: !bar.wifiDev; text: "No Wi-Fi adapter found."; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13 }
                Repeater {
                    model: bar.networks.slice(0, 8)
                    Rectangle {
                        id: netRow
                        required property var modelData
                        Layout.fillWidth: true
                        height: 40; radius: 6
                        color: netMouse.containsMouse ? Theme.emulsion : "transparent"
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: Theme.s8; anchors.rightMargin: Theme.s8
                            spacing: Theme.s8
                            Glyph { text: netRow.modelData.signalStrength > 0.8 ? "󰤨" : netRow.modelData.signalStrength > 0.55 ? "󰤥" : netRow.modelData.signalStrength > 0.3 ? "󰤢" : "󰤟"; color: netRow.modelData.connected ? Theme.pencil : Theme.paper }
                            Text { text: netRow.modelData.name || "Hidden network"; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13; font.weight: netRow.modelData.connected ? Font.Medium : Font.Normal; Layout.fillWidth: true; elide: Text.ElideRight }
                            Glyph { visible: netRow.modelData.security !== WifiSecurityType.None; text: "󰌾"; size: 12; color: Theme.fixer }
                            Text { text: netRow.modelData.connected ? "connected" : (netRow.modelData.stateChanging ? "connecting" : (netRow.modelData.known ? "saved" : "")); color: netRow.modelData.connected ? Theme.good : Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12 }
                        }
                        MouseArea {
                            id: netMouse
                            anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                const n = netRow.modelData;
                                if (n.connected) return;
                                if (n.known || n.security === WifiSecurityType.None) n.connect();
                                else qs.pendingNetwork = n;
                            }
                        }
                    }
                }
                // Password prompt for a new secured network
                Rectangle {
                    visible: qs.pendingNetwork !== null
                    Layout.fillWidth: true
                    height: 76; radius: 6
                    color: Theme.emulsion
                    Column {
                        anchors.fill: parent; anchors.margins: Theme.s8; spacing: Theme.s4
                        Text { text: "Password for " + (qs.pendingNetwork ? qs.pendingNetwork.name : ""); color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13 }
                        Rectangle {
                            width: parent.width; height: 30; radius: 4; color: Theme.darkroom; border.color: pw.activeFocus ? Theme.pencil : Theme.emulsion
                            TextInput {
                                id: pw
                                anchors.fill: parent; anchors.margins: 6
                                color: Theme.paper; font.family: Theme.mono; font.pixelSize: Theme.fs13
                                echoMode: TextInput.Password
                                focus: qs.pendingNetwork !== null
                                onAccepted: { if (qs.pendingNetwork) qs.pendingNetwork.connectWithPsk(text); text = ""; qs.pendingNetwork = null; }
                                Keys.onEscapePressed: { text = ""; qs.pendingNetwork = null; }
                            }
                        }
                    }
                }
            }

            // Bluetooth
            ColumnLayout {
                visible: qs.section === "bluetooth"
                Layout.fillWidth: true
                spacing: Theme.s8
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Bluetooth"; color: Theme.paper; font.family: Theme.casual; font.pixelSize: Theme.fs18; font.weight: Font.Medium; Layout.fillWidth: true }
                    Text { visible: bar.btAdapter && bar.btAdapter.discovering; text: "searching"; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12 }
                    Toggle { on: bar.btAdapter ? bar.btAdapter.enabled : false; onToggled: if (bar.btAdapter) bar.btAdapter.enabled = !bar.btAdapter.enabled }
                }
                Text { visible: !bar.btAdapter; text: "No Bluetooth adapter found."; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13 }
                Repeater {
                    model: bar.btDevices.filter(d => d.paired || d.connected || (d.name && d.name !== "")).slice(0, 8)
                    Rectangle {
                        id: btRow
                        required property var modelData
                        Layout.fillWidth: true
                        height: 40; radius: 6
                        color: btMouse.containsMouse ? Theme.emulsion : "transparent"
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: Theme.s8; anchors.rightMargin: Theme.s8
                            spacing: Theme.s8
                            Glyph { text: btRow.modelData.connected ? "󰂱" : "󰂯"; color: btRow.modelData.connected ? Theme.pencil : Theme.paper }
                            Text { text: btRow.modelData.name || btRow.modelData.address; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13; Layout.fillWidth: true; elide: Text.ElideRight }
                            Text { visible: btRow.modelData.batteryAvailable; text: Math.round(btRow.modelData.battery * 100) + "%"; color: Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs12 }
                            Text { text: btRow.modelData.connected ? "connected" : (btRow.modelData.state === BluetoothDeviceState.Connecting ? "connecting" : (btRow.modelData.paired ? "paired" : "")); color: btRow.modelData.connected ? Theme.good : Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12 }
                        }
                        MouseArea {
                            id: btMouse
                            anchors.fill: parent; hoverEnabled: true
                            onClicked: { const d = btRow.modelData; if (d.connected) d.disconnect(); else d.connect(); }
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: 6
                    color: scanMouse.containsMouse ? Theme.emulsion : "transparent"
                    border.color: Theme.emulsion
                    Text { anchors.centerIn: parent; text: bar.btAdapter && bar.btAdapter.discovering ? "Stop searching" : "Search for devices"; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13 }
                    MouseArea { id: scanMouse; anchors.fill: parent; hoverEnabled: true; onClicked: if (bar.btAdapter) bar.btAdapter.discovering = !bar.btAdapter.discovering }
                }
            }

            // Sound and brightness
            ColumnLayout {
                visible: qs.section === "sound"
                Layout.fillWidth: true
                spacing: Theme.s8
                Text { text: "Sound"; color: Theme.paper; font.family: Theme.casual; font.pixelSize: Theme.fs18; font.weight: Font.Medium }
                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.s8
                    Glyph { text: Services.Audio.icon(); size: 18; MouseArea { anchors.fill: parent; onClicked: Services.Audio.toggleMute() } }
                    Slider { Layout.fillWidth: true; value: Services.Audio.volume; onMoved: v => Services.Audio.setVolume(v) }
                    Text { text: Math.round(Services.Audio.volume * 100); width: 30; horizontalAlignment: Text.AlignRight; color: Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs13 }
                }
                Repeater {
                    model: Services.Audio.sinks
                    Rectangle {
                        id: sinkRow
                        required property var modelData
                        readonly property bool isDefault: Services.Audio.sink === modelData
                        Layout.fillWidth: true; height: 34; radius: 6
                        color: sinkMouse.containsMouse ? Theme.emulsion : "transparent"
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: Theme.s8; anchors.rightMargin: Theme.s8
                            Glyph { text: sinkRow.isDefault ? "󰄬" : " "; color: Theme.pencil; size: 13 }
                            Text { text: sinkRow.modelData.nickname || sinkRow.modelData.description || sinkRow.modelData.name; color: sinkRow.isDefault ? Theme.paper : Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                        MouseArea { id: sinkMouse; anchors.fill: parent; hoverEnabled: true; onClicked: Services.Audio.setSink(sinkRow.modelData) }
                    }
                }
                Text { Layout.topMargin: Theme.s8; text: "Screen brightness"; color: Theme.paper; font.family: Theme.casual; font.pixelSize: Theme.fs18; font.weight: Font.Medium }
                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.s8
                    Glyph { text: "󰃟"; size: 18 }
                    Slider { Layout.fillWidth: true; value: Services.Brightness.level; enabled: Services.Brightness.available; onMoved: v => Services.Brightness.setLevel(v) }
                    Text { text: Math.round(Services.Brightness.level * 100); width: 30; horizontalAlignment: Text.AlignRight; color: Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs13 }
                }
                Text { visible: Services.Brightness.error !== ""; text: Services.Brightness.error; color: Theme.warn; font.family: Theme.sans; font.pixelSize: Theme.fs12; wrapMode: Text.Wrap; Layout.fillWidth: true }
                RowLayout {
                    visible: bar.battery && bar.battery.isPresent
                    Layout.topMargin: Theme.s4
                    Text { text: qs.batteryState(); color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13; Layout.fillWidth: true }
                    Text { text: qs.batteryTime(); color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13 }
                }
            }
        }
    }
}
