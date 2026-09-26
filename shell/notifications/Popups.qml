pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../services" as Services
import ".."

PanelWindow {
    id: win
    required property var modelData
    screen: modelData
    property bool suppressed: false
    // Only one screen shows popups: the focused one (see shell.qml).
    property bool primary: true
    visible: primary && Services.Notifs.popups.length > 0 && !suppressed
    anchors { top: true; right: true }
    margins { top: 12; right: 12 }
    implicitWidth: 380
    implicitHeight: Math.max(1, col.implicitHeight)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprnav-shell-notifications"

    Column {
        id: col
        width: parent.width
        spacing: Theme.s8
        add: Transition { NumberAnimation { properties: "opacity"; from: 0; to: 1; duration: Theme.tRise } NumberAnimation { properties: "x"; from: 24; to: 0; duration: Theme.tRise; easing.type: Easing.OutCubic } }
        Repeater {
            model: Services.Notifs.popups
            NotificationCard { required property var modelData; notification: modelData; width: col.width }
        }
    }
}
