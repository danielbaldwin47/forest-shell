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
//     Audio.sinks           // the drill-in's output picker (#45)
//     Audio.streams         // the per-application mixer
//     Audio.setDefaultSink(id)
//     Audio.setStreamVolume(id, 0.4)
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

    /// The microphone's own level (#44). The bar never needed it — a mic has no
    /// indicator, only a mute glyph — so it arrives with the control centre's
    /// slider, which is its first caller. Clamped by the same policy as the
    /// sink: a source over unity is a source that clips.
    function setSourceVolume(volume: real) {
        if (!root.hasSource) {
            Logger.warn("audio", "no default source — ignoring mic volume " + volume);
            return;
        }
        root.source.audio.volume = root.policy.clamp(volume);
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

    // --- the drill-in's two lists (#45) --------------------------------------
    //
    // The output picker and the per-application mixer. Both are the same shape
    // as the wifi and bluetooth lists and for the same reasons — see
    // Services/Networking/Networking.qml for the long version of the #75
    // argument — with one extra trap that is specific to PipeWire and that the
    // header of this file already names once: **a node's properties are empty
    // until something tracks it.** The tracker at the bottom of this file used
    // to hold two nodes; it now holds every sink and every stream on screen,
    // because a mixer row for an untracked node draws a slider at zero for an
    // application that is audibly playing.

    /// Every output this machine has. `isSink` and not a stream: an application
    /// playing into a sink is not a device to switch to.
    readonly property var sinkNodes: {
        const out = [];
        const nodes = Pipewire.nodes ? Pipewire.nodes.values : [];
        for (const node of nodes)
            if (node.isSink && !node.isStream && node.audio)
                out.push(node);
        return out;
    }

    /// Every application currently playing. An output stream — `isStream` with
    /// `isSink` false is a *recording* stream, which belongs to a microphone
    /// mixer this panel does not have.
    readonly property var streamNodes: {
        const out = [];
        const nodes = Pipewire.nodes ? Pipewire.nodes.values : [];
        for (const node of nodes)
            if (node.isStream && node.isSink && node.audio)
                out.push(node);
        return out;
    }

    readonly property var sinkCandidates: {
        const rows = [];
        for (const node of root.sinkNodes)
            rows.push({
                id: String(node.id),
                description: node.description,
                nickname: node.nickname,
                name: node.name,
                isDefault: root.sink !== null && node.id === root.sink.id,
                live: node
            });
        return rows;
    }

    readonly property var streamCandidates: {
        const rows = [];
        for (const node of root.streamNodes)
            rows.push({
                id: String(node.id),
                description: node.description,
                name: node.name,
                properties: node.properties,
                live: node
            });
        return rows;
    }

    /// What the two `Repeater`s are given, republished only when the policy's
    /// signature moves (#75). The volumes are not in either signature and must
    /// not be: a mixer row is a *slider*, and rebuilding its delegate mid-drag
    /// is the one rebuild the user can feel.
    property var sinks: []
    property string sinkSignature: ""

    onSinkCandidatesChanged: {
        const rows = root.policy.sinks(root.sinkCandidates);
        const signature = root.policy.sinkSignature(rows);
        if (signature === root.sinkSignature)
            return;
        root.sinkSignature = signature;
        root.sinks = rows;
    }

    property var streams: []
    property string streamSignature: ""

    onStreamCandidatesChanged: {
        const rows = root.policy.streams(root.streamCandidates);
        const signature = root.policy.streamSignature(rows);
        if (signature === root.streamSignature)
            return;
        root.streamSignature = signature;
        root.streams = rows;
    }

    /// Switch the machine's output.
    ///
    /// `preferredDefaultAudioSink` and not `defaultAudioSink`: the latter is
    /// what PipeWire currently resolves to and is read-only, and the former is
    /// the *preference* — which is what makes this survive the device going
    /// away and coming back, and what makes it agree with what `wpctl
    /// set-default` would have done.
    function setDefaultSink(id: string): void {
        for (const node of root.sinkNodes) {
            if (String(node.id) !== id)
                continue;
            Pipewire.preferredDefaultAudioSink = node;
            Logger.log("audio", root.policy.switched(root.policy.deviceName({
                description: node.description, nickname: node.nickname,
                name: node.name })));
            return;
        }
        Logger.warn("audio", root.policy.streamRefused(id, "no such output"));
    }

    function streamNodeFor(id: string): var {
        for (const node of root.streamNodes)
            if (String(node.id) === id)
                return node;
        return null;
    }

    /// One application's own level, 0-1. The mixer's whole point: turning a
    /// notification down without turning the music down with it.
    function setStreamVolume(id: string, volume: real): void {
        const node = root.streamNodeFor(id);
        if (node === null || !node.audio) {
            Logger.warn("audio", root.policy.streamRefused(id, "no such stream"));
            return;
        }
        // Logged here and not off a property change, the way the default sink's
        // switch is: the mixer's levels are read straight off the nodes by the
        // delegates and this service holds no `percent` for them to notify
        // (#141 — every set reached PipeWire and none of them said so).
        const level = root.policy.clamp(volume);
        node.audio.volume = level;
        Logger.log("audio", root.policy.streamMoved(root.policy.streamName(node),
                                                    root.policy.percent(level)));
    }

    function setStreamMuted(id: string, muted: bool): void {
        const node = root.streamNodeFor(id);
        if (node === null || !node.audio) {
            Logger.warn("audio", root.policy.streamRefused(id, "no such stream"));
            return;
        }
        node.audio.muted = muted;
        Logger.log("audio", root.policy.streamMuted(root.policy.streamName(node), muted));
    }

    function toggleStreamMute(id: string): void {
        const node = root.streamNodeFor(id);
        if (node === null || !node.audio) {
            Logger.warn("audio", root.policy.streamRefused(id, "no such stream"));
            return;
        }
        root.setStreamMuted(id, !node.audio.muted);
    }

    // --- is anything playing (#48) -------------------------------------------
    //
    // The idle ladder's suspend gate, and the only reader of the link tracker
    // below. A *link* and not a stream: a paused player keeps its node — which
    // is what keeps its mixer row — and PipeWire moves the link between `Paused`
    // and `Active` as it corks and uncorks. Services/Media/AudioPolicy.qml
    // argues the difference where the decision is.
    //
    // Costs nothing while nothing is playing: `linkGroups` is a list PipeWire
    // pushes changes to, so an idle machine has an empty list and no wakeups
    // (#22 §5).

    readonly property var linkStates: {
        const states = [];
        for (const group of sinkLinks.linkGroups ?? [])
            states.push(group.state);
        return states;
    }

    readonly property bool playing: root.policy.playing(root.linkStates, PwLinkState.Active)

    PwNodeLinkTracker {
        id: sinkLinks
        node: root.sink
    }

    /// The trap in this file's header, one object type further out: **a link
    /// group's state is empty until something tracks it.** Measured — an
    /// untracked group reports `state` as -1, which is not even `Error`, while
    /// a tracked one playing audio reports `Active`. Without this line the
    /// suspend gate reads "nothing is playing" through headphones with music in
    /// them, which is the one wrong answer it exists to prevent.
    PwObjectTracker {
        objects: sinkLinks.linkGroups
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
    // The suspend gate's input, logged because "the machine did not sleep" has
    // two causes and only one of them is this one (#48, #81).
    onPlayingChanged: Logger.log("audio", root.policy.playingLine(root.playing))

    // Tracking is what populates `audio` on every node — see the header. The
    // list is a binding, so a headphone plug that moves the default sink moves
    // the tracker with it.
    //
    // It holds the two defaults *and* every sink and stream the drill-in can
    // draw (#45), which is the same trap one scale up: an untracked node reports
    // `volume` 0 and `muted` false forever, so a mixer built on the two defaults
    // alone would draw every application at silence while they played. The cost
    // is bounded by what PipeWire has — a handful of sinks and one node per
    // playing application — and it is paid whether or not the panel is open,
    // because a tracker armed on demand would populate a frame after the list
    // it is for was already on screen.
    PwObjectTracker {
        objects: [root.sink, root.source].concat(root.sinkNodes)
                                         .concat(root.streamNodes)
    }

    Component.onCompleted: Logger.log("audio",
        Pipewire.ready ? "pipewire facade ready" : "waiting for pipewire")
}
