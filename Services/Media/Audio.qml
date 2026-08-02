pragma Singleton

// The audio facade (#36, #12 §3): the only place in the shell that knows what a
// PipeWire node is.
//
//     Audio.volume          // 0-1, the default sink's
//     Audio.muted
//     Audio.percent         // the same as a whole number, for a readout
//     Audio.sourceMuted     // the microphone
//     Audio.setVolume(0.4)
//     Audio.stepVolume(1)   // one notch up, snapped to the step grid
//     Audio.toggleMute()
//
// Native throughout — `Quickshell.Services.Pipewire` is a real PipeWire client
// (#4 §2.5), so nothing here shells out to `wpctl` or `pactl` and nothing polls.
// Every property below is a binding on a node PipeWire pushes changes to, which
// is what keeps an idle shell at zero wakeups for audio (#22 §5).
//
// The one trap worth naming, because it fails silently: **a PipeWire object's
// properties are empty until something tracks it.** `PwObjectTracker` at the
// bottom of this file is what binds the default sink and source; without it
// `sink.audio.volume` reads 0 forever and the bar shows a muted-looking shell
// on a machine playing music (#4 §2.5 calls it the single most common
// Quickshell/PipeWire bug).
//
// Every decision — which glyph, what a step is, what "muted" reads as — is in
// Services/Media/AudioPolicy.qml, which imports nothing but QtQuick so tests/
// can reach it. This file is the wiring.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Core

Singleton {
    id: root

    // Held as its own property rather than declared inline — see Core/Config.qml
    // for what an inline declaration assigned to a child costs.
    readonly property AudioPolicy policy: AudioPolicy {}

    /// Whether PipeWire answered at all. False on a machine running plain ALSA,
    /// or in the first moments of startup: the socket connection is
    /// asynchronous, so this is a binding and never a value read once.
    readonly property bool ready: Pipewire.ready

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    /// Whether there is anything to play through. A machine with no sink shows
    /// no volume glyph rather than a permanent zero.
    readonly property bool hasSink: root.sink !== null && root.sink.audio !== null
    readonly property bool hasSource: root.source !== null && root.source.audio !== null

    readonly property real volume: root.hasSink ? root.sink.audio.volume : 0
    readonly property bool muted: root.hasSink ? root.sink.audio.muted : false
    readonly property real sourceVolume: root.hasSource ? root.source.audio.volume : 0
    readonly property bool sourceMuted: root.hasSource ? root.source.audio.muted : false

    /// The whole-number readout, and the thing the log line follows: a volume
    /// is a float that moves in fractions of a percent as PipeWire recalculates
    /// it, and a line per float change would be a log nobody can read.
    readonly property int percent: root.policy.percent(root.volume)

    readonly property string icon: root.policy.sinkIcon(root.volume, root.muted)
    readonly property string sourceIcon: root.policy.sourceIcon(root.sourceMuted)

    /// Whether the mic is worth showing at all — true only while it is muted
    /// (#9: the cluster is quiet, and a live mic is the normal state). A
    /// property rather than something a surface asks the policy for directly:
    /// a caller reaching through the service into its policy is a caller that
    /// would keep working if the service stopped answering.
    readonly property bool showSource: root.policy.showSource(root.sourceMuted)

    // --- setting it ----------------------------------------------------------

    function setVolume(volume: real) {
        if (!root.hasSink) {
            Logger.warn("audio", "no default sink — ignoring volume " + volume);
            return;
        }
        root.sink.audio.volume = root.policy.clamp(volume);
    }

    /// One notch up (1) or down (-1). Snapped to the step grid by the policy, so
    /// the readout reaches round numbers however it was left.
    function stepVolume(direction: int) {
        root.setVolume(root.policy.stepped(root.volume, direction));
    }

    function setMuted(muted: bool) {
        if (!root.hasSink) {
            Logger.warn("audio", "no default sink — ignoring mute " + muted);
            return;
        }
        root.sink.audio.muted = muted;
    }

    function toggleMute() {
        root.setMuted(!root.muted);
    }

    function setSourceMuted(muted: bool) {
        if (!root.hasSource) {
            Logger.warn("audio", "no default source — ignoring mic mute " + muted);
            return;
        }
        root.source.audio.muted = muted;
    }

    function toggleSourceMute() {
        root.setSourceMuted(!root.sourceMuted);
    }

    // --- what a harness reads ------------------------------------------------
    //
    // A line per state change, which for audio is a keypress and never a frame
    // (#81: the lock lifecycle logged nothing, and one bug then had two
    // candidate causes for a week). The default-device line is the one that
    // matters most in practice — plugging in headphones moves every property
    // above at once, and without it the log shows four unexplained changes.

    onSinkChanged: Logger.log("audio", root.hasSink
        ? "default sink: " + root.sink.description
        : "no default sink")
    onSourceChanged: Logger.log("audio", root.hasSource
        ? "default source: " + root.source.description
        : "no default source")
    onPercentChanged: Logger.log("audio", "volume " + root.percent + "%")
    onMutedChanged: Logger.log("audio", root.muted ? "muted" : "unmuted")
    onSourceMutedChanged: Logger.log("audio", root.sourceMuted ? "mic muted" : "mic live")

    // Tracking is what populates `audio` on both nodes — see the header. The
    // list is a binding, so a headphone plug that moves the default sink moves
    // the tracker with it.
    PwObjectTracker {
        objects: [root.sink, root.source]
    }

    Component.onCompleted: Logger.log("audio",
        Pipewire.ready ? "pipewire facade ready" : "waiting for pipewire")
}
