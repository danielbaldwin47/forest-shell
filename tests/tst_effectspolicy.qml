// The `reducedEffects` ladder (#69), which is #22 §7's three rungs written as
// one object.
//
// The ladder is a *decision* — given the knob and what a surface asked for,
// what does it get — so it lives on this side of the seam and is checked here.
// What the rungs then do is checked where the effect is: the compositor's own
// reply to the blur rule at seam 2 (tools/blur-harness.sh), and the picture at
// seam 3 (tools/capture-harness.sh).
//
// Core/Theme.qml wires this to `appearance.reducedEffects`; it imports
// Quickshell and so cannot be loaded here.
import QtQuick
import QtTest
import "../Core"

TestCase {
    name: "EffectsPolicy"

    EffectsPolicy { id: ladder }
    Tokens { id: tokens }

    // --- rung 1: the compositor blur ----------------------------------------

    function test_rung_one_takes_the_blur_away_and_never_adds_it() {
        // The knob only ever subtracts. A user who turned the bar's blur off
        // does not get it back by asking for fewer effects.
        compare(ladder.blurRequested(true, false), true);
        compare(ladder.blurRequested(true, true), false);
        compare(ladder.blurRequested(false, false), false);
        compare(ladder.blurRequested(false, true), false);
    }

    // --- rung 2: decorative effects -----------------------------------------

    function test_rung_two_is_the_knob_itself() {
        compare(ladder.drawsDecoration(false), true);
        compare(ladder.drawsDecoration(true), false);
    }

    // --- rung 3: transitions ------------------------------------------------

    function test_every_transition_collapses_to_the_fastest_step() {
        for (const step of tokens.motionSteps)
            compare(ladder.duration(step, true), tokens.motionFast);
    }

    function test_an_unreduced_transition_gets_exactly_what_it_asked_for() {
        for (const step of tokens.motionSteps)
            compare(ladder.duration(step, false), step);
    }

    function test_a_reduced_exit_is_the_same_length_as_its_entrance() {
        // 140 is the floor of the ladder, so "exits run one step faster" has
        // nowhere left to go: reduced, the two are one duration.
        for (const step of tokens.motionSteps)
            compare(ladder.exitDuration(step, true), ladder.duration(step, true));
    }

    function test_an_unreduced_exit_still_runs_one_step_faster() {
        // Unreduced, the ladder is untouched — this is Tokens.exitDuration.
        compare(ladder.exitDuration(tokens.motionSlow, false), tokens.motionStandard);
        compare(ladder.exitDuration(tokens.motionStandard, false), tokens.motionFast);
        compare(ladder.exitDuration(tokens.motionFast, false), tokens.motionFast);
    }

    function test_a_duration_off_the_ladder_is_still_floored_when_reduced() {
        // Nothing in the shell should be asking for one, but a surface that
        // does must not be able to buy itself a longer reduced transition.
        compare(ladder.duration(1000, true), tokens.motionFast);
        compare(ladder.exitDuration(1000, true), tokens.motionFast);
    }

    function test_no_reduced_transition_outlasts_the_fastest_step() {
        // The invariant behind both, stated once: whatever is asked for,
        // reduced never runs longer than 140.
        for (const ms of [0, 1, 140, 240, 320, 1000, -5])
            verify(ladder.duration(ms, true) <= tokens.motionFast);
    }

    function test_transforms_stop_animating() {
        // Half of "opacity-only": what moves or resizes snaps to its new value.
        // The other half — that fades keep fading — is the absence of a gate on
        // them, so there is nothing here to ask.
        compare(ladder.animatesTransforms(false), true);
        compare(ladder.animatesTransforms(true), false);
    }

    // --- the ladder as a whole ----------------------------------------------

    function test_the_knob_off_changes_nothing() {
        // The acceptance criterion for the off state, at this seam: every rung
        // is the identity when `reducedEffects` is false.
        compare(ladder.blurRequested(true, false), true);
        compare(ladder.drawsDecoration(false), true);
        compare(ladder.animatesTransforms(false), true);
        for (const step of tokens.motionSteps) {
            compare(ladder.duration(step, false), step);
            compare(ladder.exitDuration(step, false), tokens.exitDuration(step));
        }
    }
}
