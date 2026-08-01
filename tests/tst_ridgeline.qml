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

    // Every test below starts from the same row, so a test that moves the peak
    // to watch it animate does not decide what the next one is reading.
    function init() {
        ridge.cells = sample;
        ridge.animateExtent = true;
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

    // --- the row as an item tree, not as an encoding -------------------------
    //
    // #75: every test above passed from the first commit and the indicator had
    // still never animated on any machine. `strata` returns a *new* array of
    // new objects each time `cells` changes, and a Repeater over a JS array
    // does not diff it — so a workspace switch tore down every delegate and
    // built fresh ones, and a QML `Behavior` does not run on a property's
    // initial value. The Behaviors were attached to items that were destroyed
    // before they could ever fire.
    //
    // Nothing above could see that, because nothing above looked at what the
    // widget *built*. These do. It is still seam 1 — Ridgeline imports nothing
    // but QtQuick, so its item tree and its animations are as reachable from
    // qmltestrunner as its arithmetic was.

    /// The delegate items, in row order. The Grid holds the Repeater as well,
    /// which is told apart by not carrying a `modelData`.
    function forms() {
        const grid = ridge.children[0];
        const out = [];
        for (let i = 0; i < grid.children.length; i++)
            if (grid.children[i].modelData !== undefined)
                out.push(grid.children[i]);
        return out;
    }

    /// The Rectangle inside a delegate — the thing that is actually drawn, and
    /// the thing the Behaviors are on. The handlers are not items, so it is the
    /// delegate's only child.
    function drawn(form) {
        return form.children[0];
    }

    /// A row of `count` cells with the peak at `peak`, all occupied.
    function row(count, peak) {
        const out = [];
        for (let i = 0; i < count; i++)
            out.push({ id: i + 1, occupied: true, active: i === peak });
        return out;
    }

    /// Put the row in a known state and let anything in flight land, so a test
    /// starting here is measuring its own change and not the previous one's.
    function settle(cells) {
        ridge.cells = cells;
        wait(ridge.motionMs + 120);
    }

    function test_a_workspace_change_reuses_the_forms_it_already_built() {
        // The bug, stated directly: same number of slots, so the same items
        // must still be there afterwards. New items would have no previous
        // value to animate from.
        settle(row(5, 2));
        const before = forms();
        compare(before.length, 5);

        ridge.cells = row(5, 4);

        const after = forms();
        compare(after.length, 5);
        for (let i = 0; i < 5; i++)
            verify(before[i] === after[i], "form " + i + " was rebuilt by a workspace change");
    }

    function test_the_extent_animates_rather_than_snapping() {
        settle(row(5, 2));

        // Two positions from the peak, so `occupiedHeight - falloff`.
        const rising = drawn(forms()[4]);
        compare(rising.height, 7);

        ridge.cells = row(5, 4);

        // A Behavior holds the property at its old value and animates from
        // there; a rebuilt delegate is born at the new one, which is exactly
        // what #75 measured as one frame per switch.
        verify(rising.height < ridge.activeHeight,
               "the peak snapped to " + rising.height + " instead of animating");
        verify(rising.height > 0);
        tryCompare(rising, "height", ridge.activeHeight, 2000);
    }

    function test_the_haze_animates_too() {
        settle(row(5, 2));

        const rising = drawn(forms()[4]);
        fuzzyCompare(rising.opacity, 0.52, 0.0001);

        ridge.cells = row(5, 4);

        verify(rising.opacity < 1.0, "the haze snapped to full opacity");
        tryCompare(rising, "opacity", 1.0, 2000);
    }

    function test_reduced_effects_snaps_the_extent_and_keeps_the_fade() {
        // `animateExtent: false` is the bottom rung of the degrade ladder
        // (#22 §7): an opacity-only crossfade, with the heights arriving at
        // once. The forms are still reused — that is what leaves the fade
        // something to run on.
        settle(row(5, 2));
        ridge.animateExtent = false;

        const rising = drawn(forms()[4]);
        ridge.cells = row(5, 4);

        compare(rising.height, ridge.activeHeight);
        verify(rising.opacity < 1.0, "reduced effects lost the crossfade as well");
        tryCompare(rising, "opacity", 1.0, 2000);

        ridge.animateExtent = true;
    }

    function test_a_row_that_changes_length_is_rebuilt_and_still_correct() {
        // The one case that *should* rebuild: `bar.ridgeline.slots` changed, or
        // a live workspace appeared past the slot range, so the row is a
        // genuinely different row. Both directions, because shrinking asks
        // delegates to read an index their row no longer has.
        failOnWarning(/TypeError/);

        settle(row(5, 2));
        compare(forms().length, 5);

        settle(row(6, 5));
        const grown = forms();
        compare(grown.length, 6);
        compare(drawn(grown[5]).height, ridge.activeHeight);
        compare(drawn(grown[0]).height, ridge.minHeight);

        settle(row(3, 0));
        const shrunk = forms();
        compare(shrunk.length, 3);
        compare(drawn(shrunk[0]).height, ridge.activeHeight);
        compare(drawn(shrunk[2]).height, ridge.occupiedHeight - ridge.falloff);

        ridge.cells = sample;
    }

    function test_a_live_workspace_past_the_slot_range_still_draws() {
        // What `WorkspaceSlots` hands over when you open a workspace 9 by hand:
        // a row that is the slot range plus one, with the stray on the right.
        failOnWarning(/TypeError/);

        settle([
            { id: 1, occupied: true, active: false },
            { id: 2, occupied: false, active: false },
            { id: 3, occupied: false, active: false },
            { id: 4, occupied: false, active: false },
            { id: 5, occupied: false, active: false },
            { id: 9, occupied: true, active: true }
        ]);

        const built = forms();
        compare(built.length, 6);
        compare(drawn(built[5]).height, ridge.activeHeight);
        compare(built[5].modelData.id, 9);

        ridge.cells = sample;
    }
}
