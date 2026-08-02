// The `reducedEffects` ladder (#69) — what the one degrade knob (#22 §7) cuts,
// in cost order, as pure functions.
//
//     EffectsPolicy { id: ladder }
//     ladder.duration(Theme.motionStandard, reduced)
//
// Core/Theme.qml wires this to `appearance.reducedEffects` and is what surfaces
// actually call; the functions take the flag as an argument so this file has no
// Quickshell imports and `tests/` can reach it.
//
// ## The two readings, reconciled
//
// Two resolutions defined this key and they read differently. #22 §7 makes it a
// **ladder** — "Hyprland blur layerrule off → drop shadows / decorative
// MultiEffects off (icon colorization stays) → all transitions collapse to
// opacity-only fades at the fastest motion step (140 ms)". #27 names only the
// last of those — "all motion collapses to opacity-only 140 crossfades".
//
// They do not actually disagree: #27 is a motion spec and says what motion
// does, which is rung 3 verbatim. The ladder is the whole semantic, #27's
// clause is its bottom rung, and there is no separate `reducedMotion` knob
// (#27 fixes that too). Rungs, in the cost order #22 gives them:
//
//   1. **No compositor blur is requested.** `blurRequested`. The bar's
//      layerrule is pushed as `blur 0` rather than withdrawn — Hyprland 0.5x
//      has no clearing verb (Services/Compositor/LayerRulePolicy.qml).
//   2. **No decorative effects are drawn.** `drawsDecoration`. #22 names drop
//      shadows and decorative `MultiEffect`s, and exempts icon colorization —
//      measured negligible in #19, and needed for correctness, since
//      Widgets/Icon.qml's glyphs are white until it recolours them. As of this
//      ticket that exemption is the *only* `MultiEffect` in the shell and there
//      are no drop shadows, so this rung cuts nothing today. It is here because
//      the rung is the contract: the next decorative effect binds its `visible`
//      to `Theme.drawDecoration` rather than re-litigating the ladder.
//   3. **Every transition is an opacity-only fade at 140 ms.** `duration`,
//      `exitDuration`, `stagger`, `animatesTransforms`.
//
// ## What rung 3 means by "opacity-only"
//
// The phrase has to answer two questions the specs leave open, and both answers
// are the same one: *nothing moves.*
//
//   - **What still animates.** Fades do — opacity, and colour, which is the
//     same crossfade applied to a colour and costs no layout, no transform and
//     no re-rasterization. What moves or resizes does not: position, scale,
//     translation, width and height snap to their new value. That is both the
//     cheap reading (#22's budget is fill rate on a UHD 620) and the accessible
//     one — this knob is also the shell's only motion-sensitivity control, and
//     a 140 ms colour crossfade is not what a motion-sensitive user is asking
//     to be rid of.
//   - **A transform that *was* an entrance.** A surface whose entrance is a
//     slide does not simply pop: it fades in over 140 instead. #22 §7 asks for
//     "a fully supported look, not a broken mode", and the bar's reveal
//     (Surfaces/Bar/Bar.qml) is the one place in the shell where that
//     distinction has teeth.
//
// Durations collapse rather than being dropped, so a reduced shell still reads
// as the same shell moving quickly — 140 is the design system's own in-place
// step (Core/Tokens.qml), not a new value invented for this mode.
import QtQuick

QtObject {
    id: ladder

    // The motion ladder this floors against. Instantiated rather than passed
    // in, like Core/SettingsSchema.qml's `Coerce {}`: a stateless bag of
    // constants is cheaper to build than to share, and it keeps every caller
    // from having to hand the floor over.
    readonly property QtObject tokens: Tokens {}

    // --- rung 1: the compositor blur -----------------------------------------

    /// Whether the compositor should be asked for blur, given what the surface's
    /// own setting wants.
    ///
    /// Subtractive on purpose: the knob can only take blur away. Turning
    /// `reducedEffects` off does not hand blur to a user who turned the bar's
    /// own blur setting off.
    function blurRequested(wanted: bool, reduced: bool): bool {
        return wanted === true && reduced !== true;
    }

    // --- rung 2: decorative effects ------------------------------------------

    /// Whether decoration that exists only to look like something — a drop
    /// shadow, a decorative `MultiEffect` — is drawn. Icon colorization is not
    /// decoration and is never gated on this; see the header.
    function drawsDecoration(reduced: bool): bool {
        return reduced !== true;
    }

    // --- rung 3: transitions -------------------------------------------------

    /// How long a transition runs, given the step it asked for. Reduced, every
    /// step collapses to the fastest one — including a duration that is not on
    /// the ladder at all, which must not be able to buy itself a longer reduced
    /// transition than a design-system value gets.
    function duration(requestedMs: int, reduced: bool): int {
        return reduced === true ? tokens.motionFast : requestedMs;
    }

    /// How long the matching exit runs. Unreduced this is the design system's
    /// "exits run one step faster" (Core/Tokens.qml); reduced there is nothing
    /// to be faster than, since 140 is the floor of the ladder, so an entrance
    /// and its exit are one duration.
    function exitDuration(enterMs: int, reduced: bool): int {
        return reduced === true ? tokens.motionFast : tokens.exitDuration(enterMs);
    }

    /// How long a transition waits before it starts. Reduced, it does not: #27
    /// asks for "no entrance stagger anywhere", and the only difference between
    /// a row cascade and the +100 ms an incoming drawer waits (#38) is how far
    /// apart the two things being staggered are.
    ///
    /// Separate from `duration` because it collapses to nothing rather than to
    /// the floor — a 140 ms *wait* is not a faster version of a 100 ms one, it
    /// is a longer one.
    function stagger(requestedMs: int, reduced: bool): int {
        return reduced === true ? 0 : requestedMs;
    }

    /// Whether a transition that moves or resizes something runs at all. False
    /// reduced: the property snaps, which is what makes the surviving
    /// transitions opacity-only.
    ///
    /// There is deliberately no companion for fades. A fade always runs — what
    /// reduced changes is how long it takes — so a `Behavior` on opacity or
    /// colour carries no gate at all, and the absence of one is the rule.
    function animatesTransforms(reduced: bool): bool {
        return reduced !== true;
    }
}
