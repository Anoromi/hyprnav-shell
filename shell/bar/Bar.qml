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

// Left edge column, like the edge of a film strip: the screen's workspace
// numbers run down from the top, and while hyprnav holds a lock the locked
// roll's frame numbers sit on a pencil rail in the middle. The bottom stacks,
// from the top: launcher and clipboard, tray, the notification bell, the
// system cluster (opens quick settings), the clock.
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

    // Top: the workspace selector, two groups that are pure functions of
    // state and never share a row.
    //
    // At the top, every Hyprland workspace on this screen with an id from 1
    // to 99, in id order: the current one in a Pencil block, occupied ones
    // Paper, empty ones Fixer. Specials and hyprnav's managed workspaces
    // (100 and up) never get a pip. Clicking one goes there; right-clicking
    // one that belongs to a roll locks that roll. The group is always there
    // and never moves; when it is taller than the room left it clips and
    // scrolls on the wheel, with soft edges.
    //
    // At a fixed place near the middle of the bar, only while hyprnav holds
    // a lock: the locked roll's monogram over its numbered frames on a Pencil
    // rail with a lock at its head, digits Darkroom, the frame on screen
    // inverted to a Darkroom block. It fades in place when a lock appears and
    // goes when it is dropped (160 ms, ease out cubic). Clicking a frame goes
    // there, clicking the monogram or the lock unlocks. The workspace on
    // screen can show in both groups and is marked in both.
    //
    // The rail's head never moves (see TESTING.md, "No layout shifts"): its
    // y is a function of the bar's height only, so the workspace list above,
    // the tray and the clock below, a lock change and the roll's length all
    // leave it where it is. A roll grows and shrinks downward from the head;
    // the list above clips and scrolls at the head instead of pushing it.
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
    // Held while the middle group fades out, so it leaves with what it showed.
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
    readonly property color dimDarkroom: Qt.rgba(0.102, 0.098, 0.090, 0.55)

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

    // A column of numbers with one block for the current one, on the bare
    // bar (Pencil block, Paper digits) or on the rail (Darkroom block,
    // Darkroom digits). Rows are fixed and spare ones kept, so a new
    // workspace fades into an existing row instead of rebuilding the column.
    component PipColumn: Item {
        id: col
        property var items: []
        property bool onRail: false
        readonly property int current: items.findIndex(s => s.current)
        width: 36
        height: Math.max(1, items.length) * bar.pipStep - Theme.s4
        Rectangle {
            id: blk
            x: 4; width: 28; height: 28; radius: Theme.rFrame
            y: Math.max(0, col.current) * bar.pipStep
            color: col.onRail ? Theme.darkroom : Theme.pencil
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
                        : (col.onRail ? Qt.rgba(0.102, 0.098, 0.090, 0.14) : Theme.hover)
                    Behavior on color { ColorAnimation { duration: Theme.tHover } }
                }
                Digit {
                    text: row.it ? row.it.label : ""
                    cover: row.cover
                    big: row.it && row.it.current ? row.cover : 0
                    rest: col.onRail ? (row.it && !row.it.filled ? bar.dimDarkroom : Theme.darkroom)
                        : (row.it && row.it.filled ? Theme.paper : Theme.fixer)
                    hot: col.onRail ? Theme.pencil : Theme.darkroom
                }
                // Pin: a spawned process tree is stuck to this frame.
                Glyph { anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: -3; anchors.topMargin: -5; visible: col.onRail && row.it !== null && row.it.stuck; text: "󰐃"; size: 12; color: Theme.darkroom }
                MouseArea {
                    id: rowMouse; anchors.fill: parent; hoverEnabled: true
                    enabled: row.it !== null
                    acceptedButtons: col.onRail ? Qt.LeftButton : Qt.LeftButton | Qt.RightButton
                    onClicked: m => bar.goTo(row.it, m.button)
                    onContainsMouseChanged: bar.pipTip(row, row.it, containsMouse)
                }
            }
        }
    }

    // Room for the selector: from the top margin to above the bottom stack.
    readonly property real selTop: Theme.s12
    readonly property real selBottom: bottomStack.y - Theme.s12
    // The middle group's full height: monogram, rail head, frames.
    readonly property int monoH: 24
    readonly property int lockH: 18
    readonly property int railY0: monoH + Theme.s4
    readonly property int framesY: lockH + Theme.s4          // inside the rail
    readonly property int headH: railY0 + framesY
    readonly property real midFull: headH + railItems.length * pipStep
    // The middle group's anchor: a four-frame roll sits centred on the bar.
    // It depends on the bar's height alone. On a bar too short for that it
    // moves up just enough to keep the head and one frame above the fixed
    // part of the bottom stack (everything but the tray, which grows upward
    // into the rail's room instead), and never above two workspace rows.
    readonly property real midTop: {
        const centred = Math.round((height - (headH + 4 * pipStep)) / 2);
        const low = fixedStackTop - Theme.s12 - headH - pipStep;
        const high = selTop + 2 * pipStep - Theme.s4 + groupGap;
        return Math.max(high, Math.min(centred, low));
    }
    // Top of the bottom stack without the tray and its hairline.
    readonly property real fixedStackTop: bottomStack.y
        + (trayGroup.visible ? trayGroup.height + 2 * bottomStack.spacing + 1 : 0)
    // The middle group keeps its room while it fades out.
    readonly property bool midReserved: hasLock || mid.opacity > 0
    readonly property real topFull: Math.max(1, spaceItems.length) * pipStep - Theme.s4
    // The top group stops above the rail's head while a lock is shown, and
    // above the bottom stack otherwise; past that it clips and scrolls.
    readonly property real topView: Math.max(0, Math.min(topFull,
        (midReserved ? midTop - groupGap : selBottom) - selTop))

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

    Item {
        id: mid
        // 0 absent, 1 shown: fades and grows in place.
        property real shown: bar.hasLock ? 1 : 0
        Behavior on shown { NumberAnimation { duration: Theme.tLock; easing.type: Easing.OutCubic } }
        // Fixed head; the frames below it clip and scroll once the bottom
        // stack (a growing tray) takes their room.
        readonly property real room: Math.max(bar.headH + bar.pipStep, bar.selBottom - y)
        anchors.horizontalCenter: parent.horizontalCenter
        width: 36
        height: Math.min(bar.midFull, room)
        y: bar.midTop
        visible: opacity > 0
        opacity: shown
        // Appears from its head: it grows down, never around its centre.
        scale: bar.lerp(0.96, 1, shown)
        transformOrigin: Item.Top
        // A roll change while locked eases the column to its new length,
        // downward from the head.
        Behavior on height { enabled: mid.shown === 1; NumberAnimation { duration: Theme.tLock; easing.type: Easing.OutCubic } }

        // The roll's initials; they cross-fade when the lock moves to
        // another roll.
        Item {
            id: monogram
            readonly property string text: Services.Hyprnav.monogramFor(bar.railEnv)
            property bool flip: false
            anchors.horizontalCenter: parent.horizontalCenter
            width: 36; height: bar.monoH
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

        Rectangle {
            id: rail
            y: bar.railY0
            width: 36; height: parent.height - y
            radius: Theme.rSheet - 2
            color: Theme.pencil
            Glyph {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.s4; height: bar.lockH - 2
                text: "󰌾"; size: 13; color: Theme.darkroom
            }
            Item {
                id: railFrames
                y: bar.framesY
                width: 36; height: parent.height - y - Theme.s4
                Flickable {
                    id: railFlick
                    anchors.fill: parent
                    clip: true
                    interactive: false
                    contentWidth: width; contentHeight: railCol.height
                    PipColumn { id: railCol; items: bar.railItems; onRail: true }
                }
                ScrollEdges { anchors.fill: parent; flick: railFlick; step: bar.pipStep; fadeColor: Theme.pencil }
            }
        }

        // Monogram and lock: unlock.
        MouseArea {
            id: headArea
            width: parent.width; height: bar.railY0 + bar.framesY
            hoverEnabled: true
            enabled: bar.hasLock
            onClicked: Services.Hyprnav.unlock()
            onContainsMouseChanged: containsMouse ? bar.tip(monogram, bar.railTitle + " (locked)\nClick to unlock") : bar.untip()
        }
    }

    // Bottom stack, above the clock, from the top: tray, launcher and
    // clipboard, the bell, the system cluster. Every row is a 28 px cell, 4 px apart
    // inside a group and a hairline with 8 px either side between groups, so
    // the glyphs sit on one rhythm. Glyphs are one family (Material Design
    // from the Nerd Font) at 16 px; tray icons are drawn flat in Paper at the
    // same optical size so an app's own colour icon does not break the set.
    Column {
        id: bottomStack
        anchors.bottom: clock.top; anchors.bottomMargin: Theme.s16
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.s8

        // The tray sits at the top of the stack: the stack hangs from the
        // clock, so items that come and go only grow it upward, into free
        // space, and never move the launcher, the bell or the cluster.
        // Tray: left click activates (or opens the menu for menu-only items),
        // right click opens the menu beside the bar, middle click is the
        // secondary action, the wheel scrolls the item.
        Column {
            id: trayGroup
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.s4
            visible: SystemTray.items.values.length > 0
            Repeater {
                model: SystemTray.items
                Pressable {
                    id: trayItem
                    required property var modelData
                    readonly property string label: modelData.tooltipTitle || modelData.title || modelData.id
                    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
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

        Hair { visible: SystemTray.items.values.length > 0 }

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
