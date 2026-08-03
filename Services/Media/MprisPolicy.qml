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

    /// Whether a player is worth showing at all: it is holding a track, and it
    /// has something to say about it.
    ///
    /// **`stopped` is what "nothing plays" means** (#37's criterion). A player
    /// that is playing or paused is holding something you were listening to and
    /// can get back to with one click; a stopped one — and a browser tab that
    /// has registered an MPRIS name and never played anything is stopped — is a
    /// name on the bus and nothing more. Without this the pill would be
    /// permanently on the bar saying "Firefox" on any machine with a browser
    /// open, which is exactly the furniture #9 keeps off the bar.
    ///
    /// `canControl` is deliberately *not* part of it. A player that cannot be
    /// paused from here is still the thing that is playing, and the pill's
    /// first job is to say so; the click degrades to a logged no-op.
    function eligible(player: var): bool {
        return player !== undefined && player !== null
            && player.stopped !== true
            && policy.label(player.title, player.artist, player.identity) !== "";
    }

    /// Which player the pill is about — an index into `players`, or -1 for
    /// none. Each entry is `{ id, playing, stopped, title, artist, identity }`.
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

    // --- the dashboard's card (#49) ------------------------------------------
    //
    // The bar's pill is one glyph and a title; the dashboard's card is the whole
    // player — cover art, two lines of text, three transport buttons and a track
    // position you can drag. The three decisions the position brings with it are
    // here, because every one of them is arithmetic on numbers that arrive from
    // another application and are routinely absent, negative or nonsense.

    /// A track position or length as a clock: `m:ss`, and `h:mm:ss` once there
    /// is an hour in it. Minutes are unpadded because that is how a duration is
    /// written and how every player writes it; seconds always are, because
    /// `3:7` is not a time.
    ///
    /// Anything that is not a usable number — a missing property, a NaN out of
    /// a division, the negative a player reports between tracks — is `0:00`
    /// rather than blank: this sits under a progress bar, and a label that
    /// disappears re-lays the card out every time a track changes.
    function clock(seconds: var): string {
        const total = Number(seconds);
        if (!isFinite(total) || total <= 0)
            return "0:00";

        const whole = Math.floor(total);
        const s = whole % 60;
        const m = Math.floor(whole / 60) % 60;
        const h = Math.floor(whole / 3600);
        const pad = value => (value < 10 ? "0" : "") + value;

        return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s);
    }

    /// How far through the track, 0 to 1, for the width of a filled bar.
    ///
    /// Clamped at both ends rather than trusted: a player that reports a
    /// position past its own length — which happens on the last second of a
    /// track, and permanently on streams whose length is a guess — would
    /// otherwise draw a fill wider than the bar it is inside, and a negative one
    /// would draw it backwards.
    ///
    /// A length of zero is 0 and not a division: a live stream has no end to be
    /// a fraction of.
    function progress(position: var, length: var): real {
        const at = Number(position);
        const total = Number(length);
        if (!isFinite(at) || !isFinite(total) || total <= 0)
            return 0;
        return Math.max(0, Math.min(1, at / total));
    }

    /// Whether the bar can be *dragged* — an absolute seek, which is what a
    /// progress bar under a finger means.
    ///
    /// Three conditions and all of them necessary: the player has to allow
    /// seeking at all, it has to report a position (upstream refuses the write
    /// otherwise, and a bar that jumps back to zero on release is worse than one
    /// that does not move), and there has to be a length for a fraction of the
    /// bar to mean a time.
    ///
    /// A player that fails this still gets the bar, drawn and inert — where it
    /// is up to is worth showing even where it cannot be changed.
    function scrubbable(canSeek: var, positionSupported: var, length: var): bool {
        return canSeek === true && positionSupported === true
            && isFinite(Number(length)) && Number(length) > 0;
    }

    /// Where a click at `fraction` across the bar lands, in seconds.
    ///
    /// Clamped into the track, because the fraction comes from a pointer that
    /// can be dragged past either end of the bar it started in — and rounded to
    /// the millisecond MPRIS counts in, so the number handed back is one a
    /// player can act on rather than a float with a tail on it.
    function seekTarget(fraction: var, length: var): real {
        const total = Number(length);
        if (!isFinite(total) || total <= 0)
            return 0;
        const at = Number(fraction);
        if (!isFinite(at))
            return 0;
        return Math.round(Math.max(0, Math.min(1, at)) * total * 1000) / 1000;
    }
}
