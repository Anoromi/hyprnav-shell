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
// in services/Brightness.qml. Only the focused screen shows it. The surface
// stays mapped (input region empty) so a change never waits for a new window;
// the pill rises from the bar edge like the sheets and leaves faster.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData
    property bool primary: true
    property bool suppressed: false
    property string kind: "volume"          // volume | brightness
    property bool shown: false

    visible: primary
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
        id: pill
        anchors.fill: parent
        radius: height / 2
        color: Theme.sheet
        border.color: Theme.emulsion
        visible: opacity > 0
        opacity: 0
        scale: 0.97
        transformOrigin: Item.Left
        transform: Translate { id: shift; x: -Theme.riseDistance }
        states: State {
            name: "shown"; when: win.shown
            PropertyChanges { pill.opacity: 1; pill.scale: 1; shift.x: 0 }
        }
        transitions: [
            Transition { to: "shown"; NumberAnimation { targets: [pill, shift]; properties: "opacity,scale,x"; duration: Theme.tOpen; easing.type: Easing.OutCubic } },
            Transition { from: "shown"; NumberAnimation { targets: [pill, shift]; properties: "opacity,scale,x"; duration: Theme.tClose; easing.type: Easing.InCubic } }
        ]
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.s16; anchors.rightMargin: Theme.s16
            spacing: Theme.s12
            Glyph {
                text: win.kind === "volume" ? Services.Audio.icon() : "󰃟"
                size: 18
                // One width for every glyph, so the slider never slides.
                Layout.preferredWidth: 20
                horizontalAlignment: Text.AlignHCenter
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
