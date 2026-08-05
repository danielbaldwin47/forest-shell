// What the control centre's drill-ins decide (#45): which control opens which
// panel, where a second press lands, when a radio is allowed to scan, and which
// way the slide goes.
//
// The slide itself is a picture and the scan is a real radio — both live at the
// other two seams. What is here is every decision made before either.
import QtQuick
import QtTest
import "../Surfaces/Drawers"

TestCase {
    name: "DrillInPolicy"

    DrillInPolicy { id: policy }

    // --- the five ------------------------------------------------------------

    function test_there_are_five_panels_and_each_has_words_and_a_glyph() {
        compare(policy.panels.length, 5);
        for (const name of policy.panels) {
            verify(policy.title(name) !== "");
            verify(policy.icon(name) !== "");
        }
    }

    function test_a_name_nothing_opens_is_not_known() {
        // Over IPC this is something a person typed into a keybind, and a
        // keybind that does nothing deserves the line saying why.
        verify(!policy.known("nonesuch"));
        verify(!policy.known(""));
        verify(!policy.known(null));
    }

    function test_the_sound_panel_is_not_called_audio_on_screen() {
        // It holds an output picker *and* a per-application mixer, and neither
        // is what a person calls "audio".
        compare(policy.title("audio"), "Sound");
        compare(policy.title("wifi"), "Wi-Fi");
    }

    // --- which control opens which panel -------------------------------------

    function test_three_tiles_are_both_a_switch_and_a_door() {
        compare(policy.panelFor("wifi"), "wifi");
        compare(policy.panelFor("bluetooth"), "bluetooth");
        compare(policy.panelFor("vpn"), "vpn");
    }

    function test_the_wallpaper_tile_is_a_door_and_nothing_else() {
        // It has no on-state, so there is no toggle a body press could mean and
        // a chevron alone would leave five sixths of the tile dead.
        compare(policy.panelFor("wallpaper"), "wallpaper");
        verify(policy.doorOnly("wallpaper"));
    }

    function test_the_switches_that_are_only_switches_open_nothing() {
        // Night Light and the power profile are each a single value the
        // settings window already owns a full editor for (#54); a third place
        // to set a colour temperature is a third place for it to disagree.
        for (const id of ["dnd", "nightlight", "keepawake", "mode", "powerprofile"]) {
            compare(policy.panelFor(id), "");
            verify(!policy.doorOnly(id));
        }
    }

    function test_the_sound_panel_hangs_off_the_sliders_rather_than_a_tile() {
        // "Which speakers is this slider moving" is asked while looking at the
        // slider.
        compare(policy.panelForSlider("volume"), "audio");
        compare(policy.panelForSlider("mic"), "audio");
    }

    function test_brightness_opens_nothing_because_there_is_one_backlight() {
        compare(policy.panelForSlider("brightness"), "");
        compare(policy.panelForSlider("nonesuch"), "");
    }

    // --- and from the bar (#184) ---------------------------------------------

    function test_the_four_bar_indicators_with_a_panel_behind_them() {
        // The bar's status cluster reads the same four things three of these
        // panels are about, so a click on a glyph is the request the matching
        // tile's chevron already makes: "which network is this" is asked while
        // looking at the wifi glyph, not after opening the control centre.
        compare(policy.panelForIndicator("wifi"), "wifi");
        compare(policy.panelForIndicator("bluetooth"), "bluetooth");
        compare(policy.panelForIndicator("volume"), "audio");
        compare(policy.panelForIndicator("mic"), "audio");
    }

    function test_the_readouts_with_no_panel_stay_readouts() {
        // The three the bar shows and nothing opens. This is the table the
        // pointer cursor is drawn from, so an answer here for one of these
        // would be a hand cursor promising a door that does not exist —
        // building the battery panel is its own piece of work, not this one.
        const readouts = ["battery", "brightness", "systemmonitor", ""];
        for (let i = 0; i < readouts.length; i++)
            compare(policy.panelForIndicator(readouts[i]), "");
    }

    function test_the_indicator_table_is_not_the_tile_table() {
        // Deliberately its own switch rather than a call to `panelFor`: that
        // one also answers for `vpn` and `wallpaper`, and neither has a bar
        // indicator to click. A door named by a table nothing draws is a door
        // that goes unnoticed when it breaks.
        compare(policy.panelFor("vpn"), "vpn");
        compare(policy.panelForIndicator("vpn"), "");
        compare(policy.panelForIndicator("wallpaper"), "");
    }

    // --- moving between them -------------------------------------------------

    function test_opening_a_panel_from_the_root() {
        compare(policy.next("", "wifi"), "wifi");
    }

    function test_pressing_the_door_you_are_behind_takes_you_back_out() {
        // The same rule DrawerPolicy applies one level up: the control that
        // opened a thing closes it, so no press is a no-op the user has to find
        // another way out of.
        compare(policy.next("wifi", "wifi"), "");
    }

    function test_one_panel_replaces_another_rather_than_stacking() {
        // Depth of exactly one. A control centre you can get lost two levels
        // down in is one where the way out is a guess.
        compare(policy.next("wifi", "bluetooth"), "bluetooth");
    }

    function test_a_panel_nobody_built_leaves_the_open_one_alone() {
        compare(policy.next("wifi", "nonesuch"), "wifi");
        compare(policy.next("", "nonesuch"), "");
    }

    function test_back_is_always_the_root() {
        compare(policy.back(), "");
    }

    function test_the_root_is_not_a_panel_name() {
        // "Am I drilled in" is one comparison and not a lookup.
        verify(!policy.drilled(""));
        verify(policy.drilled("wifi"));
    }

    // --- what an open costs --------------------------------------------------

    function test_only_the_two_radio_panels_start_a_scan() {
        // Neither radio is scanning already, and that is the idle budget
        // (#22 §5): a scan is a radio kept awake for a list nobody is looking
        // at. Opening the panel is the moment somebody is.
        verify(policy.scans("wifi"));
        verify(policy.scans("bluetooth"));
        verify(!policy.scans("audio"));
        verify(!policy.scans("vpn"));
        verify(!policy.scans("wallpaper"));
    }

    function test_the_root_scans_nothing() {
        // Which is what ties the scan to the panel's lifetime: `back` is the
        // moment the user stops looking, and it answers false.
        verify(!policy.scans(""));
    }

    // --- the slide -----------------------------------------------------------

    function test_forward_is_leftward_and_back_reverses_it() {
        // The one convention that makes a depth-of-one navigation legible
        // without a breadcrumb: the way back is the way you came.
        const inFromRight = policy.offset(true, true);
        const outToLeft = policy.offset(true, false);
        verify(inFromRight > 0);
        verify(outToLeft < 0);

        compare(policy.offset(false, true), outToLeft);
        compare(policy.offset(false, false), inFromRight);
    }

    function test_the_slide_stays_inside_the_panel() {
        // A tenth of the width: enough to read as arriving from the right,
        // small enough not to look like something flying in from off screen.
        verify(policy.slideFraction > 0);
        verify(policy.slideFraction <= 0.25);
    }

    // --- the log -------------------------------------------------------------

    function test_every_act_has_a_line_with_the_panel_in_it() {
        compare(policy.opened("wifi"), "wifi panel opened");
        compare(policy.closed("wifi", "back"), "wifi panel closed (back)");
        compare(policy.closed("wifi", "drawer"), "wifi panel closed (drawer)");
        compare(policy.refused("nonesuch", "no such panel"),
                "no nonesuch panel — no such panel");
    }
}
