pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool ready: Pipewire.ready && sink !== null && sink.audio !== null
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready ? sink.audio.muted : false
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property string sinkName: sink ? (sink.nickname || sink.description || sink.name) : "No output"

    // Inputs. Sources are the non-sink audio nodes; a sink's monitor is not a
    // node of its own, so it does not show up here.
    readonly property bool sourceReady: Pipewire.ready && source !== null && source.audio !== null
    readonly property real sourceVolume: sourceReady ? source.audio.volume : 0
    readonly property bool sourceMuted: sourceReady ? source.audio.muted : false
    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)

    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].concat(root.sinks, root.sources) }

    function nodeName(node) { return node.nickname || node.description || node.name; }

    function setVolume(v) { if (ready) { sink.audio.muted = false; sink.audio.volume = Math.max(0, Math.min(1, v)); } }
    function toggleMute() { if (ready) sink.audio.muted = !sink.audio.muted; }
    function setSink(node) { Pipewire.preferredDefaultAudioSink = node; }

    function setSourceVolume(v) { if (sourceReady) { source.audio.muted = false; source.audio.volume = Math.max(0, Math.min(1, v)); } }
    function toggleSourceMute() { if (sourceReady) source.audio.muted = !source.audio.muted; }
    function setSource(node) { Pipewire.preferredDefaultAudioSource = node; }

    function icon() {
        if (!ready || muted || volume === 0) return "󰖁";      // volume off
        if (volume < 0.34) return "󰕿";                        // low
        if (volume < 0.67) return "󰖀";                        // medium
        return "󰕾";                                            // high
    }
    function micIcon() {
        return !sourceReady || sourceMuted || sourceVolume === 0 ? "󰍭" : "󰍬";   // mic off / mic
    }
}
