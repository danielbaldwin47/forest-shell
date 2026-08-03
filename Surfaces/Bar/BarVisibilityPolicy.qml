// What decides whether the bar is on screen (#70).
//
// Three things can hide the bar and one can force it back: the `bar.autoHide`
// setting with its pointer reveal (#35, PR #68), a fullscreen window on the
// focused screen, and an explicit `qs ipc call bar hide` or keybind. The
// arithmetic that resolves them is here rather than in Bar.qml because Bar.qml
// imports Quickshell and is therefore unreachable from tests/ — the split
// CLAUDE.md asks for, and the same shape as BarLegibility and SurfaceOpacity
// next door.
//
// Imports nothing but QtQuick, so tests/tst_barvisibility.qml can reach it.
import QtQuick

QtObject {
    id: policy

    /// The manual override, driven by IPC and by the global shortcut. `auto`
    /// is not "shown" — it is "nobody has said, so the settings and the
    /// compositor decide", which is the state the shell starts in and the one
    /// a toggle returns to as soon as it can (see `next`).
    readonly property var overrides: ["auto", "shown", "hidden"]

    /// The functions Bar.qml's IpcHandler exposes on the `bar` target, written
    /// down here so tests/ can check them against the verbs the `qs ipc`
    /// client eats (Core/SurfaceBusPolicy.qml `reservedVerbs`, #77).
    ///
    /// This is why the door is `reveal` and not `show`: #70's acceptance
    /// criterion asked for `show`, and closed PR #67 duly declared one — but
    /// `qs ipc call bar show` is parsed as `qs ipc show`, which prints the
    /// target listing and exits 0 without calling anything. A verb that can
    /// never be typed is worse than no verb, because it is the one everybody
    /// types first.
    readonly property var verbs: ["toggle", "reveal", "hide", "auto",
                                  "isRevealed"]

    /// A context is `{ autoHide, hovering, lingering, override, fullscreen,
    /// focusedScreen }`. Every function below takes one, so the surface builds
    /// it once and the tests build it by hand.
    function context(autoHide: bool, hovering: bool, lingering: bool,
                     override: string, fullscreen: bool,
                     focusedScreen: bool): var {
        return {
            autoHide: autoHide,
            hovering: hovering,
            lingering: lingering,
            override: override,
            fullscreen: fullscreen,
            focusedScreen: focusedScreen
        };
    }

    /// Whether something other than the user's own pointer wants the bar out
    /// of the way.
    ///
    /// The fullscreen clause is gated on the screen being the focused one.
    /// `Compositor.focusedFullscreen` is a single global read off the focused
    /// workspace, so without the gate one monitor going fullscreen would take
    /// the bar off every monitor — the multi-monitor correctness tier #22 §1
    /// says must not break even though it gets no tuning.
    function autoHidden(ctx: var): bool {
        return ctx.autoHide === true
            || (ctx.fullscreen === true && ctx.focusedScreen === true);
    }

    /// Whether the bar is showing.
    ///
    /// An explicit override wins over everything, in both directions: it is
    /// the escape hatch that makes a fullscreen bar reachable without a
    /// setting, and the reason #70 could reject the knob.
    function revealed(ctx: var): bool {
        if (ctx.override === "shown")
            return true;
        if (ctx.override === "hidden")
            return false;
        if (!policy.autoHidden(ctx))
            return true;
        return ctx.hovering === true || ctx.lingering === true;
    }

    /// Whether the pointer may reveal the bar by touching the screen edge.
    ///
    /// Armed only for the reasons the shell chose on the user's behalf. An
    /// explicit hide is intent, and a pointer crossing the edge on its way
    /// somewhere else must not undo it — that would make the keybind feel
    /// broken exactly when the user is reaching for something at the top of
    /// the screen. Not armed under `shown` either: there is nothing to reveal.
    function hoverArms(ctx: var): bool {
        return ctx.override === "auto" && policy.autoHidden(ctx);
    }

    /// Whether the window reserves its strip of screen, letting the compositor
    /// tile under it.
    ///
    /// An auto-hiding bar does not — that is the point of it — and neither
    /// does one the user has explicitly hidden, because a hidden bar that
    /// still reserved 32px would leave a blank band where it used to be.
    ///
    /// Fullscreen is deliberately *not* here, and that is the one asymmetry
    /// with `revealed`. A fullscreen surface ignores exclusive zones already,
    /// so dropping the zone buys no pixels; what it would cost is a reflow of
    /// every tiled window on the way into fullscreen and another on the way
    /// out, for a change nobody can see while it applies.
    function reservesSpace(ctx: var): bool {
        return ctx.override !== "hidden" && ctx.autoHide !== true;
    }

    /// What `toggle` sets the override to, given what is on screen now.
    ///
    /// Flips the *rendered* state rather than cycling the override, so the
    /// first press always does the visible thing — a bar that is auto-hidden
    /// under fullscreen comes back on one press, not two.
    ///
    /// It returns to `auto` whenever `auto` already produces the wanted
    /// result, which is what keeps the override from becoming a trap: hiding
    /// a fullscreen-revealed bar leaves it on `auto`, so leaving fullscreen
    /// brings the bar back by itself instead of stranding it behind a keybind
    /// the user has to remember pressing.
    function next(ctx: var): string {
        const wanted = !policy.revealed(ctx);
        const auto = policy.context(ctx.autoHide, ctx.hovering, ctx.lingering,
                                    "auto", ctx.fullscreen, ctx.focusedScreen);
        if (policy.revealed(auto) === wanted)
            return "auto";
        return wanted ? "shown" : "hidden";
    }

    /// Why the bar is where it is, for the log line. #81 was a silent
    /// lifecycle and one bug then had two candidate causes for a week; with
    /// three hide reasons now converging on one property, "the bar is not
    /// there" needs to say which one did it.
    function reason(ctx: var): string {
        if (ctx.override === "shown")
            return "ipc";
        if (ctx.override === "hidden")
            return "ipc";
        if (!policy.autoHidden(ctx))
            return "pinned";
        if (ctx.hovering === true)
            return "hover";
        if (ctx.lingering === true)
            return "linger";
        return ctx.autoHide === true ? "autohide" : "fullscreen";
    }

    /// One line for the log: what the bar is doing and what decided it.
    function describe(ctx: var): string {
        return (policy.revealed(ctx) ? "shown" : "hidden")
            + " (" + policy.reason(ctx) + ")";
    }
}
