// The full-dynamic palette (#59): the mapping, the two output shapes, the
// strict exit status, and the contrast contract a generated palette has to
// clear before anything wears it.
//
// This is the seam the ticket lives at. "With matugen installed, a wallpaper
// change restyles the shell" is a lifecycle and belongs to
// tools/theming-harness.sh; everything that decides *what colour* is arithmetic
// over a JSON document and needs no compositor, no wallpaper and no binary.
//
// The fixtures are real matugen 4.1.0 output — three wallpapers run through it
// and trimmed to the roles the mapping actually reads. They are checked in
// rather than generated, because a test that shells out to the optional
// dependency it exists to test cannot run on a machine without it.
import QtQuick
import QtTest
import "../Core"
import "../Services/Theming"

TestCase {
    name: "MatugenPolicy"

    MatugenPolicy { id: policy }
    Tokens { id: tokens }

    // --- fixtures -------------------------------------------------------------
    //
    // `role: [dark, light]`, which is the shape a person can read; `nested()`
    // below inflates it into the shape matugen actually emits.

    /// A lake-blue wallpaper — the cool end, and the one whose generated accent
    /// is furthest from the shipped teal.
    readonly property var lake: ({
        surface: ["#101418", "#f7f9ff"],
        surface_container_lowest: ["#0b0e12", "#ffffff"],
        surface_container_low: ["#181c20", "#f2f3f9"],
        surface_container: ["#1c2024", "#eceef4"],
        surface_container_high: ["#272a2f", "#e6e8ee"],
        outline_variant: ["#42474e", "#c2c7cf"],
        outline: ["#8c9199", "#72777f"],
        on_surface: ["#e0e2e8", "#181c20"],
        on_surface_variant: ["#c2c7cf", "#42474e"],
        primary: ["#9ccbfb", "#30628c"],
        primary_container: ["#114a73", "#cfe5ff"],
        tertiary: ["#d4bee6", "#695779"],
        error: ["#ffb4ab", "#ba1a1a"],
        secondary: ["#b9c8da", "#526070"],
        inverse_surface: ["#e0e2e8", "#2d3135"]
    })

    /// A warm sunset — the other end of the wheel, and the one where matugen's
    /// own neutrals carry a heavy cast.
    readonly property var amber: ({
        surface: ["#17130b", "#fff8f3"],
        surface_container_lowest: ["#120e07", "#ffffff"],
        surface_container_low: ["#201b13", "#fdf2e5"],
        surface_container: ["#241f17", "#f7ecdf"],
        surface_container_high: ["#2f2921", "#f2e6d9"],
        outline_variant: ["#4e4639", "#d1c5b4"],
        outline: ["#9a8f80", "#807667"],
        on_surface: ["#ece1d4", "#201b13"],
        on_surface_variant: ["#d1c5b4", "#4e4639"],
        primary: ["#eebf6d", "#7b580d"],
        primary_container: ["#5e4200", "#ffdea9"],
        tertiary: ["#b3cea6", "#4d6544"],
        error: ["#ffb4ab", "#ba1a1a"],
        secondary: ["#dac3a1", "#6d5c3f"],
        inverse_surface: ["#ece1d4", "#353027"]
    })

    /// A near-greyscale wallpaper. #58's mode declines this one outright — no
    /// dominant hue, keep the shipped accent — and this mode cannot: matugen
    /// always answers, so the palette it produces from a flat grey has to be
    /// legible on its own merits rather than by falling back to one that is.
    readonly property var grey: ({
        surface: ["#111318", "#f9f9ff"],
        surface_container_lowest: ["#0c0e13", "#ffffff"],
        surface_container_low: ["#1a1b20", "#f3f3fa"],
        surface_container: ["#1e1f25", "#ededf4"],
        surface_container_high: ["#282a2f", "#e8e7ee"],
        outline_variant: ["#44474f", "#c4c6d0"],
        outline: ["#8e9099", "#74777f"],
        on_surface: ["#e2e2e9", "#1a1b20"],
        on_surface_variant: ["#c4c6d0", "#44474f"],
        primary: ["#adc6ff", "#445e91"],
        primary_container: ["#2b4678", "#d8e2ff"],
        tertiary: ["#debcdf", "#715573"],
        error: ["#ffb4ab", "#ba1a1a"],
        secondary: ["#bfc6dc", "#575e71"],
        inverse_surface: ["#e2e2e9", "#2f3036"]
    })

    readonly property var fixtures: ({ lake: lake, amber: amber, grey: grey })

    /// matugen 4.x: the modes nest under the role, each behind a `color` key.
    function nested(pairs) {
        const colors = {};
        for (const role in pairs)
            colors[role] = {
                dark: { color: pairs[role][0] },
                default: { color: pairs[role][0] },
                light: { color: pairs[role][1] }
            };
        return JSON.stringify({ colors: colors, mode: "dark", is_dark_mode: true });
    }

    /// Everything before 4.0, and still reachable via `--old-json-output`: the
    /// role nests under the mode and the value is the string itself.
    function flat(pairs) {
        const dark = {};
        const light = {};
        for (const role in pairs) {
            dark[role] = pairs[role][0];
            light[role] = pairs[role][1];
        }
        return JSON.stringify({ colors: { dark: dark, light: light } });
    }

    // --- the mapping ----------------------------------------------------------

    function test_the_mapping_names_every_role_the_shell_paints_with() {
        // Not "seventeen" — the token set itself. A role added to
        // Core/Tokens.qml and not here would be a role the generated palette
        // silently left at its shipped value, which is a colour from the other
        // palette sitting in the middle of this one.
        compare(policy.roles.length, tokens.colorRoles.length);
        for (const role of tokens.colorRoles)
            verify(policy.roleSources[role] !== undefined,
                   role + " has no M3 source");
    }

    function test_the_backgrounds_come_off_one_ladder_in_order() {
        // The elevation series, and the reason the five are not five hand-picked
        // tones: they have to keep their *spacing* or an overlay stops looking
        // raised.
        for (const name of ["lake", "amber", "grey"]) {
            const palette = policy.paletteFrom(rowOf(fixtures[name], true));
            const order = ["bgSunken", "bgBase", "surface", "surfaceRaised",
                           "surfaceOverlay"];
            for (let i = 1; i < order.length; i++)
                verify(policy.luminance(palette[order[i]])
                       >= policy.luminance(palette[order[i - 1]]),
                       name + ": " + order[i] + " is not above " + order[i - 1]);
        }
    }

    function rowOf(pairs, darkMode) {
        const row = {};
        for (const role in pairs)
            row[role] = pairs[role][darkMode ? 0 : 1];
        return row;
    }

    // --- reading the output ---------------------------------------------------

    function test_the_4x_shape_parses() {
        const parsed = policy.parse(nested(lake));
        verify(parsed.ok);
        compare(parsed.dark.primary, "#9ccbfb");
        compare(parsed.light.primary, "#30628c");
    }

    function test_the_pre_4x_shape_parses_too() {
        // Which shape a machine emits is a property of the matugen its
        // distribution shipped. A mode that worked on one machine and silently
        // did nothing on another is what admitting both avoids.
        const parsed = policy.parse(flat(lake));
        verify(parsed.ok);
        compare(parsed.dark.primary, "#9ccbfb");
        compare(parsed.light.primary, "#30628c");
    }

    function test_both_rows_arrive_from_one_run() {
        // matugen emits the whole scheme in both modes whatever --mode it was
        // given, so the dark/light flip is a re-map and not a re-read.
        const parsed = policy.parse(nested(amber));
        verify(policy.paletteFrom(parsed.dark).textPrimary !== undefined);
        verify(policy.paletteFrom(parsed.light).textPrimary !== undefined);
        verify(policy.paletteFrom(parsed.dark).bgBase
               !== policy.paletteFrom(parsed.light).bgBase);
    }

    function test_nonsense_is_refused_rather_than_guessed_at() {
        verify(!policy.parse("").ok);
        verify(!policy.parse("   ").ok);
        verify(!policy.parse("Error: could not read image").ok);
        verify(!policy.parse("{}").ok);
        verify(!policy.parse('{"colors":{}}').ok);
    }

    function test_a_scheme_missing_a_role_is_refused_whole() {
        // Partial is the one outcome worse than none: the missing roles fall
        // back to the shipped forest ones, and a bar half in one palette and
        // half in the other is a bug nobody can read off a screenshot.
        const short = JSON.parse(nested(lake));
        delete short.colors.outline;
        compare(Object.keys(policy.paletteFrom(policy.parse(
            JSON.stringify(short)).dark)).length, 0);
        compare(policy.outcome(0, JSON.stringify(short), true).ok, false);
        compare(policy.outcome(0, JSON.stringify(short), true).error,
                "incomplete scheme");
    }

    // --- the exit status (#78) ------------------------------------------------

    function test_a_failed_run_is_a_failure_and_not_an_empty_palette() {
        // matugen exits 1 with an empty stdout when an image has several
        // candidate source colours and no terminal to ask. A caller that read
        // only stdout would call that "this wallpaper has no colours", which is
        // a sentence about the wallpaper rather than about the failure.
        const failed = policy.outcome(1, "", true);
        compare(failed.ok, false);
        compare(failed.error, "matugen exited 1");
        compare(Object.keys(failed.palette).length, 0);
    }

    function test_a_nonzero_exit_is_refused_even_with_output_on_stdout() {
        // `--continue-on-error` and a half-written template run both produce
        // this: usable-looking JSON behind a status that says it went wrong.
        const failed = policy.outcome(2, nested(lake), true);
        compare(failed.ok, false);
        compare(failed.error, "matugen exited 2");
    }

    function test_a_clean_exit_with_nothing_on_stdout_is_still_a_failure() {
        compare(policy.outcome(0, "", true).ok, false);
        compare(policy.outcome(0, "", true).error, "no output");
    }

    // --- the contrast contract ------------------------------------------------

    function test_every_fixture_clears_the_floor_in_both_modes() {
        // The gate the ticket asked for, at the seam where it is arithmetic:
        // the same pairings tests/tst_tokens.qml holds the shipped rows to,
        // applied to a palette nobody authored and nobody looked at.
        for (const name of ["lake", "amber", "grey"])
            for (const darkMode of [true, false]) {
                const result = policy.outcome(0, nested(fixtures[name]), darkMode);
                verify(result.ok, name + " did not generate: " + result.error);
                const failures = policy.shortfalls(result.palette);
                verify(failures.length === 0,
                       name + " " + (darkMode ? "dark" : "light") + ": "
                       + failures.map(f => f.fg + " on " + f.bg + " is "
                                      + f.ratio.toFixed(2) + ":1 (floor "
                                      + f.floor + ")").join(", "));
            }
    }

    function test_the_run_reports_how_much_rescuing_it_took() {
        // A wallpaper whose palette needs half its roles lifted is a wallpaper
        // the mode is barely serving, and the log is where that shows up.
        for (const name of ["lake", "amber", "grey"])
            for (const darkMode of [true, false]) {
                const raw = policy.paletteFrom(rowOf(fixtures[name], darkMode));
                const result = policy.outcome(0, nested(fixtures[name]), darkMode);
                let moved = 0;
                for (const role of policy.roles)
                    if (result.palette[role] !== raw[role])
                        moved++;
                compare(result.lifted, moved, name + ": miscounted the lift");
            }
    }

    function test_the_raw_mapping_does_not_already_clear_it() {
        // Otherwise the test above would pass on a pass that never ran, and the
        // legibility pass could be deleted without a single failure. At least
        // one fixture has to arrive short — matugen's tones hold AA for M3's
        // own pairings, and the shell's are not those.
        let shortSomewhere = false;
        for (const name of ["lake", "amber", "grey"])
            for (const darkMode of [true, false]) {
                const raw = policy.paletteFrom(rowOf(fixtures[name], darkMode));
                if (policy.shortfalls(raw).length > 0)
                    shortSomewhere = true;
            }
        verify(shortSomewhere,
               "every fixture already cleared the floor — the pass is untested");
    }

    function test_the_pass_moves_lightness_and_leaves_the_colour_alone() {
        // Rescuing contrast by rotating would turn the colour the wallpaper
        // earned into a different one and call it the same. AccentPolicy makes
        // the same promise about the same axis.
        const raw = policy.paletteFrom(rowOf(lake, true));
        const fixed = policy.enforce(raw);
        for (const failure of policy.shortfalls(raw)) {
            const before = policy.color.toOklch(raw[failure.fg]);
            const after = policy.color.toOklch(fixed[failure.fg]);
            verify(Math.abs(after.H - before.H) < 2.0
                   || Math.abs(Math.abs(after.H - before.H) - 360) < 2.0,
                   failure.fg + " changed hue: " + before.H.toFixed(1) + "° → "
                   + after.H.toFixed(1) + "°");
            verify(Math.abs(after.L - before.L) > 0.0001,
                   failure.fg + " was short and did not move");
        }
    }

    function test_the_pass_leaves_the_backgrounds_where_it_found_them() {
        // They are the structure: five tones whose spacing is what makes an
        // overlay look raised. A pass that nudged one to rescue a label would
        // flatten the ladder to fix a word.
        for (const name of ["lake", "amber", "grey"])
            for (const darkMode of [true, false]) {
                const raw = policy.paletteFrom(rowOf(fixtures[name], darkMode));
                const fixed = policy.enforce(raw);
                for (const role of policy.backgroundRoles)
                    compare(fixed[role], raw[role],
                            name + ": " + role + " moved");
            }
    }

    function test_a_palette_that_starts_illegible_still_ends_legible() {
        // The adversarial case, and the one no real wallpaper produced: every
        // text and accent role set to the background itself, 1.0:1 across the
        // board. Nothing about the input is salvageable, so what is being
        // tested is that the pass answers with a legible palette anyway rather
        // than with the least-bad version of an unreadable one.
        const flatGrey = policy.paletteFrom(rowOf(grey, true));
        for (const role of ["textPrimary", "textSecondary", "textMuted",
                            "accentPrimary", "accentWarm", "accentEmber",
                            "accentLichen", "accentStone", "borderSubtle",
                            "borderStrong"])
            flatGrey[role] = flatGrey.bgBase;
        verify(policy.shortfalls(flatGrey).length > 0);
        const left = policy.shortfalls(policy.enforce(flatGrey));
        verify(left.length === 0,
               left.map(f => f.fg + " on " + f.bg + " is " + f.ratio.toFixed(2)
                        + ":1 (floor " + f.floor + ")").join(", "));
    }

    function test_the_pass_does_not_move_a_role_that_already_clears() {
        const fixed = policy.enforce(policy.paletteFrom(rowOf(lake, true)));
        const twice = policy.enforce(fixed);
        for (const role of policy.roles)
            compare(twice[role], fixed[role], role + " moved on a second pass");
    }

    function test_the_fill_is_measured_under_the_text_that_sits_on_it() {
        // `accentDeep` is never text: it is the selected chip, the active
        // session row, the lit control-centre tile, and all three draw
        // `textPrimary` on it.
        for (const name of ["lake", "amber", "grey"])
            for (const darkMode of [true, false]) {
                const palette = policy.outcome(0, nested(fixtures[name]),
                                               darkMode).palette;
                const ratio = policy.color.contrast(
                    policy.luminance(palette.textPrimary),
                    policy.luminance(palette.accentDeep));
                verify(ratio >= policy.minRatio - 0.0005,
                       name + ": textPrimary on accentDeep is "
                       + ratio.toFixed(2) + ":1");
            }
    }

    function test_the_fog_flips_sides_with_the_mode() {
        // The fog is a wash whose job is to obscure. Ten per cent of a pale
        // mist over a pale desktop is a scrim you can read straight through —
        // Core/Tokens.qml's own argument for inverting this one role.
        for (const name of ["lake", "amber", "grey"]) {
            const dark = policy.outcome(0, nested(fixtures[name]), true).palette;
            const light = policy.outcome(0, nested(fixtures[name]), false).palette;
            verify(policy.luminance(dark.fogWash) > policy.luminance(dark.bgBase),
                   name + ": the dark fog is darker than the page");
            verify(policy.luminance(light.fogWash) < policy.luminance(light.bgBase),
                   name + ": the light fog is lighter than the page");
        }
    }

    function test_every_colour_is_a_colour_the_settings_file_accepts() {
        // The palette is written to `appearance.dynamic`, and Core/Tokens.qml
        // drops anything it cannot parse with a warning — which would be a hole
        // in the palette rather than a refusal.
        for (const name of ["lake", "amber", "grey"])
            for (const darkMode of [true, false]) {
                const palette = policy.outcome(0, nested(fixtures[name]),
                                               darkMode).palette;
                compare(Object.keys(palette).length, tokens.colorRoles.length);
                for (const role of tokens.colorRoles)
                    verify(tokens.isColor(palette[role]),
                           name + ": " + role + " = " + palette[role]);
            }
    }

    function test_short_hex_is_normalized_rather_than_passed_through() {
        // Legal in the settings file, but the arithmetic round-trips through
        // six digits — and a palette whose keys changed shape between
        // "generated" and "regenerated" would rewrite the file every time.
        compare(policy.normalize("#ABC"), "#aabbcc");
        compare(policy.normalize("#A1B2C3"), "#a1b2c3");
    }

    // --- the command ----------------------------------------------------------

    function test_templates_are_off_unless_asked_for() {
        // Without --dry-run matugen renders every template in the user's own
        // config, reloads the apps they name and runs their post-hooks — on
        // every wallpaper change, none of it asked for by the shell.
        const quiet = policy.argv("/wall.png", true, false);
        verify(quiet.indexOf("--dry-run") >= 0);
        const loud = policy.argv("/wall.png", true, true);
        compare(loud.indexOf("--dry-run"), -1);
    }

    function test_the_command_never_waits_for_a_terminal() {
        // On an image with several candidate source colours matugen asks the
        // terminal which to use, and a shell that spawned it has no terminal to
        // ask — it exits 1 instead. This is the flag that makes the mode work
        // on wallpapers with more than one colour in them, which is all of them.
        const argv = policy.argv("/wall.png", true, false);
        const at = argv.indexOf("--prefer");
        verify(at >= 0);
        compare(argv[at + 1], "saturation");
    }

    function test_the_mode_travels_with_the_command() {
        // Only decides which row matugen calls `default` — both rows are in the
        // JSON either way — but a template renders from `default`, so with
        // templates on this is what keeps the external apps in the shell's mode.
        const dark = policy.argv("/wall.png", true, false);
        compare(dark[dark.indexOf("--mode") + 1], "dark");
        const light = policy.argv("/wall.png", false, false);
        compare(light[light.indexOf("--mode") + 1], "light");
        compare(light[2], "/wall.png");
    }

    // --- the log (#81) --------------------------------------------------------

    function test_each_outcome_says_which_one_it_was() {
        verify(policy.generatedLine("#9ccbfb", 3, true).indexOf("#9ccbfb") >= 0);
        verify(policy.generatedLine("#9ccbfb", 3, true).indexOf("dark") >= 0);
        verify(policy.generatedLine("#9ccbfb", 3, false).indexOf("light") >= 0);
        verify(policy.failedLine("matugen exited 1").indexOf("exited 1") >= 0);
        verify(policy.absentLine().indexOf("not installed") >= 0);
        verify(policy.clearedLine("forest").indexOf("forest") >= 0);
    }
}
