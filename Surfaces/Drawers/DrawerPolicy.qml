// Which drawer is open, on which screen, and what a monitor change does to
// that (#38).
//
// The drawers — launcher (#39), control centre (#44), dashboard (#49), session
// (here) — share one window per screen and one open-drawer name (#12 §3; #187
// is why there is no focus grab under that any more). That topology only holds
// if "which drawer is open" is a single value rather than a
// flag per surface, so it is one here: a name, or the empty string for none.
// Two drawers open at once is then not a bug that can happen, and the swap
// between them is a transition rather than a race between two windows.
//
// Everything on this side of the line is a decision. The window, the fog and
// the input routing are `Drawers.qml` and `DrawerWindow.qml` next door, which
// import Quickshell and so cannot be reached from `tests/`; this file imports
// nothing but QtQuick, which is why the state machine, the screen choice and
// the hotplug reset are here instead of inside a `PanelWindow`.
//
// The durations are deliberately *not* here. Enter is `Theme.motionSlow` and
// exit is `Theme.exitDuration` of it — design-system steps that
// Core/EffectsPolicy.qml already owns and `tests/tst_effectspolicy.qml`
// already checks. The only timing this file owns is the one #27 invents for
// the cross-drawer swap and nothing else in the shell has: the +100 ms the
// incoming drawer waits before it starts.
import QtQuick

QtObject {
    id: policy

    /// The drawers that exist. A toggle for anything else changes nothing —
    /// the bar's buttons are already drawn for surfaces that have not landed
    /// (#37), and pressing one of those must not close the drawer that is open.
    ///
    /// Grows by one line per tenant ticket; `session` is the first (#38),
    /// `launcher` the second (#39), `notificationcenter` the third (#43),
    /// `controlcenter` the fourth (#44) and `dashboard` the fifth (#49) —
    /// which is the last one the build plan names.
    ///
    /// Writable, and nothing in the shell writes it: `tests/` does, to reach
    /// the states a five-drawer shell does not have yet.
    property var tenants: ["session", "launcher", "notificationcenter", "controlcenter",
                           "dashboard"]

    /// Whether a drawer exists to be opened at all.
    function known(name: string): bool {
        return policy.tenants.indexOf(name) >= 0;
    }

    // --- which drawer is open ------------------------------------------------

    /// The drawer that is open after `requested` is toggled. The one verb, for
    /// the reason Core/SurfaceBus.qml gives: it is what a bar button can mean
    /// and what the shell-switch keybind sends.
    function next(current: string, requested: string): string {
        if (!policy.known(requested))
            return current;
        return current === requested ? "" : requested;
    }

    /// What a click on the *bar* does to the open drawer (#187).
    ///
    /// The whole table, in one place, because the alternative is four bar
    /// modules each growing their own idea of dismissal. Every click on the bar
    /// arrives here — the doors call `SurfaceBus.barClick(name)` and dead space
    /// calls it with `""` — so this is the routing rather than a description of
    /// it:
    ///
    ///     the open drawer's own door      →  "toggle"   — it closes
    ///     a different drawer's door       →  "toggle"   — swap, in one gesture
    ///     dead space, or a readout        →  "dismiss"  — put it away
    ///     an interactive control          →  "none"     — it acts, drawer stays
    ///
    /// `target` is what the click landed on: a drawer's name for a door, `""`
    /// for anything that claimed nothing, and any other name for a control that
    /// is not a door. The last row is the one worth saying out loud — mute, the
    /// media transport, the keyboard layout and the recorder are things you
    /// reach for *while* a panel is open, and a shell that closed the panel
    /// under you for using one would be worse than one that swallowed the click.
    ///
    /// Toggling is `next()` above and not a separate answer here: a door's
    /// close and a door's swap are the same verb from the same table, which is
    /// what makes the swap a transition rather than a close and then an open.
    ///
    /// A door is a door whether or not anything is open — that is the first
    /// clause, and it is the one the table above does not say out loud because
    /// it is the everyday case: with nothing open, pressing the launcher button
    /// opens the launcher. The rows above are what changes once something *is*
    /// open. With nothing open there is nothing to dismiss either, so dead space
    /// is "none" and the control — if there is one — does what it always did.
    function barClick(current: string, target: string): string {
        if (policy.known(target))
            return "toggle";
        if (current === "")
            return "none";
        return target === "" ? "dismiss" : "none";
    }

    // --- which screen --------------------------------------------------------

    /// The screen a drawer opens on: the focused one, by name.
    ///
    /// A name and not a `ShellScreen`, for the reason
    /// Services/Compositor/Compositor.qml holds the focused screen as a name —
    /// a `ShellScreen` kept across a hotplug is a dangling reference.
    ///
    /// Falls back to the first screen rather than refusing: `focusedScreenName`
    /// is empty with no Hyprland at all, and can name a screen that was
    /// unplugged between the button press and here. A drawer that quietly does
    /// not appear is #81 — the failure with two candidate causes.
    function openOn(focusedScreenName: string, screenNames: var): string {
        const names = screenNames ?? [];
        if (names.length === 0)
            return "";
        return names.indexOf(focusedScreenName) >= 0 ? focusedScreenName : names[0];
    }

    // --- hotplug -------------------------------------------------------------

    /// Whether the same screens are there, whatever order they arrive in.
    /// Quickshell re-emits its screen list for reasons that are not a cable
    /// moving, and closing the drawer under the user's hand for one of those
    /// would be worse than the state it is meant to reset.
    function sameScreens(before: var, after: var): bool {
        const a = (before ?? []).slice().sort();
        const b = (after ?? []).slice().sort();
        if (a.length !== b.length)
            return false;
        for (let i = 0; i < a.length; i++)
            if (a[i] !== b[i])
                return false;
        return true;
    }

    /// Whether an open drawer survives a change to the screen set.
    ///
    /// It does not, and losing its own screen is only the obvious half. #22 §3
    /// destroys and recreates every per-screen surface on hotplug, and an
    /// anchored drawer points at an icon on a bar whose geometry has just
    /// changed — so the reset is the whole state, not just the case where the
    /// window went away underneath it.
    function survivesScreenChange(screenName: string, before: var, after: var): bool {
        return policy.sameScreens(before, after)
            && (after ?? []).indexOf(screenName) >= 0;
    }

    // --- motion --------------------------------------------------------------

    /// How long the incoming drawer waits before starting, when one drawer
    /// replaces another. #27 variant A: out 140, in 240 beginning at +100 ms,
    /// so the two overlap by about 40 ms and the fog is never briefly empty.
    ///
    /// The value only; what `reducedEffects` does to it is `Theme.stagger`,
    /// because "no stagger anywhere" is a rung of the ladder rather than a fact
    /// about drawers (Core/EffectsPolicy.qml).
    readonly property int crossfadeDelayMs: 100

    /// What a drawer's contents scale from as they arrive: 1% under, settling
    /// to 1 (#27). Reduced, the entrance is the fade alone, so there is nothing
    /// to settle from.
    ///
    /// Takes `Theme.animateTransforms` rather than the knob, because a scale is
    /// exactly what that rung governs and reading the knob directly is a rung
    /// nobody wrote down (Core/Theme.qml). One call and no branch at the call
    /// site: the rung is asked once, here.
    function entryScale(animateTransforms: bool): real {
        return animateTransforms === true ? 0.99 : 1.0;
    }

    // --- what the log says ---------------------------------------------------
    //
    // One line per state change worth asserting on, which is what makes the
    // window drivable from tools/drawer-harness.sh. The wording is the
    // contract: #81 was a lifecycle with no log line, and one bug then had two
    // candidate causes for a week.

    /// A drawer arrived, and on which screen.
    function opened(name: string, screenName: string): string {
        return name + " opened on " + screenName;
    }

    /// A drawer left, and what sent it away.
    function closed(name: string, reason: string): string {
        return name + " closed (" + (reason ? reason : "request") + ")";
    }

    /// One drawer replaced another without the fog going anywhere.
    function switched(from: string, to: string): string {
        return from + " → " + to;
    }
}
