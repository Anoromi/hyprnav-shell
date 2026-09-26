pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../services" as Services
import "../bar"
import ".."

// The session's notifications, grouped by app, in one sheet beside the bar.
// Opens from the bar's bell or `qs ipc call center toggle`. Opening marks
// everything as seen; do not disturb lives in the header.
SheetWindow {
    id: win
    required property var modelData
    screen: modelData
    property var expanded: ({})             // app name -> true when the group shows all
    readonly property int perGroup: 3
    // Bumps on every open; entries replay their staggered rise when it changes.
    property int openCount: 0

    anchors { top: true; bottom: true; left: true }
    margins { top: 8; bottom: 8; left: 52 }
    implicitWidth: 400
    sheetHeight: head.implicitHeight + Math.min(list.contentHeight, 640) + Theme.s24 + Theme.s12
    WlrLayershell.namespace: "hyprnav-shell-notification-center"

    PerfProbe { id: perf; label: "center" }
    onOpened: { perf.arm("open"); openCount++; Services.Notifs.markSeen(); }
    onDismissed: Services.Notifs.markSeen()

    ColumnLayout {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.s12 }
        spacing: Theme.s12

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.s8
            Text { text: "Notifications"; color: Theme.paper; font.family: Theme.casual; font.pixelSize: Theme.fs18; font.weight: Font.Medium }
            Text { visible: Services.Notifs.count > 0; text: Services.Notifs.count; color: Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs13; Layout.alignment: Qt.AlignBaseline }
            Item { Layout.fillWidth: true }
            Text {
                visible: Services.Notifs.count > 0
                text: "Clear all"; color: clearMouse.containsMouse ? Theme.paper : Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13
                MouseArea { id: clearMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: Services.Notifs.clearAll() }
            }
        }

        // Do not disturb: popups are held back, the centre still fills.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: dndRow.implicitHeight + Theme.s16
            radius: Theme.rControl
            color: Services.Notifs.dnd ? Theme.emulsion : "transparent"
            border.color: Theme.emulsion
            Behavior on color { ColorAnimation { duration: Theme.tFast } }
            RowLayout {
                id: dndRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.s8; rightMargin: Theme.s8 }
                spacing: Theme.s8
                Glyph { text: Services.Notifs.dnd ? "󰂛" : "󰂚"; size: 17; color: Services.Notifs.dnd ? Theme.pencil : Theme.paper }
                Column {
                    Layout.fillWidth: true
                    Text { text: "Do not disturb"; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13 }
                    Text { text: Services.Notifs.dnd ? "Popups held back. Urgent ones still show." : "Popups show as they arrive."; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12 }
                }
                Toggle { on: Services.Notifs.dnd; onToggled: Services.Notifs.setDnd(!Services.Notifs.dnd) }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.emulsion }

        Text {
            visible: Services.Notifs.count === 0
            text: "Nothing yet. Notifications from this session collect here."
            color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13
            wrapMode: Text.Wrap; Layout.fillWidth: true
        }
    }

    Flickable {
        id: list
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom; margins: Theme.s12; topMargin: Theme.s12 }
        contentHeight: groupsCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: groupsCol
            width: list.width
            spacing: Theme.s16
            Repeater {
                model: Services.Notifs.groups
                Column {
                    id: group
                    required property var modelData
                    required property int index
                    readonly property bool open: win.expanded[modelData.app] === true
                    readonly property int hidden: Math.max(0, modelData.entries.length - win.perGroup)
                    width: groupsCol.width
                    spacing: Theme.s4

                    RowLayout {
                        id: groupHead
                        width: parent.width
                        spacing: Theme.s8
                        // Rises with the group's first card, one stagger step ahead.
                        property real appear: 1
                        opacity: appear
                        transform: Translate { y: (1 - groupHead.appear) * Theme.riseDistance * 0.66 }
                        SequentialAnimation {
                            id: headRise
                            PropertyAction { target: groupHead; property: "appear"; value: 0 }
                            PauseAnimation { duration: Math.min(group.index * 4, 12) * Theme.tStaggerList }
                            NumberAnimation { target: groupHead; property: "appear"; to: 1; duration: Theme.tRise; easing.type: Easing.OutCubic }
                        }
                        Connections { target: win; function onOpenCountChanged() { headRise.restart(); } }
                        // App icon when the theme has one, else the app's initial.
                        Item {
                            readonly property string icon: {
                                const name = group.modelData.icon;
                                if (name && name.startsWith("/")) return "file://" + name;
                                if (name) { const p = Quickshell.iconPath(name, true); if (p) return p; }
                                const entry = DesktopEntries.heuristicLookup(group.modelData.app);
                                return entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : "";
                            }
                            implicitWidth: 16; implicitHeight: 16
                            IconImage { anchors.fill: parent; visible: parent.icon !== ""; source: parent.icon }
                            Rectangle {
                                anchors.fill: parent; radius: 3; color: Theme.emulsion; visible: parent.icon === ""
                                Text { anchors.centerIn: parent; text: group.modelData.app.charAt(0).toUpperCase(); color: Theme.paper; font.family: Theme.mono; font.pixelSize: 11; font.weight: Font.Bold }
                            }
                        }
                        Text { text: group.modelData.app; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13; font.weight: Font.Medium; elide: Text.ElideRight; Layout.maximumWidth: 240 }
                        Text { text: group.modelData.entries.length; color: Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs12 }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Clear"; color: grpClear.containsMouse ? Theme.paper : Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12
                            MouseArea { id: grpClear; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: Services.Notifs.clearApp(group.modelData.app) }
                        }
                    }
                    Repeater {
                        model: group.open ? group.modelData.entries : group.modelData.entries.slice(0, win.perGroup)
                        NotificationCard {
                            required property var modelData
                            required property int index
                            notification: modelData; compact: true; width: group.width
                            riseIndex: Math.min(group.index * 4 + index + 1, 12)
                            riseToken: win.openCount
                        }
                    }
                    Text {
                        visible: group.hidden > 0
                        text: group.open ? "Show fewer" : "Show " + group.hidden + " more"
                        color: moreMouse.containsMouse ? Theme.paper : Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12
                        MouseArea {
                            id: moreMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true
                            onClicked: { const e = Object.assign({}, win.expanded); e[group.modelData.app] = !group.open; win.expanded = e; }
                        }
                    }
                }
            }
        }
    }
}
