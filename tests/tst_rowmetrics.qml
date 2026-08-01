// How a settings row divides its width between prose and control (#80).
//
// The row shipped with the text column on `Layout.fillWidth` (take the
// leftovers) and the control slot on an unbounded `implicitWidth` (never
// shrink), so the control was served first however wide it was. On the
// Appearance tab that put the theming-mode hint on nine lines of one word and
// pushed the three chips off the right edge of the window.
//
// The arithmetic that replaces it is here; the picture it produces is seam 2's
// problem, and the capture that would prove it needs a real session (see the
// header of tools/nested-session.sh).
import QtQuick
import QtTest
import "../Surfaces/Settings/Controls"

TestCase {
    name: "RowMetrics"

    RowMetrics { id: metrics }

    // The Appearance tab in the window's default size: 900 wide, less the
    // 196px rail, its hairline, and the page's 32px padding either side.
    readonly property real widePane: 900 - 196 - 1 - 32 * 2

    // ...and at the window's minimum size, 720 wide.
    readonly property real narrowPane: 720 - 196 - 1 - 32 * 2

    // Row spacing plus the reset affordance, which is what the row spends on
    // itself before either column gets any.
    readonly property real taken: 20 + 20

    function test_the_text_column_keeps_its_floor() {
        // The whole bug in one line: whatever the control wants, the prose
        // keeps a readable measure.
        compare(metrics.slotCeiling(widePane, taken), widePane - metrics.textFloor - taken);
        verify(widePane - metrics.slotCeiling(widePane, taken) >= metrics.textFloor);
        verify(narrowPane - metrics.slotCeiling(narrowPane, taken) >= metrics.textFloor);
    }

    function test_the_control_keeps_a_floor_of_its_own() {
        // Past the point where both fit, the row stops taking width off the
        // control and gets taller instead.
        compare(metrics.slotCeiling(300, taken), metrics.slotFloor);
        compare(metrics.slotCeiling(0, taken), metrics.slotFloor);
        verify(metrics.slotCeiling(-100, taken) > 0);
    }

    function test_a_narrow_control_is_left_where_it_is() {
        // A switch is 40px wide. It must not be stretched across a 300px slot,
        // or every row's control drifts away from the right edge.
        const ceiling = metrics.slotCeiling(widePane, taken);
        compare(metrics.slotWidth(40, ceiling), 40);
    }

    function test_an_over_wide_control_is_what_gets_compressed() {
        // Three theming chips, near enough: wider than the ceiling, so the
        // control wraps and the hint keeps its column.
        const ceiling = metrics.slotCeiling(narrowPane, taken);
        compare(metrics.slotWidth(400, ceiling), ceiling);
        verify(metrics.slotWidth(400, ceiling) >= metrics.slotFloor);
    }

    function test_no_ceiling_means_no_constraint() {
        // A control used outside a SettingRow — the notification rule row, the
        // module pool — has no slot around it and keeps its natural width.
        compare(metrics.slotWidth(400, 0), 400);
    }
}
