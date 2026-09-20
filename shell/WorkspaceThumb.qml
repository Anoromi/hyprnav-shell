pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

// Live miniature of one workspace: every window drawn where it sits, scaled
// to fit. Empty workspaces show the app icon that would open there, or nothing.
Item {
    id: root
    property int workspaceId: -1
    property bool live: true
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
        model: root.toplevels
        delegate: Item {
            id: winItem
            required property var modelData
            // Held rather than bound: Hyprland's toplevel cache hands out a new
            // IPC object on every refresh, and re-reading `wayland` through it
            // would restart the capture for nothing.
            readonly property var wayland: modelData.wayland
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
                color: Theme.emulsion
                ScreencopyView {
                    id: view
                    anchors.fill: parent
                    // Only hold a capture while the overlay is shown; a captured
                    // toplevel that closes while bound kills the Wayland connection.
                    // Rebinding this restarts the capture and blanks the frame,
                    // so it changes only when the window itself does.
                    captureSource: root.live ? winItem.wayland : null
                    live: root.live
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
            color: Theme.fixer
            font.family: Theme.sans
            font.pixelSize: Theme.fs13
        }
    }
}
