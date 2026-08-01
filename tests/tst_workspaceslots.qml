// A workspace row that holds still (#35), on top of a compositor that destroys
// empty workspaces the moment you leave them.
import QtQuick
import QtTest
import "../Surfaces/Bar/Modules"

TestCase {
    name: "WorkspaceSlots"

    WorkspaceSlots { id: slots }

    function test_the_row_is_the_slot_range_even_when_nothing_exists() {
        // A freshly started session has one workspace. The row still has five
        // slots, or switching to workspace 4 would mean clicking nothing.
        const row = slots.row([{ id: 1, occupied: true, active: true }], 5);
        compare(row.length, 5);
        compare(row.map(cell => cell.id), [1, 2, 3, 4, 5]);
        compare(row[0].occupied, true);
        compare(row[3].occupied, false);
        compare(row[3].active, false);
    }

    function test_live_workspaces_past_the_range_are_appended() {
        // Workspaces opened by hand past the slot range show up rather than
        // stretching the row out to meet them.
        const row = slots.row([
            { id: 1, occupied: true, active: false },
            { id: 9, occupied: true, active: true }
        ], 3);
        compare(row.map(cell => cell.id), [1, 2, 3, 9]);
        compare(row[3].active, true);
    }

    function test_the_row_is_ascending_whatever_order_it_arrives_in() {
        const row = slots.row([
            { id: 12, occupied: true, active: false },
            { id: 7, occupied: true, active: false }
        ], 2);
        compare(row.map(cell => cell.id), [1, 2, 7, 12]);
    }

    function test_special_workspaces_are_not_part_of_the_row() {
        // Scratchpads have negative ids. They are not places you move along a
        // row, and putting them in one would make the row jump.
        const row = slots.row([
            { id: -99, occupied: true, active: true },
            { id: 1, occupied: true, active: false }
        ], 2);
        compare(row.map(cell => cell.id), [1, 2]);
    }

    function test_an_empty_compositor_answer_still_gives_a_row() {
        // `Hyprland.workspaces` populates asynchronously — this is what the
        // first frame or two actually renders.
        compare(slots.row([], 5).length, 5);
        compare(slots.row(null, 3).map(cell => cell.id), [1, 2, 3]);
        for (const cell of slots.row(null, 3)) {
            compare(cell.occupied, false);
            compare(cell.active, false);
        }
    }

    function test_a_single_slot_row_is_legal() {
        compare(slots.row([{ id: 1, occupied: true, active: true }], 1).length, 1);
    }
}
