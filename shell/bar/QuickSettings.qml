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
//
// Speed (see TESTING.md, "Control centre speed"): the surface is created once
// (SheetWindow); the Wi-Fi and Bluetooth lists are plain arrays that only
// change when the set or order of entries changes, so a scan updating signal
// strengths does not rebuild rows; the Wi-Fi scan starts only after the Wi-Fi
// view has been open for a second, or from its Scan button, and the list
// shows NetworkManager's cached results at once.
SheetWindow {
    id: qs
    required property var modelData
    screen: modelData
    property string section: "wifi"      // wifi | bluetooth | sound

    anchors { top: true; bottom: true; left: true }
    margins { top: 8; bottom: 8; left: 52 }
    implicitWidth: 400
    sheetHeight: content.implicitHeight + Theme.s24
    WlrLayershell.namespace: "hyprnav-shell-quicksettings"

    PerfProbe { id: perf; label: "qs" }
    onOpened: { perf.arm("open " + section); bar.refresh(); Services.NightLight.probe(); }
    onDismissed: { if (bar.wifiDev) bar.wifiDev.scannerEnabled = false; pendingNetwork = null; }

    // Shared lookups. `networks` and `btDevices` are refreshed on a short
    // debounce while the sheet is open and assigned only when they differ.
    QtObject {
        id: bar
        readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
        readonly property int netCount: wifiDev ? wifiDev.networks.values.length : 0
        readonly property var connectedNet: wifiDev ? (wifiDev.networks.values.find(n => n.connected) ?? null) : null
        readonly property var btAdapter: Bluetooth.defaultAdapter
        readonly property int btCount: btAdapter ? btAdapter.devices.values.length : 0
        readonly property int btConnected: btAdapter ? btAdapter.devices.values.filter(d => d.connected).length : 0
        readonly property var battery: UPower.displayDevice
        property var networks: []
        property var btDevices: []
        onNetCountChanged: if (qs.shown) debounce.restart()
        onBtCountChanged: if (qs.shown) debounce.restart()
        function same(a, b) { return a.length === b.length && a.every((x, i) => x === b[i]); }
        function strength(n) { return Math.round(n.signalStrength * 4); }   // coarse, so small wobbles do not reorder
        function refresh() {
            const nets = wifiDev ? wifiDev.networks.values.slice()
                .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (strength(b) - strength(a)) || String(a.name).localeCompare(String(b.name)))
                .slice(0, 8) : [];
            if (!same(nets, networks)) networks = nets;
            const bts = btAdapter ? btAdapter.devices.values
                .filter(d => d.paired || d.connected || (d.name && d.name !== ""))
                .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || String(a.name).localeCompare(String(b.name)))
                .slice(0, 8) : [];
            if (!same(bts, btDevices)) btDevices = bts;
        }
    }
    Timer { id: debounce; interval: 250; onTriggered: bar.refresh() }
    // Order can change without the count changing (a connect, a stronger AP).
    Timer { interval: 2000; repeat: true; running: qs.shown && qs.section !== "sound"; onTriggered: bar.refresh() }
    // Scan only when someone is looking at the list.
    Timer {
        interval: 1000
        running: qs.shown && qs.section === "wifi"
        onTriggered: if (bar.wifiDev && Networking.wifiEnabled) bar.wifiDev.scannerEnabled = true
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
    Timer { id: shotDelay; interval: Theme.tClose + 150; onTriggered: {
        const out = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const grab = qs.shotMode === "area" ? 'g=$(slurp) || exit 0; grim -g "$g" "$f"' : 'grim ${OUT:+-o "$OUT"} "$f"';
        Quickshell.execDetached({
            command: ["sh", "-c",
                'd="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"; mkdir -p "$d"; f="$d/$(date +%F_%H-%M-%S).png"; ' + grab +
                ' && { wl-copy --type image/png < "$f"; notify-send -a Screenshot -i "$f" "Screenshot saved" "$f"; }'],
            environment: { OUT: out }
        });
    } }


    component Heading: Text {
        color: Theme.paper; font.family: Theme.casual; font.pixelSize: Theme.fs18; font.weight: Font.Medium
    }
    component Meta: Text {
        color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12
    }
    component Hairline: Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.emulsion }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.s12 }
        spacing: Theme.s12

        // Quick tiles: one click each, state in the tile.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.s4
            Repeater {
                model: [
                    { id: "night", glyph: Services.NightLight.active ? "󰖔" : "󰖙", label: "Night light",
                      sub: !Services.NightLight.available ? "Not installed" : Services.NightLight.active ? Services.NightLight.temperature + " K" : "Off",
                      on: Services.NightLight.active, enabled: Services.NightLight.available },
                    { id: "dnd", glyph: Services.Notifs.dnd ? "󰂛" : "󰂚", label: "Do not disturb",
                      sub: Services.Notifs.dnd ? "On" : "Off", on: Services.Notifs.dnd, enabled: Services.Notifs.enabled },
                    { id: "area", glyph: "󰩭", label: "Screenshot", sub: "Area", on: false, enabled: true },
                    { id: "screen", glyph: "󰹑", label: "Screenshot", sub: "Screen", on: false, enabled: true }
                ]
                Pressable {
                    id: tile
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 64
                    active: modelData.on
                    outlined: true
                    interactive: modelData.enabled
                    opacity: modelData.enabled ? 1 : 0.5
                    Column {
                        anchors.centerIn: parent; spacing: 2
                        width: parent.width - Theme.s8
                        CrossGlyph { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.glyph; size: 18; color: tile.modelData.on ? Theme.pencil : Theme.paper }
                        Text { width: parent.width; text: tile.modelData.label; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs12; fontSizeMode: Text.HorizontalFit; minimumPixelSize: 10; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter }
                        Meta { width: parent.width; text: tile.modelData.sub; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter }
                    }
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
                Pressable {
                    id: seg
                    required property var modelData
                    readonly property bool on: PowerProfiles.profile === modelData.p
                    Layout.fillWidth: true
                    implicitHeight: 32
                    active: on
                    outlined: true
                    Row {
                        anchors.centerIn: parent; spacing: 6
                        CrossGlyph { anchors.verticalCenter: parent.verticalCenter; text: seg.modelData.glyph; size: 15; color: seg.on ? Theme.pencil : Theme.paper }
                        Text { text: seg.modelData.label; color: seg.on ? Theme.paper : Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13; anchors.verticalCenter: parent.verticalCenter }
                    }
                    onClicked: PowerProfiles.profile = seg.modelData.p
                }
            }
        }
        Text {
            visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
            text: "Performance limited: " + PerformanceDegradationReason.toString(PowerProfiles.degradationReason)
            color: Theme.warn; font.family: Theme.sans; font.pixelSize: Theme.fs12
        }

        Hairline {}

        // Section tabs, each with its live state
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.s4
            Repeater {
                model: [
                    { id: "wifi", glyph: Networking.wifiEnabled ? "󰖩" : "󰖪", label: bar.connectedNet ? bar.connectedNet.name : (Networking.wifiEnabled ? "Wi-Fi" : "Wi-Fi off") },
                    { id: "bluetooth", glyph: bar.btConnected > 0 ? "󰂱" : "󰂯", label: bar.btAdapter && bar.btAdapter.enabled ? (bar.btConnected + " connected") : "Bluetooth off" },
                    { id: "sound", glyph: Services.Audio.icon(), label: Services.Audio.muted ? "Muted" : Math.round(Services.Audio.volume * 100) + "%" }
                ]
                Pressable {
                    id: tab
                    required property var modelData
                    readonly property bool on: qs.section === modelData.id
                    Layout.fillWidth: true
                    implicitHeight: 56
                    active: on
                    outlined: on
                    Column {
                        anchors.centerIn: parent; spacing: 2
                        width: parent.width - Theme.s8
                        CrossGlyph { anchors.horizontalCenter: parent.horizontalCenter; text: tab.modelData.glyph; size: 18; color: tab.on ? Theme.pencil : Theme.paper }
                        Meta { width: parent.width; text: tab.modelData.label; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter; color: tab.on ? Theme.paper : Theme.fixer }
                    }
                    onClicked: qs.section = tab.modelData.id
                }
            }
        }

        Hairline {}

        // Wi-Fi
        ColumnLayout {
            visible: qs.section === "wifi"
            Layout.fillWidth: true
            spacing: Theme.s4
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s8
                Heading { text: "Wi-Fi"; Layout.fillWidth: true }
                Pressable {
                    visible: bar.wifiDev !== null && Networking.wifiEnabled
                    implicitWidth: scanLabel.implicitWidth + Theme.s16; implicitHeight: 24
                    interactive: bar.wifiDev !== null && !bar.wifiDev.scannerEnabled
                    Meta { id: scanLabel; anchors.centerIn: parent; text: bar.wifiDev && bar.wifiDev.scannerEnabled ? "Scanning" : "Scan"; color: parent.hovered ? Theme.paper : Theme.fixer }
                    onClicked: if (bar.wifiDev) bar.wifiDev.scannerEnabled = true
                }
                Toggle { on: Networking.wifiEnabled; onToggled: Networking.wifiEnabled = !Networking.wifiEnabled }
            }
            Text { visible: !bar.wifiDev; text: "No Wi-Fi adapter found."; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13 }
            Repeater {
                model: bar.networks
                Pressable {
                    id: netRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 40
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: Theme.s8; anchors.rightMargin: Theme.s8
                        spacing: Theme.s8
                        Glyph { text: netRow.modelData.signalStrength > 0.8 ? "󰤨" : netRow.modelData.signalStrength > 0.55 ? "󰤥" : netRow.modelData.signalStrength > 0.3 ? "󰤢" : "󰤟"; color: netRow.modelData.connected ? Theme.pencil : Theme.paper }
                        Text { text: netRow.modelData.name || "Hidden network"; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13; font.weight: netRow.modelData.connected ? Font.Medium : Font.Normal; Layout.fillWidth: true; elide: Text.ElideRight }
                        Glyph { visible: netRow.modelData.security !== WifiSecurityType.None; text: "󰌾"; size: 12; color: Theme.fixer }
                        Meta { text: netRow.modelData.connected ? "connected" : (netRow.modelData.stateChanging ? "connecting" : (netRow.modelData.known ? "saved" : "")); color: netRow.modelData.connected ? Theme.good : Theme.fixer }
                    }
                    onClicked: {
                        const n = netRow.modelData;
                        if (n.connected) return;
                        if (n.known || n.security === WifiSecurityType.None) n.connect();
                        else qs.pendingNetwork = n;
                    }
                }
            }
            // Password prompt for a new secured network
            Rectangle {
                visible: qs.pendingNetwork !== null
                Layout.fillWidth: true
                implicitHeight: 76; radius: Theme.rControl
                color: Theme.emulsion
                Column {
                    anchors.fill: parent; anchors.margins: Theme.s8; spacing: Theme.s4
                    Text { text: "Password for " + (qs.pendingNetwork ? qs.pendingNetwork.name : ""); color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13 }
                    Rectangle {
                        width: parent.width; height: 30; radius: 6; color: Theme.darkroom; border.color: pw.activeFocus ? Theme.pencil : Theme.emulsion
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
            spacing: Theme.s4
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s8
                Heading { text: "Bluetooth"; Layout.fillWidth: true }
                Meta { visible: bar.btAdapter !== null && bar.btAdapter.discovering; text: "Searching" }
                Toggle { on: bar.btAdapter ? bar.btAdapter.enabled : false; onToggled: if (bar.btAdapter) bar.btAdapter.enabled = !bar.btAdapter.enabled }
            }
            Text { visible: !bar.btAdapter; text: "No Bluetooth adapter found."; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13 }
            Repeater {
                model: bar.btDevices
                Pressable {
                    id: btRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 40
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: Theme.s8; anchors.rightMargin: Theme.s8
                        spacing: Theme.s8
                        Glyph { text: btRow.modelData.connected ? "󰂱" : "󰂯"; color: btRow.modelData.connected ? Theme.pencil : Theme.paper }
                        Text { text: btRow.modelData.name || btRow.modelData.address; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { visible: btRow.modelData.batteryAvailable; text: Math.round(btRow.modelData.battery * 100) + "%"; color: Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs12 }
                        Meta { text: btRow.modelData.connected ? "connected" : (btRow.modelData.state === BluetoothDeviceState.Connecting ? "connecting" : (btRow.modelData.paired ? "paired" : "")); color: btRow.modelData.connected ? Theme.good : Theme.fixer }
                    }
                    onClicked: { const d = btRow.modelData; if (d.connected) d.disconnect(); else d.connect(); }
                }
            }
            Pressable {
                Layout.fillWidth: true; implicitHeight: 32
                Layout.topMargin: Theme.s4
                outlined: true
                Text { anchors.centerIn: parent; text: bar.btAdapter && bar.btAdapter.discovering ? "Stop searching" : "Search for devices"; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13 }
                onClicked: if (bar.btAdapter) bar.btAdapter.discovering = !bar.btAdapter.discovering
            }
        }

        // Sound and brightness
        ColumnLayout {
            visible: qs.section === "sound"
            Layout.fillWidth: true
            spacing: Theme.s8
            Heading { text: "Sound" }
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.s8
                Pressable {
                    implicitWidth: 28; implicitHeight: 28
                    CrossGlyph { anchors.centerIn: parent; text: Services.Audio.icon(); size: 18; color: Services.Audio.muted ? Theme.fixer : Theme.paper }
                    onClicked: Services.Audio.toggleMute()
                }
                Slider { id: vol; Layout.fillWidth: true; value: Services.Audio.volume; onDraggingChanged: perf.track("volume drag", dragging); onMoved: v => Services.Audio.setVolume(v) }
                ValueLabel { slider: vol }
            }
            Repeater {
                model: Services.Audio.sinks
                Pressable {
                    id: sinkRow
                    required property var modelData
                    readonly property bool isDefault: Services.Audio.sink === modelData
                    Layout.fillWidth: true; implicitHeight: 34
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: Theme.s8; anchors.rightMargin: Theme.s8
                        Glyph { text: sinkRow.isDefault ? "󰄬" : " "; color: Theme.pencil; size: 13 }
                        Text { text: sinkRow.modelData.nickname || sinkRow.modelData.description || sinkRow.modelData.name; color: sinkRow.isDefault ? Theme.paper : Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                    onClicked: Services.Audio.setSink(sinkRow.modelData)
                }
            }
            Heading { Layout.topMargin: Theme.s8; text: "Screen brightness" }
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.s8
                Item { implicitWidth: 28; implicitHeight: 28; Glyph { anchors.centerIn: parent; text: "󰃟"; size: 18 } }
                Slider { id: bright; Layout.fillWidth: true; value: Services.Brightness.level; enabled: Services.Brightness.available; onDraggingChanged: perf.track("brightness drag", dragging); onMoved: v => Services.Brightness.setLevel(v) }
                ValueLabel { slider: bright }
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

    // The number beside a slider: Pencil and a step heavier while dragging.
    component ValueLabel: Text {
        required property var slider
        text: Math.round(slider.shownValue * 100)
        Layout.preferredWidth: 32
        horizontalAlignment: Text.AlignRight
        color: slider.dragging ? Theme.pencil : Theme.fixer
        font.family: Theme.mono; font.pixelSize: Theme.fs13
        font.weight: slider.dragging ? Font.Bold : Font.Normal
        Behavior on color { ColorAnimation { duration: Theme.tHover } }
    }
}
