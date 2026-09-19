pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

// Large caption at the bottom centre, for recordings and walkthroughs.
// `qs ipc call caption display "text" 5000`, `qs ipc call caption hide`.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData
    property string text: ""
    property bool shown: false

    visible: shown || fadeOut.running
    anchors { bottom: true; left: true; right: true }
    margins { bottom: 48 }
    implicitHeight: 120
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprnav-shell-caption"
    mask: Region {}

    function show(t, ms) {
        text = t; shown = true;
        hideTimer.interval = ms > 0 ? ms : 5000; hideTimer.restart();
    }
    function hide() { hideTimer.stop(); shown = false; }
    Timer { id: hideTimer; onTriggered: win.shown = false }

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: label.implicitWidth + 64
        height: label.implicitHeight + 36
        radius: 14
        color: Theme.sheet
        border.color: Theme.pencil
        border.width: 2
        opacity: win.shown ? 1 : 0
        y: win.shown ? 0 : 10
        Behavior on opacity { NumberAnimation { id: fadeOut; duration: Theme.tRise; easing.type: Easing.OutCubic } }
        Text {
            id: label
            anchors.centerIn: parent
            text: win.text
            color: Theme.paper
            font.family: Theme.casual
            font.pixelSize: 30
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            width: Math.min(implicitWidth, win.width - 300)
            wrapMode: Text.Wrap
        }
    }
}
