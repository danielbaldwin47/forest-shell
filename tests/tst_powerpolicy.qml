// What the battery module decides (#36): a UPower fraction and a state enum
// turned into a percentage, a glyph and a level of alarm.
//
// The percentage and the low threshold came from the lock screen (#30), which
// grew them first and now reads them from here — the lock and the bar
// disagreeing about what "low" means would be visible on the same screen.
import QtQuick
import QtTest
import "../Services/Hardware"

TestCase {
    name: "PowerPolicy"

    PowerPolicy { id: policy }

    function test_a_upower_fraction_reads_as_a_whole_percent() {
        // `UPowerDevice.percentage` is energy / energyCapacity — a 0-1
        // fraction, not the 0-100 the name suggests.
        compare(policy.percent(0.48653940283896235), 49);
        compare(policy.percent(0), 0);
        compare(policy.percent(1), 100);
    }

    function test_a_battery_over_a_hundred_percent_does_not_widen_the_pill() {
        compare(policy.percent(1.04), 100);
        compare(policy.percent(-0.1), 0);
        compare(policy.percent(NaN), 0);
    }

    function test_the_upower_states_have_names() {
        // The enum is `UPowerDeviceState`, and the ints are what the binding
        // hands over. Named here so nothing downstream compares magic numbers.
        compare(policy.stateName(0), "unknown");
        compare(policy.stateName(1), "charging");
        compare(policy.stateName(2), "discharging");
        compare(policy.stateName(3), "empty");
        compare(policy.stateName(4), "full");
        compare(policy.stateName(5), "pendingCharge");
        compare(policy.stateName(6), "pendingDischarge");
        compare(policy.stateName(99), "unknown");
    }

    function test_plugged_in_is_not_the_same_as_charging() {
        // A full battery on mains is not charging and a pending charge is not
        // either, but neither is draining — and "is it draining" is the
        // question the bar is actually answering.
        verify(policy.onMains(1));    // charging
        verify(policy.onMains(4));    // full
        verify(policy.onMains(5));    // pending charge
        verify(!policy.onMains(2));   // discharging
        verify(!policy.onMains(6));   // pending discharge
    }

    function test_charging_has_its_own_glyph_at_any_level() {
        compare(policy.icon(0.05, 1), "battery-charging");
        compare(policy.icon(0.95, 1), "battery-charging");
    }

    function test_the_glyph_follows_the_charge_while_discharging() {
        compare(policy.icon(0.9, 2), "battery-full");
        compare(policy.icon(0.5, 2), "battery-medium");
        compare(policy.icon(0.25, 2), "battery-low");
        compare(policy.icon(0.05, 2), "battery-warning");
    }

    function test_low_and_critical_are_the_two_thresholds() {
        verify(!policy.low(0.25));
        verify(policy.low(0.20));
        verify(policy.low(0.05));
        verify(!policy.critical(0.15));
        verify(policy.critical(0.10));
        verify(!policy.low(NaN));
        verify(!policy.critical(NaN));
    }

    function test_a_charging_battery_is_never_urgent() {
        // The one thing a low battery asks for is already happening.
        compare(policy.emphasis(0.05, 1), "quiet");
        compare(policy.emphasis(0.05, 2), "urgent");
        compare(policy.emphasis(0.18, 2), "attention");
        compare(policy.emphasis(0.80, 2), "quiet");
    }

    function test_the_time_left_is_written_the_way_a_person_says_it() {
        compare(policy.timeRemaining(0), "");
        compare(policy.timeRemaining(-1), "");
        compare(policy.timeRemaining(45 * 60), "45m");
        compare(policy.timeRemaining(3 * 3600 + 20 * 60), "3h 20m");
        compare(policy.timeRemaining(2 * 3600), "2h");
        compare(policy.timeRemaining(30), "1m");   // never "0m"
    }

    function test_a_desktop_shows_no_battery_module_at_all() {
        // `UPower.displayDevice` exists on every machine; on a desktop it is a
        // placeholder reporting nothing. A module that rendered it would show
        // 0% forever.
        verify(policy.hasBattery(true, true));
        verify(!policy.hasBattery(false, true));
        verify(!policy.hasBattery(true, false));
    }

    function test_the_label_is_a_percent() {
        compare(policy.label(0.486), "49%");
        compare(policy.label(1), "100%");
    }
}
