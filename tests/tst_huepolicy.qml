// Which hue an event wears.
//
// The property under test is not "is this the right colour" — no test can say
// that — it is **stability**: the same event gets the same hue on every run, on
// every machine, before and after its neighbours are deleted. That is what makes
// two captures of the same fixture the same picture, and it is the only thing
// the surface is entitled to assume.
import QtQuick
import QtTest
import "../Surfaces/Calendar"

TestCase {
    id: testCase

    name: "HuePolicy"

    HuePolicy { id: hues }

    function test_eight_names() {
        compare(hues.count, 8);
        compare(hues.names.length, 8);
        // Named rather than counted: the table in DESIGN-SPEC.md is indexed by
        // this order, so a reordering that kept the count would silently
        // repaint every calendar.
        compare(hues.names, ["glacier", "moss", "lamplight", "ember",
                             "lake", "lichen", "heather", "stone"]);
    }

    function test_named_colour_wins() {
        compare(hues.indexFor("glacier", "evt-1"), 0);
        compare(hues.indexFor("stone", "evt-1"), 7);
        compare(hues.indexFor("Heather", "evt-1"), 6);
        compare(hues.indexFor("  lake  ", "evt-1"), 4);
    }

    function test_numeric_colour_accepted() {
        compare(hues.indexFor("3", "evt-1"), 3);
        compare(hues.indexFor("0", "evt-1"), 0);
        compare(hues.indexFor("7", "evt-1"), 7);
    }

    function test_out_of_range_number_falls_through() {
        // 8 is not a hue. It must not clamp to 7 and must not become 0 — both
        // would hide the mistake behind a plausible colour.
        compare(hues.indexFor("8", "evt-1"), hues.indexFor("", "evt-1"));
        compare(hues.indexFor("-1", "evt-1"), hues.indexFor("", "evt-1"));
    }

    function test_unknown_name_falls_through_not_to_zero() {
        // A typo must not make every mistyped event glacier: two different
        // typos on two different events stay two different events.
        compare(hues.indexFor("gclaier", "evt-1"), hues.indexFor("", "evt-1"));
        compare(hues.indexFor("gclaier", "evt-2"), hues.indexFor("", "evt-2"));
    }

    function test_uncoloured_is_stable_and_in_range() {
        for (let i = 1; i <= 200; i++) {
            const id = "evt-" + i;
            const first = hues.indexFor("", id);
            verify(first >= 0 && first < hues.count, id + " -> " + first);
            compare(hues.indexFor("", id), first);
            // Nothing about the *other* events may reach the answer: it is a
            // function of the id alone, so deleting evt-1 never repaints evt-2.
            compare(hues.forEvent({ "id": id, "colour": "" }), first);
        }
    }

    function test_the_hash_never_hands_out_grey() {
        // `stone` is the grey one, and grey is a *status* in every calendar
        // anyone has used — declined, tentative, someone else's. An event that
        // was auto-coloured grey is wearing a meaning nobody gave it, which on
        // the fixture week made `Retro` read as a meeting that had been turned
        // down. So the hash draws from the seven chromatic hues; the eighth
        // stays on the wheel for a person to pick.
        compare(hues.autoCount, 7);
        compare(hues.names[hues.count - 1], "stone");
        for (let i = 1; i <= 400; i++)
            verify(hues.indexFor("", "evt-" + i) < hues.autoCount,
                   "evt-" + i + " -> " + hues.indexFor("", "evt-" + i));
        // Picked by name or by index it is still reachable — the rule is about
        // the coin toss, not about the colour.
        compare(hues.indexFor("stone", "evt-1"), 7);
        compare(hues.indexFor("7", "evt-1"), 7);
    }

    function test_uncoloured_spreads_over_the_wheel() {
        // Not a distribution proof — just the guard against a hash that
        // collapses. The fixture's eleven events would be one colour if djb2
        // were replaced with something that ignored short suffixes.
        const seen = {};
        for (let i = 1; i <= 40; i++)
            seen[hues.indexFor("", "evt-" + i)] = true;
        verify(Object.keys(seen).length >= 6, Object.keys(seen).join(","));
    }

    function test_missing_event_is_not_an_exception() {
        compare(hues.forEvent(null), 0);
        compare(hues.forEvent(undefined), 0);
    }

    function test_undefined_colour_reads_as_absent() {
        const byId = hues.indexFor("", "evt-9");
        compare(hues.forEvent({ "id": "evt-9" }), byId);
        compare(hues.forEvent({ "id": "evt-9", "colour": null }), byId);
    }

    // --- keeping neighbours apart ---------------------------------------------

    function test_two_hues_of_the_same_family_are_a_collision() {
        // `ember` (15) beside `lamplight` (30) is the pair that was reported as
        // one colour with a glitch down the middle.
        verify(hues.separation(3, 2) < hues.minSeparationDeg);
        // And the pair nobody has ever confused is not.
        verify(hues.separation(1, 0) >= hues.minSeparationDeg);
        // Grey has no angle and is far from everything, which is true of it.
        compare(hues.separation(7, 3), 360);
        compare(hues.separation(3, 7), 360);
    }

    function test_a_day_never_puts_two_near_hues_side_by_side() {
        // The fixture's Tuesday: three concurrent events, none of them coloured
        // by hand, and the hash's own answer put two neighbours a family apart.
        const cluster = [
            { "id": "evt-3", "colour": "" },
            { "id": "evt-4", "colour": "" },
            { "id": "evt-5", "colour": "" }
        ];
        const spread = hues.spread(cluster);
        compare(spread.length, 3);
        for (let i = 0; i < spread.length; i++)
            for (let j = i + 1; j < spread.length; j++)
                verify(hues.separation(spread[i], spread[j]) >= hues.minSeparationDeg);
    }

    function test_the_hash_still_decides_where_nothing_collides() {
        // A hue only ever moves because it collided. The first event in a
        // cluster has nothing to collide with, so it always keeps its own.
        const cluster = [{ "id": "evt-3", "colour": "" }, { "id": "evt-4", "colour": "" }];
        compare(hues.spread(cluster)[0], hues.forEvent(cluster[0]));
        // And a lone event is its hash, spread or not.
        compare(hues.spread([{ "id": "evt-9", "colour": "" }])[0],
                hues.forEvent({ "id": "evt-9", "colour": "" }));
    }

    function test_a_chosen_colour_is_never_moved() {
        // Someone picked it. A policy that overrode a choice to improve a
        // picture would be lying about the data — even where it collides.
        const cluster = [
            { "id": "evt-1", "colour": "ember" },
            { "id": "evt-2", "colour": "lamplight" }
        ];
        const spread = hues.spread(cluster);
        compare(spread[0], 3);
        compare(spread[1], 2);
    }

    function test_spread_is_stable_and_total() {
        // Same input, same answer, every run — a picture that repainted itself
        // between two captures of one fixture is not a picture.
        const cluster = [
            { "id": "evt-3", "colour": "" },
            { "id": "evt-4", "colour": "" },
            { "id": "evt-5", "colour": "" }
        ];
        const first = hues.spread(cluster);
        const again = hues.spread(cluster);
        for (let i = 0; i < first.length; i++) {
            compare(first[i], again[i]);
            verify(first[i] >= 0 && first[i] < hues.count);
        }
        // Nothing in, nothing out — a delegate mid-rebuild asks with whatever
        // it has and must not take an exception back.
        compare(hues.spread([]).length, 0);
        compare(hues.spread(null).length, 0);
        compare(hues.spread(undefined).length, 0);
    }

    function test_a_crowd_falls_back_rather_than_inventing() {
        // Seven auto hues cannot all be 45 degrees apart. Past the point the
        // wheel runs out, the hash's own answer stands: a repeated colour is a
        // smaller lie than one chosen by how far the loop happened to get.
        const crowd = [];
        for (let i = 0; i < 7; i++)
            crowd.push({ "id": "evt-" + i, "colour": "" });
        const spread = hues.spread(crowd);
        compare(spread.length, 7);
        for (let i = 0; i < 7; i++)
            verify(spread[i] >= 0 && spread[i] < hues.autoCount);
    }

    // --- the tint ----------------------------------------------------------------
    //
    // How strongly a hue is laid over the panel to become a chip's body. It is
    // one number and it lives here because it was three: two hand-solved hex
    // tables and a month view that had drifted off both. What is pinned is the
    // arithmetic and the alphas, not the eight results — the results are
    // `CalendarTokens`' business.

    function test_the_alphas_are_the_specs() {
        compare(hues.tintAlpha(true), 0.16);
        compare(hues.tintAlpha(false), 0.12);
    }

    // The eight dark fills in DESIGN-SPEC.md are exactly `bar` over
    // `Theme.surface` at 0.16, which is the claim that lets the table be
    // deleted and computed instead.
    function test_dark_tints_land_on_the_spec_table() {
        const surface = "#141b17";
        compare(hues.tint("#6fbec4", surface, 0.16), "#233533");
        compare(hues.tint("#8fbf6a", surface, 0.16), "#283524");
        compare(hues.tint("#5b9dd9", surface, 0.16), "#1f3036");
        compare(hues.tint("#9d9e8d", surface, 0.16), "#2a302a");
    }

    function test_light_tints_land_on_the_spec_table() {
        const surface = "#f7f9f5";
        compare(hues.tint("#0c757b", surface, 0.12), "#dbe9e6");
        compare(hues.tint("#4a7d35", surface, 0.12), "#e2eade");
        compare(hues.tint("#68695b", surface, 0.12), "#e6e8e3");
    }

    function test_the_ends_of_the_range_are_the_two_colours() {
        compare(hues.tint("#6fbec4", "#141b17", 0), "#141b17");
        compare(hues.tint("#6fbec4", "#141b17", 1), "#6fbec4");
    }

    // A binding mid-rebuild hands this whatever it has. Black on black is the
    // failure mode; a base that survives is the requirement.
    function test_nonsense_falls_back_to_the_base_rather_than_to_black() {
        compare(hues.tint("", "#141b17", 0.16), "#141b17");
        compare(hues.tint(undefined, "#141b17", 0.16), "#141b17");
        compare(hues.tint("#6fbec4", "not a colour", 0.16), "#000000");
    }

    function test_alpha_is_clamped_rather_than_extrapolated() {
        compare(hues.tint("#6fbec4", "#141b17", -3), "#141b17");
        compare(hues.tint("#6fbec4", "#141b17", 9), "#6fbec4");
    }

    function test_short_hex_is_accepted() {
        compare(hues.tint("#fff", "#000", 1), "#ffffff");
        compare(hues.tint("#fff", "#000000", 0.5), "#808080");
    }

    // Every ink the surface prints on a tint has to clear AA on it. Solved at
    // 6:1 against the old heavy fills, they land far above it on these.
    function test_every_ink_clears_4_5_on_its_tint() {
        const barsDark = ["#6fbec4", "#8fbf6a", "#d8ac81", "#e07a5f",
                          "#5b9dd9", "#afbd7a", "#b295cf", "#9d9e8d"];
        const inksDark = ["#bbdede", "#c7ddb9", "#e6d6c2", "#efd0c7",
                          "#c3daed", "#d2dbbd", "#ddd5e8", "#d6d7d0"];
        for (let i = 0; i < barsDark.length; i++) {
            const fill = hues.tint(barsDark[i], "#141b17", hues.tintAlphaDark);
            verify(testCase.contrast(inksDark[i], fill) >= 4.5,
                   inksDark[i] + " on " + fill + " is "
                   + testCase.contrast(inksDark[i], fill).toFixed(2) + ":1");
        }
        const barsLight = ["#0c757b", "#4a7d35", "#8a5a2f", "#b0512f",
                           "#23608f", "#59682c", "#6b4a8f", "#68695b"];
        const inksLight = ["#085256", "#305224", "#664323", "#783821",
                           "#1c4d74", "#434e21", "#593d77", "#4b4b41"];
        for (let i = 0; i < barsLight.length; i++) {
            const fill = hues.tint(barsLight[i], "#f7f9f5", hues.tintAlphaLight);
            verify(testCase.contrast(inksLight[i], fill) >= 4.5,
                   inksLight[i] + " on " + fill + " is "
                   + testCase.contrast(inksLight[i], fill).toFixed(2) + ":1");
        }
    }

    /// WCAG, in the test rather than in the shipping code — the same arithmetic
    /// `tools/measure-contrast.py` runs on a capture.
    function contrast(a, b) {
        const l1 = testCase.relativeLuminance(a);
        const l2 = testCase.relativeLuminance(b);
        return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
    }

    function relativeLuminance(hex) {
        const c = hues.channels(hex).map(function (v) {
            const s = v / 255;
            return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
        });
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
    }
}
