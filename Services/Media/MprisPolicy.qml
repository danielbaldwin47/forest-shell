// Everything the media pill decides, as pure functions (#37).
//
// Split out of Services/Media/Mpris.qml for the reason AudioPolicy.qml is split
// out of Audio.qml: this file imports nothing but QtQuick, so tests/ can reach
// it. What is left next door is the MPRIS wiring, which is not a decision.
//
// Two decisions live here and both are about *which* player, not about how a
// pill looks. A machine playing music usually has more than one MPRIS name on
// the bus — a browser tab that has never played, a paused video, the thing you
// are actually listening to — and a bar that shows the wrong one is worse than
// a bar that shows nothing.
import QtQuick

QtObject {
    id: policy

    /// Between the track and who is playing it. A middot rather than an em
    /// dash: the pill is capped in width and elided from the right, and a dash
    /// with spaces around it eats three characters of a title to say what a
    /// single mark says.
    readonly property string separator: " · "

    /// The pill's text. Title first, because that is what is being read at a
    /// glance and what survives the elide.
    ///
    /// A player with no track falls back to its own name: a browser that has
    /// registered an MPRIS name but has nothing loaded still answers
    /// "Firefox", and a pill saying that is honest. A player with neither is
    /// not shown at all — see `pick`.
    ///
    /// The three parameters are `var` and not `string` on purpose: a typed
    /// `string` parameter coerces a missing value into the *word* "undefined"
    /// rather than into an empty one, and every one of these is read off a
    /// player that may not be there yet.
    function label(title: var, artist: var, identity: var): string {
        const track = policy.clean(title);
        const by = policy.clean(artist);
        if (track === "")
            return policy.clean(identity);
        return by === "" ? track : track + policy.separator + by;
    }

    /// Whitespace-normalised, because a track title arrives from whatever wrote
    /// the file's tags: leading spaces, tabs and the occasional newline all
    /// turn up, and a newline in a bar label is a row that grows to two lines.
    function clean(text: var): string {
        if (text === undefined || text === null)
            return "";
        return String(text).replace(/\s+/g, " ").trim();
    }

    /// The glyph, which says **what a click does** rather than what is
    /// happening. The pill is a button and the text beside it already says what
    /// is playing; a play triangle sitting next to a title that is audibly
    /// playing reads as broken, and this is the one control on the bar whose
    /// two states are otherwise indistinguishable.
    function icon(playing: bool): string {
        return playing ? "pause" : "play";
    }

    /// Whether a player is worth showing at all: it has something to say.
    ///
    /// `canControl` is deliberately not part of this. A player that cannot be
    /// paused from here is still the thing that is playing, and the pill's
    /// first job is to say so; the click degrades to a logged no-op.
    function eligible(player: var): bool {
        return player !== undefined && player !== null
            && policy.label(player.title, player.artist, player.identity) !== "";
    }

    /// Which player the pill is about — an index into `players`, or -1 for
    /// none. Each entry is `{ id, playing, title, artist, identity }`.
    ///
    /// `previousId` is what the pill was showing a moment ago, and it is why
    /// this takes an argument at all: without it, a second player starting up
    /// while you are listening to the first would steal the pill, and every
    /// change to any player's metadata could move it back. The rule is
    /// **whatever is playing stays**, and only a player that has stopped can
    /// lose the pill.
    function pick(players: var, previousId: var): int {
        if (!Array.isArray(players))
            return -1;

        let firstEligible = -1;
        let firstPlaying = -1;
        let previous = -1;

        for (let i = 0; i < players.length; i++) {
            const player = players[i];
            if (!policy.eligible(player))
                continue;
            if (firstEligible < 0)
                firstEligible = i;
            if (player.playing && firstPlaying < 0)
                firstPlaying = i;
            if (previous < 0 && player.id !== undefined && player.id === previousId)
                previous = i;
        }

        if (previous >= 0 && players[previous].playing)
            return previous;
        if (firstPlaying >= 0)
            return firstPlaying;
        // Nothing is playing: the paused thing you were listening to keeps the
        // pill rather than handing it to whichever name sorts first, so
        // pausing and resuming does not move it.
        if (previous >= 0)
            return previous;
        return firstEligible;
    }

    /// Whether the module belongs on the bar. The pill is not a permanent slot
    /// that empties (#9: the bar is quiet) — with nothing to show it takes no
    /// width and no module gap.
    function showing(label: var): bool {
        return policy.clean(label) !== "";
    }
}
