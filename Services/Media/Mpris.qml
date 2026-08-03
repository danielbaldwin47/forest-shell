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
    /// The bar's pill is one click (#37); the control centre's media card is
    /// three (#44), which is what `canSkip`/`canGoBack` below arrived with. The
    /// track *position* is still deliberately not read here — a progress bar is
    /// a property that changes every frame something is playing, and #22 §5
    /// costs that in wakeups whether or not a surface is on screen.
    readonly property bool canToggle: root.player !== null && root.player.canTogglePlaying

    readonly property bool canSkip: root.player !== null && root.player.canGoNext
    readonly property bool canGoBack: root.player !== null && root.player.canGoPrevious

    /// The artist alone, for a card with room for two lines where the bar had
    /// one. Empty when the client did not say, which is common enough that the
    /// card has to lay out without it.
    readonly property string trackTitle: root.player?.trackTitle ?? ""
    readonly property string trackArtist: root.player?.trackArtist ?? ""

    // --- the dashboard's card (#49) ------------------------------------------
    //
    // The bar's pill is a title and a glyph; the dashboard's card is the player
    // — cover art, and a position you can drag. Both arrive here rather than in
    // the card, because "which player" is this file's whole job and a card that
    // reached for `Mp.Mpris.players` itself would be a second answer to it.

    /// The cover, as whatever URL the client gave — usually a `file://` into a
    /// cache directory, sometimes an `https://`, often nothing at all. The card
    /// draws a placeholder rather than a hole when it is empty or does not load,
    /// because "no art" is the common case and not an error.
    readonly property string artUrl: root.player?.trackArtUrl ?? ""

    /// How long the track is, in seconds. 0 for a player that does not say —
    /// a live stream, or a client that reports length only once it feels like
    /// it — which is what takes the progress bar's fill and its scrubbing away
    /// (Services/Media/MprisPolicy.qml).
    readonly property real length: root.player?.length ?? 0

    /// Where the track is up to, in seconds.
    ///
    /// **This does not tick on its own, and that is upstream's design and this
    /// shell's requirement at once**: MPRIS position "usually will not update
    /// reactively", so a consumer that wants a moving number asks for one by
    /// calling `refresh()` on a timer of its own. That keeps the cost where
    /// #22 §5 wants it — a progress bar costs one wakeup a second *while a card
    /// showing it is on screen*, and nothing at all the rest of the time, which
    /// is why the bar's pill has never shown elapsed time.
    readonly property real position: root.player?.position ?? 0

    readonly property bool positionSupported: root.player?.positionSupported === true

    /// Whether the position can be *set* — dragged to a point in the track.
    /// A player can allow seeking and still refuse to say where it is, so this
    /// is three questions and MprisPolicy asks all of them.
    readonly property bool scrubbable: root.policy.scrubbable(
        root.player?.canSeek === true, root.positionSupported, root.length)

    /// Ask the player where it is again. The whole of the polling mechanism:
    /// re-emitting the signal is what makes every binding on `position` above
    /// re-read it.
    function refresh(): void {
        if (root.player !== null)
            root.player.positionChanged();
    }

    /// Jump to a point in the track, given as a fraction of it — which is what
    /// a pointer on a progress bar knows, and the one form that needs no length
    /// arithmetic at the call site (MprisPolicy does it, and clamps).
    ///
    /// Refuses loudly rather than silently, like the transport calls above: a
    /// bar that swallows a drag is #81 with a pointer on it.
    function seekToFraction(fraction: real): void {
        if (!root.scrubbable) {
            Logger.warn("media", root.player === null
                ? "no player — ignoring seek"
                : root.player.identity + " cannot be seeked from here");
            return;
        }

        const target = root.policy.seekTarget(fraction, root.length);
        root.player.position = target;
        Logger.log("media", "seek to " + root.policy.clock(target));
    }

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

    /// The two the control centre's card adds (#44). Both refuse loudly rather
    /// than silently: a transport button that does nothing and says nothing is
    /// #81, and "this player will not skip from here" is a real answer for the
    /// browsers that advertise MPRIS without implementing all of it.
    function next() {
        if (!root.canSkip) {
            Logger.warn("media", root.player === null
                ? "no player — ignoring skip"
                : root.player.identity + " cannot skip from here");
            return;
        }
        root.player.next();
    }

    function previous() {
        if (!root.canGoBack) {
            Logger.warn("media", root.player === null
                ? "no player — ignoring previous"
                : root.player.identity + " cannot go back from here");
            return;
        }
        root.player.previous();
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
