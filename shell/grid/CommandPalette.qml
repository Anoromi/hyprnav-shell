pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import ".."

// Command palette for the grid. Ctrl+P opens it. Type to filter, Up/Down to
// pick, Enter runs, Esc closes. Actions that need text ask for it in the same
// field as a second step.
Item {
    id: pal
    property bool open: false
    property var actions: []          // [{ id, title, scope, needsText, prompt }]
    property int selected: 0
    property var pendingAction: null  // action waiting for text
    signal run(var action, string text)

    readonly property var filtered: {
        const q = field.text.trim().toLowerCase();
        if (pendingAction) return [];
        if (q === "") return actions;
        return actions.filter(a => a.title.toLowerCase().indexOf(q) >= 0 || a.scope.toLowerCase().indexOf(q) >= 0);
    }
    onFilteredChanged: selected = Math.min(selected, Math.max(0, filtered.length - 1))

    function show() { open = true; pendingAction = null; field.text = ""; selected = 0; field.forceActiveFocus(); }
    function hide() { open = false; pendingAction = null; field.text = ""; }
    function accept() {
        if (pendingAction) { const a = pendingAction; const t = field.text; hide(); run(a, t); return; }
        const a = filtered[selected]; if (!a) return;
        if (a.needsText) { pendingAction = a; field.text = a.defaultText || ""; field.selectAll(); return; }
        hide(); run(a, "");
    }

    visible: open
    anchors.centerIn: parent
    width: 560
    height: box.implicitHeight

    Rectangle {
        id: box
        width: parent.width
        implicitHeight: col.implicitHeight + Theme.s16
        radius: Theme.rSheet
        color: Theme.sheet
        border.color: Theme.pencil
        border.width: 2
        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.s8 }
            spacing: Theme.s4
            Rectangle {
                width: parent.width; height: 40; radius: 6
                color: Theme.darkroom
                Row {
                    anchors.fill: parent; anchors.leftMargin: Theme.s12; anchors.rightMargin: Theme.s12
                    spacing: Theme.s8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pal.pendingAction !== null
                        text: pal.pendingAction ? pal.pendingAction.prompt : ""
                        color: Theme.pencil
                        font.family: Theme.sans; font.pixelSize: Theme.fs15
                    }
                    TextInput {
                        id: field
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - (pal.pendingAction ? 200 : 0)
                        color: Theme.paper
                        font.family: Theme.sans; font.pixelSize: Theme.fs15
                        selectionColor: Theme.pencil; selectedTextColor: Theme.darkroom
                        Text { visible: field.text === "" && !pal.pendingAction; text: "Type an action"; color: Theme.fixer; font: field.font }
                        Keys.onPressed: ev => {
                            if (ev.key === Qt.Key_Down) { pal.selected = Math.min(pal.filtered.length - 1, pal.selected + 1); ev.accepted = true; }
                            else if (ev.key === Qt.Key_Up) { pal.selected = Math.max(0, pal.selected - 1); ev.accepted = true; }
                            else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { pal.accept(); ev.accepted = true; }
                            else if (ev.key === Qt.Key_Escape) { if (pal.pendingAction) { pal.pendingAction = null; field.text = ""; } else pal.hide(); ev.accepted = true; }
                            else if (ev.key === Qt.Key_P && (ev.modifiers & Qt.ControlModifier)) { pal.hide(); ev.accepted = true; }
                        }
                    }
                }
            }
            Repeater {
                model: pal.filtered.slice(0, 10)
                Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool on: index === pal.selected
                    width: col.width; height: 34; radius: 6
                    color: on ? Theme.emulsion : "transparent"
                    Row {
                        anchors.fill: parent; anchors.leftMargin: Theme.s12; anchors.rightMargin: Theme.s12
                        spacing: Theme.s12
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 90
                            text: row.modelData.scope
                            color: Theme.fixer
                            font.family: Theme.sans; font.pixelSize: Theme.fs12
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.title
                            color: row.on ? Theme.paper : Theme.fixer
                            font.family: Theme.sans; font.pixelSize: Theme.fs15
                            font.weight: row.on ? Font.Medium : Font.Normal
                        }
                    }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: pal.selected = row.index; onClicked: pal.accept() }
                }
            }
            Text {
                visible: pal.filtered.length === 0 && !pal.pendingAction
                text: "No action matches."
                color: Theme.fixer
                font.family: Theme.sans; font.pixelSize: Theme.fs13
                leftPadding: Theme.s12; topPadding: Theme.s4; bottomPadding: Theme.s4
            }
        }
    }
}
