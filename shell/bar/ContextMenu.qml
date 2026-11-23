pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

// Floating in-sheet context menu opened at the pointer inside a SheetWindow.
// Creates no extra Wayland surfaces or GL contexts; clamps inside the sheet
// bounds, eats outside clicks, and handles Esc / Up / Down / Return locally
// without dismissing the underlying sheet.
Item {
    id: menu
    anchors.fill: parent
    z: 50

    property bool shown: false
    property string title: ""
    property var items: []          // [{ label, glyph, danger, checked, enabled, separator, action }]
    property real anchorX: 0
    property real anchorY: 0
    property int highlighted: -1
    signal closed()

    function open(x, y, heading, entries) {
        title = heading || "";
        items = entries || [];
        anchorX = x;
        anchorY = y;
        highlighted = -1;
        shown = true;
        Qt.callLater(() => box.forceActiveFocus());
    }

    function close() {
        if (!shown) return;
        shown = false;
        highlighted = -1;
        closed();
    }

    function _selectableIndices() {
        const out = [];
        for (let i = 0; i < items.length; i++) {
            const it = items[i];
            if (it && !it.separator && it.enabled !== false) out.push(i);
        }
        return out;
    }

    function _step(dir) {
        const idx = _selectableIndices();
        if (idx.length === 0) return;
        const pos = idx.indexOf(highlighted);
        if (pos < 0) highlighted = dir > 0 ? idx[0] : idx[idx.length - 1];
        else highlighted = idx[(pos + dir + idx.length) % idx.length];
    }

    function _activate(entry) {
        if (!entry || entry.separator || entry.enabled === false) return;
        const fn = entry.action;
        close();
        if (typeof fn === "function") fn();
    }

    visible: shown || box.opacity > 0

    // Click-away catcher inside the sheet.
    MouseArea {
        anchors.fill: parent
        enabled: menu.shown
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        onPressed: menu.close()
        onWheel: {} // keep scroll from leaking behind the open menu
    }

    Rectangle {
        id: box
        readonly property real pad: Theme.s8
        width: 196
        height: col.implicitHeight + Theme.s8 + 4
        x: Math.max(pad, Math.min(menu.width - width - pad, menu.anchorX))
        y: Math.max(pad, Math.min(menu.height - height - pad, menu.anchorY))
        radius: Theme.rControl
        color: Theme.darkroom
        border.width: 1
        border.color: Theme.emulsion
        opacity: menu.shown ? 1 : 0
        scale: menu.shown ? 1 : 0.96
        transformOrigin: Item.TopLeft
        Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
        Behavior on scale { NumberAnimation { duration: Theme.tFast; easing.type: Easing.OutCubic } }

        focus: menu.shown
        Keys.onEscapePressed: ev => { menu.close(); ev.accepted = true; }
        Keys.onUpPressed: ev => { menu._step(-1); ev.accepted = true; }
        Keys.onDownPressed: ev => { menu._step(1); ev.accepted = true; }
        Keys.onReturnPressed: ev => {
            if (menu.highlighted >= 0 && menu.highlighted < menu.items.length)
                menu._activate(menu.items[menu.highlighted]);
            ev.accepted = true;
        }
        Keys.onEnterPressed: ev => {
            if (menu.highlighted >= 0 && menu.highlighted < menu.items.length)
                menu._activate(menu.items[menu.highlighted]);
            ev.accepted = true;
        }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 2

            Text {
                visible: menu.title !== ""
                Layout.fillWidth: true
                Layout.leftMargin: Theme.s8
                Layout.rightMargin: Theme.s8
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                text: menu.title
                color: Theme.fixer
                font.family: Theme.sans
                font.pixelSize: Theme.fs12
                elide: Text.ElideRight
            }

            Rectangle {
                visible: menu.title !== ""
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                Layout.bottomMargin: 2
                implicitHeight: 1
                color: Theme.emulsion
            }

            Repeater {
                model: menu.items
                Item {
                    id: entry
                    required property var modelData
                    required property int index
                    readonly property bool isSep: modelData.separator === true
                    readonly property bool isEnabled: modelData.enabled !== false
                    readonly property bool isDanger: modelData.danger === true
                    readonly property bool isHot: (rowArea.containsMouse || menu.highlighted === index) && isEnabled

                    Layout.fillWidth: true
                    implicitHeight: isSep ? 9 : 28

                    Rectangle {
                        visible: entry.isSep
                        anchors.centerIn: parent
                        width: parent.width - 8
                        height: 1
                        color: Theme.emulsion
                    }

                    Rectangle {
                        visible: !entry.isSep
                        anchors.fill: parent
                        radius: 6
                        color: !entry.isHot ? "transparent"
                            : (entry.isDanger ? Qt.rgba(0.878, 0.424, 0.294, 0.22) : Theme.emulsion)
                        Behavior on color { ColorAnimation { duration: Theme.tHover } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.s8
                            anchors.rightMargin: Theme.s8
                            spacing: Theme.s8
                            Glyph {
                                visible: (entry.modelData.glyph || "") !== ""
                                text: entry.modelData.glyph || ""
                                size: 14
                                color: entry.isDanger ? Theme.warn
                                    : (entry.modelData.checked ? Theme.pencil : (entry.isHot ? Theme.paper : Theme.fixer))
                                Layout.preferredWidth: 16
                            }
                            Text {
                                Layout.fillWidth: true
                                text: entry.modelData.label || ""
                                color: !entry.isEnabled ? Theme.fixer
                                    : (entry.isDanger ? Theme.warn : Theme.paper)
                                font.family: Theme.sans
                                font.pixelSize: Theme.fs13
                                elide: Text.ElideRight
                            }
                            Glyph {
                                visible: entry.modelData.checked === true
                                text: "󰄬"
                                size: 13
                                color: Theme.pencil
                            }
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: entry.isEnabled
                            onEntered: menu.highlighted = entry.index
                            onClicked: menu._activate(entry.modelData)
                        }
                    }
                }
            }
        }
    }
}
