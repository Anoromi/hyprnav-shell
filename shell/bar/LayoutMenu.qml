pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../services" as Services
import ".."

// Keyboard layout picker beside the bar, level with the layout badge.
// Same SheetWindow surface and dismissal rules as TrayMenu: Esc, click-away,
// or picking a layout closes it.
SheetWindow {
    id: menu
    property real atY: 0
    required property var bar

    function open(y) {
        Services.Keyboard.refresh();
        atY = y;
        show();
    }

    screen: bar.screen
    anchors { top: true; bottom: true; left: true }
    margins { left: bar.width + 4 }
    implicitWidth: 220
    sheetHeight: col.implicitHeight + Theme.s12
    sheetTop: atY - 6
    fromTop: true
    WlrLayershell.namespace: "hyprnav-shell-layout-menu"

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
        spacing: 2

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.s8
            Layout.rightMargin: Theme.s8
            Layout.topMargin: 2
            Layout.bottomMargin: 4
            text: "Keyboard layout"
            color: Theme.fixer
            font.family: Theme.sans
            font.pixelSize: Theme.fs12
        }

        Repeater {
            model: Services.Keyboard.layouts
            Pressable {
                id: row
                required property var modelData
                readonly property bool isCurrent: Services.Keyboard.activeIndex === modelData.index
                Layout.fillWidth: true
                implicitHeight: 30
                active: isCurrent
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.s8
                    anchors.rightMargin: Theme.s8
                    spacing: Theme.s8
                    Text {
                        Layout.preferredWidth: 24
                        text: row.modelData.code
                        color: row.isCurrent ? Theme.pencil : Theme.fixer
                        font.family: Theme.mono
                        font.pixelSize: Theme.fs12
                        font.weight: row.isCurrent ? Font.Bold : Font.Normal
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.label
                        color: row.isCurrent ? Theme.paper : Theme.fixer
                        font.family: Theme.sans
                        font.pixelSize: Theme.fs13
                        font.weight: row.isCurrent ? Font.Medium : Font.Normal
                        elide: Text.ElideRight
                    }
                    Glyph {
                        visible: row.isCurrent
                        text: "󰄬"
                        size: 13
                        color: Theme.pencil
                    }
                }
                onClicked: {
                    Services.Keyboard.setLayout(row.modelData.index);
                    menu.close();
                }
            }
        }
    }
}
