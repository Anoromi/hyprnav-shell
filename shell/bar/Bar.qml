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

// Left edge column, like the edge of a film strip: workspace numbers, or a
// locked roll's frame numbers on a pencil rail, run down it. The bottom
// stacks, from
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

    // Top: the workspace selector. Two lists share one column of fixed rows.
    //
    // Unlocked (hyprnav follows focus, or this screen shows a workspace that
    // is not in the locked roll): every Hyprland workspace on this screen,
    // ids 1 and up in id order. Special workspaces and hyprnav's managed
    // workspaces (101 and up) are left out, except the one on screen, which
    // is listed last under its frame number in its roll rather than a raw
    // "103". The current one sits in a Pencil block, occupied ones are Paper,
    // empty ones Fixer. No monogram; an open lock at the head locks the roll
    // of the current workspace when it has one.
    //
    // Locked to the roll of the current workspace: its numbered frames sit on
    // a Pencil rail with a lock at its head and the roll's initials above,
    // digits Darkroom, the current frame inverted to a Darkroom block.
    //
    // Switching modes never moves a digit. Row i is always at the same y; a
    // row whose label differs between the lists cross-fades in place. The
    // rail grows out from behind the current frame to cover the group
    // (160 ms, ease out cubic) and each digit takes its locked colour as the
    // rail passes it; unlocking runs the same geometry back. The column keeps
    // room for the longer list.
    readonly property var frames: roll.map(c => c.snapshot).filter(c => c && !c.unnumbered)
    readonly property int activeIndex: cell ? frames.findIndex(c => c.slot_index === cell.slot_index) : -1
    readonly property int pipStep: 28 + Theme.s4
    readonly property string envTitle: cell ? (cell.environment_title || cell.environment_name || cell.environment_id || "") : ""
    readonly property int lockRow: 18        // rail head that holds the lock
    readonly property int railY0: 24 + Theme.s4                // below the monogram
    readonly property int stripY: railY0 + lockRow + Theme.s4  // first row

    // Every workspace on this screen. Hyprland.workspaces follows the
    // compositor's create, destroy and focus events and each workspace's
    // toplevels its window events, so nothing here polls.
    readonly property var spaces: {
        const name = screen ? screen.name : "";
        const cur = focusedWs ? focusedWs.id : null;
        return Hyprland.workspaces.values
            .filter(w => w.id >= 1 && w.monitor && w.monitor.name === name && (w.id < 101 || w.id === cur))
            .sort((a, b) => a.id - b.id);
    }
    readonly property var spaceItems: spaces.map(w => ({
        id: w.id,
        label: w.id < 101 ? String(w.id)
            : (cell && cell.physical_workspace_id === w.id && !cell.unnumbered ? String(cell.slot_index) : w.name),
        current: focusedWs !== null && w.id === focusedWs.id,
        filled: w.toplevels.values.length > 0
    }))
    readonly property int spaceIndex: spaceItems.findIndex(s => s.current)

    // `lockRaw` is what the daemon says right now. Moving focus from one roll
    // to another reads unlocked for the ~100 ms until the daemon's new lock
    // arrives, so a drop to unlocked waits briefly while a lock exists
    // elsewhere; an explicit unlock (no lock anywhere) shows at once.
    readonly property bool lockRaw: cell !== null && (cell.environment_locked === true || Services.Hyprnav.lockedEnv === cell.environment_id)
    property bool locked: false
    onLockRawChanged: {
        if (lockRaw || Services.Hyprnav.lockedEnv === "") { lockHold.stop(); locked = lockRaw; }
        else lockHold.restart();
    }
    Connections {
        target: Services.Hyprnav
        function onLockedEnvChanged() { if (Services.Hyprnav.lockedEnv === "" && !bar.lockRaw) { lockHold.stop(); bar.locked = false; } }
    }
    Timer { id: lockHold; interval: 250; onTriggered: bar.locked = bar.lockRaw }

    // 0 unlocked, 1 locked; drives the rail, the colours and the monogram.
    property real lockT: locked ? 1 : 0
    Behavior on lockT { NumberAnimation { duration: Theme.tLock; easing.type: Easing.OutCubic } }

    // The roll on the rail, held while the rail is up so it can shrink back
    // over the frames it covered after focus has left the roll.
    property var railFrames: []
    property int railActive: -1
    property string railEnv: ""
    function syncRail() {
        if (lockT > 0 && !locked) return;
        if (frames.length === 0 && lockT > 0) return;
        railFrames = frames; railActive = activeIndex; railEnv = cell ? cell.environment_id : "";
    }
    onFramesChanged: syncRail()
    onActiveIndexChanged: syncRail()
    onLockedChanged: syncRail()
    onLockTChanged: if (lockT === 0) syncRail()
    Component.onCompleted: { locked = lockRaw; syncRail(); }
    readonly property var railItems: railFrames.map((f, i) => ({
        label: String(f.slot_index), current: i === railActive, filled: f.window_count > 0, stuck: f.stuck === true, frame: f
    }))
    // Rail length in rows, eased so a roll change while locked never snaps it.
    property real railLen: railFrames.length
    Behavior on railLen { NumberAnimation { duration: Theme.tLock; easing.type: Easing.OutCubic } }
    readonly property int rowCount: Math.max(spaceItems.length, railFrames.length)

    // Rail geometry: from the current frame's 28 px box to the whole group.
    readonly property int railOrigin: Math.max(0, railActive)
    readonly property real railTop: lerp(stripY + railOrigin * pipStep, railY0, lockT)
    readonly property real railBottom: lerp(stripY + railOrigin * pipStep + 28,
        railY0 + lockRow + Theme.s4 * 2 + railLen * pipStep - Theme.s4, lockT)
    readonly property bool headReached: clamp01((stripY - Theme.s4 - railTop) / lockRow) >= 0.5
    property real headT: headReached ? 1 : 0
    Behavior on headT { NumberAnimation { duration: Theme.tHover; easing.type: Easing.OutCubic } }
    // How far the rail has reached row i: 0 bare, 1 on the rail.
    function rowT(i) {
        if (i >= railFrames.length || i === railOrigin) return lockT;
        const top = stripY + i * pipStep;
        return i < railOrigin ? clamp01((top + 28 - railTop) / 28) : clamp01((railBottom - top) / 28);
    }
    function lerp(a, b, t) { return a + (b - a) * t; }
    function clamp01(x) { return Math.max(0, Math.min(1, x)); }
    function mix(a, b, t) { return Qt.rgba(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t), lerp(a.a, b.a, t)); }
    readonly property color dimDarkroom: Qt.rgba(0.102, 0.098, 0.090, 0.55)

    function rollTip() {
        if (locked) return envTitle + " (locked)\nClick the initials to follow focus";
        return cell ? "Workspaces on this screen\nClick the lock to keep " + envTitle : "Workspaces on this screen";
    }
    function toggleLock() {
        if (locked) Services.Hyprnav.unlock();
        else if (cell) Services.Hyprnav.lock(cell.environment_id);
    }

    // A frame number that cross-fades when its text changes. `cover` is how
    // much of it the block covers: its colour turns as the block slides over
    // it, so a digit is never dark on the bare bar while the block is still
    // on its way. `big` grows it into the current style (Bold, 18 px).
    component Digit: Item {
        id: d
        property string text: ""
        property real cover: 0
        property real big: 0
        property color rest: Theme.paper
        property color hot: Theme.darkroom
        property bool flip: false
        readonly property color tone: bar.mix(rest, hot, cover)
        readonly property real textScale: (Theme.fs15 + (Theme.fs18 - Theme.fs15) * big) / Theme.fs18
        width: 28; height: 28
        onTextChanged: {
            if (!d.flip && da.text === text || d.flip && db.text === text) return;
            if (d.flip) da.text = text; else db.text = text;
            d.flip = !d.flip;
        }
        Component.onCompleted: da.text = text
        Text {
            id: da
            anchors.centerIn: parent; color: d.tone; scale: d.textScale
            opacity: d.flip ? 0 : 1
            font.family: Theme.mono; font.pixelSize: Theme.fs18; font.weight: d.big > 0.5 ? Font.Bold : Font.Normal
            Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
        }
        Text {
            id: db
            anchors.centerIn: parent; color: d.tone; scale: d.textScale
            opacity: d.flip ? 1 : 0
            font.family: Theme.mono; font.pixelSize: Theme.fs18; font.weight: d.big > 0.5 ? Font.Bold : Font.Normal
            Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
        }
    }

    Item {
        id: top
        anchors.top: parent.top; anchors.topMargin: Theme.s12
        anchors.horizontalCenter: parent.horizontalCenter
        width: 36
        height: bar.stripY + Math.max(1, bar.rowCount) * bar.pipStep

        // The rail, drawn first so the block and digits sit on it.
        Rectangle {
            id: rail
            visible: bar.lockT > 0 && bar.railFrames.length > 0
            x: bar.lerp(4, 0, bar.lockT)
            width: bar.lerp(28, 36, bar.lockT)
            y: bar.railTop
            height: bar.railBottom - bar.railTop
            radius: bar.lerp(Theme.rFrame, Theme.rSheet - 2, bar.lockT)
            color: Theme.pencil
            // Shrinking into the block it simply disappears behind it. When
            // the block has gone to another row it fades over the last
            // quarter instead, so it never snaps off in the open.
            opacity: block.row === bar.railOrigin ? 1 : bar.clamp01(bar.lockT * 4)
        }

        // The current workspace or frame: one block for both lists.
        Rectangle {
            id: block
            readonly property int row: bar.locked ? bar.railActive : bar.spaceIndex
            x: 4; width: 28; height: 28; radius: Theme.rFrame
            y: bar.stripY + Math.max(0, row) * bar.pipStep
            color: bar.mix(Theme.pencil, Theme.darkroom, bar.lockT)
            opacity: row >= 0 ? 1 : 0
            Behavior on y { enabled: !Theme.reducedMotion; SpringAnimation { spring: 4.2; damping: 0.36; epsilon: 0.2 } }
            Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
        }

        // Head: the roll's initials, then the lock. Open in Fixer while
        // unlocked (only when the current workspace belongs to a roll),
        // closed in Darkroom once the rail reaches it.
        // Initials cross-fade when focus moves the lock to another roll.
        Item {
            id: monogram
            readonly property string text: Services.Hyprnav.monogramFor(bar.railEnv)
            property bool flip: false
            anchors.horizontalCenter: parent.horizontalCenter
            width: 36; height: 24
            opacity: bar.headT
            onTextChanged: {
                if (!flip && ma.text === text || flip && mb.text === text) return;
                if (flip) ma.text = text; else mb.text = text;
                flip = !flip;
            }
            Component.onCompleted: ma.text = text
            Text {
                id: ma
                anchors.centerIn: parent; color: Theme.pencil; opacity: monogram.flip ? 0 : 1
                font.family: Theme.casual; font.pixelSize: Theme.fs15; font.weight: Font.Bold
                Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
            }
            Text {
                id: mb
                anchors.centerIn: parent; color: Theme.pencil; opacity: monogram.flip ? 1 : 0
                font.family: Theme.casual; font.pixelSize: Theme.fs15; font.weight: Font.Bold
                Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
            }
        }
        property real canLock: bar.cell !== null ? 1 : 0
        Behavior on canLock { NumberAnimation { duration: Theme.tHover } }
        Glyph {
            anchors.horizontalCenter: parent.horizontalCenter
            y: bar.railY0 + Theme.s4; height: bar.lockRow - 2
            text: "󰌿"; size: 13; color: headArea.containsMouse ? Theme.paper : Theme.fixer
            opacity: (1 - bar.headT) * top.canLock
            Behavior on color { ColorAnimation { duration: Theme.tHover } }
        }
        Glyph {
            anchors.horizontalCenter: parent.horizontalCenter
            y: bar.railY0 + Theme.s4; height: bar.lockRow - 2
            text: "󰌾"; size: 13; color: Theme.darkroom
            opacity: bar.headT
        }
        MouseArea {
            id: headArea
            width: parent.width; height: bar.stripY - Theme.s4
            hoverEnabled: true
            enabled: bar.locked || bar.cell !== null
            onClicked: bar.toggleLock()
            onContainsMouseChanged: containsMouse ? bar.tip(monogram, bar.rollTip()) : bar.untip()
        }
        Connections {
            target: bar
            function onLockedChanged() { if (headArea.containsMouse) bar.tip(monogram, bar.rollTip()); }
        }

        // Fixed rows. A spare dozen are kept so a new workspace fades into an
        // existing row instead of rebuilding the column.
        Repeater {
            model: Math.max(12, bar.rowCount)
            Item {
                id: row
                required property int index
                readonly property var u: bar.spaceItems[index] ?? null
                readonly property var l: bar.railItems[index] ?? null
                // The digit turns once the rail reaches its row and then
                // cross-fades over 120 ms: a rail edge moving 15 px a frame
                // would otherwise swap a digit within a frame or two.
                readonly property bool reached: bar.rowT(index) >= 0.5
                property real t: reached ? 1 : 0
                Behavior on t { NumberAnimation { duration: Theme.tHover; easing.type: Easing.OutCubic } }
                readonly property var mine: bar.locked ? l : u
                readonly property real cover: block.opacity * bar.clamp01(1 - Math.abs(block.y - y) / 28)
                // Same label and role in both lists: one digit that changes
                // colour, so nothing dims halfway through.
                readonly property bool same: u !== null && l !== null && u.label === l.label && u.current === l.current
                x: 4; y: bar.stripY + index * bar.pipStep
                width: 28; height: 28
                Rectangle {
                    anchors.fill: parent; radius: Theme.rFrame
                    color: !rowMouse.containsMouse || row.mine === null || row.mine.current ? "transparent"
                        : bar.mix(Theme.hover, Qt.rgba(0.102, 0.098, 0.090, 0.14), bar.lockT)
                    Behavior on color { ColorAnimation { duration: Theme.tHover } }
                }
                Digit {
                    text: row.u ? row.u.label : ""
                    cover: row.cover
                    big: row.u && row.u.current ? row.cover : 0
                    rest: {
                        const r = row.u && row.u.filled ? Theme.paper : Theme.fixer;
                        return row.same ? bar.mix(r, row.l.filled ? Theme.darkroom : bar.dimDarkroom, row.t) : r;
                    }
                    hot: row.same ? bar.mix(Theme.darkroom, Theme.pencil, row.t) : Theme.darkroom
                    opacity: row.same ? 1 : 1 - row.t
                }
                Digit {
                    text: row.l ? row.l.label : ""
                    cover: row.cover
                    big: row.l && row.l.current ? row.cover : 0
                    rest: row.l && !row.l.filled ? bar.dimDarkroom : Theme.darkroom
                    hot: Theme.pencil
                    opacity: row.same ? 0 : row.t
                }
                // Pin: a spawned process tree is stuck to this frame.
                Glyph { anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: -3; anchors.topMargin: -5; visible: row.l !== null && row.l.stuck; opacity: row.t; text: "󰐃"; size: 12; color: Theme.darkroom }
                MouseArea {
                    id: rowMouse; anchors.fill: parent; hoverEnabled: true
                    enabled: row.mine !== null
                    onClicked: {
                        const it = row.mine;
                        if (!it) return;
                        if (it.current) Quickshell.execDetached(["qs", "-p", Quickshell.shellDir, "ipc", "call", "grid", "toggle"]);
                        else if (bar.locked) Services.Hyprnav.gotoSlot(it.frame.environment_id, it.frame.slot_index);
                        else Services.Hyprnav.gotoPhysical(it.id);
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
