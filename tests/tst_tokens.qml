// The design system as data (#8, #34): the token set, the two palette rows and
// their per-token fallback, and the motion ladder.
//
// Core/Theme.qml itself imports Quickshell and so cannot be loaded here; what
// it adds over this file is the Config wiring, which the shell verifies by
// running (see the ticket's acceptance criteria).
import QtQuick
import QtTest
import "../Core"

TestCase {
    name: "Tokens"

    Tokens { id: tokens }

    // --- colour --------------------------------------------------------------

    function test_the_dark_row_is_the_brief_verbatim() {
        // Board design brief §2, adopted verbatim by #8 — names included. If a
        // value here changes, the brief changed, not someone's taste.
        compare(tokens.dark.bgBase, "#0b100d");
        compare(tokens.dark.bgSunken, "#070a08");
        compare(tokens.dark.surface, "#141b17");
        compare(tokens.dark.surfaceRaised, "#1c2621");
        compare(tokens.dark.surfaceOverlay, "#243029");
        compare(tokens.dark.borderSubtle, "#2a3830");
        compare(tokens.dark.borderStrong, "#3c554d");
        compare(tokens.dark.textPrimary, "#e6ece8");
        compare(tokens.dark.textSecondary, "#a9b8b0");
        compare(tokens.dark.textMuted, "#7d8f86");
        compare(tokens.dark.accentPrimary, "#6fbec4");
        compare(tokens.dark.accentDeep, "#0c757b");
        compare(tokens.dark.accentWarm, "#d8ac81");
        compare(tokens.dark.accentEmber, "#e07a5f");
        compare(tokens.dark.accentLichen, "#afbd7a");
        compare(tokens.dark.accentStone, "#9d9e8d");
        compare(tokens.dark.fogWash, "#beced1");
    }

    function test_the_dark_row_is_complete_and_has_no_extra_roles() {
        // Dark is the row every other row falls back to, so it is the one that
        // may never have a hole.
        compare(Object.keys(tokens.dark).length, tokens.colorRoles.length);
        for (const role of tokens.colorRoles)
            verify(tokens.isColor(tokens.dark[role]), role + " is not a colour");
    }

    function test_the_light_seed_only_names_roles_that_exist() {
        // A light-only role would break mode-blindness — the brief's
        // `accent-secondary` is held out of the token set for exactly this
        // reason (#8: provisional pending role symmetry).
        for (const role in tokens.lightSeed)
            verify(tokens.colorRoles.indexOf(role) >= 0, role + " is not a token role");
        compare(tokens.lightSeed.accentSecondary, undefined);
        for (const role in tokens.lightSeed)
            verify(tokens.isColor(tokens.lightSeed[role]), role + " is not a colour");
    }

    function test_the_light_seed_is_deliberately_partial() {
        // #8 recorded the brief's light table as incomplete. The gap is
        // structural, not an oversight, and shrinks when the light theme is
        // actually built.
        const fallbacks = tokens.lightFallbackRoles;
        verify(fallbacks.length > 0);
        for (const role of fallbacks)
            compare(tokens.lightSeed[role], undefined);
        for (const role of tokens.colorRoles)
            verify(tokens.lightSeed[role] !== undefined || fallbacks.indexOf(role) >= 0);
    }

    function test_both_palettes_answer_every_role() {
        // The mode-blindness contract: a consumer reads a role, never a mode.
        for (const darkMode of [true, false]) {
            const p = tokens.palette(darkMode, null);
            compare(Object.keys(p).length, tokens.colorRoles.length);
            for (const role of tokens.colorRoles)
                verify(tokens.isColor(p[role]), role + " unresolved in "
                       + (darkMode ? "dark" : "light"));
        }
    }

    function test_light_falls_back_per_token_not_wholesale() {
        const light = tokens.palette(false, null);
        // Seeded roles are the light value...
        compare(light.bgBase, tokens.lightSeed.bgBase);
        compare(light.accentPrimary, tokens.lightSeed.accentPrimary);
        // ...and only the unseeded ones borrow from dark, individually.
        for (const role of tokens.lightFallbackRoles)
            compare(light[role], tokens.dark[role]);
        verify(light.bgBase !== tokens.dark.bgBase);
    }

    function test_dark_ignores_the_light_seed_entirely() {
        const palette = tokens.palette(true, null);
        for (const role of tokens.colorRoles)
            compare(palette[role], tokens.dark[role]);
    }

    function test_overrides_replace_single_roles() {
        const light = tokens.palette(false, { accentWarm: "#123456" });
        compare(light.accentWarm, "#123456");
        // Nothing else moves.
        compare(light.accentEmber, tokens.lightSeed.accentEmber);
    }

    function test_overrides_survive_a_hand_edited_file() {
        // `appearance.paletteOverrides` is a free-form object in settings.json
        // (#33), so it arrives unvalidated. Junk is dropped, not painted.
        ignoreWarning(/unknown palette role/);
        ignoreWarning(/not a colour/);
        const p = tokens.palette(true, {
            noSuchRole: "#ffffff",
            accentPrimary: "teal",       // named colours are refused on purpose
            accentDeep: "#0c757bff"
        });
        compare(p.accentPrimary, tokens.dark.accentPrimary);
        compare(p.accentDeep, "#0c757bff");
        compare(p.noSuchRole, undefined);
    }

    function test_palette_does_not_hand_out_its_own_table() {
        // Callers hold the result across a mode flip; it must not alias the
        // source rows.
        const p = tokens.palette(true, null);
        p.bgBase = "#ffffff";
        compare(tokens.dark.bgBase, "#0b100d");
        compare(tokens.palette(true, null).bgBase, "#0b100d");
    }

    // --- spacing, radii ------------------------------------------------------

    function test_spacing_is_a_4px_grid() {
        const scale = [tokens.space1, tokens.space2, tokens.space3, tokens.space4,
                       tokens.space5, tokens.space6, tokens.space7, tokens.space8,
                       tokens.space9, tokens.space10];
        compare(scale, [4, 8, 12, 16, 20, 24, 32, 40, 48, 64]);
        for (const step of scale)
            compare(step % 4, 0, step + " is off the grid");
    }

    function test_radii_are_the_four_the_brief_names() {
        compare(tokens.radiusSm, 6);
        compare(tokens.radiusMd, 10);
        compare(tokens.radiusLg, 16);
        // "full-round" — any radius past half the largest plausible control.
        verify(tokens.radiusFull > tokens.radiusLg * 100);
    }

    // --- type ----------------------------------------------------------------

    function test_type_names_plain_families_only() {
        // fontconfig also exposes "IBM Plex Sans Medm" and friends; naming one
        // renders, but leaves `font.weight` with nowhere to go (#18).
        for (const family of [tokens.fontUi, tokens.fontMono, tokens.fontDisplay])
            verify(!/ (Medm|SmBld|Light|Text|Thin|ExtraLight|SemiBold|Bold)$/.test(family),
                   family + " is a sub-family, not a family");
        compare(tokens.fontUi, "IBM Plex Sans");
        compare(tokens.fontMono, "IBM Plex Mono");
        compare(tokens.fontDisplay, "Newsreader");
    }

    function test_weights_stay_inside_the_briefs_range() {
        // 300–600, no blacks (brief §4). 450 is Plex "Text", which QML has no
        // named constant for; 300 is the Newsreader Light the clock uses.
        compare(tokens.weightDisplay, 300);
        compare(tokens.weightText, 450);
        for (const weight of [tokens.weightDisplay, tokens.weightRegular,
                              tokens.weightText, tokens.weightMedium]) {
            verify(weight >= 300 && weight <= 600, weight + " is out of range");
        }
    }

    function test_px_to_pt_is_exact_at_96_dpi() {
        // `font.pixelSize` is an int and the scale has half-pixel steps, so
        // sizes go through pointSize.
        compare(tokens.pt(96), 72);
        compare(tokens.pt(10.5), 7.875);
    }

    function test_caps_tracking_is_em_relative() {
        compare(tokens.capsSize, 10.5);
        compare(tokens.capsTrackingEm, 0.08);
        compare(tokens.tracking(tokens.capsSize, tokens.capsTrackingEm), 0.84);
    }

    // --- motion --------------------------------------------------------------

    function test_the_one_curve() {
        // cubic-bezier(0.22, 1, 0.36, 1), in easing.bezierCurve's six-number
        // form. Every transition in the shell uses it, no exceptions.
        compare(tokens.fogEase, [0.22, 1.0, 0.36, 1.0, 1.0, 1.0]);
    }

    function test_the_ladder_has_exactly_three_steps() {
        compare(tokens.motionSteps, [140, 240, 320]);
    }

    function test_exits_run_one_step_faster_with_a_floor() {
        compare(tokens.exitDuration(tokens.motionSlow), tokens.motionStandard);
        compare(tokens.exitDuration(tokens.motionStandard), tokens.motionFast);
        // The 140 class is symmetric — no fourth micro-step gets invented (#27).
        compare(tokens.exitDuration(tokens.motionFast), tokens.motionFast);
    }

    function test_an_off_ladder_duration_gets_the_floor() {
        // Not a design system value, so it does not get design system
        // arithmetic either.
        compare(tokens.exitDuration(500), tokens.motionFast);
        compare(tokens.exitDuration(0), tokens.motionFast);
    }
}
