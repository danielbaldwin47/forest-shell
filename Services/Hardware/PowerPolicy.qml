// Everything the battery readout decides, as pure functions (#36).
//
// The percentage and the low threshold were the lock screen's first (#30,
// Surfaces/Lock/LockPolicy.qml) and moved here when this ticket gave the shell
// a power service: the lock and the bar are on screen at the same moment often
// enough that two definitions of "low" would be visible as a disagreement.
import QtQuick

QtObject {
    id: policy

    // Below this the readout turns warm — the "plug me in before you walk
    // away" point, matched to where suspend-on-battery becomes a real risk to
    // unsaved work. Below `criticalFraction` it turns ember and means it.
    readonly property real lowFraction: 0.20
    readonly property real criticalFraction: 0.10

    /// `UPowerDevice.percentage` is `energy / energyCapacity` — a 0-1 fraction
    /// rather than the 0-100 the name suggests. Clamped, because a battery
    /// reporting 104% should not widen the pill.
    function percent(fraction: real): int {
        if (!isFinite(fraction))
            return 0;
        return Math.round(Math.max(0, Math.min(1, fraction)) * 100);
    }

    function label(fraction: real): string {
        return policy.percent(fraction) + "%";
    }

    function low(fraction: real): bool {
        return isFinite(fraction) && fraction <= policy.lowFraction;
    }

    function critical(fraction: real): bool {
        return isFinite(fraction) && fraction <= policy.criticalFraction;
    }

    /// `UPowerDeviceState`, named. The binding hands over an int, and an int
    /// compared against a literal at four call sites is four chances to get the
    /// enum order wrong.
    function stateName(state: int): string {
        switch (state) {
        case 1: return "charging";
        case 2: return "discharging";
        case 3: return "empty";
        case 4: return "full";
        case 5: return "pendingCharge";
        case 6: return "pendingDischarge";
        }
        return "unknown";
    }

    /// Whether the machine is on mains — which is not the same as charging. A
    /// full battery is not charging, and a pending charge is not either, but
    /// neither of them is draining, and "is it draining" is the question the
    /// bar answers.
    function onMains(state: int): bool {
        const name = policy.stateName(state);
        return name === "charging" || name === "full" || name === "pendingCharge";
    }

    /// The glyph. Charging has one of its own at every level: while the cable
    /// is in, the level is the less interesting half of the state.
    ///
    /// The four discharging buckets are *levels*, not alarms — the alarm is the
    /// tint, from `emphasis` below. Tying the glyph to the thresholds instead
    /// would leave the shape unchanged across the whole top four fifths of the
    /// range, which is most of the time anybody looks at it.
    function icon(fraction: real, state: int): string {
        if (policy.stateName(state) === "charging")
            return "battery-charging";
        if (policy.critical(fraction))
            return "battery-warning";
        if (fraction >= 0.8)
            return "battery-full";
        return fraction >= 0.4 ? "battery-medium" : "battery-low";
    }

    /// "quiet", "attention" or "urgent" — a word, not a colour, so the module
    /// maps it to a Theme role and this file needs no Theme.
    ///
    /// A charging battery is never urgent, at any level: the one thing a flat
    /// battery is asking for is already happening, and an ember pill that
    /// stays ember while you watch it fill is a warning that teaches people to
    /// ignore warnings.
    function emphasis(fraction: real, state: int): string {
        if (policy.onMains(state))
            return "quiet";
        if (policy.critical(fraction))
            return "urgent";
        return policy.low(fraction) ? "attention" : "quiet";
    }

    /// `timeToEmpty` / `timeToFull` in seconds, written the way a person says
    /// it. UPower reports 0 while it has no estimate — a fresh boot, or a
    /// battery whose rate has not settled — and an empty string is the honest
    /// rendering of that rather than "0m".
    function timeRemaining(seconds: real): string {
        if (!isFinite(seconds) || seconds <= 0)
            return "";
        const minutes = Math.max(1, Math.round(seconds / 60));
        const hours = Math.floor(minutes / 60);
        const rest = minutes % 60;
        if (hours && rest)
            return hours + "h " + rest + "m";
        if (hours)
            return hours + "h";
        return rest + "m";
    }

    /// Whether there is a battery to draw at all.
    ///
    /// `UPower.displayDevice` exists on every machine, including desktops,
    /// where it is a placeholder reporting nothing — so a module that rendered
    /// it unconditionally would show 0% forever on a tower.
    function hasBattery(isPresent: bool, isLaptopBattery: bool): bool {
        return isPresent === true && isLaptopBattery === true;
    }
}
