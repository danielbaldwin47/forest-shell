// The workspace row: fixed slots unioned with whatever Hyprland currently has
// (#35). Services/Compositor/Compositor.qml itself imports Quickshell and so
// cannot be loaded here; what it adds over this file is the IPC wiring, which
// the shell verifies by running.
import QtQuick
import QtTest
import "../Services/Compositor"

TestCase {
    name: "WorkspaceSlots"

    WorkspaceSlots { id: slots }

    function test_the_fixed_range_is_always_there() {
        // Nothing running at all still draws a five-slot ridge.
        const cells = slots.cells(5, [], 1);
        compare(cells.length, 5);
        compare(cells.map(c => c.id).join(","), "1,2,3,4,5");
        verify(cells.every(c => !c.occupied));
    }

    function test_occupancy_comes_from_the_window_count() {
        const cells = slots.cells(3, [{ id: 1, windows: 2 }, { id: 2, windows: 0 }], 1);
        compare(cells[0].occupied, true);
        compare(cells[1].occupied, false);
        compare(cells[2].occupied, false);
    }

    function test_a_workspace_with_no_window_count_counts_as_occupied() {
        // `lastIpcObject` is only filled after a refresh. Until then the
        // workspace exists, which is itself the evidence — Hyprland does not
        // keep empty ones.
        const cells = slots.cells(2, [{ id: 2 }], 1);
        compare(cells[1].occupied, true);
    }

    function test_live_workspaces_beyond_the_range_are_appended_in_order() {
        const cells = slots.cells(3, [{ id: 9, windows: 1 }, { id: 5, windows: 1 }], 1);
        compare(cells.map(c => c.id).join(","), "1,2,3,5,9");
        compare(cells[3].occupied, true);
        compare(cells[4].occupied, true);
    }

    function test_special_workspaces_never_get_a_slot() {
        // Negative ids are Hyprland's scratchpad; they are not part of the
        // numbered range and drawing them would put a stray peak on the ridge.
        const cells = slots.cells(2, [{ id: -99, windows: 3 }], 1);
        compare(cells.map(c => c.id).join(","), "1,2");
    }

    function test_the_active_workspace_is_always_in_the_row() {
        // The focus event can arrive before the workspace list catches up.
        const cells = slots.cells(3, [], 7);
        compare(cells.map(c => c.id).join(","), "1,2,3,7");
        compare(cells[3].active, true);
        compare(cells[3].occupied, true);
    }

    function test_exactly_one_cell_is_active() {
        const cells = slots.cells(5, [{ id: 3, windows: 1 }], 3);
        compare(cells.filter(c => c.active).length, 1);
        compare(cells.filter(c => c.active)[0].id, 3);
    }

    function test_a_duplicated_id_does_not_duplicate_a_slot() {
        // The union is over ids, not over list entries — a workspace reported
        // twice by two monitors is still one peak.
        const cells = slots.cells(1, [{ id: 4, windows: 0 }, { id: 4, windows: 2 }], 1);
        compare(cells.map(c => c.id).join(","), "1,4");
        compare(cells[1].occupied, true);
    }

    function test_garbage_survives_contact() {
        // Everything here arrives from an IPC object that may be half-parsed.
        compare(slots.cells(0, null, 0).length, 0);
        compare(slots.cells(2, [null, { id: "x" }, { }], 1).map(c => c.id).join(","), "1,2");
    }
}
