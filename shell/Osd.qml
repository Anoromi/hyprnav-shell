pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "services" as Services
import "bar"

// Volume and brightness pill beside the bar, 1.5 s after the last change.
// Volume follows the default sink's PipeWire node (its volume and mute
// properties change on PipeWire events); brightness follows the sysfs watch
// in services/Brightness.qml. Only the focused screen shows it.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData
    property bool primary: true
    property bool suppressed: false
    property string kind: "volume"          // volume | brightness
    property bool shown: false

    visible: primary && (shown || fade.running)
    anchors { left: true; bottom: true }
    margins { left: 52; bottom: Math.round(screen.height * 0.18) }
    implicitWidth: 248
    implicitHeight: 48
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprnav-shell-osd"

    function show(k) {
        if (suppressed) return;
        kind = k; shown = true; hide.restart();
    }
    Timer { id: hide; interval: 1500; onTriggered: win.shown = false }

    // Changes in the first second after start, or right after the default
    // sink changes, are the initial property reads, not the user.
    property bool armed: false
    Timer { id: arm; interval: 1000; running: true; onTriggered: win.armed = true }
    readonly property var sinkAudio: Services.Audio.ready ? Services.Audio.sink.audio : null
    onSinkAudioChanged: { armed = false; arm.restart(); }
    Connections {
        target: win.sinkAudio
        function onVolumesChanged() { if (win.armed) win.show("volume"); }
        function onMutedChanged() { if (win.armed) win.show("volume"); }
    }
    Connections {
        target: Services.Brightness
        function onChangesChanged() { if (win.armed) win.show("brightness"); }
    }

    readonly property real value: kind === "volume" ? (Services.Audio.muted ? 0 : Services.Audio.volume) : Services.Brightness.level

    Rectangle {
        anchors.fill: parent
        radius: 24
        color: Theme.sheet
        border.color: Theme.emulsion
        opacity: win.shown ? 1 : 0
        x: win.shown ? 0 : -8
        Behavior on opacity { NumberAnimation { id: fade; duration: Theme.tScrim; easing.type: Easing.OutCubic } }
        Behavior on x { NumberAnimation { duration: Theme.tScrim; easing.type: Easing.OutCubic } }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.s16; anchors.rightMargin: Theme.s16
            spacing: Theme.s12
            Glyph {
                text: win.kind === "volume" ? Services.Audio.icon() : "󰃟"
                size: 18
                color: win.kind === "volume" && Services.Audio.muted ? Theme.fixer : Theme.paper
            }
            Slider { Layout.fillWidth: true; value: win.value; enabled: !(win.kind === "volume" && Services.Audio.muted) }
            Text {
                text: win.kind === "volume" && Services.Audio.muted ? "off" : Math.round(win.value * 100)
                Layout.preferredWidth: 28
                horizontalAlignment: Text.AlignRight
                color: Theme.fixer; font.family: Theme.mono; font.pixelSize: Theme.fs13
            }
        }
    }
}
