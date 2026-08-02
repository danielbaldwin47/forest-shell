pragma Singleton

// The MPRIS facade (#37, #12 §3): the only place in the shell that knows what a
// player on the bus is.
//
//     Mpris.showing         // is there anything to put on the bar
//     Mpris.label           // "Reckoner · Radiohead"
//     Mpris.playing
//     Mpris.icon            // what a click would do
//     Mpris.togglePlaying()
//
// Native — `Quickshell.Services.Mpris` is a real MPRIS client (#4 §2.5), so
// nothing here shells out to `playerctl` and nothing polls. Every property is a
// binding on a player the service pushes changes to, which is what keeps an
// idle shell at zero wakeups for media (#22 §5). Position is deliberately not
// among them: it is the one MPRIS property that does *not* push, and a bar pill
// that showed elapsed time would be a timer running whenever anything is
// playing, for a number nobody reads at 12pt.
//
// The name shadows the upstream singleton, so the module is imported under an
// alias — `Mp.Mpris` is upstream's, `Mpris` everywhere else in the shell is
// this. That is the rule Services/README.md added in #36, and the failure it
// prevents is silent: two types with one name resolve to whichever the engine
// saw last, and every property reads back `undefined`.
//
// **Which player** is the whole difficulty, and it is in
// Services/Media/MprisPolicy.qml with the rest of the decisions — a machine
// usually has several MPRIS names on the bus and only one of them is what you
// are listening to.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Services.Mpris as Mp
import qs.Core

Singleton {
    id: root

    // Held as its own property rather than declared inline — see Core/Config.qml
    // for what an inline declaration assigned to a child costs.
    readonly property MprisPolicy policy: MprisPolicy {}

    /// Every player on the bus, as plain data for the policy. Rebuilt when any
    /// player's state changes, which is what re-runs the choice below.
    ///
    /// A JS array and not the model: this is read *by* the policy, which has no
    /// Quickshell types to speak in. Nothing renders from it — the pill is one
    /// player — so #75's rule about reassigning a model does not apply here.
    readonly property var snapshot: {
        const out = [];
        const players = Mp.Mpris.players ? Mp.Mpris.players.values : [];
        for (const player of players) {
            out.push({
                id: player.dbusName,
                playing: player.playbackState === Mp.MprisPlaybackState.Playing,
                // Not `!playing`: paused and stopped are different answers, and
                // the difference is the whole of "hidden when nothing plays".
                stopped: player.playbackState === Mp.MprisPlaybackState.Stopped,
                title: player.trackTitle,
                artist: player.trackArtist,
                identity: player.identity
            });
        }
        return out;
    }

    /// The bus name of the player the pill is about. Written, not bound: the
    /// choice depends on what was showing a moment ago (MprisPolicy.pick), and
    /// a binding that read its own previous value would be a loop.
    property string chosenId: ""

    // Re-choose whenever anything about any player changes — a track ending, a
    // second player starting, a browser tab registering a name. The policy is
    // what keeps this from flapping: a player that is playing keeps the pill.
    onSnapshotChanged: {
        const index = root.policy.pick(root.snapshot, root.chosenId);
        root.chosenId = index < 0 ? "" : root.snapshot[index].id;
    }

    /// The chosen player, as the upstream object — the handle the transport
    /// calls need. Null when nothing is playing anywhere.
    readonly property var player: {
        const players = Mp.Mpris.players ? Mp.Mpris.players.values : [];
        for (const candidate of players)
            if (candidate.dbusName === root.chosenId)
                return candidate;
        return null;
    }

    readonly property bool playing: root.player !== null && root.player.isPlaying

    /// What the bar shows. Empty when there is nothing to show, which is what
    /// takes the module off the bar.
    readonly property string label: root.player === null ? ""
        : root.policy.label(root.player.trackTitle, root.player.trackArtist,
                            root.player.identity)

    readonly property bool showing: root.policy.showing(root.label)
    readonly property string icon: root.policy.icon(root.playing)

    /// Whether a click will do anything. A player that cannot be paused from
    /// here is still shown — the pill's first job is to say what is playing —
    /// but the click is a logged no-op rather than a silent one.
    ///
    /// Play/pause is the only transport the shell has a caller for: the pill is
    /// one click (#37), and skipping a track belongs to the control centre's
    /// media card (#44), which will want `next`/`previous` and the position
    /// this facade also deliberately does not read.
    readonly property bool canToggle: root.player !== null && root.player.canTogglePlaying

    // --- driving it ----------------------------------------------------------

    function togglePlaying() {
        if (!root.canToggle) {
            Logger.warn("media", root.player === null
                ? "no player — ignoring play/pause"
                : root.player.identity + " cannot be paused from here");
            return;
        }
        root.player.togglePlaying();
    }

    // --- what a harness reads ------------------------------------------------
    //
    // A line per state change, which for media is a keypress or a track change
    // and never a frame (#81). The chosen-player line is the one that matters
    // most: every property above moves at once when the pill changes hands, and
    // without it the log shows four unexplained changes.

    onChosenIdChanged: Logger.log("media", root.chosenId === ""
        ? "no player"
        : "player " + root.chosenId + " (" + root.label + ")")
    onPlayingChanged: Logger.log("media", root.playing ? "playing" : "paused")
    onLabelChanged: if (root.label !== "") Logger.log("media", "track " + root.label)

    Component.onCompleted: Logger.log("media",
        "mpris facade ready (" + root.snapshot.length + " player(s))")
}
