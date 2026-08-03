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

    function test_the_light_row_names_every_role_itself() {
        // #8 recorded the brief's light table as incomplete and seven roles fell
        // through to their dark values. #44 is the ticket that made that
        // visible — the Dark/Light tile flips this palette live — and filling
        // them is part of it: a light mode borrowing dark's `surfaceOverlay`
        // paints a near-black hover onto a white card.
        compare(tokens.lightFallbackRoles, []);
        for (const role of tokens.colorRoles)
            verify(tokens.lightSeed[role] !== undefined, role + " missing from light");
    }

    // --- contrast ------------------------------------------------------------
    //
    // #44 owes a contrast gate over the light palette: the Dark/Light tile is
    // the first thing in the shell that flips it live, and after #79 and #94
    // authored numbers do not get the benefit of the doubt.
    //
    // The gate is *here* rather than at seam 3, and that is a correction to the
    // ticket rather than a shortcut. `tools/capture-harness.sh --contrast`
    // measures a **composite** — an authored fill at some opacity over a
    // wallpaper, which is a number no palette table can predict and only a
    // render can produce (#79 is exactly that measurement, on the bar). Every
    // surface in the control centre is opaque over an opaque panel, so its
    // ratios are palette arithmetic and nothing else: rendering them would
    // photograph two constants and divide them. Done here they also cover both
    // modes, every role pair, and every surface the shell draws on — not the
    // handful a posed capture happens to put on screen — and they run in CI
    // with no compositor and no session.
    //
    // What seam 3 does own for this surface is the picture: #80-class overflow
    // and the layout, `--surface controlcenter`.

    readonly property var backgroundRoles: [
        "bgBase", "bgSunken", "surface", "surfaceRaised", "surfaceOverlay"
    ]

    /// WCAG 2.1 relative luminance and contrast ratio. Written out rather than
    /// taken from `tools/measure-contrast.py`, which is the same arithmetic
    /// over a PNG — this side of the line has no PNG and no python.
    function channel(value) {
        const c = value / 255;
        return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    }

    function luminance(hex) {
        const h = String(hex).replace("#", "");
        const r = parseInt(h.substring(0, 2), 16);
        const g = parseInt(h.substring(2, 4), 16);
        const b = parseInt(h.substring(4, 6), 16);
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
    }

    function contrast(a, b) {
        const la = luminance(a);
        const lb = luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }

    function test_the_ratio_maths_agrees_with_a_known_pair() {
        // Black on white is 21:1 by definition; the dark row's own recorded
        // "16.0:1 on base" is the second anchor. Without this the four tests
        // below would pass just as happily on arithmetic that was subtly wrong.
        compare(Math.round(contrast("#000000", "#ffffff")), 21);
        verify(Math.abs(contrast("#e6ece8", "#0b100d") - 16.0) < 0.3);
    }

    function test_body_text_clears_aa_on_every_surface_in_both_modes() {
        // The two text roles go anywhere, including into a well.
        for (const darkMode of [true, false]) {
            const p = tokens.palette(darkMode, null);
            for (const fg of ["textPrimary", "textSecondary"])
                for (const bg of backgroundRoles) {
                    const ratio = contrast(p[fg], p[bg]);
                    verify(ratio >= 4.5,
                           (darkMode ? "dark" : "light") + " " + fg + " on " + bg
                           + " is " + ratio.toFixed(2) + ":1");
                }
        }
    }

    function test_accent_text_clears_aa_on_the_surfaces_it_is_labelled_on() {
        // The four a label can land on. `bgSunken` is deliberately not among
        // them: it is wells, insets and slider grooves (Core/Tokens.qml names
        // it that), and the shell draws no accent-coloured text into one — the
        // control centre's groove has an accent *fill* beside it, which is an
        // adjacency and not a legibility ratio.
        const labelSurfaces = ["bgBase", "surface", "surfaceRaised", "surfaceOverlay"];
        for (const darkMode of [true, false]) {
            const p = tokens.palette(darkMode, null);
            for (const fg of ["accentPrimary", "accentWarm", "accentEmber",
                              "accentLichen", "accentStone"])
                for (const bg of labelSurfaces) {
                    const ratio = contrast(p[fg], p[bg]);
                    verify(ratio >= 4.5,
                           (darkMode ? "dark" : "light") + " " + fg + " on " + bg
                           + " is " + ratio.toFixed(2) + ":1");
                }
        }
    }

    function test_muted_text_clears_the_large_text_floor_in_both_modes() {
        // 3:1, AA for large text, and deliberately not 4.5. #8 recorded the
        // light row's `textMuted` at 4.0:1 as large-text-only; that is the
        // brief's decision about a role, not a gap in it, and a gate that
        // demanded 4.5 here would be this file overruling the design brief.
        for (const darkMode of [true, false]) {
            const p = tokens.palette(darkMode, null);
            for (const bg of backgroundRoles) {
                const ratio = contrast(p.textMuted, p[bg]);
                verify(ratio >= 3.0,
                       (darkMode ? "dark" : "light") + " textMuted on " + bg
                       + " is " + ratio.toFixed(2) + ":1");
            }
        }
    }

    function test_the_accent_fill_reads_under_the_text_that_sits_on_it() {
        // `accentDeep` is a fill and never text: the selected chip (#54), the
        // active session row (#38), the lit control-centre tile (#44). All
        // three draw `textPrimary` on it and one draws `textSecondary` too, so
        // those are the two pairings that have to hold.
        //
        // This is the pair that made #44 fill the light row rather than let it
        // fall through: light mode's `textPrimary` is *dark*, so a light
        // `accentDeep` that darkened to match dark's would have been dark ink
        // on a dark fill — the one combination that cannot be read at all.
        for (const darkMode of [true, false]) {
            const p = tokens.palette(darkMode, null);
            const mode = darkMode ? "dark" : "light";
            const ratio = contrast(p.textPrimary, p.accentDeep);
            verify(ratio >= 4.5,
                   mode + " textPrimary on accentDeep is " + ratio.toFixed(2) + ":1");
            // And the reason nothing dimmer may go there: on a fill this
            // saturated the next role down is already under AA in dark, which
            // is what forces the lit tile's detail line onto `textPrimary` and
            // a smaller size (Surfaces/Drawers/ControlTile.qml).
            verify(contrast(p.textSecondary, p.accentDeep) < 4.5
                   || contrast(p.textMuted, p.accentDeep) < 4.5,
                   mode + " a dimmer role now reads on accentDeep — the tile "
                   + "detail could use it");
        }
    }

    function test_a_border_is_visible_against_what_it_borders() {
        // Not a text ratio: 1.2:1 is the point at which a hairline stops being
        // a hairline and becomes an edge nobody can see. `borderStrong` is a
        // focus ring, so it has to clear more than a subtle one does.
        for (const darkMode of [true, false]) {
            const p = tokens.palette(darkMode, null);
            const mode = darkMode ? "dark" : "light";
            for (const bg of ["surface", "surfaceRaised"]) {
                verify(contrast(p.borderSubtle, p[bg]) >= 1.2,
                       mode + " borderSubtle is invisible on " + bg);
                verify(contrast(p.borderStrong, p[bg]) >= 1.8,
                       mode + " borderStrong is too faint on " + bg);
            }
        }
    }

    function test_the_fallback_list_is_derived_rather_than_hand_written() {
        // It is empty now and the mechanism has to outlive that: a theme preset
        // (#56) can replace the row with a partial one, and a role it does not
        // name must resolve rather than arrive undefined. Derived means the
        // list re-computes instead of being a stale constant nobody updated.
        const computed = tokens.colorRoles.filter(
            role => tokens.lightSeed[role] === undefined);
        compare(tokens.lightFallbackRoles, computed);
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
        ignoreWarning(/not a colour/);
        const p = tokens.palette(true, {
            noSuchRole: "#ffffff",
            accentPrimary: "teal",        // named colours are refused on purpose
            accentWarm: "#0c7f",          // #RGBA — a form QColor cannot parse
            accentDeep: "#ff0c757b"       // #AARRGGBB — alpha leads, not trails
        });
        compare(p.accentPrimary, tokens.dark.accentPrimary);
        compare(p.accentWarm, tokens.dark.accentWarm);
        compare(p.accentDeep, "#ff0c757b");
        compare(p.noSuchRole, undefined);
    }

    // --- the wallpaper-coupled layer (#58) ------------------------------------

    function test_fixed_forest_is_the_shipped_row_untouched() {
        // The ticket's fourth acceptance criterion, and the reason the layer is
        // a separate argument rather than folded into the overrides: with no
        // mode running there is nothing between the row and the consumer, so
        // fixed forest renders exactly as it did before Services/Theming/
        // existed.
        for (const darkMode of [true, false]) {
            const before = tokens.palette(darkMode, null);
            for (const empty of [null, undefined, {}]) {
                const after = tokens.palette(darkMode, null, empty);
                for (const role of tokens.colorRoles)
                    compare(after[role], before[role]);
            }
        }
    }

    function test_the_dynamic_layer_replaces_single_roles() {
        // What a wallpaper-coupled mode writes: a sparse map of the roles it
        // moved. Everything it does not name is the shipped colour, which is
        // what makes "constrained" structural rather than promised.
        const p = tokens.palette(true, null, {
            accentPrimary: "#7bb8d8", accentDeep: "#0e6f8f"
        });
        compare(p.accentPrimary, "#7bb8d8");
        compare(p.accentDeep, "#0e6f8f");
        for (const role of tokens.colorRoles)
            if (role !== "accentPrimary" && role !== "accentDeep")
                compare(p[role], tokens.dark[role]);
    }

    function test_a_hand_written_override_outranks_the_wallpaper() {
        // Someone who typed a colour into the settings window has said
        // something more specific than a sampler can, and a mode that
        // overwrote it would make the field look broken.
        const p = tokens.palette(true, { accentPrimary: "#123456" },
                                       { accentPrimary: "#7bb8d8",
                                         accentDeep: "#0e6f8f" });
        compare(p.accentPrimary, "#123456");
        compare(p.accentDeep, "#0e6f8f");   // the role nobody claimed
    }

    function test_the_dynamic_layer_is_checked_like_any_other() {
        // The shell writes this key, but the user can edit the same file — so
        // it gets the hand-edited treatment rather than being trusted.
        ignoreWarning(/unknown palette role/);
        ignoreWarning(/not a colour/);
        const p = tokens.palette(true, null, {
            noSuchRole: "#ffffff", accentPrimary: "chartreuse"
        });
        compare(p.accentPrimary, tokens.dark.accentPrimary);
        compare(p.noSuchRole, undefined);
    }

    function test_only_the_hex_lengths_qcolor_parses_are_accepted() {
        // Qt takes #RGB, #RRGGBB and #AARRGGBB. There is no #RGBA: a
        // four-digit override would sail through and then paint as something
        // else entirely.
        for (const value of ["#fff", "#0c757b", "#ff0c757b"])
            verify(tokens.isColor(value), value + " should be accepted");
        for (const value of ["#f0f0", "#12345", "#0c757", "0c757b", "teal",
                             "rgb(1,2,3)", "", 16777215, null, undefined])
            verify(!tokens.isColor(value), value + " should be refused");
    }

    function test_palette_does_not_hand_out_its_own_table() {
        // Callers hold the result across a mode flip; it must not alias the
        // source rows.
        const p = tokens.palette(true, null);
        p.bgBase = "#ffffff";
        compare(tokens.dark.bgBase, "#0b100d");
        compare(tokens.palette(true, null).bgBase, "#0b100d");
    }

    // --- fog, veil -----------------------------------------------------------

    function test_the_fog_is_a_wash_not_a_dim() {
        // Brief §3.1: a scrim reads as pale mist, not as black at 50%. The
        // mist is a colour *role* — it recolours with the palette like every
        // other one — and the opacity is what keeps it a wash rather than a dim.
        compare(tokens.dark.fogWash, "#beced1");
        compare(tokens.fogWashOpacity, 0.10);
        verify(tokens.fogWashOpacity < 0.25);
    }

    function test_the_fog_pulse_thickens_the_same_fog() {
        // A refusal thickens the mist for a moment (#30's failure UX). Opacity
        // only — the blur never animates (#8) — and it has to be a visible step
        // up from resting without becoming a dim.
        verify(tokens.fogPulseOpacity > tokens.fogWashOpacity);
        verify(tokens.fogPulseOpacity < 0.5);
    }

    function test_the_veil_runs_dark_at_the_bottom() {
        // Brief §3.2: every pin is dark at the bottom and bright at the top,
        // and the veil is that gradient. Inverting it would light the surface
        // from below, which is the one thing the board never does.
        verify(tokens.veilBottom > tokens.veilTop);
        for (const alpha of [tokens.veilTop, tokens.veilBottom])
            verify(alpha >= 0 && alpha <= 1, alpha + " is not an alpha");
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
