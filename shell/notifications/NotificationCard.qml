import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import "../services" as Services
import ".."

// One notification record (see services/Notifs.qml). `compact` is the centre's
// variant: no app name (the group header carries it), time instead.
Rectangle {
    id: card
    property var notification               // a record from Services.Notifs
    property bool compact: false
    // The live Notification while its sender keeps it; null afterwards.
    readonly property var live: (Services.Notifs.revision, notification ? notification.live : null)
    readonly property bool critical: notification && notification.urgency === NotificationUrgency.Critical
    // Pictures sent with the notification win; theme icons (including the
    // image://icon/ form) are looked up and dropped when the theme lacks them.
    function iconSource() {
        const n = notification; if (!n) return "";
        const img = n.image || "";
        if (img !== "" && !img.startsWith("image://icon/")) return img;
        const name = img !== "" ? img.slice("image://icon/".length) : n.appIcon;
        if (!name) return "";
        if (name.startsWith("/")) return "file://" + name;
        if (name.startsWith("file://")) return name;
        return Quickshell.iconPath(name, true);
    }
    // Motion: a staggered rise when the centre opens (riseToken bumps, the
    // card waits riseIndex stagger steps), and on dismiss a slide out to the
    // right, then the gap closes.
    property int riseIndex: 0
    property int riseToken: 0
    property real appear: 1
    property real collapse: 1
    onRiseTokenChanged: rise.restart()
    function leave(then) { if (!leaving.running) { leaving.then = then; leaving.start(); } }
    SequentialAnimation {
        id: rise
        PropertyAction { target: card; property: "appear"; value: 0 }
        PauseAnimation { duration: card.riseIndex * Theme.tStaggerList }
        NumberAnimation { target: card; property: "appear"; to: 1; duration: Theme.tRise; easing.type: Easing.OutCubic }
    }
    SequentialAnimation {
        id: leaving
        property var then: null
        ParallelAnimation {
            NumberAnimation { target: slide; property: "x"; to: card.width * 0.6; duration: Theme.tRise; easing.type: Easing.InCubic }
            NumberAnimation { target: card; property: "appear"; to: 0; duration: Theme.tRise; easing.type: Easing.InCubic }
        }
        NumberAnimation { target: card; property: "collapse"; to: 0; duration: Theme.tClose; easing.type: Easing.OutCubic }
        ScriptAction { script: if (leaving.then) leaving.then() }
    }
    opacity: appear
    transform: Translate { id: slide; y: (1 - card.appear) * Theme.riseDistance * 0.66 * (card.collapse < 1 || slide.x > 0 ? 0 : 1) }
    clip: collapse < 1
    implicitHeight: (body.implicitHeight + Theme.s16) * collapse
    radius: Theme.rControl
    color: compact ? Theme.emulsion : Theme.sheet
    border.color: critical ? Theme.warn : (compact ? "transparent" : Theme.emulsion)
    RowLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.s8 }
        spacing: Theme.s8
        IconImage {
            visible: !card.compact && source.toString() !== ""
            implicitSize: 28
            Layout.alignment: Qt.AlignTop
            source: card.iconSource()
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                Text { text: card.live ? card.live.summary : (card.notification ? card.notification.summary : ""); color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13; font.weight: Font.Medium; Layout.fillWidth: true; elide: Text.ElideRight }
                Text {
                    text: !card.notification ? "" : card.compact ? Qt.formatDateTime(new Date(card.notification.time), "HH:mm") : card.notification.appName
                    color: Theme.fixer; font.family: card.compact ? Theme.mono : Theme.sans; font.pixelSize: Theme.fs12
                }
            }
            Text {
                visible: text !== ""
                text: card.live ? card.live.body : (card.notification ? card.notification.body : "")
                color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13
                wrapMode: Text.Wrap; Layout.fillWidth: true
                maximumLineCount: card.compact ? 2 : 4; elide: Text.ElideRight; textFormat: Text.StyledText
            }
            Row {
                visible: card.live !== null && card.live.actions.length > 0
                spacing: Theme.s8
                Repeater {
                    model: card.live ? card.live.actions : []
                    Rectangle {
                        required property var modelData
                        width: actText.implicitWidth + 16; height: 24; radius: 6
                        color: actMouse.containsMouse ? Theme.pencil : Theme.darkroom
                        Text { id: actText; anchors.centerIn: parent; text: parent.modelData.text; color: actMouse.containsMouse ? Theme.darkroom : Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs12 }
                        MouseArea { id: actMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { parent.modelData.invoke(); card.leave(() => Services.Notifs.dismiss(card.notification)); } }
                    }
                }
            }
        }
        Glyph {
            text: "󰅖"; size: 13; color: closeMouse.containsMouse ? Theme.paper : Theme.fixer
            Layout.alignment: Qt.AlignTop
            MouseArea { id: closeMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: card.leave(() => Services.Notifs.dismiss(card.notification)) }
        }
    }
}
