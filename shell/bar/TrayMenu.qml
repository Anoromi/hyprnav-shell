pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."

// A tray item's dbusmenu drawn as a small sheet beside the bar. Submenus
// open in place with a back row on top. A click outside closes it.
PopupWindow {
    id: menu
    property var item: null                 // SystemTrayItem whose menu is open
    property var stack: []                  // submenu entries, innermost last
    property real atY: 0
    required property var bar

    function open(trayItem, y) { stack = []; atY = y; item = trayItem; visible = true; }
    function close() { visible = false; }
    onVisibleChanged: if (!visible) { item = null; stack = []; }

    anchor.window: bar
    anchor.rect.x: bar.width + 4
    anchor.rect.y: atY
    grabFocus: true
    implicitWidth: 240
    implicitHeight: col.implicitHeight + Theme.s12
    color: "transparent"

    QsMenuOpener {
        id: opener
        menu: menu.stack.length > 0 ? menu.stack[menu.stack.length - 1] : (menu.item ? menu.item.menu : null)
    }

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Theme.sheet
        border.color: Theme.emulsion
        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 0
            // Back row inside a submenu.
            Rectangle {
                visible: menu.stack.length > 0
                Layout.fillWidth: true; implicitHeight: 28; radius: 4
                color: backMouse.containsMouse ? Theme.emulsion : "transparent"
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: Theme.s8; anchors.rightMargin: Theme.s8; spacing: Theme.s8
                    Glyph { text: "󰅁"; size: 13; color: Theme.fixer }
                    Text { text: menu.stack.length > 0 ? menu.stack[menu.stack.length - 1].text : ""; color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13; Layout.fillWidth: true; elide: Text.ElideRight }
                }
                MouseArea { id: backMouse; anchors.fill: parent; hoverEnabled: true; onClicked: menu.stack = menu.stack.slice(0, -1) }
            }
            Repeater {
                model: opener.children
                Item {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: modelData.isSeparator ? 9 : 28
                    Rectangle { visible: row.modelData.isSeparator; anchors.centerIn: parent; width: parent.width - 12; height: 1; color: Theme.emulsion }
                    Rectangle {
                        visible: !row.modelData.isSeparator
                        anchors.fill: parent; radius: 4
                        color: rowMouse.containsMouse && row.modelData.enabled ? Theme.emulsion : "transparent"
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: Theme.s8; anchors.rightMargin: Theme.s8; spacing: Theme.s8
                            // Check or radio state, else the entry's icon, else nothing.
                            Item {
                                implicitWidth: 16; implicitHeight: 16
                                Rectangle {
                                    visible: row.modelData.buttonType !== QsMenuButtonType.None
                                    anchors.centerIn: parent; width: 12; height: 12
                                    radius: row.modelData.buttonType === QsMenuButtonType.RadioButton ? 6 : 2
                                    color: row.modelData.checkState === Qt.Checked ? Theme.pencil : "transparent"
                                    border.color: row.modelData.checkState === Qt.Checked ? Theme.pencil : Theme.fixer
                                }
                                IconImage {
                                    visible: row.modelData.buttonType === QsMenuButtonType.None && row.modelData.icon !== ""
                                    anchors.fill: parent; source: row.modelData.icon
                                }
                            }
                            Text {
                                text: row.modelData.text.replace(/_([^_])/g, "$1")   // strip mnemonics
                                color: row.modelData.enabled ? Theme.paper : Theme.fixer
                                font.family: Theme.sans; font.pixelSize: Theme.fs13
                                Layout.fillWidth: true; elide: Text.ElideRight
                            }
                            Glyph { visible: row.modelData.hasChildren; text: "󰅂"; size: 13; color: Theme.fixer }
                        }
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent; hoverEnabled: true
                            enabled: row.modelData.enabled
                            onClicked: {
                                if (row.modelData.hasChildren) { menu.stack = menu.stack.concat([row.modelData]); return; }
                                row.modelData.triggered();
                                menu.close();
                            }
                        }
                    }
                }
            }
        }
    }
}
