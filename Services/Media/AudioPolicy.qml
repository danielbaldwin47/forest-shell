// Everything the volume and mic indicators decide, as pure functions (#36).
//
// Split out of Services/Media/Audio.qml for the reason Core/Tokens.qml is split
// out of Core/Theme.qml: this file imports nothing but QtQuick, so tests/ can
// reach it. What is left next door is the PipeWire wiring, which is not a
// decision at all.
import QtQuick

QtObject {
    id: policy

    /// One nudge of the volume, as a fraction. 5% is the smallest step that is
    /// audible on the T480's speakers; smaller ones read as a key that did
    /// nothing.
    readonly property real step: 0.05

    /// A volume the shell is willing to set. PipeWire will happily go above
    /// 1.0, and the amplification it does there is the distorted kind — so the
    /// ceiling is the device's own, and `percent` below agrees with it rather
    /// than reporting a number the setter would refuse.
    function clamp(volume: real): real {
        if (!isFinite(volume))
            return 0;
        return Math.max(0, Math.min(1, volume));
    }

    /// A volume as a whole percent, for a readout.
    function percent(volume: real): int {
        return Math.round(policy.clamp(volume) * 100);
    }

    /// The volume one step up (`direction` 1) or down (-1) from here.
    ///
    /// Snapped to the step grid rather than added to: a level nudged from 0.43
    /// otherwise spends the rest of the session three percent off every round
    /// number, and the readout never says a number anyone recognises.
    function stepped(volume: real, direction: int): real {
        const base = policy.clamp(volume) / policy.step;
        // The epsilon is for a level that is *already* on the grid: floating
        // point makes 0.45/0.05 land at 8.999999999999998 as readily as 9.
        const grid = direction > 0 ? Math.floor(base + 1e-9) : Math.ceil(base - 1e-9);
        const next = (grid + (direction > 0 ? 1 : -1)) * policy.step;
        return Math.round(policy.clamp(next) * 1000) / 1000;
    }

    /// The output glyph. Mute outranks the level — a mute drawn as "quiet"
    /// would be one nobody can find their way back from — and the level
    /// underneath is unchanged, so unmuting returns to it.
    function sinkIcon(volume: real, muted: bool): string {
        if (muted)
            return "volume-x";
        if (policy.clamp(volume) <= 0)
            return "volume";
        return policy.clamp(volume) >= 0.5 ? "volume-2" : "volume-1";
    }

    function sourceIcon(muted: bool): string {
        return muted ? "mic-off" : "mic";
    }

    /// Whether the mic belongs on the bar at all.
    ///
    /// The cluster is quiet by default (#9): a live mic is the normal state and
    /// says nothing; a muted one is the surprise — "why can nobody hear me" is
    /// the question this glyph exists to answer, and it is only ever asked in
    /// one direction.
    function showSource(muted: bool): bool {
        return muted === true;
    }

    /// The readout under a slider, or in a tooltip. "Muted" rather than "0%",
    /// because a muted sink still has a level and the two are different states.
    function readable(volume: real, muted: bool): string {
        return muted ? "Muted" : policy.percent(volume) + "%";
    }
}
