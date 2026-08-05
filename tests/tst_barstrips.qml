// The arithmetic that keeps an auto-hidden bar clickable while a drawer is open
// (#199): where the bar's input strip is, and what the drawer subtracts from
// its own mask to leave it reachable.
//
// The registry the two halves talk through is Core/BarStrips.qml, which is a
// `Singleton` and imports Quickshell, so it cannot be loaded here; neither can
// either surface. What that side does is driven with a real pointer by
// tools/bar-click-harness.sh, which runs #187's table twice — once with
// `bar.autoHide` off, where geometry does the work, and once with it on, where
// this file's hole does.
import QtQuick
import QtTest
import "../Core"

TestCase {
    name: "BarStrips"

    BarStripsPolicy { id: policy }

    // A 1920×1080 screen with a 32px bar at the top, not floating, reserving
    // space — the ordinary pinned bar, and the case #187 already covers.
    function pinned(overrides) {
        const base = {
            atTop: true, revealed: true, reserves: true, barHeight: 32,
            floating: false, marginH: 12, marginV: 8,
            screenW: 1920, screenH: 1080
        };
        for (const key in (overrides || {}))
            base[key] = overrides[key];
        return policy.context(base.atTop, base.revealed, base.reserves,
                              base.barHeight, base.floating, base.marginH,
                              base.marginV, base.screenW, base.screenH);
    }

    function rectOf(overrides) {
        return policy.stripRect(pinned(overrides));
    }

    // --- where the strip is --------------------------------------------------

    function test_a_revealed_top_bar_spans_the_screen_width() {
        const r = rectOf({ });
        compare(r.x, 0);
        compare(r.y, 0);
        compare(r.width, 1920);
        compare(r.height, 32);
    }

    function test_a_revealed_bottom_bar_sits_against_the_bottom_edge() {
        const r = rectOf({ atTop: false });
        compare(r.y, 1080 - 32);
        compare(r.height, 32);
    }

    /// The window keeps its height while the bar is away; only the mask shrinks,
    /// so only the mask is what gets published.
    function test_b_a_hidden_top_bar_is_one_pixel_at_the_edge() {
        const r = rectOf({ revealed: false, reserves: false });
        compare(r.y, 0);
        compare(r.height, 1);
        compare(r.width, 1920);
    }

    function test_b_a_hidden_bottom_bar_is_one_pixel_at_the_bottom_edge() {
        const r = rectOf({ atTop: false, revealed: false, reserves: false });
        compare(r.y, 1079);
        compare(r.height, 1);
    }

    /// "There is no bar" must not produce a pixel of one.
    function test_b_a_zero_height_bar_has_no_strip_hidden_or_shown() {
        compare(rectOf({ barHeight: 0 }).height, 0);
        compare(rectOf({ barHeight: 0, revealed: false }).height, 0);
    }

    // --- floating insets -----------------------------------------------------

    function test_c_a_floating_bar_is_inset_by_its_margins() {
        const r = rectOf({ floating: true });
        compare(r.x, 12);
        compare(r.width, 1920 - 24);
        compare(r.y, 8);
        compare(r.height, 32);
    }

    function test_c_a_floating_bottom_bar_is_inset_from_the_bottom() {
        const r = rectOf({ floating: true, atTop: false });
        compare(r.y, 1080 - 8 - 32);
    }

    /// The reveal strip is anchored to the window's edge, and a floating
    /// window's edge is the screen's inset by the margin — so the pixel moves
    /// with it rather than staying on the screen edge.
    function test_c_a_hidden_floating_bottom_bar_keeps_its_pixel_at_the_window_edge() {
        const r = rectOf({ floating: true, atTop: false, revealed: false });
        compare(r.y, 1080 - 8 - 1);
        compare(r.height, 1);
    }

    function test_c_margins_are_ignored_while_the_bar_is_not_floating() {
        const r = rectOf({ floating: false });
        compare(r.x, 0);
        compare(r.width, 1920);
    }

    /// A margin wider than the screen would otherwise produce a negative width,
    /// which is a mask the compositor has to interpret.
    function test_c_absurd_margins_clamp_rather_than_going_negative() {
        const r = rectOf({ floating: true, marginH: 4000 });
        compare(r.width, 0);
    }

    // --- what the drawer subtracts -------------------------------------------

    /// The case #187 already solved. The fog is laid out below the reserved
    /// strip and never overlapped it, so a hole would be punched through fog
    /// that is somewhere else.
    function test_d_a_reserving_bar_gets_no_hole() {
        const strip = rectOf({ reserves: true });
        verify(policy.isEmpty(policy.cutout(strip, 1920, 1048, 1920, 1080)));
    }

    function test_d_an_auto_hidden_revealed_bar_gets_its_whole_band() {
        const strip = rectOf({ reserves: false, revealed: true });
        const hole = policy.cutout(strip, 1920, 1080, 1920, 1080);
        compare(hole.x, 0);
        compare(hole.y, 0);
        compare(hole.width, 1920);
        compare(hole.height, 32);
    }

    /// #199's second acceptance criterion, at the seam that decides it. There is
    /// nothing behind the fog to reach while the bar is away — its dismiss
    /// handler is parked outside the window with the rest of `content` — so the
    /// whole band stays fog and a click anywhere in it dismisses.
    function test_d_a_bar_that_is_away_gets_no_hole_at_all() {
        const strip = rectOf({ reserves: false, revealed: false });
        verify(policy.isEmpty(policy.cutout(strip, 1920, 1080, 1920, 1080)));
    }

    /// Including the pixel it would have been reachable through. A hole there
    /// would be a row of the band that neither acts nor dismisses.
    function test_d_not_even_over_the_reveal_strip() {
        const strip = { x: 0, y: 0, width: 1920, height: 1,
                        reserves: false, revealed: false };
        verify(policy.isEmpty(policy.cutout(strip, 1920, 1080, 1920, 1080)));
    }

    function test_d_a_screen_with_no_bar_gets_no_hole() {
        verify(policy.isEmpty(policy.cutout(null, 1920, 1080, 1920, 1080)));
        verify(policy.isEmpty(policy.cutout(undefined, 1920, 1080, 1920, 1080)));
    }

    /// Somebody else reserved a zone, so this window's origin is offset from the
    /// screen's by an amount the policy cannot see. Refusing degrades to the
    /// pre-#199 behaviour; guessing would cut a hole in the wrong place.
    function test_d_a_window_smaller_than_its_screen_gets_no_hole() {
        const strip = rectOf({ reserves: false });
        verify(policy.isEmpty(policy.cutout(strip, 1920, 1048, 1920, 1080)));
        verify(policy.isEmpty(policy.cutout(strip, 1900, 1080, 1920, 1080)));
    }

    function test_d_a_hole_is_clamped_to_the_window() {
        const strip = { x: 1900, y: 1070, width: 400, height: 400,
                        reserves: false, revealed: true };
        const hole = policy.cutout(strip, 1920, 1080, 1920, 1080);
        compare(hole.x, 1900);
        compare(hole.y, 1070);
        compare(hole.width, 20);
        compare(hole.height, 10);
    }

    function test_d_a_strip_entirely_off_the_window_is_no_hole() {
        const strip = { x: 4000, y: 0, width: 100, height: 32,
                        reserves: false, revealed: true };
        verify(policy.isEmpty(policy.cutout(strip, 1920, 1080, 1920, 1080)));
    }

    function test_d_a_zero_height_strip_is_no_hole() {
        const strip = { x: 0, y: 0, width: 1920, height: 0,
                        reserves: false, revealed: true };
        verify(policy.isEmpty(policy.cutout(strip, 1920, 1080, 1920, 1080)));
    }

    // --- the registry map ----------------------------------------------------
    //
    // The merge lives on this side of the line so it can be checked here; the
    // singleton that holds the map (Core/BarStrips.qml) imports Quickshell and
    // qmltestrunner cannot load it.

    function test_f_a_strip_is_added_without_touching_the_others() {
        const before = { "DP-1": { width: 1 } };
        const after = policy.withStrip(before, "DP-2", { width: 2 });
        compare(after["DP-1"].width, 1);
        compare(after["DP-2"].width, 2);
    }

    /// A new map every time, or a binding on `strips[name]` never re-evaluates.
    function test_f_the_original_map_is_left_alone() {
        const before = { "DP-1": { width: 1 } };
        const after = policy.withStrip(before, "DP-2", { width: 2 });
        compare(before["DP-2"], undefined);
        verify(before !== after);
    }

    function test_f_publishing_the_same_screen_twice_replaces_it() {
        let map = policy.withStrip({}, "DP-1", { width: 1 });
        map = policy.withStrip(map, "DP-1", { width: 9 });
        compare(map["DP-1"].width, 9);
    }

    function test_f_a_screen_is_dropped_and_the_rest_survive() {
        const before = policy.withStrip(policy.withStrip({}, "DP-1", { width: 1 }),
                                        "DP-2", { width: 2 });
        const after = policy.withoutStrip(before, "DP-1");
        compare(after["DP-1"], undefined);
        compare(after["DP-2"].width, 2);
        compare(before["DP-1"].width, 1);
    }

    function test_f_dropping_a_screen_that_is_not_there_is_harmless() {
        const after = policy.withoutStrip({ "DP-1": { width: 1 } }, "DP-9");
        compare(after["DP-1"].width, 1);
    }

    function test_f_an_absent_map_is_treated_as_an_empty_one() {
        compare(policy.withStrip(null, "DP-1", { width: 1 })["DP-1"].width, 1);
        compare(policy.withoutStrip(undefined, "DP-1")["DP-1"], undefined);
    }

    // --- the line seam 2 reads ----------------------------------------------

    function test_e_the_log_line_names_the_screen_and_the_hole() {
        const hole = { x: 0, y: 0, width: 1920, height: 32 };
        compare(policy.cutoutLine("DP-1", hole), "bar cutout on DP-1: 1920×32+0+0");
    }

    function test_e_no_hole_says_so() {
        compare(policy.cutoutLine("DP-1", { x: 0, y: 0, width: 0, height: 0 }),
                "no bar cutout on DP-1");
        compare(policy.cutoutLine("DP-1", null), "no bar cutout on DP-1");
    }
}
