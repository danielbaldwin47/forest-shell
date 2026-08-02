// Everything the OSD decides, as pure functions (#46).
//
// The surface is three services' worth of numbers and one question: *is this
// change worth putting a window on the screen for*. That question is the whole
// of this file, and it is the reason the OSD has a policy at all — the picture
// is a glyph, a track and a reading, and none of those are hard. What is hard
// is the arming rule below, which is what separates "the user pressed a volume
// key" from "PipeWire finished connecting".
//
// Imports nothing but QtQuick so `tests/` can reach it (CLAUDE.md, seam 1);
// Osd.qml is the half that needs Quickshell.
import QtQuick

QtObject {
    id: policy

    /// The three things that pop it, in the order the control centre lists its
    /// sliders (#9, #44). A channel not on this list does not exist: the IPC
    /// door takes a name typed by a human, and an unknown one is refused with a
    /// line rather than mapping a window with no glyph in it.
    readonly property var channels: ["volume", "mic", "brightness"]

    /// Where the pill may sit. Layer-shell centres a surface on whichever axis
    /// it is not anchored to, so each of the first four is one edge with the
    /// pill centred against it, and `center` is the middle of the screen.
    ///
    /// Closed, and the settings schema validates against the same list: an
    /// unknown position has no obvious reading, and guessing one is worse than
    /// falling back (Core/Coerce.qml).
    readonly property var positions: ["top", "bottom", "left", "right", "center"]

    /// Bottom, because the bar is at the top and an OSD that lands under it is
    /// one that argues with the thing it is reporting on. Centred against that
    /// edge, clear of the corner the notification stack owns (#42).
    readonly property string defaultPosition: "bottom"

    /// The pill's size. A component dimension rather than a token — the design
    /// system fixes spacing and radii and leaves the size of a thing to the
    /// ticket that builds it (#8) — but it is *here* rather than in
    /// OsdContent.qml because the window has to know how big its surface is
    /// before the content it will hold exists. Two copies of that number is two
    /// copies that drift, and the visible form of the drift is a window that
    /// resizes itself the first time it is shown.
    ///
    /// Wide enough for a track that reads as a level rather than a dot, short
    /// enough that it is a pill and not a panel.
    readonly property int pillWidth: 280
    readonly property int pillHeight: 56

    readonly property int defaultTimeoutMs: 2000
    readonly property int minTimeoutMs: 300
    readonly property int maxTimeoutMs: 10000

    // #27's OSD row: 240 in, 140 out, in-place value update 140. These are the
    // *requested* durations — every consumer passes them through Theme.duration
    // / Theme.exitDuration, which is what collapses them under reducedEffects
    // (#69) and what makes the exit one step faster than the entrance without
    // arithmetic here.
    readonly property int enterMs: 240
    readonly property int inPlaceMs: 140

    function known(channel: string): bool {
        return policy.channels.indexOf(channel) >= 0;
    }

    // --- what pops it ---------------------------------------------------------

    /// How long a channel stays silent after it appears.
    ///
    /// A facade knowing it *has* a device and knowing what that device is doing
    /// are two events, and they are not the same frame: the backlight probe
    /// answers "there is a panel" before the sysfs read lands, which on the
    /// first run of tools/osd-harness.sh armed the channel at 0% and popped an
    /// OSD sixteen milliseconds later at the machine's real 1%. PipeWire has
    /// the same shape one node further out.
    ///
    /// So availability starts a window rather than ending the wait. Long enough
    /// to cover a service settling, short enough that it cannot swallow a
    /// keypress: nothing the user does in the first three quarters of a second
    /// of a device existing is a thing to interrupt them about.
    readonly property int settleMs: 750

    /// What a new reading of one channel means: `"pop"`, `"arm"` or `"ignore"`.
    ///
    /// `next` is `{ available, percent, muted }` as the facades hand it over;
    /// `previous` is what `record()` last stored, or null the first time, and
    /// carries the moment its channel was armed. `nowMs` is `Date.now()`.
    ///
    /// The arming rule is the reason this function exists. Every channel's
    /// first reading is a jump from nothing to whatever the machine was already
    /// at — PipeWire answers a frame or two after the shell starts, the panel
    /// probe answers after that — and a shell that popped on those would greet
    /// every login with three OSDs. Same argument for a device that goes away
    /// and comes back at its own level: unplugging headphones is not the user
    /// asking for anything.
    function observe(previous: var, next: var, nowMs: real): string {
        if (!next || next.available !== true)
            return "ignore";
        if (!previous || previous.available !== true)
            return "arm";
        if (nowMs - previous.armedAt < policy.settleMs)
            return "arm";
        if (policy.clampPercent(previous.percent) === policy.clampPercent(next.percent)
                && (previous.muted === true) === (next.muted === true))
            return "ignore";
        return "pop";
    }

    /// What to keep for next time: the reading that just arrived, stamped with
    /// the moment its channel was armed.
    ///
    /// The stamp is from when the channel *appeared*, and is carried forward
    /// through everything after — a window measured from the last thing the
    /// channel did would be pushed forward by every step of a service settling,
    /// and a channel that is genuinely being used would never come out of it.
    function record(previous: var, next: var, verdict: string, nowMs: real): var {
        const fresh = !previous || previous.available !== true;
        return {
            available: next.available === true,
            percent: next.percent,
            muted: next.muted === true,
            armedAt: (verdict === "arm" && fresh) || !previous ? nowMs : previous.armedAt
        };
    }

    /// Whether something on screen already answers the question the OSD would.
    ///
    /// The control centre (#44) holds a live slider for all three channels, so
    /// an OSD over it is the same number twice — one of them on top of the
    /// control being dragged. The lock (#47) is a session-lock surface above
    /// every layer, so an OSD under it is frames nobody sees; the keys still
    /// work, they are just silent.
    function suppressed(drawer: string, locked: bool): bool {
        return locked === true || drawer === "controlcenter";
    }

    // --- what it says ---------------------------------------------------------

    /// The glyph. The volume ladder is Services/Media/AudioPolicy.qml's, in
    /// percent rather than 0-1 because the OSD is fed by three services and
    /// only one of them thinks in fractions — `tests/tst_osdpolicy.qml`
    /// compares the two tables value by value rather than trusting this
    /// comment.
    function icon(channel: string, percent: var, muted: bool): string {
        const level = policy.clampPercent(percent);
        switch (channel) {
        case "volume":
            if (muted === true)
                return "volume-x";
            if (level <= 0)
                return "volume";
            return level >= 50 ? "volume-2" : "volume-1";
        case "mic":
            return muted === true ? "mic-off" : "mic";
        case "brightness":
            // One sun at every level. The control centre's brightness slider
            // has no second glyph either, and a dimming icon would be a
            // decision no ticket has made.
            return "sun";
        }
        return "";
    }

    /// What the channel is called, in the pill and in the log line.
    function name(channel: string): string {
        switch (channel) {
        case "volume": return "Volume";
        case "mic": return "Microphone";
        case "brightness": return "Brightness";
        }
        return "";
    }

    /// The reading beside the track. Mute outranks the level for the two
    /// channels that can mute — the level underneath is unchanged and unmuting
    /// returns to it, which is the same argument AudioPolicy makes about the
    /// glyph. Brightness cannot mute: a screen at 0% is not a muted screen and
    /// there is nothing to restore it to.
    function readout(channel: string, percent: var, muted: bool): string {
        if (muted === true && channel !== "brightness")
            return "Muted";
        return policy.clampPercent(percent) + "%";
    }

    /// The track's fill, 0-1. Over-unity volume is representable in PipeWire
    /// and is not drawable.
    function fraction(percent: var): real {
        return policy.clampPercent(percent) / 100;
    }

    /// A level from anywhere, as a whole percent. The IPC door takes one typed
    /// by a human; PipeWire hands over a float that moves in fractions.
    function clampPercent(percent: var): int {
        const value = Number(percent);
        if (!isFinite(value))
            return 0;
        return Math.max(0, Math.min(100, Math.round(value)));
    }

    // --- where it sits and how long it stays ---------------------------------

    /// The four layer-shell anchor flags for a position. One edge, or none.
    function anchorsFor(position: string): var {
        const at = policy.positions.indexOf(position) >= 0 ? position
                                                           : policy.defaultPosition;
        return {
            top: at === "top",
            bottom: at === "bottom",
            left: at === "left",
            right: at === "right"
        };
    }

    /// The margin, on the anchored edge only. A margin on an edge the surface
    /// is not anchored to is a pill shoved off the centre it was meant to be
    /// on.
    function marginsFor(position: string, margin: var): var {
        const anchors = policy.anchorsFor(position);
        const gap = Math.max(0, Math.round(Number(margin)) || 0);
        return {
            top: anchors.top ? gap : 0,
            bottom: anchors.bottom ? gap : 0,
            left: anchors.left ? gap : 0,
            right: anchors.right ? gap : 0
        };
    }

    /// How long it stays up. Bounded either side: 0 would be a surface that
    /// maps and unmaps in one frame, and the settings schema clamps to the same
    /// pair, so a hand-edit and an IPC call are refused identically.
    function timeoutMs(ms: var): int {
        const value = Number(ms);
        if (!isFinite(value))
            return policy.defaultTimeoutMs;
        return Math.max(policy.minTimeoutMs,
                        Math.min(policy.maxTimeoutMs, Math.round(value)));
    }

    // --- what a harness reads -------------------------------------------------
    //
    // A line per state change, with the *reason* in it — #81's lesson, and what
    // the maintenance pass on #46 asked for by name. Seam 2 asserts on these
    // (tools/osd-harness.sh); without them a surface that showed for the wrong
    // reason and one that never showed at all look the same in a log.

    function shown(channel: string, percent: var, muted: bool): string {
        return channel + " " + policy.clampPercent(percent) + "% — showing ("
            + policy.name(channel) + " " + policy.readout(channel, percent, muted) + ")";
    }

    function hidden(reason: string): string {
        return "hidden (" + reason + ")";
    }

    function suppressedBy(what: string): string {
        return "suppressed while " + what + " is open";
    }

    function armed(channel: string, percent: var): string {
        return channel + " armed at " + policy.clampPercent(percent) + "% — not showing";
    }

    function refused(channel: string): string {
        return "no such channel: " + channel;
    }
}
