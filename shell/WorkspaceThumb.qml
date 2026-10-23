pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

// Miniature of one workspace: every window drawn where it sits, scaled to
// fit, from one still frame per window. Empty workspaces show the app icon
// that would open there, or nothing.
//
// The frames are stills on purpose. A running capture re-arms on every frame
// for as long as it is bound, and Quickshell 0.3.1 can send one of those
// re-arms for a window the compositor has already closed; that is a fatal
// Wayland error ("invalid object") that takes the whole shell down
// (quickshell#1123, seen here on 2026-09-27 and 2026-10-12). Each running
// capture also holds buffers and their fds; many at once ran the shell out
// of fds (2026-10-06). A still is one request at bind time and nothing after.
Item {
    id: root
    property int workspaceId: -1
    // The overlay is up (or fading out) and this miniature is on screen. Only
    // then does a window hold its frame; dropping it frees the buffers.
    property bool shown: false
    property string fallbackClass: ""
    property string emptyText: ""

    readonly property var workspace: Hyprland.workspaces.values.find(w => w.id === root.workspaceId) ?? null
    readonly property var toplevels: workspace ? workspace.toplevels.values : []
    readonly property bool empty: toplevels.length === 0

    // Bounding box of all windows, so stale geometry from a never-shown
    // workspace still produces a sensible miniature.
    readonly property var bbox: {
        let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9, any = false;
        for (const t of toplevels) {
            const o = t.lastIpcObject; if (!o || !o.at || !o.size) continue;
            any = true;
            x0 = Math.min(x0, o.at[0]); y0 = Math.min(y0, o.at[1]);
            x1 = Math.max(x1, o.at[0] + o.size[0]); y1 = Math.max(y1, o.at[1] + o.size[1]);
        }
        if (!any) return { x: 0, y: 0, w: 1920, h: 1080 };
        return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) };
    }
    readonly property real fit: Math.min(width / bbox.w, height / bbox.h)
    readonly property real ox: (width - bbox.w * fit) / 2
    readonly property real oy: (height - bbox.h * fit) / 2

    Repeater {
        // Diffed, so a workspace event that hands back the same windows keeps
        // their items instead of rebuilding every miniature.
        model: ScriptModel { values: root.toplevels }
        delegate: Item {
            id: winItem
            required property var modelData
            // Held rather than bound: Hyprland's toplevel cache hands out a new
            // IPC object on every refresh, and re-reading `wayland` through it
            // would restart the capture for nothing.
            readonly property var wayland: modelData.wayland
            // Hyprland's `closewindow` reaches us on the IPC socket before the
            // toplevel's `closed` is handled on the Wayland connection. Drop
            // the capture right then: a live capture that re-arms on a closed
            // toplevel sends a request on an object the compositor already
            // destroyed, and that is a fatal protocol error ("invalid object")
            // that takes the whole shell down.
            readonly property string address: String(modelData.address).replace(/^0x/, "")
            property bool gone: false
            Connections {
                target: Hyprland
                enabled: root.shown && !winItem.gone
                function onRawEvent(ev) {
                    if (ev.name === "closewindow" && ev.data.replace(/^0x/, "") === winItem.address) winItem.gone = true;
                }
            }
            readonly property var o: modelData.lastIpcObject
            readonly property bool placed: !!(o && o.at && o.size)
            x: placed ? root.ox + (o.at[0] - root.bbox.x) * root.fit : 0
            y: placed ? root.oy + (o.at[1] - root.bbox.y) * root.fit : 0
            width: placed ? o.size[0] * root.fit : root.width
            height: placed ? o.size[1] * root.fit : root.height
            ClippingRectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 2
                color: Theme.oEmulsion
                ScreencopyView {
                    id: view
                    anchors.fill: parent
                    // Binding the source takes one frame; `live: false` never
                    // asks for another, so the still stays until the overlay
                    // hides or the window closes, and then the source drops.
                    // Rebinding takes a new frame and blanks the old one, so
                    // the source changes only when the window itself does.
                    captureSource: root.shown && !winItem.gone ? winItem.wayland : null
                    live: false
                    paintCursor: false
                }
                IconImage {
                    anchors.centerIn: parent
                    visible: !view.hasContent
                    implicitSize: Math.min(parent.width, parent.height) * 0.35
                    source: Theme.appIcon(winItem.modelData.lastIpcObject?.class ?? "")
                }
            }
        }
    }

    // Empty frame
    Column {
        anchors.centerIn: parent
        spacing: Theme.s8
        visible: root.empty
        IconImage {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.fallbackClass !== ""
            implicitSize: Math.min(root.width, root.height) * 0.3
            source: Theme.appIcon(root.fallbackClass)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.emptyText !== ""
            text: root.emptyText
            color: Theme.oFixer
            font.family: Theme.sans
            font.pixelSize: Theme.fs13
        }
    }
}
