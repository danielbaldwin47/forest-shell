// What the night-light tile decides (#44): what gets run, whether it worked,
// and how warm "warm" is.
//
// The command is config (`weatherTime.nightLight.*`) rather than a constant
// here, because what dims a screen differs by compositor — hyprsunset on
// Hyprland, wlsunset or gammastep elsewhere — and the shell has no business
// guessing. That makes the two interesting decisions here: how a template
// becomes argv, and how to tell a run that worked from one that did not on a
// tool that exits 0 either way (#78).
import QtQuick
import QtTest
import "../Services/Hardware"

TestCase {
    name: "NightLightPolicy"

    NightLightPolicy { id: policy }

    // --- what gets run -------------------------------------------------------

    function test_the_template_carries_the_temperature_into_argv() {
        compare(policy.argv("hyprctl hyprsunset temperature {temp}", 4000),
                ["hyprctl", "hyprsunset", "temperature", "4000"]);
    }

    function test_a_template_with_no_placeholder_still_runs() {
        // wlsunset takes its temperature from its own config, and a user who
        // points this at one has a command with nothing to substitute.
        compare(policy.argv("wlsunset -T 4000", 3000), ["wlsunset", "-T", "4000"]);
    }

    function test_a_placeholder_appearing_twice_is_filled_both_times() {
        compare(policy.argv("x -a {temp} -b {temp}", 4000),
                ["x", "-a", "4000", "-b", "4000"]);
    }

    function test_argv_is_split_rather_than_handed_to_a_shell() {
        // The same call Surfaces/Drawers/SessionPolicy.qml makes and for the
        // same reason: `sh -c` on a config string buys quoting, globbing and
        // word-splitting for no gain.
        compare(policy.argv("  gammastep   -O 4000  ", 4000),
                ["gammastep", "-O", "4000"]);
    }

    function test_a_command_nobody_configured_is_no_command() {
        compare(policy.argv("", 4000), []);
        compare(policy.argv("   ", 4000), []);
        compare(policy.argv(null, 4000), []);
    }

    function test_a_blank_command_takes_the_tile_away() {
        // Emptying the key is how a user on a compositor none of this fits
        // removes the control, rather than keeping a tile that fails on every
        // press.
        verify(policy.available("hyprctl hyprsunset temperature {temp}", "hyprctl hyprsunset identity"));
        verify(!policy.available("", "hyprctl hyprsunset identity"));
        verify(!policy.available("hyprctl hyprsunset temperature {temp}", ""));
        verify(!policy.available(null, null));
    }

    // --- how warm ------------------------------------------------------------

    function test_the_temperature_is_held_inside_what_a_screen_can_do() {
        // Below ~1000K is an unreadable orange and above 6500K is not a night
        // light at all; both ends are what the tools themselves accept.
        compare(policy.clamp(4000), 4000);
        compare(policy.clamp(500), 1000);
        compare(policy.clamp(9000), 6500);
        compare(policy.clamp(4000.6), 4001);
        compare(policy.clamp(NaN), policy.defaultTemperature);
        compare(policy.clamp(null), policy.defaultTemperature);
    }

    function test_the_shipped_default_is_a_warm_evening_rather_than_amber() {
        compare(policy.defaultTemperature, 4000);
        compare(policy.minTemperature, 1000);
        compare(policy.maxTemperature, 6500);
    }

    // --- did it work ---------------------------------------------------------

    function test_a_tool_that_says_nothing_and_exits_zero_worked() {
        // gammastep, wlsunset: silence is success.
        verify(policy.accepted(0, ""));
        verify(policy.accepted(0, "\n"));
        verify(policy.accepted(0, null));
    }

    function test_hyprctls_ok_is_a_yes_and_its_prose_is_a_no() {
        // #78: hyprctl exits 0 when it refuses, so the exit status alone is not
        // the answer — the same trap Services/Compositor/LayerRulePolicy.qml
        // documents for layer rules.
        verify(policy.accepted(0, "ok"));
        verify(policy.accepted(0, "ok\n"));
        verify(!policy.accepted(0, "Invalid dispatcher"));
        verify(!policy.accepted(0, "hyprsunset is not running"));
    }

    function test_a_non_zero_exit_is_a_no_whatever_it_printed() {
        verify(!policy.accepted(1, "ok"));
        verify(!policy.accepted(127, ""));
    }

    // --- what the log says ---------------------------------------------------

    function test_turning_it_on_names_the_temperature_and_off_does_not() {
        compare(policy.applied(true, 4000), "night light on at 4000K");
        compare(policy.applied(false, 4000), "night light off");
    }

    function test_a_refusal_says_what_was_attempted_and_what_came_back() {
        compare(policy.complaint(true, 4000, 0, "Invalid dispatcher"),
                "night light on at 4000K refused — exit 0: Invalid dispatcher");
        compare(policy.complaint(false, 4000, 127, ""),
                "night light off refused — exit 127");
    }
}
