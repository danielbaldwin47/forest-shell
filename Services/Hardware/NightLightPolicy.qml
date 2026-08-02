// What the night-light tile decides (#44), as pure functions.
//
// What warms a screen differs by compositor — `hyprsunset` on Hyprland,
// `wlsunset` or `gammastep` elsewhere — and none of them is a DBus service with
// a Quickshell client. So the command is *config*
// (`weatherTime.nightLight.command`, beside the location and sunset keys #50
// will land) and this file turns it into argv, decides how warm is warm, and
// decides whether a finished run actually did anything.
//
// The last of those is the trap #78 named: `hyprctl` exits 0 when it refuses,
// and answers `ok` when it does not. So the exit status alone is not the
// answer here any more than it was for a layer rule
// (Services/Compositor/LayerRulePolicy.qml) — but unlike a layer rule, the
// command may be a plain binary that succeeds silently, so an empty reply has
// to count as a yes too.
//
// Imports nothing but QtQuick so `tests/` can reach it.
import QtQuick

QtObject {
    id: policy

    /// A warm evening rather than the amber a candle setting gives: 4000K is
    /// legible for text, which is what a screen is still being used for at the
    /// hour anybody turns this on.
    readonly property int defaultTemperature: 4000

    // Both ends are what the tools themselves accept. Below the floor the
    // screen is an unreadable orange; at the ceiling it is not a night light.
    readonly property int minTemperature: 1000
    readonly property int maxTemperature: 6500

    function clamp(kelvin: var): int {
        // `null` explicitly, because `Number(null)` is 0 rather than NaN — and
        // an absent key clamping to a 1000K candle is the one wrong answer this
        // function could give.
        if (kelvin === null || kelvin === undefined || kelvin === "")
            return policy.defaultTemperature;
        const value = Number(kelvin);
        if (!isFinite(value))
            return policy.defaultTemperature;
        return Math.round(Math.max(policy.minTemperature,
                                   Math.min(policy.maxTemperature, value)));
    }

    /// A configured command as argv, with `{temp}` filled in.
    ///
    /// Split on whitespace rather than handed to `sh -c`, the call
    /// Surfaces/Drawers/SessionPolicy.qml already makes for the session
    /// commands: a shell buys quoting, globbing and word-splitting on a string
    /// from the config file, for no gain.
    ///
    /// Empty for a command nobody configured — an empty argv reaching `Process`
    /// is a tile that spins.
    function argv(command: var, kelvin: var): var {
        const filled = String(command ?? "")
            .split("{temp}").join(String(policy.clamp(kelvin)))
            .trim();
        return filled === "" ? [] : filled.split(/\s+/);
    }

    /// Whether this machine has a night light to offer at all. Emptying either
    /// key is how a user on a compositor none of this fits removes the tile,
    /// rather than keeping one that fails on every press — and a control that
    /// can be turned on but not off is worse than no control.
    function available(command: var, offCommand: var): bool {
        return String(command ?? "").trim() !== ""
            && String(offCommand ?? "").trim() !== "";
    }

    /// Whether a finished run did anything.
    ///
    /// Two tools in one predicate: `hyprctl` answers `ok` and exits 0 whether
    /// or not it took the dispatch (#78), and `gammastep`/`wlsunset` say
    /// nothing at all when they work. So silence and `ok` are both yes, and any
    /// other prose is the tool explaining why not.
    function accepted(exitCode: int, output: var): bool {
        if (exitCode !== 0)
            return false;
        const reply = String(output ?? "").trim();
        return reply === "" || reply === "ok";
    }

    // Both outcomes get a line, and the on-line carries the temperature: a
    // state change with no log line is one no harness can assert on (#81), and
    // "on" without the number says nothing about what actually changed.
    function applied(on: bool, kelvin: var): string {
        return on ? "night light on at " + policy.clamp(kelvin) + "K"
                  : "night light off";
    }

    function complaint(on: bool, kelvin: var, exitCode: int, output: var): string {
        const reply = String(output ?? "").trim();
        return policy.applied(on, kelvin) + " refused — exit " + exitCode
            + (reply ? ": " + reply : "");
    }
}
