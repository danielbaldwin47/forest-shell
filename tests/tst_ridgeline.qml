// The ridgeline encoding (#10, #35): height *and* opacity both falling away
// with distance from the peak, which is what makes the row read as a range of
// hills rather than as a bar chart.
//
// Widgets/Ridgeline.qml imports nothing but QtQuick, so the encoding is
// exercised here directly. What is not checked here is what it looks like —
// that was measured on the T480 during the prototype, and the numbers those
// measurements settled live in Core/SettingsSchema.qml.
import QtQuick
import QtTest
import "../Core"
import "../Widgets"

TestCase {
    name: "Ridgeline"

    SettingsSchema { id: settings }
    SpecStore { id: store }

    // The state the prototype's screenshots were taken in: workspaces 1, 2, 3
    // and 5 occupied with 3 focused, so the falloff is visible in both
    // directions and an empty slot sits between two occupied ones.
    readonly property var sample: [
        { id: 1, occupied: true, active: false },
        { id: 2, occupied: true, active: false },
        { id: 3, occupied: true, active: true },
        { id: 4, occupied: false, active: false },
        { id: 5, occupied: true, active: false }
    ]

    Ridgeline {
        id: ridge
        cells: [
            { id: 1, occupied: true, active: false },
            { id: 2, occupied: true, active: false },
            { id: 3, occupied: true, active: true },
            { id: 4, occupied: false, active: false },
            { id: 5, occupied: true, active: false }
        ]
    }

    function test_the_active_form_is_the_peak() {
        const strata = ridge.strata;
        compare(strata[2].active, true);
        compare(strata[2].extent, ridge.activeHeight);
        // Fully opaque, always: the peak is the one form that never hazes.
        compare(strata[2].haze, 1.0);
    }

    function test_occupied_neighbours_fall_away_by_step() {
        const strata = ridge.strata;
        // One step out keeps the full occupied height; each further step loses
        // `falloff` px and `hazeFalloff` of opacity.
        compare(strata[1].extent, 9);
        compare(strata[0].extent, 7);
        compare(strata[1].haze, 0.62);
        fuzzyCompare(strata[0].haze, 0.52, 0.0001);
    }

    function test_empty_forms_sit_at_the_vanishing_height_regardless() {
        // Distance does not apply to an empty workspace: it is already as gone
        // as it gets, and stepping it further would make it disappear.
        const strata = ridge.strata;
        compare(strata[3].extent, ridge.emptyHeight);
        compare(strata[3].haze, ridge.emptyHaze);
        compare(strata[3].occupied, false);
    }

    function test_distance_is_counted_along_the_row_not_in_ids() {
        // Workspace 5 is two positions from the peak, not two ids past a gap —
        // what recedes is what is further away on screen.
        compare(ridge.strata[4].extent, 7);
    }

    function test_the_falloff_has_a_floor() {
        // A long row must not walk occupied workspaces down to nothing: past
        // the floor they stop shrinking and stay countable.
        const long = [];
        for (let id = 1; id <= 12; id++)
            long.push({ id: id, occupied: true, active: id === 1 });
        ridge.cells = long;

        const strata = ridge.strata;
        compare(strata[11].extent, ridge.minHeight);
        compare(strata[11].haze, ridge.minHaze);
        verify(strata[11].extent > 0);

        ridge.cells = sample;
    }

    function test_nothing_focused_yet_picks_no_winner() {
        // `Hyprland.workspaces` populates asynchronously, so this is the state
        // the bar paints for its first frame or two.
        ridge.cells = [
            { id: 1, occupied: true, active: false },
            { id: 2, occupied: false, active: false }
        ];
        const strata = ridge.strata;
        compare(strata[0].active, false);
        compare(strata[0].extent, ridge.occupiedHeight);
        compare(strata[1].extent, ridge.emptyHeight);

        ridge.cells = sample;
    }

    function test_ids_are_carried_through_untouched() {
        // The widget has no idea what a workspace is; the id is a handle it
        // hands back with `cellActivated`.
        ridge.cells = [{ id: "scratch", occupied: true, active: true }];
        compare(ridge.strata[0].id, "scratch");

        ridge.cells = sample;
    }

    function test_the_row_reserves_the_tallest_form_it_could_draw() {
        // Not the tallest one currently drawn: the bar's layout must not
        // reflow every time you switch workspace.
        compare(ridge.extent, ridge.activeHeight);
        compare(ridge.implicitHeight, ridge.activeHeight);
        compare(ridge.implicitWidth, 5 * ridge.unitWidth + 4 * ridge.gap);
    }

    function test_the_widgets_own_defaults_are_the_decided_ones() {
        // The geometry lives in two places — here as the widget's fallback,
        // and in `bar.ridgeline` as what the bar actually passes. Both are the
        // measured taste call from #10, and this is what stops the copies
        // drifting apart in silence.
        const decided = store.defaults(settings.spec).bar.ridgeline;
        compare(ridge.unitWidth, decided.unitWidth);
        compare(ridge.gap, decided.gap);
        compare(ridge.activeHeight, decided.activeHeight);
        compare(ridge.occupiedHeight, decided.occupiedHeight);
        compare(ridge.emptyHeight, decided.emptyHeight);
        compare(ridge.falloff, decided.falloff);
        compare(ridge.minHeight, decided.minHeight);
        compare(ridge.occupiedHaze, decided.occupiedHaze);
        compare(ridge.emptyHaze, decided.emptyHaze);
        compare(ridge.hazeFalloff, decided.hazeFalloff);
        compare(ridge.minHaze, decided.minHaze);
    }

    function test_an_empty_row_has_no_size_and_does_not_throw() {
        ridge.cells = [];
        compare(ridge.strata.length, 0);
        compare(ridge.implicitWidth, 0);

        ridge.cells = sample;
    }
}
