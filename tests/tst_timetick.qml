// The shell clock's wakeup schedule (#22 §5, #35). Core/Time.qml itself imports
// Quickshell and so cannot be loaded here; what it adds over this file is a
// Timer that re-arms from this function on every tick.
import QtQuick
import QtTest
import "../Core"

TestCase {
    name: "TimeTick"

    TimeTick { id: tick }

    readonly property int minute: 60000

    function test_a_tick_lands_on_the_minute() {
        // 12:34:20 waits 40 s, not 60 — the display has to change on the same
        // edge the user's watch does.
        compare(tick.msUntilNext(Date.UTC(2026, 7, 1, 12, 34, 20), minute), 40000);
        compare(tick.msUntilNext(Date.UTC(2026, 7, 1, 12, 34, 59, 999), minute), 1);
    }

    function test_exactly_on_the_boundary_waits_a_whole_period() {
        // Never zero: a timer asked to fire in no time at all is a busy loop,
        // and a clock already showing 12:34 wants 12:35.
        compare(tick.msUntilNext(Date.UTC(2026, 7, 1, 12, 34, 0), minute), minute);
    }

    function test_the_wait_is_always_inside_one_period() {
        for (const offset of [0, 1, 999, 30000, 59999]) {
            const wait = tick.msUntilNext(Date.UTC(2026, 7, 1, 12, 34, 0) + offset, minute);
            verify(wait > 0, "wait of " + wait + " would busy-loop");
            verify(wait <= minute, "wait of " + wait + " overruns the period");
        }
    }

    function test_alignment_is_absolute_not_relative_to_the_first_tick() {
        // Two shells started 20 s apart tick together, and a tick that arrives
        // late (a suspended laptop) costs one late minute rather than a drift
        // that grows all day.
        const late = Date.UTC(2026, 7, 1, 12, 34, 0) + 3 * minute + 7000;
        compare(tick.msUntilNext(late, minute), minute - 7000);
    }

    function test_a_nonsense_period_does_not_produce_a_busy_loop() {
        // Not reachable from the schema — the guard is here so a future
        // caller's arithmetic mistake costs a fast clock, not a spinning CPU.
        verify(tick.msUntilNext(1000, 0) > 0);
        verify(tick.msUntilNext(1000, -5) > 0);
        compare(tick.msUntilNext(NaN, minute), minute);
    }
}
