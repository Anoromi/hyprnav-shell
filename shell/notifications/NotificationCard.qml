import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../services" as Services
import ".."

Rectangle {
    id: card
    property var notification
    property bool compact: false
    implicitHeight: body.implicitHeight + Theme.s16
    radius: 6
    color: compact ? Theme.emulsion : Theme.sheet
    border.color: compact ? "transparent" : Theme.emulsion
    RowLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.s8 }
        spacing: Theme.s8
        IconImage {
            visible: source.toString() !== ""
            implicitSize: 28
            Layout.alignment: Qt.AlignTop
            source: card.notification ? (card.notification.image || (card.notification.appIcon ? Quickshell.iconPath(card.notification.appIcon, "dialog-information") : "")) : ""
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                Text { text: card.notification ? card.notification.summary : ""; color: Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs13; font.weight: Font.Medium; Layout.fillWidth: true; elide: Text.ElideRight }
                Text { text: card.notification ? card.notification.appName : ""; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12 }
            }
            Text { visible: text !== ""; text: card.notification ? card.notification.body : ""; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13; wrapMode: Text.Wrap; Layout.fillWidth: true; maximumLineCount: card.compact ? 2 : 4; elide: Text.ElideRight; textFormat: Text.StyledText }
            Row {
                visible: card.notification && card.notification.actions.length > 0
                spacing: Theme.s8
                Repeater {
                    model: card.notification ? card.notification.actions : []
                    Rectangle {
                        required property var modelData
                        width: actText.implicitWidth + 16; height: 24; radius: 4
                        color: actMouse.containsMouse ? Theme.pencil : Theme.darkroom
                        Text { id: actText; anchors.centerIn: parent; text: parent.modelData.text; color: actMouse.containsMouse ? Theme.darkroom : Theme.paper; font.family: Theme.sans; font.pixelSize: Theme.fs12 }
                        MouseArea { id: actMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { parent.modelData.invoke(); Services.Notifs.dismiss(card.notification); } }
                    }
                }
            }
        }
        Glyph {
            text: "󰅖"; size: 13; color: closeMouse.containsMouse ? Theme.paper : Theme.fixer
            Layout.alignment: Qt.AlignTop
            MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: Services.Notifs.dismiss(card.notification) }
        }
    }
}
