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
//
// Size: the sheet is one height for every view. The tiles, power profile
// and tab strip above are fixed, and the views share one area of fixed
// height (Theme.qsViewH, the tallest view's); a view with more content
// scrolls inside it. Every list sits in a box of fixed height (ScrollList,
// heights from Theme), so a view is the same height from its first frame
// however many rows a scan brings in; the rows scroll inside the box. The connected
// network and connected devices are pinned above their list. With
// HNS_FAKE_WIFI / HNS_FAKE_BT (lab only) the radios are
// services/FakeRadios.qml.
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
    onOpened: { perf.arm("open " + section); bar.refresh(); Services.NightLight.probe(); focusList(); }
    onSectionChanged: if (shown) focusList()
    // The visible list takes the keys (Up/Down/PageUp/PageDown/Home/End); Esc
    // is not taken and reaches the sheet.
    function focusList() {
        Qt.callLater(() => {
            const l = section === "wifi" ? wifiList : section === "bluetooth" ? btList : sinkList;
            if (qs.pendingNetwork === null) l.view.forceActiveFocus();
        });
    }
    onDismissed: { if (bar.wifiDev) bar.wifiDev.scannerEnabled = false; pendingNetwork = null; }

    // Shared lookups. `networks` and `btDevices` are refreshed on a short
    // debounce while the sheet is open and assigned only when they differ.
    QtObject {
        id: bar
        readonly property bool fakeWifi: Services.FakeRadios.wifi
        readonly property bool fakeBt: Services.FakeRadios.bt
        readonly property var wifiDev: fakeWifi ? Services.FakeRadios.wifiDev : (Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null)
        readonly property bool wifiOn: fakeWifi ? Services.FakeRadios.wifiEnabled : Networking.wifiEnabled
        function toggleWifi() { if (fakeWifi) Services.FakeRadios.wifiEnabled = !Services.FakeRadios.wifiEnabled; else Networking.wifiEnabled = !Networking.wifiEnabled; }
        readonly property int netCount: wifiDev ? wifiDev.networks.values.length : 0
        readonly property var connectedNet: wifiDev ? (wifiDev.networks.values.find(n => n.connected) ?? null) : null
        readonly property var btAdapter: fakeBt ? Services.FakeRadios.btAdapter : Bluetooth.defaultAdapter
        readonly property int btCount: btAdapter ? btAdapter.devices.values.length : 0
        readonly property int btConnected: btAdapter ? btAdapter.devices.values.filter(d => d.connected).length : 0
        readonly property var battery: UPower.displayDevice
        // Pinned above the list (the connected network, up to two connected
        // devices) and the scrolling rest. Assigned only when the set or order
        // changes; the ScriptModels diff them, so kept rows keep their delegates.
        property var pinnedNets: []
        property var networks: []
        property var pinnedBt: []
        property var btDevices: []
        onNetCountChanged: if (qs.shown) debounce.restart()
        onBtCountChanged: if (qs.shown) debounce.restart()
        onConnectedNetChanged: if (qs.shown) debounce.restart()
        onBtConnectedChanged: if (qs.shown) debounce.restart()
        onWifiOnChanged: refresh()
        function same(a, b) { return a.length === b.length && a.every((x, i) => x === b[i]); }
        function strength(n) { return Math.round(n.signalStrength * 4); }   // coarse, so small wobbles do not reorder
        function refresh() {
            const nets = wifiDev && wifiOn ? wifiDev.networks.values.slice()
                .sort((a, b) => (b.known - a.known) || (strength(b) - strength(a)) || String(a.name).localeCompare(String(b.name)))
                .slice(0, 60) : [];
            const pn = nets.filter(n => n.connected), rn = nets.filter(n => !n.connected);
            if (!same(pn, pinnedNets)) pinnedNets = pn;
            if (!same(rn, networks)) networks = rn;
            const bts = btAdapter && btAdapter.enabled ? btAdapter.devices.values
                .filter(d => d.paired || d.connected || (d.name && d.name !== ""))
                .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || String(a.name).localeCompare(String(b.name)))
                .slice(0, 60) : [];
            const pb = bts.filter(d => d.connected).slice(0, 2), rb = bts.filter(d => !pb.includes(d));
            if (!same(pb, pinnedBt)) pinnedBt = pb;
            if (!same(rb, btDevices)) btDevices = rb;
        }
    }
    Timer { id: debounce; interval: 250; onTriggered: bar.refresh() }
    // Order can change without the count changing (a connect, a stronger AP).
    Timer { interval: 2000; repeat: true; running: qs.shown && qs.section !== "sound"; onTriggered: bar.refresh() }
    // Scan only when someone is looking at the list.
    Timer {
        id: scanWait
        interval: 1000
        running: qs.shown && qs.section === "wifi"
        onTriggered: if (bar.wifiDev && bar.wifiOn) bar.wifiDev.scannerEnabled = true
    }
    property var pendingNetwork: null   // network awaiting a password
    onPendingNetworkChanged: if (pendingNetwork !== null) Qt.callLater(() => pw.forceActiveFocus())

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
    // Width of a row's status word column ("connecting" is the longest).
    TextMetrics { id: statusMetrics; font.family: Theme.sans; font.pixelSize: Theme.fs12; text: "connecting" }
    readonly property int statusW: Math.ceil(statusMetrics.advanceWidth)
    component Hairline: Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.emulsion }

    // One network. Used for the pinned connected row and the list rows.
    component NetRow: Pressable {
        id: netRow
        required property var modelData
        width: ListView.view ? ListView.view.width : (parent ? parent.width : 0)
        implicitHeight: Theme.rowH
        Component.onCompleted: if (perf.enabled) console.info("[perf] qs wifi row created " + modelData.name)
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: Theme.s8; anchors.rightMargin: Theme.s8
            spacing: Theme.s8
            Glyph { text: netRow.modelData.signalStrength > 0.8 ? "󰤨" : netRow.modelData.signalStrength > 0.55 ? "󰤥" : netRow.modelData.signalStrength > 0.3 ? "󰤢" : "󰤟"; color: netRow.modelData.connected ? Theme.pencil : Theme.paper }
            Text { text: netRow.modelData.name || "Hidden network"; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13; font.weight: netRow.modelData.connected ? Font.Medium : Font.Normal; Layout.fillWidth: true; elide: Text.ElideRight }
            Glyph { visible: netRow.modelData.security !== WifiSecurityType.Open; text: "󰌾"; size: 12; color: Theme.fixer }
            Meta { Layout.preferredWidth: qs.statusW; horizontalAlignment: Text.AlignRight; text: netRow.modelData.connected ? "connected" : (netRow.modelData.stateChanging ? "connecting" : (netRow.modelData.known ? "saved" : "")); color: netRow.modelData.connected ? Theme.good : Theme.fixer }
        }
        onClicked: {
            const n = netRow.modelData;
            if (n.connected) return;
            if (n.known || n.security === WifiSecurityType.Open) n.connect();
            else qs.pendingNetwork = n;
        }
    }

    // One Bluetooth device, pinned or in the list.
    component BtRow: Pressable {
        id: btRow
        required property var modelData
        width: ListView.view ? ListView.view.width : (parent ? parent.width : 0)
        implicitHeight: Theme.rowH
        Component.onCompleted: if (perf.enabled) console.info("[perf] qs bt row created " + modelData.name)
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: Theme.s8; anchors.rightMargin: Theme.s8
            spacing: Theme.s8
            Glyph { text: btRow.modelData.connected ? "󰂱" : "󰂯"; color: btRow.modelData.connected ? Theme.pencil : Theme.paper }
            Text { text: btRow.modelData.name || btRow.modelData.address; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13; Layout.fillWidth: true; elide: Text.ElideRight }
            Text { visible: btRow.modelData.batteryAvailable; text: Math.round(btRow.modelData.battery * 100) + "%"; color: Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs12 }
            Meta { Layout.preferredWidth: qs.statusW; horizontalAlignment: Text.AlignRight; text: btRow.modelData.connected ? "connected" : (btRow.modelData.state === BluetoothDeviceState.Connecting ? "connecting" : (btRow.modelData.paired ? "paired" : "")); color: btRow.modelData.connected ? Theme.good : Theme.fixer }
        }
        onClicked: { const d = btRow.modelData; if (d.connected) d.disconnect(); else d.connect(); }
    }

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
        Hairline {}

        // Section tabs, each with its live state
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.s4
            Repeater {
                model: [
                    { id: "wifi", glyph: bar.wifiOn ? "󰖩" : "󰖪", label: bar.connectedNet ? bar.connectedNet.name : (bar.wifiOn ? "Wi-Fi" : "Wi-Fi off") },
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

        // The views: one area of fixed height, whichever view is shown.
        Item {
            id: viewArea
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.qsViewH

            // Wi-Fi: a fixed box, the connected network pinned at its top.
            ColumnLayout {
                visible: qs.section === "wifi"
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: Theme.s4
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.qsHeaderH
                    spacing: Theme.s8
                    Heading { text: "Wi-Fi"; Layout.fillWidth: true }
                    // Sized for its longer label, so "Scan" and "Scanning" hold one box.
                    TextMetrics { id: scanWide; font.family: Theme.sans; font.pixelSize: Theme.fs12; text: "Scanning" }
                    Pressable {
                        visible: bar.wifiDev !== null && bar.wifiOn
                        implicitWidth: Math.ceil(scanWide.advanceWidth) + Theme.s16; implicitHeight: 24
                        interactive: bar.wifiDev !== null && !bar.wifiDev.scannerEnabled
                        Meta { id: scanLabel; anchors.centerIn: parent; text: bar.wifiDev && bar.wifiDev.scannerEnabled ? "Scanning" : "Scan"; color: parent.hovered ? Theme.paper : Theme.fixer }
                        onClicked: if (bar.wifiDev) bar.wifiDev.scannerEnabled = true
                    }
                    Toggle { visible: bar.wifiDev !== null; on: bar.wifiOn; onToggled: bar.toggleWifi() }
                }
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.wifiListH
                    Column {
                        id: wifiPinned
                        width: parent.width
                        spacing: Theme.listGap
                        Repeater { model: ScriptModel { values: bar.pinnedNets } delegate: NetRow {} }
                    }
                    ScrollList {
                        id: wifiList
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: parent.height - (bar.pinnedNets.length > 0 ? wifiPinned.height + Theme.listGap : 0)
                        bottomInset: qs.pendingNetwork !== null ? pwBox.height + Theme.s4 : 0
                        model: ScriptModel { values: bar.networks }
                        delegate: NetRow {}
                        placeholder: !bar.wifiDev ? "No Wi-Fi adapter found."
                            : !bar.wifiOn ? "Wi-Fi is off."
                            : (bar.wifiDev.scannerEnabled || scanWait.running) ? "Scanning…"
                            : bar.pinnedNets.length > 0 ? "No other networks in range." : "No networks in range."
                    }
                    // Password prompt for a new secured network, over the bottom of
                    // the box so the sheet keeps its height.
                    Rectangle {
                        id: pwBox
                        visible: qs.pendingNetwork !== null
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 76; radius: Theme.rControl
                        color: Theme.emulsion
                        Column {
                            anchors.fill: parent; anchors.margins: Theme.s8; spacing: Theme.s4
                            Text { width: parent.width; elide: Text.ElideRight; text: "Password for " + (qs.pendingNetwork ? qs.pendingNetwork.name : ""); color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13 }
                            Rectangle {
                                width: parent.width; height: 30; radius: 6; color: Theme.darkroom; border.color: pw.activeFocus ? Theme.pencil : Theme.emulsion
                                TextInput {
                                    id: pw
                                    anchors.fill: parent; anchors.margins: 6
                                    color: Theme.paper; font.family: Theme.mono; font.pixelSize: Theme.fs13
                                    echoMode: TextInput.Password
                                    focus: qs.pendingNetwork !== null
                                    onAccepted: { if (qs.pendingNetwork) qs.pendingNetwork.connectWithPsk(text); text = ""; qs.pendingNetwork = null; qs.focusList(); }
                                    Keys.onEscapePressed: { text = ""; qs.pendingNetwork = null; qs.focusList(); }
                                }
                            }
                        }
                    }
                }
            }

            // Bluetooth: a fixed box, connected devices pinned at its top.
            ColumnLayout {
                visible: qs.section === "bluetooth"
                anchors.fill: parent
                spacing: Theme.s4
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.qsHeaderH
                    spacing: Theme.s8
                    Heading { text: "Bluetooth"; Layout.fillWidth: true }
                    Meta { visible: bar.btAdapter !== null && bar.btAdapter.discovering; text: "Searching" }
                    Toggle { visible: bar.btAdapter !== null; on: bar.btAdapter ? bar.btAdapter.enabled : false; onToggled: if (bar.btAdapter) bar.btAdapter.enabled = !bar.btAdapter.enabled }
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true             // the area less the header and the button
                    Column {
                        id: btPinned
                        width: parent.width
                        spacing: Theme.listGap
                        Repeater { model: ScriptModel { values: bar.pinnedBt } delegate: BtRow {} }
                    }
                    ScrollList {
                        id: btList
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: parent.height - (bar.pinnedBt.length > 0 ? btPinned.height + Theme.listGap : 0)
                        model: ScriptModel { values: bar.btDevices }
                        delegate: BtRow {}
                        placeholder: !bar.btAdapter ? "No Bluetooth adapter found."
                            : !bar.btAdapter.enabled ? "Bluetooth is off."
                            : bar.btAdapter.discovering ? "Searching…"
                            : bar.pinnedBt.length > 0 ? "No other devices." : "No devices."
                    }
                }
                Pressable {
                    Layout.fillWidth: true; implicitHeight: 32
                    Layout.topMargin: Theme.s4
                    outlined: true
                    interactive: bar.btAdapter !== null && bar.btAdapter.enabled
                    opacity: interactive ? 1 : 0.5
                    Text { anchors.centerIn: parent; text: bar.btAdapter && bar.btAdapter.discovering ? "Stop searching" : "Search for devices"; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13 }
                    onClicked: if (bar.btAdapter) bar.btAdapter.discovering = !bar.btAdapter.discovering
                }
            }

            // Sound and brightness. Their lines (a brightness error, the battery,
            // a power limit) come and go, so the view scrolls inside the area
            // rather than resize it.
            Flickable {
                id: soundFlick
                visible: qs.section === "sound"
                anchors.fill: parent
                contentWidth: width; contentHeight: soundCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: soundCol
                    width: soundFlick.width
                    spacing: Theme.s8
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.qsHeaderH
                        Heading { text: "Sound"; Layout.fillWidth: true }
                    }
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
                    // Outputs: a box of three rows, the rest scroll.
                    ScrollList {
                        id: sinkList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.sinkListH
                        step: Theme.rowCompactH + Theme.listGap
                        model: ScriptModel { values: Services.Audio.sinks }
                        placeholder: "No outputs."
                        delegate: Pressable {
                            id: sinkRow
                            required property var modelData
                            readonly property bool isDefault: Services.Audio.sink === modelData
                            width: ListView.view.width; implicitHeight: Theme.rowCompactH
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: Theme.s8; anchors.rightMargin: Theme.s8
                                Glyph { text: sinkRow.isDefault ? "󰄬" : " "; color: Theme.pencil; size: 13; Layout.preferredWidth: 16 }
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
                    // Was under the power profile row, where it pushed the tabs down.
                    Text {
                        visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
                        text: "Performance limited: " + PerformanceDegradationReason.toString(PowerProfiles.degradationReason)
                        color: Theme.warn; font.family: Theme.sans; font.pixelSize: Theme.fs12
                        wrapMode: Text.Wrap; Layout.fillWidth: true
                    }
                }
            }
            ScrollEdges { visible: soundFlick.visible; anchors.fill: soundFlick; flick: soundFlick; step: Theme.rowH }
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
