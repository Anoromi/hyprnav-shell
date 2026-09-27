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

// Left edge column, like the edge of a film strip, in three groups that are
// each anchored on their own: the screen's workspace numbers hang from the
// top; launcher, clipboard, the bell, the system cluster and the tray sit
// centred on the bar in a box of fixed height; the clock stands at the
// bottom, and while hyprnav holds a lock the locked roll's frames stand on
// it, growing upward. Nothing in one group moves another.
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

    // Three groups, each anchored on its own (see TESTING.md, "No layout
    // shifts"), so no state in one moves another:
    //
    // Top, hanging from the top edge: every Hyprland workspace on this
    // screen with an id from 1 to 99, in id order: the current one in a
    // Pencil block, occupied ones Paper, empty ones Fixer. Specials and
    // hyprnav's managed workspaces (100 and up) never get a pip. Clicking one
    // goes there; right-clicking one that belongs to a roll locks that roll.
    // When it is taller than the room above the middle group it clips and
    // scrolls on the wheel, with soft edges.
    //
    // Middle, centred on the bar in a box whose height is a constant:
    // launcher and clipboard, the bell, the system cluster, the tray. The
    // tray has four slots that stay reserved whether or not anything sits in
    // them; a fifth item scrolls inside the slots.
    //
    // Bottom, standing on the bottom edge: the clock, and above it, only
    // while hyprnav holds a lock, the locked roll: its monogram, a small lock,
    // its frame numbers in the same pips as the list at the top, and a thin
    // Pencil rule down its left side, the one mark that says "locked". Its
    // bottom edge is a fixed baseline above the clock; frames coming and
    // going move only its top. Clicking a frame goes there, clicking the
    // monogram or the lock unlocks. The workspace on screen can show in both
    // the top list and the roll and is marked in both.
    readonly property int pipStep: 28 + Theme.s4
    readonly property int groupGap: Theme.s16

    // Every workspace on this screen. Hyprland.workspaces follows the
    // compositor's create, destroy and focus events and each workspace's
    // toplevels its window events, so nothing here polls.
    readonly property var spaceItems: {
        const name = screen ? screen.name : "";
        return Hyprland.workspaces.values
            .filter(w => w.id >= 1 && w.id < 100 && w.monitor && w.monitor.name === name)
            .sort((a, b) => a.id - b.id)
            .map(w => ({
                id: w.id,
                label: String(w.id),
                current: focusedWs !== null && w.id === focusedWs.id,
                filled: w.toplevels.values.length > 0
            }));
    }

    // The locked roll. `status_get` carries the lock; the grid snapshot's
    // row flag covers the moment before the first status reply.
    readonly property string lockEnv: Services.Hyprnav.lockedEnv !== "" ? Services.Hyprnav.lockedEnv
        : (Services.Hyprnav.rows.find(r => r.locked)?.envId ?? "")
    // A locked worktree has no row of its own when its threads have frames:
    // its frames show, shared, in each thread's row. Take the first row on
    // the lock's chain and keep only the frames the locked environment
    // resolves itself (bound by it or an ancestor).
    readonly property var lockedRoll: lockEnv !== "" ? (Services.Hyprnav.rows.find(r => r.envId === lockEnv)
        ?? Services.Hyprnav.rows.find(r => r.chainIds.includes(lockEnv)) ?? null) : null
    readonly property var lockChain: lockedRoll ? lockedRoll.chainIds.slice(0, lockedRoll.chainIds.indexOf(lockEnv) + 1) : []
    readonly property var rollItems: (lockedRoll ? lockedRoll.cells : [])
        .map(c => c.snapshot).filter(f => f && !f.unnumbered)
        .filter(f => !lockedRoll || lockedRoll.envId === lockEnv || lockChain.includes(f.owner_environment_id || f.binding_environment_id))
        .map(f => ({
            label: String(f.slot_index),
            current: focusedWs !== null && f.physical_workspace_id === focusedWs.id,
            filled: f.window_count > 0, stuck: f.stuck === true, frame: f
        }))
    readonly property bool hasLock: rollItems.length > 0
    // Held while the roll fades out, so it leaves with what it showed.
    property var railItems: []
    property string railEnv: ""
    property string railTitle: ""
    function syncRail() {
        if (!hasLock || !lockedRoll) return;
        railItems = rollItems; railEnv = lockEnv;
        const at = lockedRoll.envId === lockEnv ? -1 : lockedRoll.chainIds.indexOf(lockEnv);
        railTitle = (at >= 0 ? lockedRoll.chainLabels[at] : "") || lockedRoll.title || lockedRoll.displayId || lockEnv;
    }
    onRollItemsChanged: syncRail()
    Component.onCompleted: syncRail()

    function goTo(it, button) {
        if (!it) return;
        if (button === Qt.RightButton) {
            // A plain workspace that is a roll's frame: keep that roll.
            const c = it.frame ? null : Services.Hyprnav.cellForWorkspace(it.id);
            if (c && c.environment_id !== lockEnv) Services.Hyprnav.lock(c.environment_id);
            return;
        }
        if (it.current) Quickshell.execDetached(["qs", "-p", Quickshell.shellDir, "ipc", "call", "grid", "toggle"]);
        else if (it.frame) Services.Hyprnav.gotoSlot(it.frame.environment_id, it.frame.slot_index);
        else Services.Hyprnav.gotoPhysical(it.id);
    }
    function pipTip(row, it, on) {
        if (!on || !it || it.frame) { bar.untip(); return; }
        const c = Services.Hyprnav.cellForWorkspace(it.id);
        if (!c) { bar.untip(); return; }
        const title = c.environment_title || c.environment_id;
        bar.tip(row, c.environment_id === lockEnv ? title + ", frame " + c.slot_index
            : title + ", frame " + c.slot_index + "\nRight-click to lock");
    }

    function lerp(a, b, t) { return a + (b - a) * t; }
    function clamp01(x) { return Math.max(0, Math.min(1, x)); }
    function mix(a, b, t) { return Qt.rgba(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t), lerp(a.a, b.a, t)); }

    // A frame number that cross-fades when its text changes. `cover` is how
    // much of it the block covers: its colour turns as the block slides over
    // it. `big` grows it into the current style (Bold, 18 px).
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

    // A column of numbers with one Pencil block for the current one, the
    // same in the top list and in the locked roll. Rows are fixed and spare
    // ones kept, so a new workspace fades into an existing row instead of
    // rebuilding the column. `inRoll`: frames of the locked roll (left click
    // only, and the pin for a stuck frame).
    component PipColumn: Item {
        id: col
        property var items: []
        property bool inRoll: false
        readonly property int current: items.findIndex(s => s.current)
        width: 36
        height: Math.max(1, items.length) * bar.pipStep - Theme.s4
        Rectangle {
            id: blk
            x: 4; width: 28; height: 28; radius: Theme.rFrame
            y: Math.max(0, col.current) * bar.pipStep
            color: Theme.pencil
            opacity: col.current >= 0 ? 1 : 0
            Behavior on y { enabled: !Theme.reducedMotion && blk.opacity > 0; SpringAnimation { spring: 4.2; damping: 0.36; epsilon: 0.2 } }
            Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
        }
        Repeater {
            model: Math.max(12, col.items.length)
            Item {
                id: row
                required property int index
                readonly property var it: col.items[index] ?? null
                readonly property real cover: blk.opacity * bar.clamp01(1 - Math.abs(blk.y - y) / 28)
                x: 4; y: index * bar.pipStep
                width: 28; height: 28
                opacity: it ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
                Rectangle {
                    anchors.fill: parent; radius: Theme.rFrame
                    color: !rowMouse.containsMouse || row.it === null || row.it.current ? "transparent"
                        : Theme.hover
                    Behavior on color { ColorAnimation { duration: Theme.tHover } }
                }
                Digit {
                    text: row.it ? row.it.label : ""
                    cover: row.cover
                    big: row.it && row.it.current ? row.cover : 0
                    rest: row.it && row.it.filled ? Theme.paper : Theme.fixer
                    hot: Theme.darkroom
                }
                // Pin: a spawned process tree is stuck to this frame.
                Glyph { anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: -3; anchors.topMargin: -5; visible: col.inRoll && row.it !== null && row.it.stuck; text: "󰐃"; size: 10; color: Theme.fixer }
                MouseArea {
                    id: rowMouse; anchors.fill: parent; hoverEnabled: true
                    enabled: row.it !== null
                    acceptedButtons: col.inRoll ? Qt.LeftButton : Qt.LeftButton | Qt.RightButton
                    onClicked: m => bar.goTo(row.it, m.button)
                    onContainsMouseChanged: bar.pipTip(row, row.it, containsMouse)
                }
            }
        }
    }

    readonly property real selTop: Theme.s12
    readonly property real topFull: Math.max(1, spaceItems.length) * pipStep - Theme.s4
    // The top group stops above the middle group; past that it clips and
    // scrolls. Its room is a function of the bar's height only.
    readonly property real topView: Math.max(0, Math.min(topFull, middle.y - groupGap - selTop))

    Item {
        id: topGroup
        anchors.horizontalCenter: parent.horizontalCenter
        y: bar.selTop
        width: 36; height: bar.topView
        Flickable {
            id: topFlick
            anchors.fill: parent
            clip: true
            interactive: false
            contentWidth: width; contentHeight: bar.topFull
            PipColumn { id: topCol; items: bar.spaceItems }
        }
        ScrollEdges { id: topEdges; anchors.fill: parent; flick: topFlick; step: bar.pipStep }
        // Keep the current workspace in view when it changes.
        function reveal() {
            const i = topCol.current;
            if (i < 0 || !topEdges.overflows) return;
            const y0 = i * bar.pipStep, y1 = y0 + 28;
            // One row of margin, so the current one never sits under a fade.
            const m = bar.pipStep;
            if (y0 - m < topFlick.contentY) topEdges.scrollTo(y0 - m, true);
            else if (y1 + m > topFlick.contentY + topFlick.height) topEdges.scrollTo(y1 + m - topFlick.height, true);
        }
        Connections { target: topCol; function onCurrentChanged() { topGroup.reveal(); } }
        onHeightChanged: { topEdges.scrollTo(topFlick.contentY, false); reveal(); }
    }

    // Middle group, centred on the bar. Every row is a 28 px cell, 4 px
    // apart inside a group and a hairline with 8 px either side between
    // groups, so the glyphs sit on one rhythm. Glyphs are one family
    // (Material Design from the Nerd Font) at 16 px; tray icons are drawn
    // flat in Paper at the same optical size so an app's own colour icon
    // does not break the set. Its height is a constant: the tray's slots are
    // reserved, and the tray's hairline fades rather than leaving the column.
    readonly property int traySlots: 4
    Column {
        id: middle
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((bar.height - height) / 2)
        spacing: Theme.s8

        // Launcher and clipboard history, both vicinae views.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.s4
            BarButton { glyph: "󰀻"; label: "Launcher"; onClicked: Quickshell.execDetached(["vicinae", "toggle"]) }
            BarButton { glyph: "󰅍"; label: "Clipboard history"; onClicked: Quickshell.execDetached(["vicinae", "cmd", "launch", "clipboard:history"]) }
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

        Hair { opacity: SystemTray.items.values.length > 0 ? 1 : 0 }

        // Tray: four reserved slots, filled from the top; an icon arriving
        // or leaving moves nothing around it. More than four scroll inside
        // the slots on the wheel (the soft edges and the wheel handler are
        // only there while they overflow, so otherwise the wheel reaches the
        // item). Left click activates (or opens the menu for menu-only
        // items), right click opens the menu beside the bar, middle click is
        // the secondary action, the wheel scrolls the item.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 32; height: bar.traySlots * bar.pipStep - Theme.s4
            Flickable {
                id: trayFlick
                anchors.fill: parent
                clip: true
                interactive: false
                contentWidth: width; contentHeight: trayGroup.height
                Column {
                    id: trayGroup
                    width: 32
                    spacing: Theme.s4
                    Repeater {
                        model: SystemTray.items
                        Pressable {
                            id: trayItem
                            required property var modelData
                            readonly property string label: modelData.tooltipTitle || modelData.title || modelData.id
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
            }
            ScrollEdges { id: trayEdges; anchors.fill: parent; flick: trayFlick; step: bar.pipStep; visible: overflows }
        }
    }

    // Bottom group: the locked roll stands on a fixed baseline above the
    // clock and grows upward; only its top edge moves. It takes the room
    // between the middle group and the baseline; a longer roll keeps its
    // head and scrolls its frames.
    readonly property int monoH: 20
    readonly property int lockH: 14
    readonly property int headH: monoH + lockH + Theme.s4
    readonly property real rollFull: headH + Math.max(1, railItems.length) * pipStep - Theme.s4
    readonly property real rollRoom: Math.max(headH + pipStep - Theme.s4,
        clock.y - Theme.s16 - (middle.y + middle.height + groupGap))

    Item {
        id: roll
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: clock.top; anchors.bottomMargin: Theme.s16
        width: 36
        height: Math.min(bar.rollFull, bar.rollRoom)
        // A short fade in place; nothing travels.
        opacity: bar.hasLock ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.tFast } }

        // The one "locked" mark: a thin Pencil rule down the roll's left edge.
        Rectangle {
            x: 0; y: 2
            width: 2; height: parent.height - 2
            radius: 1
            color: Theme.pencilDim
        }

        // The roll's initials; they cross-fade when the lock moves to
        // another roll.
        Item {
            id: monogram
            readonly property string text: Services.Hyprnav.monogramFor(bar.railEnv)
            property bool flip: false
            x: 4; width: 32; height: bar.monoH
            onTextChanged: {
                if (!flip && ma.text === text || flip && mb.text === text) return;
                if (flip) ma.text = text; else mb.text = text;
                flip = !flip;
            }
            Component.onCompleted: ma.text = text
            Text {
                id: ma
                anchors.centerIn: parent; color: Theme.pencilDim; opacity: monogram.flip ? 0 : 1
                font.family: Theme.casual; font.pixelSize: Theme.fs13
                Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
            }
            Text {
                id: mb
                anchors.centerIn: parent; color: Theme.pencilDim; opacity: monogram.flip ? 1 : 0
                font.family: Theme.casual; font.pixelSize: Theme.fs13
                Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
            }
        }
        Glyph {
            x: 4; width: 32; y: bar.monoH; height: bar.lockH
            horizontalAlignment: Text.AlignHCenter
            text: "󰌾"; size: 10; color: Theme.fixer; opacity: 0.7
        }

        Item {
            id: rollFrames
            y: bar.headH
            width: 36; height: parent.height - y
            Flickable {
                id: rollFlick
                anchors.fill: parent
                clip: true
                interactive: false
                contentWidth: width; contentHeight: rollCol.height
                PipColumn { id: rollCol; items: bar.railItems; inRoll: true }
            }
            ScrollEdges { id: rollEdges; anchors.fill: parent; flick: rollFlick; step: bar.pipStep }
            function reveal() {
                const i = rollCol.current;
                if (i < 0 || !rollEdges.overflows) return;
                const y0 = i * bar.pipStep, y1 = y0 + 28;
                if (y0 < rollFlick.contentY) rollEdges.scrollTo(y0, true);
                else if (y1 > rollFlick.contentY + rollFlick.height) rollEdges.scrollTo(y1 - rollFlick.height, true);
            }
            Connections { target: rollCol; function onCurrentChanged() { rollFrames.reveal(); } }
            onHeightChanged: { rollEdges.scrollTo(rollFlick.contentY, false); reveal(); }
        }

        // Monogram and lock: unlock.
        MouseArea {
            id: headArea
            width: parent.width; height: bar.headH
            hoverEnabled: true
            enabled: bar.hasLock
            onClicked: Services.Hyprnav.unlock()
            onContainsMouseChanged: containsMouse ? bar.tip(monogram, bar.railTitle + " (locked)\nClick to unlock") : bar.untip()
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
