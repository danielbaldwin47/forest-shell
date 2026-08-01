// The ridgeline's falloff (#35): the rule that turns a row of workspaces into
// a range that recedes.
import QtQuick
import QtTest
import "../Surfaces/Bar"

TestCase {
    name: "RidgelineSpec"

    RidgelineSpec { id: spec }

    readonly property var knobs: spec.knobs({})

    function cells(ids, activeId, occupiedIds) {
        return ids.map(id => ({
            id: id,
            occupied: occupiedIds.indexOf(id) >= 0,
            active: id === activeId
        }));
    }

    // --- knobs ---------------------------------------------------------------

    function test_the_shipped_ridge_is_the_measured_one() {
        // #10's sheet: strata w14/gap4, heights 14/9/3, 2px falloff,
        // haze 1.0/0.62/0.22.
        compare(knobs.unitWidth, 14);
        compare(knobs.gap, 4);
        compare(knobs.activeHeight, 14);
        compare(knobs.occupiedHeight, 9);
        compare(knobs.emptyHeight, 3);
        compare(knobs.falloff, 2);
        compare(spec.activeHaze, 1.0);
        compare(knobs.occupiedHaze, 0.62);
        compare(knobs.emptyHaze, 0.22);
        compare(knobs.slots, 5);
    }

    function test_hand_edited_knobs_are_salvaged() {
        compare(spec.knobs({ unitWidth: "20" }).unitWidth, 20);
        compare(spec.knobs({ unitWidth: "wide" }).unitWidth, 14);
        compare(spec.knobs({ slots: 0 }).slots, 1);
        compare(spec.knobs({ occupiedHaze: 4 }).occupiedHaze, 1.0);
        compare(spec.knobs(null).activeHeight, 14);
    }

    // --- falloff -------------------------------------------------------------

    function test_the_active_workspace_is_the_near_edge() {
        const row = spec.strata(cells([1, 2, 3], 2, [1, 2, 3]), knobs);
        compare(row[1].length, 14);
        compare(row[1].haze, 1.0);
    }

    function test_neighbours_fall_away_by_distance() {
        const row = spec.strata(cells([1, 2, 3, 4, 5], 1, [1, 2, 3, 4, 5]), knobs);
        compare(row[1].length, 9);   // distance 1 — no falloff yet
        compare(row[2].length, 7);
        compare(row[3].length, 5);
        compare(row[4].length, 4);   // floored at minHeight, never inverted
        fuzzyCompare(row[1].haze, 0.62, 0.001);
        fuzzyCompare(row[2].haze, 0.52, 0.001);
        fuzzyCompare(row[3].haze, 0.42, 0.001);
    }

    function test_falloff_is_symmetric_around_the_active_workspace() {
        const row = spec.strata(cells([1, 2, 3, 4, 5], 3, [1, 2, 3, 4, 5]), knobs);
        compare(row[1].length, row[3].length);
        compare(row[0].length, row[4].length);
        fuzzyCompare(row[0].haze, row[4].haze, 0.0001);
    }

    function test_empty_workspaces_sit_at_the_vanishing_height() {
        // Empties do not participate in the falloff — they are already gone.
        const row = spec.strata(cells([1, 2, 3], 1, [1]), knobs);
        compare(row[1].length, 3);
        compare(row[2].length, 3);
        fuzzyCompare(row[1].haze, 0.22, 0.001);
        fuzzyCompare(row[2].haze, 0.22, 0.001);
    }

    function test_distance_is_counted_in_row_positions_not_in_ids() {
        // Hyprland leaves holes (1, 2, 3, 9). By id, workspace 9 would be six
        // steps away and hit the floor for being numbered high rather than for
        // being far; on screen it is the next stratum along.
        const row = spec.strata(cells([1, 2, 3, 9], 3, [1, 2, 3, 9]), knobs);
        compare(row[3].length, 9);
        fuzzyCompare(row[3].haze, 0.62, 0.001);
    }

    function test_a_row_with_no_active_workspace_still_draws() {
        // Between a workspace closing and the focus event arriving.
        const row = spec.strata(cells([1, 2], 0, [1, 2]), knobs);
        compare(row.length, 2);
        compare(row[0].length, 9);
        compare(row[1].length, 9);
    }

    function test_an_empty_row_is_not_an_error() {
        compare(spec.strata([], knobs).length, 0);
        compare(spec.strata(null, knobs).length, 0);
    }

    function test_the_row_keeps_its_identity() {
        // The widget draws these; the module dispatches clicks off `id`.
        const row = spec.strata(cells([1, 4], 4, [4]), knobs);
        compare(row[0].id, 1);
        compare(row[1].id, 4);
        compare(row[1].active, true);
        compare(row[0].occupied, false);
    }
}
