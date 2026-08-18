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

    /// A month banner is the only filled object in its grid, so its fill is
    /// measured against the bare cell rather than against a tinted neighbour —
    /// which is why it is a heavier alpha than the chip table's, and why it is a
    /// second number rather than a second opinion about the first.
    function test_a_banner_is_filled_harder_than_a_chip() {
        compare(hues.bannerAlpha(true), 0.26);
        compare(hues.bannerAlpha(false), 0.22);
        verify(hues.bannerAlphaDark > hues.tintAlphaDark);
        verify(hues.bannerAlphaLight > hues.tintAlphaLight);
    }

    /// The ceiling on that alpha is the ink, and it is a measurement. Every one
    /// of the eight texts must still clear the 6:1 this surface solves at when
    /// it is read on a banner fill, in both palettes. 0.30 dark was tried and
    /// put moss at 5.67, which is the number that set 0.26.
    function test_every_ink_clears_six_to_one_on_its_banner_fill() {
        const cases = [
            { "base": "#1c2621", "alpha": hues.bannerAlphaDark,
              "bars": testCase.barsDark, "inks": testCase.inksDark },
            { "base": "#ffffff", "alpha": hues.bannerAlphaLight,
              "bars": testCase.barsLight, "inks": testCase.inksLight }
        ];
        for (const c of cases)
            for (let i = 0; i < c.bars.length; i++) {
                const fill = hues.tint(c.bars[i], c.base, c.alpha);
                const ratio = hues.contrast(c.inks[i], fill);
                verify(ratio >= 6.0,
                       c.inks[i] + " on " + fill + " is " + ratio.toFixed(2) + ":1");
            }
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

    // --- past and future ------------------------------------------------------

    readonly property var barsDark: ["#6fbec4", "#8fbf6a", "#d8ac81", "#e07a5f",
                                     "#5b9dd9", "#afbd7a", "#b295cf", "#9d9e8d"]
    readonly property var inksDark: ["#bbdede", "#c7ddb9", "#e6d6c2", "#efd0c7",
                                     "#c3daed", "#d2dbbd", "#ddd5e8", "#d6d7d0"]
    readonly property var barsLight: ["#0c757b", "#4a7d35", "#8a5a2f", "#b0512f",
                                      "#23608f", "#59682c", "#6b4a8f", "#68695b"]
    readonly property var inksLight: ["#085256", "#305224", "#664323", "#783821",
                                      "#1c4d74", "#434e21", "#593d77", "#4b4b41"]

    function test_past_is_decided_by_the_end_not_the_start() {
        // The meeting the reader is sitting in started an hour ago and is the
        // loudest thing on the grid, not the quietest.
        verify(!hues.isPast("2026-08-18T14:00", "2026-08-18T13:40"));
        verify(hues.isPast("2026-08-18T13:30", "2026-08-18T13:40"));
        // The instant it ends it is past — the boundary is inclusive, so a chip
        // never sits in a third state for a minute.
        verify(hues.isPast("2026-08-18T13:40", "2026-08-18T13:40"));
    }

    function test_past_compares_chronologically_across_days() {
        verify(hues.isPast("2026-08-17T23:59", "2026-08-18T00:00"));
        verify(!hues.isPast("2026-08-19T00:00", "2026-08-18T23:59"));
        // A string compare is only the chronological one while the fields are
        // fixed-width; September must not sort before August because `9 < 1`.
        verify(hues.isPast("2026-08-31T09:00", "2026-09-01T09:00"));
        verify(!hues.isPast("2026-09-01T09:00", "2026-08-31T09:00"));
    }

    function test_no_clock_means_no_past() {
        // The capture harness, the first frame after load and every test that
        // does not care all pass "". A week that dimmed itself because it did
        // not yet know the time would flicker on every launch.
        verify(!hues.isPast("2026-08-17T09:00", ""));
        verify(!hues.isPast("2026-08-17T09:00", "not-a-stamp"));
        verify(!hues.isPast("", "2026-08-18T13:40"));
        verify(!hues.isPast("whenever", "2026-08-18T13:40"));
    }

    function test_all_day_event_is_not_past_until_its_day_is() {
        // A bare date used as an end normalises to the end of that day.
        compare(hues.normaliseEnd("2026-08-18"), "2026-08-18T23:59");
        verify(!hues.isPast("2026-08-18", "2026-08-18T13:40"));
        verify(hues.isPast("2026-08-17", "2026-08-18T13:40"));
        // And a bare date used as *now* is the start of that day, which is the
        // direction that never greys out a live meeting.
        compare(hues.normaliseNow("2026-08-18"), "2026-08-18T00:00");
        verify(!hues.isPast("2026-08-18T09:00", "2026-08-18"));
    }

    function test_stamps_of_different_precision_still_compare() {
        // Seconds on one side and none on the other would otherwise sort
        // `…T09:30:00` after `…T09:30` at exactly the minute the answer flips.
        verify(hues.isPast("2026-08-18T13:40:00", "2026-08-18T13:40"));
        verify(hues.isPast("2026-08-18T13:40", "2026-08-18T13:40:59"));
    }

    function test_event_form_survives_a_delegate_mid_rebuild() {
        verify(!hues.eventIsPast(null, "2026-08-18T13:40"));
        verify(!hues.eventIsPast(undefined, "2026-08-18T13:40"));
        verify(!hues.eventIsPast({}, "2026-08-18T13:40"));
        verify(hues.eventIsPast({"end": "2026-08-18T09:30"}, "2026-08-18T13:40"));
        compare(hues.strengthFor("2026-08-18T09:30", "2026-08-18T13:40"), "past");
        compare(hues.strengthFor("2026-08-18T15:30", "2026-08-18T13:40"), "future");
    }

    /// **The ladder is a real one and both rungs are legible.** The reference
    /// prints its past titles at about 2.5:1, which is not dim but unreadable;
    /// this asserts every past ink still clears AA on its own past fill, and
    /// that both rungs stay in their own band — past 4.5–5.5, future 7 and up,
    /// and never closer than 1.4x apart. A hierarchy that is measurable rather
    /// than eyeballed, and one a later "dim it a bit more" cannot quietly cross
    /// in either direction.
    function test_past_chips_stay_readable_and_future_ones_stay_louder() {
        const modes = [
            {"surface": "#141b17", "bars": testCase.barsDark,
             "inks": testCase.inksDark, "dark": true},
            {"surface": "#f7f9f5", "bars": testCase.barsLight,
             "inks": testCase.inksLight, "dark": false}
        ];
        for (let m = 0; m < modes.length; m++) {
            const mode = modes[m];
            for (let i = 0; i < mode.bars.length; i++) {
                const futureFill = hues.tint(mode.bars[i], mode.surface,
                                             hues.tintAlpha(mode.dark));
                const pastFill = hues.tint(mode.bars[i], mode.surface,
                                           hues.pastTintAlpha(mode.dark));
                const pastInk = hues.tint(mode.inks[i], pastFill,
                                          hues.pastInkStrength(mode.dark));
                const pastRatio = hues.contrast(pastInk, pastFill);
                const futureRatio = hues.contrast(mode.inks[i], futureFill);
                verify(pastRatio >= 4.5,
                       "past ink " + pastInk + " on " + pastFill + " is "
                       + pastRatio.toFixed(2) + ":1");
                verify(pastRatio <= 5.5,
                       "past ink " + pastInk + " is " + pastRatio.toFixed(2)
                       + ":1 — dimmed is a band, not just a floor");
                verify(futureRatio >= 7,
                       "hue " + i + " future " + futureRatio.toFixed(2)
                       + ":1 is not the loud rung");
                verify(futureRatio >= pastRatio * 1.4,
                       "hue " + i + " future " + futureRatio.toFixed(2)
                       + " is not 1.4x past " + pastRatio.toFixed(2));
            }
        }
    }

    /// The past fill has to recede, not merely change: under half the live
    /// alpha, so a past chip reads as a mark on the grid rather than a card on
    /// it. What still says *which calendar* is the bar.
    function test_past_strengths_are_the_quieter_ones() {
        verify(hues.pastTintAlphaDark < hues.tintAlphaDark / 2);
        verify(hues.pastTintAlphaLight < hues.tintAlphaLight / 2);
        verify(hues.pastBarStrength < 0.5 && hues.pastBarStrength > 0.3);
    }

    /// `contrast` agrees with the arithmetic the rest of this file has always
    /// used, which is what lets the assertions above be written against it.
    function test_contrast_matches_the_reference_arithmetic() {
        fuzzyCompare(hues.contrast("#ffffff", "#000000"), 21, 0.01);
        fuzzyCompare(hues.contrast("#141b17", "#141b17"), 1, 0.001);
        fuzzyCompare(hues.contrast("#bbdede", "#141b17"),
                     testCase.contrast("#bbdede", "#141b17"), 0.01);
    }

    // --- neutral furniture ------------------------------------------------------

    /// **Desaturating the chrome must be free.** `neutralise` mixes toward the
    /// grey of the colour's *own* luminance, so every ratio the ink held against
    /// every background it is drawn on survives. That property is the only
    /// reason a policy is allowed near a text colour at all — assert it, or the
    /// next person tunes the amount and quietly takes the gutter under AA.
    function test_neutralise_preserves_contrast() {
        const inks = ["#7d8f86", "#a9b8b0", "#e6ece8", "#5f7268", "#42544c"];
        const grounds = ["#0b100d", "#141b17", "#f7f9f5", "#e8ece9"];
        for (let i = 0; i < inks.length; i++) {
            const out = hues.neutralise(inks[i], 0.75);
            for (let g = 0; g < grounds.length; g++) {
                const before = hues.contrast(inks[i], grounds[g]);
                const after = hues.contrast(out, grounds[g]);
                verify(Math.abs(after - before) < 0.12,
                       inks[i] + " -> " + out + " on " + grounds[g] + ": "
                       + before.toFixed(2) + " became " + after.toFixed(2));
            }
        }
    }

    /// And it must actually neutralise: the green cast is what is being removed,
    /// so the channels have to converge.
    function test_neutralise_removes_the_cast() {
        const spread = c => {
            const ch = hues.channels(c);
            return Math.max(ch[0], ch[1], ch[2]) - Math.min(ch[0], ch[1], ch[2]);
        };
        // `textMuted` is #7d8f86 — 18 points of green across its channels.
        verify(spread("#7d8f86") >= 18);
        verify(spread(hues.neutralise("#7d8f86", 0.75)) <= 6);
        // 0 is a no-op and 1 is a true grey, so the knob spans what it claims.
        compare(hues.neutralise("#7d8f86", 0), "#7d8f86");
        verify(spread(hues.neutralise("#7d8f86", 1)) <= 1);
    }

    function test_neutralise_survives_nonsense() {
        compare(hues.neutralise("", 0.75), "");
        compare(hues.neutralise("not a colour", 0.75), "not a colour");
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
