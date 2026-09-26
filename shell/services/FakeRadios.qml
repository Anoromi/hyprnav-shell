pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth

// Lab-only stand-ins for NetworkManager and BlueZ, so the control centre's
// lists can be watched filling up in a lab that has no radios (and so no
// test ever scans, toggles or connects on the host).
//
//   HNS_FAKE_WIFI=<n>  a Wi-Fi device with n networks: one connected (the
//                      cached connection, there at once); the other n-1
//                      arrive one by one over 2 s once the scan starts.
//   HNS_FAKE_BT=<n>    an adapter with n devices: a connected pair of
//                      headphones and a paired keyboard at once; the rest
//                      arrive over 2 s once a search starts.
//
// Signal strengths wobble every 700 ms like a real scan. Connecting,
// toggling and searching only change these objects. `reset()` (IPC
// `qs fakeReset`) puts both back to their start.
Singleton {
    id: root
    readonly property int wifiTotal: Math.max(0, parseInt(Quickshell.env("HNS_FAKE_WIFI") || "0") || 0)
    readonly property int btTotal: Math.max(0, parseInt(Quickshell.env("HNS_FAKE_BT") || "0") || 0)
    readonly property bool wifi: wifiTotal > 0
    readonly property bool bt: btTotal > 0
    readonly property alias wifiDev: wifiDev
    readonly property alias btAdapter: btAdapter
    property bool wifiEnabled: true

    readonly property var ssids: ["Darkroom", "Contact sheet 5G", "Kissaten Hoshi", "Tokyo-Free-WiFi", "aterm-7c1f2a-g",
        "Buffalo-G-3E90", "Lab Guest", "Film & Coffee", "HP-Print-4A-LaserJet", "Nakano 2F", "Pixel_4417", "eduroam",
        "Koenji Records", "DIRECT-roku-551", "Sakura Hall", "FamilyMart", "TP-Link_88C0", "Studio B", "Rooftop", "Annex"]
    readonly property var btNames: ["WH-1000XM5", "Keychron K3", "MX Master 3S", "JBL Flip 6", "Pixel 9", "Galaxy Buds",
        "Kindle", "AirPods Pro", "Xbox Controller", "Apple Watch", "Living room TV", "Car audio"]

    component FakeNetwork: QtObject {
        id: net
        property string name
        property real signalStrength: 0.5
        property bool connected: false
        property bool known: false
        property int security: WifiSecurityType.Wpa2Psk
        property bool stateChanging: false
        property real base: 0.5
        function connect() { root.connectNetwork(net); }
        function connectWithPsk(psk) { net.known = true; root.connectNetwork(net); }
    }
    component FakeDevice: QtObject {
        id: dev
        property string name
        property string address
        property bool connected: false
        property bool paired: false
        property bool batteryAvailable: false
        property real battery: 0
        property int state: connected ? BluetoothDeviceState.Connected : BluetoothDeviceState.Disconnected
        function connect() { dev.paired = true; dev.connected = true; }
        function disconnect() { dev.connected = false; }
    }
    Component { id: netComp; FakeNetwork {} }
    Component { id: devComp; FakeDevice {} }

    QtObject {
        id: wifiDev
        readonly property int type: DeviceType.Wifi
        property bool scannerEnabled: false
        property QtObject networks: QtObject { property var values: [] }
        property int arrived: 0
        onScannerEnabledChanged: if (scannerEnabled && root.wifi && arrived < root.wifiTotal - 1) wifiFeed.start()
    }
    QtObject {
        id: btAdapter
        property bool enabled: true
        property bool discovering: false
        property QtObject devices: QtObject { property var values: [] }
        property int arrived: 0
        onDiscoveringChanged: if (discovering && root.bt && arrived < root.btTotal - 2) btFeed.start()
        onEnabledChanged: if (!enabled) { discovering = false; for (const d of devices.values) d.connected = false; }
    }

    function connectNetwork(n) {
        for (const x of wifiDev.networks.values) x.connected = false;
        n.known = true; n.connected = true;
    }
    function addNetwork(i) {
        const strength = i === 0 ? 0.9 : 0.15 + ((i * 37) % 80) / 100;
        const n = netComp.createObject(root, {
            name: root.ssids[i % root.ssids.length] + (i >= root.ssids.length ? " " + Math.floor(i / root.ssids.length + 1) : ""),
            base: strength, signalStrength: strength, connected: i === 0, known: i === 0 || i % 5 === 2,
            security: i % 6 === 3 ? WifiSecurityType.Open : WifiSecurityType.Wpa2Psk
        });
        wifiDev.networks.values = wifiDev.networks.values.concat([n]);
    }
    function addDevice(i) {
        const d = devComp.createObject(root, {
            name: root.btNames[i % root.btNames.length] + (i >= root.btNames.length ? " " + Math.floor(i / root.btNames.length + 1) : ""),
            address: "5C:3A:" + (10 + i) + ":00:4F:" + (20 + i), connected: i === 0, paired: i < 2,
            batteryAvailable: i === 0, battery: 0.8
        });
        btAdapter.devices.values = btAdapter.devices.values.concat([d]);
    }
    function reset() {
        wifiFeed.stop(); btFeed.stop();
        for (const n of wifiDev.networks.values) n.destroy();
        for (const d of btAdapter.devices.values) d.destroy();
        wifiDev.networks.values = []; btAdapter.devices.values = [];
        wifiDev.scannerEnabled = false; wifiDev.arrived = 0;
        btAdapter.discovering = false; btAdapter.arrived = 0;
        wifiEnabled = true; btAdapter.enabled = true;
        if (wifi) addNetwork(0);
        if (bt) { addDevice(0); addDevice(1); }
    }
    Component.onCompleted: reset()

    // Arrivals: the rest of the set over 2 s.
    Timer {
        id: wifiFeed
        interval: Math.max(40, 2000 / Math.max(1, root.wifiTotal - 1)); repeat: true
        onTriggered: {
            if (!root.wifiEnabled || wifiDev.arrived >= root.wifiTotal - 1) { stop(); wifiDev.scannerEnabled = false; return; }
            wifiDev.arrived++; root.addNetwork(wifiDev.arrived);
        }
    }
    Timer {
        id: btFeed
        interval: Math.max(40, 2000 / Math.max(1, root.btTotal - 2)); repeat: true
        onTriggered: {
            if (!btAdapter.enabled || btAdapter.arrived >= root.btTotal - 2) { stop(); return; }
            btAdapter.arrived++; root.addDevice(btAdapter.arrived + 1);
        }
    }
    // Signal strengths wobble a little, as they do between real scans.
    Timer {
        interval: 700; repeat: true; running: root.wifi
        property int tick: 0
        onTriggered: {
            tick++;
            for (const [i, n] of wifiDev.networks.values.entries())
                n.signalStrength = Math.max(0.05, Math.min(1, n.base + 0.06 * Math.sin(tick * 0.9 + i)));
        }
    }
}
