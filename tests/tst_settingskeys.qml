// What a key press means in the settings window (#77).
//
// The window shipped pointer-only: nothing was focusable, Space did not toggle a
// switch, the tab rail did not answer the arrow keys and Escape did not close
// it. Every one of those is a decision about a key, so all of them live in
// `Controls/KeyPolicy.qml` and are checked here — what is left in the controls
// is a focus ring and a call into it, which is the half that needs a compositor.
import QtQuick
import QtTest
import "../Surfaces/Settings/Controls"

TestCase {
    name: "SettingsKeys"

    KeyPolicy { id: keys }

    function test_space_and_enter_activate() {
        // Both, because the controls are a mix of buttons and list selections
        // and the window is not the place to remember which is which.
        verify(keys.isActivate(Qt.Key_Space));
        verify(keys.isActivate(Qt.Key_Return));
        verify(keys.isActivate(Qt.Key_Enter));   // the keypad one
        verify(!keys.isActivate(Qt.Key_Tab));
        verify(!keys.isActivate(Qt.Key_A));
        verify(!keys.isActivate(Qt.Key_Escape));
    }

    function test_escape_dismisses_and_nothing_else_does() {
        verify(keys.isDismiss(Qt.Key_Escape));
        verify(!keys.isDismiss(Qt.Key_Q));
        verify(!keys.isDismiss(Qt.Key_Backspace));
    }

    function test_arrows_step_on_both_axes() {
        // The rail is vertical and a chip row is horizontal; answering only one
        // axis would leave half the arrows dead.
        compare(keys.step(Qt.Key_Left), -1);
        compare(keys.step(Qt.Key_Up), -1);
        compare(keys.step(Qt.Key_Right), 1);
        compare(keys.step(Qt.Key_Down), 1);
        compare(keys.step(Qt.Key_Space), 0);
        compare(keys.step(Qt.Key_Home), 0);
    }

    function test_advance_walks_one_step() {
        const all = [true, true, true];
        compare(keys.advance(0, 1, all), 1);
        compare(keys.advance(1, -1, all), 0);
        compare(keys.advance(1, 0, all), 1);
    }

    function test_advance_stops_at_the_ends() {
        // Clamped, not wrapped: Right on the last chip selecting the first
        // reads as a misfire on a control whose alternatives are all visible.
        const all = [true, true, true];
        compare(keys.advance(2, 1, all), 2);
        compare(keys.advance(0, -1, all), 0);
    }

    function test_advance_skips_what_cannot_be_chosen() {
        // The Appearance tab's exact shape: fixed forest is choosable, the two
        // wallpaper-coupled modes are listed and inert until #58/#59 land.
        const modes = [true, false, false];
        compare(keys.advance(0, 1, modes), 0);

        const middleGone = [true, false, true];
        compare(keys.advance(0, 1, middleGone), 2);
        compare(keys.advance(2, -1, middleGone), 0);
    }

    function test_advance_from_an_index_that_is_not_in_the_list() {
        // A stale value in the file leaves the row with nothing selected; -1 is
        // what the control reports, and stepping on from it must land on a real
        // option rather than throwing or sitting at -1 forever.
        const all = [true, true, true];
        compare(keys.advance(-1, 1, all), 0);
        compare(keys.firstAllowed([false, true, true]), 1);
        compare(keys.firstAllowed([false, false]), -1);
    }

    function test_nudge_moves_one_step_and_clamps() {
        compare(keys.nudge(0.86, 1, 0.65, 1, 0.01, false), 0.87);
        compare(keys.nudge(0.86, -1, 0.65, 1, 0.01, false), 0.85);
        compare(keys.nudge(1, 1, 0.65, 1, 0.01, false), 1);
        compare(keys.nudge(0.65, -1, 0.65, 1, 0.01, false), 0.65);
    }

    function test_nudge_rounds_the_way_the_drag_does() {
        // The drag and the arrow keys share `roundOff`, so a keyboard step
        // cannot put `0.8600000000000001` in a file the drag would have written
        // `0.86` to.
        compare(keys.nudge(0.07, 1, 0, 1, 0.01, false), 0.08);
        compare(keys.roundOff(0.8600000000000001, false), 0.86);

        // A whole-number knob — bar height — stays whole, and it is the knob's
        // default that says so, not the step size.
        compare(keys.nudge(34, 1, 24, 48, 1, true), 35);
        verify(Number.isInteger(keys.nudge(34, 1, 24, 48, 1, true)));
        compare(keys.roundOff(34.4, true), 34);
    }

    function test_scroll_leaves_a_visible_item_alone() {
        // Tabbing along a row of controls that is already on screen must not
        // nudge the page.
        compare(keys.scrollTo(0, 400, 100, 30, 20, 1000), 0);
        compare(keys.scrollTo(200, 400, 300, 30, 20, 1000), 200);
    }

    function test_scroll_brings_an_item_below_the_fold_up() {
        // Bottom edge plus margin lands on the viewport's bottom edge.
        compare(keys.scrollTo(0, 400, 500, 30, 20, 1000), 150);
    }

    function test_scroll_brings_an_item_above_the_fold_down() {
        compare(keys.scrollTo(300, 400, 100, 30, 20, 1000), 80);
    }

    function test_scroll_stays_inside_the_content() {
        // Never past the end of the page, and never above the top — a Flickable
        // driven outside its bounds stays there.
        compare(keys.scrollTo(0, 400, 900, 30, 20, 560), 550);
        compare(keys.scrollTo(0, 400, 900, 30, 20, 100), 100);
        compare(keys.scrollTo(30, 400, 10, 30, 20, 1000), 0);
    }

    function test_scroll_does_nothing_before_the_view_has_a_height() {
        // The first focus can land before the page has been laid out.
        compare(keys.scrollTo(0, 0, 500, 30, 20, 1000), 0);
    }
}
