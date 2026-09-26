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
import QtQuick.Effects
import "../services" as Services
import ".."

// Left edge column, like the edge of a film strip: the roll's monogram and
// frame numbers run down it. The bottom stacks, from
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

    // One hover label for every button in the column, beside the bar. It
    // lives on a strip surface that stays mapped with an empty input region:
    // a popup window per hover would create a new window and GL context
    // every time the pointer crossed a button.
    property string tipText: ""
    property real tipY: 0
    function tip(item, text) { tipY = item.mapToItem(null, 0, item.height / 2).y; tipText = text; tipHide.stop(); }
    function untip() { tipHide.restart(); }
    Timer { id: tipHide; interval: 60; onTriggered: bar.tipText = "" }
    PanelWindow {
        id: tips
        screen: bar.screen
        anchors { top: true; bottom: true; left: true }
        margins { left: bar.width + 6 }
        implicitWidth: 260
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hyprnav-shell-bar-tips"
        Rectangle {
            id: tipBox
            // Hidden while a sheet is open: it would sit on top of the sheet.
            readonly property bool on: bar.tipText !== "" && Services.Sheets.open === 0
            property string text: ""
            Connections { target: bar; function onTipTextChanged() { if (bar.tipText !== "") tipBox.text = bar.tipText; } }
            y: bar.tipY - height / 2
            width: tipLabel.implicitWidth + Theme.s16
            height: tipLabel.implicitHeight + 10
            radius: 6
            color: Theme.darkroom; border.color: Theme.emulsion
            opacity: on ? 1 : 0
            transform: Translate { x: tipBox.on ? 0 : -4; Behavior on x { NumberAnimation { duration: Theme.tHover; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
            Behavior on y { enabled: tipBox.opacity > 0; NumberAnimation { duration: Theme.tHover; easing.type: Easing.OutCubic } }
            Text { id: tipLabel; anchors.centerIn: parent; text: tipBox.text; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs12 }
        }
    }

    component BarButton: Pressable {
        id: btn
        property string glyph: ""
        property string label: ""
        property color glyphColor: active ? Theme.pencil : Theme.paper
        anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
        width: 32; height: 28
        CrossGlyph { anchors.centerIn: parent; text: btn.glyph; size: 16; color: btn.glyphColor }
        onHoveredChanged: hovered ? bar.tip(btn, btn.label) : bar.untip()
    }
    TrayMenu { id: trayMenu; bar: bar }

    component Cell: Item {
        property alias text: g.text
        property alias color: g.color
        anchors.horizontalCenter: parent.horizontalCenter
        width: 32; height: 28
        CrossGlyph { id: g; anchors.centerIn: parent; size: 16 }
    }
    component Hair: Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 16; height: 1; color: Theme.emulsion }

    Rectangle { anchors.right: parent.right; height: parent.height; width: 1; color: Theme.emulsion }

    // Top: the roll. Its monogram (initials of the environment title) sits
    // above its frames in slot order; the current frame is under a block that
    // slides between them (the switcher ring's spring), so a workspace change
    // reads as movement along the strip rather than a reshuffle.
    //
    // Two modes, told apart by the whole group rather than a glyph. Following
    // focus (default): bare digits on the bar, the monogram in Fixer, the
    // current frame in a Pencil block. Locked to this roll: the frames sit on
    // a Pencil rail with a lock at its top, the way a grease pencil marks a
    // strip on the contact sheet; digits turn Darkroom, the current frame
    // inverts to a Darkroom block, the monogram turns Pencil. Clicking the
    // monogram locks or unlocks the roll; hovering the group names it.
    readonly property var frames: roll.map(c => c.snapshot).filter(c => c && !c.unnumbered)
    readonly property int activeIndex: cell ? frames.findIndex(c => c.slot_index === cell.slot_index) : -1
    readonly property int pipStep: 28 + Theme.s4
    readonly property string envTitle: cell ? (cell.environment_title || cell.environment_name || cell.environment_id || "") : ""
    readonly property bool locked: cell !== null && (cell.environment_locked === true || Services.Hyprnav.lockedEnv === cell.environment_id)
    readonly property int lockRow: 18        // rail head that holds the lock
    function rollTip() { return envTitle + (locked ? " (locked)\nClick the initials to follow focus" : "\nClick the initials to lock"); }
    function toggleLock() {
        if (!cell) return;
        if (locked) Services.Hyprnav.unlock(); else Services.Hyprnav.lock(cell.environment_id);
    }
    Item {
        id: top
        anchors.top: parent.top; anchors.topMargin: Theme.s12
        anchors.horizontalCenter: parent.horizontalCenter
        width: 36
        height: bar.frames.length > 0 ? strip.y + strip.height + Theme.s4 : bare.y + bare.height

        HoverHandler {
            id: rollHover
            enabled: bar.cell !== null
            onHoveredChanged: hovered ? bar.tip(monogram, bar.rollTip()) : bar.untip()
        }
        Connections {
            target: bar
            function onLockedChanged() { if (rollHover.hovered) bar.tip(monogram, bar.rollTip()); }
        }

        // Monogram: the roll's name at a glance, and the lock switch.
        Pressable {
            id: monogram
            anchors.horizontalCenter: parent.horizontalCenter
            width: 36; height: 24; radius: Theme.rFrame
            visible: bar.cell !== null
            onClicked: bar.toggleLock()
            Text {
                anchors.centerIn: parent
                text: bar.cell ? Services.Hyprnav.monogramFor(bar.cell.environment_id) : ""
                color: bar.locked ? Theme.pencil : Theme.fixer
                font.family: Theme.casual; font.pixelSize: Theme.fs15; font.weight: Font.Bold
                Behavior on color { ColorAnimation { duration: Theme.tHover } }
            }
        }

        // A workspace outside hyprnav: its bare number, no roll.
        Rectangle {
            id: bare
            width: 28; height: 28; radius: Theme.rFrame
            anchors.horizontalCenter: parent.horizontalCenter
            y: monogram.visible ? monogram.height + Theme.s4 : 0
            color: Theme.emulsion
            visible: bar.frames.length === 0 || bar.activeIndex < 0 && bar.cell === null
            Text { anchors.centerIn: parent; text: bar.focusedWs ? bar.focusedWs.id : ""; color: Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs15 }
        }

        // The rail and the lock at its head. The head is reserved in both
        // modes so the digits never move when the lock changes.
        Rectangle {
            id: rail
            visible: bar.frames.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: monogram.height + Theme.s4
            width: 36; height: bar.lockRow + pips.height + Theme.s4 * 2
            radius: Theme.rSheet - 2
            color: Theme.pencil
            opacity: bar.locked ? 1 : 0
            transformOrigin: Item.Top
            scale: bar.locked ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: Theme.tHover; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Theme.tHover; easing.type: Easing.OutCubic } }
            Glyph {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.s4; height: bar.lockRow - 2
                text: "󰌾"; size: 13; color: Theme.darkroom
            }
            MouseArea { width: parent.width; height: bar.lockRow + Theme.s4; onClicked: bar.toggleLock() }
        }

        Item {
            id: strip
            visible: bar.frames.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: rail.y + bar.lockRow + Theme.s4
            width: 28; height: pips.height
            Rectangle {
                id: pencil
                width: 28; height: 28; radius: Theme.rFrame
                color: bar.locked ? Theme.darkroom : Theme.pencil
                opacity: bar.activeIndex >= 0 ? 1 : 0
                y: Math.max(0, bar.activeIndex) * bar.pipStep
                Behavior on y { enabled: !Theme.reducedMotion; SpringAnimation { spring: 4.2; damping: 0.36; epsilon: 0.2 } }
                Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
                Behavior on color { ColorAnimation { duration: Theme.tHover } }
            }
            Column {
                id: pips
                spacing: Theme.s4
                Repeater {
                    model: bar.frames
                    Item {
                        id: pip
                        required property var modelData
                        required property int index
                        readonly property bool current: index === bar.activeIndex
                        readonly property bool filled: modelData.window_count > 0
                        width: 28; height: 28
                        Rectangle {
                            anchors.fill: parent; radius: Theme.rFrame
                            color: !pipMouse.containsMouse || pip.current ? "transparent"
                                : (bar.locked ? Qt.rgba(0.102, 0.098, 0.090, 0.14) : Theme.hover)
                            Behavior on color { ColorAnimation { duration: Theme.tHover } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: pip.modelData.slot_index
                            color: bar.locked
                                ? (pip.current ? Theme.pencil : Theme.darkroom)
                                : (pip.current ? Theme.darkroom : (pip.filled ? Theme.paper : Theme.fixer))
                            opacity: bar.locked && !pip.current && !pip.filled ? 0.55 : 1
                            font.family: Theme.mono; font.pixelSize: pip.current ? Theme.fs18 : Theme.fs15
                            font.weight: pip.current ? Font.Bold : Font.Normal
                            Behavior on color { ColorAnimation { duration: Theme.tHover } }
                            Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
                        }
                        // Pin: a spawned process tree is stuck to this frame.
                        Glyph { anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: -3; anchors.topMargin: -5; visible: pip.modelData.stuck === true; text: "󰐃"; size: 12; color: bar.locked ? Theme.darkroom : Theme.pencil }
                        MouseArea {
                            id: pipMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: pip.current
                                ? Quickshell.execDetached(["qs", "-p", Quickshell.shellDir, "ipc", "call", "grid", "toggle"])
                                : Services.Hyprnav.gotoSlot(pip.modelData.environment_id, pip.modelData.slot_index)
                        }
                    }
                }
            }
        }
    }

    // Bottom stack, above the clock. Every row is a 28 px cell, 4 px apart
    // inside a group and a hairline with 8 px either side between groups, so
    // the glyphs sit on one rhythm. Glyphs are one family (Material Design
    // from the Nerd Font) at 16 px; tray icons are drawn flat in Paper at the
    // same optical size so an app's own colour icon does not break the set.
    Column {
        id: bottomStack
        anchors.bottom: clock.top; anchors.bottomMargin: Theme.s16
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.s8

        // Launcher and clipboard history, both vicinae views.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.s4
            BarButton { glyph: "󰀻"; label: "Launcher"; onClicked: Quickshell.execDetached(["vicinae", "toggle"]) }
            BarButton { glyph: "󰅍"; label: "Clipboard history"; onClicked: Quickshell.execDetached(["vicinae", "cmd", "launch", "clipboard:history"]) }
        }

        Hair { visible: SystemTray.items.values.length > 0 }

        // Tray: left click activates (or opens the menu for menu-only items),
        // right click opens the menu beside the bar, middle click is the
        // secondary action, the wheel scrolls the item.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.s4
            visible: SystemTray.items.values.length > 0
            Repeater {
                model: SystemTray.items
                Pressable {
                    id: trayItem
                    required property var modelData
                    readonly property string label: modelData.tooltipTitle || modelData.title || modelData.id
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 32; height: 28
                    active: trayMenu.shown && trayMenu.item === modelData
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    IconImage {
                        anchors.centerIn: parent; implicitSize: 15
                        source: trayItem.modelData.icon
                        layer.enabled: true
                        layer.effect: MultiEffect { brightness: 1.0; colorization: 1.0; colorizationColor: trayItem.active ? Theme.pencil : Theme.paper }
                    }
                    Rectangle {
                        visible: trayItem.modelData.status === Status.NeedsAttention
                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 3
                        width: 6; height: 6; radius: 3; color: Theme.pencil
                    }
                    function openMenu() {
                        const p = trayItem.mapToItem(null, 0, 0);
                        trayMenu.open(trayItem.modelData, p.y);
                    }
                    onClicked: m => {
                        const it = trayItem.modelData;
                        bar.untip();
                        if (m.button === Qt.MiddleButton) it.secondaryActivate();
                        else if (m.button === Qt.RightButton || it.onlyMenu) {
                            if (!it.hasMenu) return;
                            if (trayMenu.shown && trayMenu.item === it) trayMenu.close(); else trayItem.openMenu();
                        }
                        else it.activate();
                    }
                    onWheel: w => {
                        const horizontal = w.angleDelta.y === 0;
                        trayItem.modelData.scroll(horizontal ? w.angleDelta.x : w.angleDelta.y, horizontal);
                    }
                    onHoveredChanged: hovered ? bar.tip(trayItem, trayItem.label) : bar.untip()
                }
            }
        }

        Hair {}

        // Notification bell: count of unseen notifications, crossed out while
        // do not disturb is on. Opens the notification centre.
        BarButton {
            id: bell
            visible: bar.center !== null
            glyph: Services.Notifs.dnd ? "󰂛" : (Services.Notifs.unread > 0 ? "󰂞" : "󰂜")
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
        Pressable {
            id: cluster
            anchors.horizontalCenter: parent.horizontalCenter
            width: 32
            height: clusterCol.implicitHeight + Theme.s8
            active: bar.quickSettings !== null && bar.quickSettings.shown
            Column {
                id: clusterCol
                anchors.centerIn: parent
                spacing: 0
                Cell { text: bar.wifiGlyph(); color: cluster.active ? Theme.pencil : (bar.wifiNet ? Theme.paper : Theme.fixer) }
                Cell { text: bar.btConnected > 0 ? "󰂱" : "󰂯"; color: bar.btAdapter && bar.btAdapter.enabled ? Theme.paper : Theme.fixer }
                Cell { text: Services.Audio.icon(); color: Services.Audio.muted ? Theme.fixer : Theme.paper }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: bar.battery && bar.battery.isPresent
                    spacing: 2
                    Cell { text: bar.batteryGlyph(); color: bar.batteryLow ? Theme.warn : Theme.paper; rotation: 90; height: 24 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: bar.battery ? Math.round(bar.battery.percentage * 100) : ""; color: bar.batteryLow ? Theme.warn : Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs12 }
                }
            }
            onClicked: if (bar.quickSettings) bar.quickSettings.toggle()
            onHoveredChanged: hovered ? bar.tip(cluster, bar.clusterLabel()) : bar.untip()
        }
    }
    function clusterLabel() {
        const parts = [wifiNet ? wifiNet.name : (Networking.wifiEnabled ? "Wi-Fi disconnected" : "Wi-Fi off")];
        if (battery && battery.isPresent) parts.push(Math.round(battery.percentage * 100) + "%");
        return parts.join(", ");
    }

    // Clock: hours over minutes in the regular mono cut (the Medium cut read
    // heavier than every glyph around it), then the date in Fixer.
    SystemClock { id: clockSrc; precision: SystemClock.Minutes }
    Column {
        id: clock
        anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.s12
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 0
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDateTime(clockSrc.date, "HH"); color: Theme.paper; font.family: Theme.mono; font.pixelSize: Theme.fs15; font.weight: Font.Normal; lineHeight: 1.1 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDateTime(clockSrc.date, "mm"); color: Theme.paper; font.family: Theme.mono; font.pixelSize: Theme.fs15; font.weight: Font.Normal; lineHeight: 1.1 }
        Item { width: 1; height: Theme.s8 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDateTime(clockSrc.date, "d"); color: Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs12; lineHeight: 1.2 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDateTime(clockSrc.date, "MMM"); color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12; lineHeight: 1.2 }
    }
}
