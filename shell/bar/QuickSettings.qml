pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import "../services" as Services
import "../notifications"
import ".."

// One sheet under the right end of the bar: network, bluetooth, sound,
// brightness, notifications. Opens from the bar cluster or `qs ipc call qs toggle`.
PanelWindow {
    id: qs
    required property var modelData
    screen: modelData
    property bool shown: false
    property string phase: "closed"
    property string section: "wifi"      // wifi | bluetooth | sound | notifications

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
    function show() { phase = "open"; shown = true; if (bar.wifiDev) bar.wifiDev.scannerEnabled = true; }
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

            // Section tabs, each with its live state
            Row {
                spacing: Theme.s4
                Repeater {
                    model: [
                        { id: "wifi", glyph: "󰖩", label: bar.wifiDev && bar.networks.find(n => n.connected) ? bar.networks.find(n => n.connected).name : "Wi-Fi" },
                        { id: "bluetooth", glyph: "󰂯", label: bar.btAdapter && bar.btAdapter.enabled ? (bar.btDevices.filter(d => d.connected).length + " connected") : "Bluetooth off" },
                        { id: "sound", glyph: Services.Audio.icon(), label: Math.round(Services.Audio.volume * 100) + "%" },
                        { id: "notifications", glyph: "󰂚", label: Services.Notifs.unread > 0 ? Services.Notifs.unread + " new" : "Quiet" }
                    ]
                    Rectangle {
                        required property var modelData
                        readonly property bool on: qs.section === modelData.id
                        width: 91; height: 56; radius: 6
                        color: on ? Theme.emulsion : "transparent"
                        border.color: on ? Theme.pencil : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.tFast } }
                        Column {
                            anchors.centerIn: parent; spacing: 2
                            Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.modelData.glyph; size: 18; color: parent.parent.on ? Theme.pencil : Theme.paper }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.modelData.label; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12; elide: Text.ElideRight; width: 84; horizontalAlignment: Text.AlignHCenter }
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
                    Text { text: bar.battery ? (bar.battery.state === UPowerDeviceState.Charging ? "Charging, " : "On battery, ") + Math.round(bar.battery.percentage * 100) + "%" : ""; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13; Layout.fillWidth: true }
                    Text { text: bar.battery && bar.battery.timeToEmpty > 0 ? Math.floor(bar.battery.timeToEmpty / 3600) + "h " + Math.round((bar.battery.timeToEmpty % 3600) / 60) + "m left" : ""; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13 }
                }
            }

            // Notifications
            ColumnLayout {
                visible: qs.section === "notifications"
                Layout.fillWidth: true
                spacing: Theme.s8
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Notifications"; color: Theme.paper; font.family: Theme.casual; font.pixelSize: Theme.fs18; font.weight: Font.Medium; Layout.fillWidth: true }
                    Text {
                        visible: Services.Notifs.unread > 0
                        text: "Clear all"; color: clearMouse.containsMouse ? Theme.paper : Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13
                        MouseArea { id: clearMouse; anchors.fill: parent; hoverEnabled: true; onClicked: Services.Notifs.clearAll() }
                    }
                }
                Text { visible: Services.Notifs.unread === 0; text: "Nothing new. Notifications you receive collect here."; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13; wrapMode: Text.Wrap; Layout.fillWidth: true }
                Repeater {
                    model: Services.Notifs.history.slice(0, 6)
                    NotificationCard { required property var modelData; notification: modelData; Layout.fillWidth: true; compact: true }
                }
            }
        }
    }
}
