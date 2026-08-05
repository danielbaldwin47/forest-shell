// The one CLI wrapper in this ticket (#36, #4 §2.6: there is no brightness type
// in Quickshell at all). Everything that can be decided without running
// `brightnessctl` is decided here — which device is ours, what the reply meant,
// what to run next — so the service next door is only the subprocess.
//
// #78 is the reason `accepted` exists: a wrapper that logs "applied" off a
// process that exited is a wrapper that reports failure as success, and that
// bug cost four PRs the last time.
import QtQuick
import QtTest
import "../Services/Hardware"

TestCase {
    name: "BacklightPolicy"

    BacklightPolicy { id: policy }

    // `brightnessctl -m` output, verbatim from the T480.
    readonly property string probeReply: "intel_backlight,backlight,2,0%,1515\n"

    function test_the_probe_asks_only_about_backlights() {
        // Without the class filter the first device on this laptop is a
        // keyboard LED, and the shell would spend the session dimming that.
        compare(policy.probeCommand(), ["brightnessctl", "-m", "-c", "backlight", "info"]);
    }

    function test_the_probe_reply_names_the_device_and_its_range() {
        const device = policy.parse(probeReply);
        compare(device.name, "intel_backlight");
        compare(device.current, 2);
        compare(device.max, 1515);
    }

    function test_a_reply_with_several_devices_takes_the_first_backlight() {
        const device = policy.parse("tpacpi::kbd_backlight,leds,0,0%,2\n"
                                    + "intel_backlight,backlight,758,50%,1515\n");
        compare(device.name, "intel_backlight");
        compare(device.current, 758);
    }

    function test_a_machine_with_no_backlight_answers_null() {
        // A desktop, or a laptop whose panel is driven by DDC. The module is
        // off by default anyway (#9); this is what keeps it off rather than
        // showing a dead slider.
        compare(policy.parse(""), null);
        compare(policy.parse("tpacpi::kbd_backlight,leds,0,0%,2\n"), null);
        compare(policy.parse("Device 'nosuch' not found.\n"), null);
        compare(policy.parse(null), null);
    }

    function test_a_raw_value_reads_as_a_percent_of_the_range() {
        compare(policy.percent(1515, 1515), 100);
        compare(policy.percent(758, 1515), 50);
        compare(policy.percent(0, 1515), 0);
    }

    function test_a_missing_range_is_zero_rather_than_infinity() {
        compare(policy.percent(10, 0), 0);
        compare(policy.percent(10, NaN), 0);
        compare(policy.percent(NaN, 1515), 0);
    }

    function test_a_step_lands_on_the_step_grid_and_never_reaches_black() {
        // 0% on an intel backlight is a screen you cannot read to turn it back
        // up with, so the floor is one step of light rather than none.
        compare(policy.stepped(50, 1), 55);
        compare(policy.stepped(52, 1), 55);
        compare(policy.stepped(52, -1), 50);
        compare(policy.stepped(100, 1), 100);
        compare(policy.stepped(3, -1), policy.minPercent);
        compare(policy.stepped(0, -1), policy.minPercent);
    }

    function test_a_set_names_the_device_it_measured() {
        // Not the default device: the probe already answered which backlight is
        // the panel, and re-guessing per call is how a keyboard LED gets dimmed.
        compare(policy.setCommand("intel_backlight", 40),
                ["brightnessctl", "-d", "intel_backlight", "-q", "set", "40%"]);
    }

    function test_a_set_outside_the_range_is_clamped_before_it_is_spelled() {
        compare(policy.setCommand("intel_backlight", 140)[5], "100%");
        compare(policy.setCommand("intel_backlight", -5)[5], policy.minPercent + "%");
    }

    function test_only_a_clean_exit_counts_as_applied() {
        // brightnessctl exits 1 and prints to stderr for a device it cannot
        // find, and exits 0 when it worked — unlike hyprctl (#78), the status
        // is the whole answer here, and it is checked.
        verify(policy.accepted(0));
        verify(!policy.accepted(1));
        verify(!policy.accepted(127));
    }

    function test_both_outcomes_have_a_log_line_that_names_the_value() {
        // A harness reads these (#81): a state change with no line is a state
        // change nothing can assert on.
        const applied = policy.applied("intel_backlight", 40);
        verify(applied.indexOf("intel_backlight") >= 0);
        verify(applied.indexOf("40") >= 0);

        const complaint = policy.complaint("intel_backlight", 40, 1, "No such device");
        verify(complaint.indexOf("intel_backlight") >= 0);
        verify(complaint.indexOf("40") >= 0);
        verify(complaint.indexOf("1") >= 0);
        verify(complaint.indexOf("No such device") >= 0);
    }

    function test_the_sysfs_path_is_derived_from_the_device_name() {
        // Reading is a file read and not a subprocess: it is free, it is live,
        // and `actual_brightness` is what the panel is really doing rather than
        // what was last asked for. There is no second path for the range — the
        // probe already reported it, and it cannot change while the machine is
        // up.
        compare(policy.valuePath("intel_backlight"),
                "/sys/class/backlight/intel_backlight/actual_brightness");
        // Before the probe has answered, and on a machine with no backlight:
        // an empty path is what keeps the FileView from reading `/sys/class/
        // backlight//actual_brightness`.
        compare(policy.valuePath(""), "");
    }

    function test_a_sysfs_read_survives_whitespace_and_nonsense() {
        compare(policy.number("1515\n"), 1515);
        compare(policy.number(" 2 "), 2);
        compare(policy.number(""), 0);
        compare(policy.number("not a number"), 0);
        compare(policy.number(null), 0);
    }

    // --- freshness (#186) ----------------------------------------------------
    //
    // A sysfs attribute change is a poll() wakeup rather than an inotify event,
    // so the file view's `watchChanges` never fires for the panel and a
    // brightness the shell did not set stays invisible to it. The facade
    // therefore re-reads on demand, and when a read is due is decided here.

    function test_a_value_that_was_never_read_is_due() {
        // 0 is the stamp before the first read, and the value behind it is the
        // facade's pre-read 0% — the number #186 was reported as seeing.
        verify(policy.readDue(10000, 0));
    }

    function test_a_value_read_a_moment_ago_is_not_read_again() {
        // Several surfaces appearing at once — the drawer and the bar module —
        // ask within the same frame, and that is one read, not three.
        verify(!policy.readDue(10000, 10000 - policy.staleMs + 1));
        verify(policy.readDue(10000, 10000 - policy.staleMs));
        verify(policy.readDue(10000, 10000 - policy.staleMs - 1));
    }

    function test_a_clock_that_moved_backwards_reads_rather_than_waits() {
        // Suspend and resume moves the clock, and a stamp in the future would
        // otherwise park the value as fresh forever — on the one transition
        // most likely to have changed the panel behind the shell's back.
        verify(policy.readDue(500, 900));
        verify(policy.readDue(10000, NaN));
        verify(policy.readDue(10000, undefined));
    }

    function test_polling_runs_only_while_something_shows_brightness() {
        // #186's constraint, and the one that rules out a bare timer: nothing
        // new ticks while no surface is displaying a level. The count is a
        // count and not a flag because the drawer and the bar module can each
        // hold one at the same time.
        verify(!policy.pollRunning(0, true));
        verify(policy.pollRunning(1, true));
        verify(policy.pollRunning(2, true));
        // A machine with no backlight has nothing to read.
        verify(!policy.pollRunning(1, false));
        // A release that ran twice must not arm the timer with a negative count.
        verify(!policy.pollRunning(-1, true));
    }

    function test_the_poll_interval_outlasts_the_freshness_window() {
        // Otherwise every tick would find its own last read still fresh and the
        // timer would run without ever reading anything.
        verify(policy.pollMs >= policy.staleMs);
        verify(policy.staleMs > 0);
    }

    function test_the_watch_line_names_the_count_and_the_interval() {
        // #81: a subscription that logs nothing is a wakeup nobody can account
        // for later.
        const line = policy.watching(2, 2000);
        verify(line.indexOf("2") >= 0);
        verify(line.indexOf("2000") >= 0);
    }
}
