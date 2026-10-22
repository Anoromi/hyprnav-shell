pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../services" as Services
import ".."
import "tabswitch.js" as TabSwitch

// Ctrl+Tab across every browser's tabs, most recently used first (see
// services/BrowserTabs.qml and tabs/mru.js).
//
// Hyprland routes Ctrl+Tab in a browser window here (global shortcuts
// `tabs-next`, `tabs-prev`) and the Ctrl release (`tabs-commit`). The first
// press picks the tab before the current one (Shift: the oldest) without
// drawing or taking the keyboard; a release within `tapTime` switches at
// once, so a quick Ctrl+Tab costs no frame. Held longer, a compact list shows
// at once (no fade in) and takes the keyboard: more Tabs step, Ctrl release,
// Enter or a click switch, Esc cancels. Nothing is previewed on the way.
// `tapTime` stays under what reads as a delay; a slower tap shows the list
// for a moment, which is cheaper than a list that lags every held Ctrl+Tab.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    property string phase: "closed"    // closed | pending | open | closing
    property bool open: false          // drawn and holding the keyboard
    property var items: []             // merged tabs, frozen for the cycle
    property int selected: 0
    readonly property int tapTime: 80
    readonly property var selectedItem: items[selected] ?? null

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprnav-shell-tabswitch"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: open ? null : nowhere
    Region { id: nowhere }

    function show(reverse) {
        if (phase === "pending" || phase === "open") { step(reverse ? -1 : 1); return; }
        const tabs = Services.BrowserTabs;
        // A browser without a host keeps its own Ctrl+Tab.
        if (tabs.passNativeTab(reverse)) return;
        const list = tabs.mruTabs();
        if (list.length < 2) return;
        items = list;
        selected = TabSwitch.start(list.length, reverse);
        finish.stop();
        phase = "pending";
        tap.restart();
    }
    function step(dir) {
        if (phase !== "pending" && phase !== "open") return;
        selected = TabSwitch.step(selected, dir, items.length);
    }
    Timer {
        id: tap
        interval: win.tapTime
        onTriggered: if (win.phase === "pending") { win.phase = "open"; win.open = true; keys.forceActiveFocus(); }
    }
    // Every way of committing lands here, often twice for one release (the
    // global shortcut and the key itself); only the first counts.
    function commit() {
        if (phase !== "pending" && phase !== "open") return;
        const item = selectedItem;
        const drawn = phase === "open";
        close();
        if (!item) return;
        // Hand the keyboard back before the browser window takes the focus,
        // as the workspace switcher does.
        if (drawn) afterRelease.run(() => Services.BrowserTabs.activate(item.id));
        else Services.BrowserTabs.activate(item.id);
    }
    function cancel() { if (phase === "pending" || phase === "open") close(); }
    function close() {
        tap.stop();
        phase = "closing";
        open = false;
        finish.interval = Theme.tSnap;
        finish.restart();
    }
    Timer { id: finish; onTriggered: { win.phase = "closed"; win.items = []; } }
    FocusRelease { id: afterRelease }

    // Rows on screen at once; the window slides to keep the selection in it.
    readonly property int rowH: 40
    readonly property int maxRows: Math.max(3, Math.min(12, Math.floor((height * 0.7) / rowH)))
    readonly property int shownRows: Math.min(items.length, maxRows)
    readonly property int firstRow: Math.max(0, Math.min(selected - Math.floor(shownRows / 2), items.length - shownRows))
    readonly property bool manyBrowsers: (Services.BrowserTabs.snapshot?.browsers ?? []).length > 1

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: ev => {
            if (ev.key === Qt.Key_Tab || ev.key === Qt.Key_Down) { win.step(1); ev.accepted = true; }
            else if (ev.key === Qt.Key_Backtab || ev.key === Qt.Key_Up) { win.step(-1); ev.accepted = true; }
            else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { win.commit(); ev.accepted = true; }
            else if (ev.key === Qt.Key_Escape) { win.cancel(); ev.accepted = true; }
        }
        Keys.onReleased: ev => { if (ev.key === Qt.Key_Control && !ev.isAutoRepeat) { win.commit(); ev.accepted = true; } }
        MouseArea { anchors.fill: parent; enabled: win.open; onClicked: win.cancel() }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: win.open ? 1 : 0
        visible: opacity > 0
        // Fades out only: the list is there on the first frame.
        // `phase` changes before `open` does, so this is settled first.
        Behavior on opacity { enabled: win.phase === "closing"; NumberAnimation { duration: Theme.tSnap } }

        Rectangle {
            id: sheet
            width: Math.min(560, win.width - Theme.s32 * 2)
            height: win.shownRows * win.rowH + Theme.s8 * 2
            anchors.centerIn: parent
            radius: Theme.rSheet
            color: Theme.oSheet
            border.width: 1
            border.color: Qt.rgba(Theme.oPaper.r, Theme.oPaper.g, Theme.oPaper.b, 0.18)
            clip: true

            Repeater {
                model: win.items.slice(win.firstRow, win.firstRow + win.shownRows)
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property int at: win.firstRow + index
                    readonly property bool isSelected: at === win.selected
                    readonly property string host: (/^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i.exec(modelData.url || "") || ["", ""])[1].replace(/^www\./, "")
                    readonly property string icon: (Services.BrowserTabs.snapshot?.icons ?? {})[modelData.icon] || ""
                    x: Theme.s8; y: Theme.s8 + index * win.rowH
                    width: sheet.width - Theme.s8 * 2; height: win.rowH

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rSheet
                        visible: row.isSelected
                        color: Qt.rgba(Theme.oPencil.r, Theme.oPencil.g, Theme.oPencil.b, 0.12)
                        border.color: Theme.oPencil
                        border.width: Theme.ringWidth
                    }
                    // Only data the browser handed over: the shell never fetches a site.
                    Item {
                        id: iconBox
                        x: Theme.s8 + 2; anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 18
                        Image {
                            id: img
                            anchors.fill: parent
                            source: row.icon.indexOf("data:") === 0 ? row.icon : ""
                            sourceSize.width: 36; sourceSize.height: 36
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: img.status !== Image.Ready
                            text: (row.host || row.modelData.title || "?").charAt(0).toUpperCase()
                            color: Theme.oFixer
                            font.family: Theme.sans; font.pixelSize: Theme.fs12; font.weight: Font.Medium
                        }
                    }
                    Text {
                        id: titleText
                        anchors.verticalCenter: parent.verticalCenter
                        x: iconBox.x + iconBox.width + Theme.s8
                        width: Math.min(implicitWidth, trail.x - x - Theme.s8)
                        elide: Text.ElideRight
                        text: row.modelData.title || row.host || row.modelData.url
                        color: Theme.oPaper
                        font.family: Theme.sans; font.pixelSize: Theme.fs13
                        font.weight: row.isSelected ? Font.Medium : Font.Normal
                    }
                    Row {
                        id: trail
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right; anchors.rightMargin: Theme.s8 + 2
                        spacing: Theme.s8
                        Text {
                            width: Math.min(implicitWidth, 160)
                            elide: Text.ElideRight
                            text: row.host
                            color: Theme.oFixer
                            font.family: Theme.sans; font.pixelSize: Theme.fs12
                        }
                        Text {
                            visible: win.manyBrowsers
                            text: row.modelData.browser || ""
                            color: Theme.oFixer
                            font.family: Theme.sans; font.pixelSize: Theme.fs12; font.weight: Font.Medium
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: win.open
                        onClicked: { win.selected = row.at; win.commit(); }
                    }
                }
            }
        }
    }
}
