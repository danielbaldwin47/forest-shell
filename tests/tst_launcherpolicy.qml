import QtQuick
import QtTest
import "../Services/Launcher"

TestCase {
    id: testCase
    name: "LauncherPolicy"

    LauncherPolicy { id: policy }

    /// `launcher.providers` as the schema resolves it — every provider on.
    readonly property var allOn: ({
        apps: true, calculator: true, clipboard: true,
        emoji: true, actions: true, claude: true
    })

    /// A handful of desktop entries in the shape Quickshell's model hands over
    /// (`Quickshell.DesktopEntries`, verified on 0.3.0): id, name, genericName,
    /// keywords.
    readonly property var entries: [
        { id: "firefox", name: "Firefox", genericName: "Web Browser",
          keywords: ["internet", "www"] },
        { id: "org.gnome.Meld", name: "Meld", genericName: "Diff Viewer",
          keywords: ["diff", "merge"] },
        { id: "kitty", name: "kitty", genericName: "Terminal", keywords: ["shell"] },
        { id: "org.pulseaudio.pavucontrol", name: "Volume Control",
          genericName: "Volume Control", keywords: ["audio", "mixer"] }
    ]

    function names(rows) {
        return rows.map(row => row.id);
    }

    // --- routing -------------------------------------------------------------

    function test_a_a_bare_query_is_the_apps_provider() {
        compare(policy.prefixOf("", testCase.allOn), "");
        compare(policy.prefixOf("fire", testCase.allOn), "");
        compare(policy.route("fire", testCase.allOn).id, "apps");
        compare(policy.bodyOf("fire", testCase.allOn), "fire");
    }

    function test_a_punctuation_prefix_picks_its_provider() {
        compare(policy.prefixOf("=2+2", testCase.allOn), "=");
        compare(policy.route("=2+2", testCase.allOn).id, "calculator");
        compare(policy.prefixOf("?why", testCase.allOn), "?");
        compare(policy.route("?why", testCase.allOn).id, "claude");
        compare(policy.route(";", testCase.allOn).id, "clipboard");
        compare(policy.route(":tree", testCase.allOn).id, "emoji");
        compare(policy.route("/lock", testCase.allOn).id, "actions");
    }

    function test_the_body_drops_the_prefix_and_one_space_after_it() {
        compare(policy.bodyOf("=2+2", testCase.allOn), "2+2");
        compare(policy.bodyOf("= 2+2", testCase.allOn), "2+2");
        // One space, not all of them — a query is allowed to start with one.
        compare(policy.bodyOf("=  2+2", testCase.allOn), " 2+2");
        compare(policy.bodyOf("=", testCase.allOn), "");
    }

    function test_punctuation_no_provider_claims_is_an_app_search() {
        compare(policy.prefixOf("!important", testCase.allOn), "");
        compare(policy.bodyOf("!important", testCase.allOn), "!important");
        compare(policy.route("!important", testCase.allOn).id, "apps");
    }

    function test_a_provider_switched_off_does_not_claim_its_prefix() {
        const noCalc = { apps: true, calculator: false, clipboard: true,
                         emoji: true, actions: true, claude: true };
        compare(policy.prefixOf("=2+2", noCalc), "");
        compare(policy.route("=2+2", noCalc).id, "apps");
        // ...and the whole query is what apps searches for, punctuation included.
        compare(policy.bodyOf("=2+2", noCalc), "=2+2");
    }

    function test_an_unreadable_config_leaves_every_provider_on() {
        // The schema fills every leaf, so a missing key means the config never
        // resolved — a launcher that answers nothing is the worse failure.
        compare(policy.prefixOf("=2+2", ({})), "=");
        compare(policy.prefixOf("=2+2", undefined), "=");
        compare(policy.enabled(policy.providers[0], undefined), true);
    }

    function test_the_legend_teaches_the_prefixes_that_are_on() {
        const legend = policy.legend(testCase.allOn);
        compare(legend.length, 5);                    // everything but apps
        compare(legend.map(entry => entry.prefix).join(""), "=;:/?");

        const noClaude = { apps: true, calculator: true, clipboard: true,
                           emoji: true, actions: true, claude: false };
        compare(policy.legend(noClaude).map(entry => entry.prefix).join(""), "=;:/");
    }

    // --- what has landed -----------------------------------------------------

    function test_five_providers_have_landed() {
        // Apps with #39; calculator, emoji and actions with #40; Ask Claude
        // with #41.
        for (const query of ["", "=2+2", ":tree", "/lock", "?why"]) {
            compare(policy.route(query, testCase.allOn).landed, true);
            compare(policy.unavailable(policy.route(query, testCase.allOn)), "");
        }
    }

    function test_an_unlanded_provider_names_the_ticket_that_lands_it() {
        // The clipboard's owner was `#40` from the day the table was written
        // and #40 is not the clipboard — #53 is. Not a comment: this string is
        // what a user typing `;` reads, so a wrong owner sends them to the
        // wrong ticket.
        //
        // One left, which is why this test still has a subject at all.
        compare(policy.unavailable(policy.route(";", testCase.allOn)),
                "Clipboard lands with #53");
    }

    // --- the provider that is not a list -------------------------------------

    function test_only_ask_claude_converses() {
        verify(policy.converses("?why is the sky blue", testCase.allOn));
        for (const query of ["", "fire", "=2+2", ":tree", "/lock"])
            verify(!policy.converses(query, testCase.allOn));
    }

    function test_a_bare_prefix_already_converses() {
        // `?` with nothing after it is the panel already being a chat waiting
        // for a question, not a list that happens to be empty.
        verify(policy.converses("?", testCase.allOn));
    }

    function test_ask_claude_switched_off_falls_back_to_a_list() {
        // Not a transcript nothing can be typed into: with the provider off
        // the prefix is unclaimed, so `?why` is an app search that finds
        // nothing and says so.
        const noClaude = { apps: true, calculator: true, clipboard: true,
                           emoji: true, actions: true, claude: false };
        verify(!policy.converses("?why", noClaude));
        compare(policy.route("?why", noClaude).id, "apps");
    }

    // --- routing without a prefix --------------------------------------------

    function test_a_leading_digit_is_the_calculator_without_saying_so() {
        compare(policy.route("12 * 60 * 24", testCase.allOn).id, "calculator");
        compare(policy.impliedId("2+2", testCase.allOn), "calculator");
        // No prefix was typed, so there is none to strip.
        compare(policy.bodyOf("2+2", testCase.allOn), "2+2");
    }

    function test_anything_else_bare_is_still_the_apps_provider() {
        compare(policy.route("fire", testCase.allOn).id, "apps");
        compare(policy.impliedId("fire", testCase.allOn), "");
        compare(policy.impliedId("", testCase.allOn), "");
        // The two an implicit route would have to be right about and is not.
        compare(policy.route("(3+4)*2", testCase.allOn).id, "apps");
        compare(policy.route("-5", testCase.allOn).id, "apps");
    }

    function test_a_calculator_switched_off_does_not_swallow_a_bare_query() {
        // The same rule `prefixOf` follows for a disabled prefix: a provider
        // that is off claims nothing, so the query falls through to apps.
        const noCalculator = { apps: true, calculator: false, clipboard: true,
                               emoji: true, actions: true, claude: true };
        compare(policy.impliedId("2048", noCalculator), "");
        compare(policy.route("2048", noCalculator).id, "apps");
        compare(policy.answers("2048", noCalculator), true);
    }

    // --- fuzzy matching ------------------------------------------------------

    function test_an_empty_query_is_not_a_filter() {
        compare(policy.score("", "Firefox"), 0);
        compare(policy.scoreEntry("", testCase.entries[0]), 0);
    }

    function test_a_subsequence_matches_and_anything_else_does_not() {
        verify(policy.score("ffx", "Firefox") >= 0);
        verify(policy.score("fox", "Firefox") >= 0);
        compare(policy.score("xyz", "Firefox"), -1);
        compare(policy.score("firefoxx", "Firefox"), -1);
        // Order matters — the letters are all there, backwards.
        compare(policy.score("xof", "Firefox"), -1);
    }

    function test_matching_ignores_case() {
        verify(policy.score("FIRE", "Firefox") >= 0);
        verify(policy.score("fire", "FIREFOX") >= 0);
    }

    function test_adjacent_and_leading_hits_score_higher() {
        // "fire" is a run from the start; "ffx" is scattered.
        verify(policy.score("fire", "Firefox") > policy.score("ffx", "Firefox"));
        // The same needle earlier in the word beats it later in the word.
        verify(policy.score("meld", "Meld") > policy.score("meld", "Text Meld"));
    }

    function test_a_name_hit_outranks_a_generic_name_or_keyword_hit() {
        // "Volume Control" has the word in its name; Firefox only in a keyword.
        const byName = policy.scoreEntry("volume", testCase.entries[3]);
        const byKeyword = policy.scoreEntry("internet", testCase.entries[0]);
        verify(byName > 0);
        verify(byKeyword > 0);
        verify(byName > byKeyword);
    }

    function test_a_keyword_or_generic_name_still_finds_the_app() {
        // The whole point of matching them: you do not know what it is called.
        verify(policy.scoreEntry("browser", testCase.entries[0]) >= 0);
        verify(policy.scoreEntry("terminal", testCase.entries[2]) >= 0);
        verify(policy.scoreEntry("merge", testCase.entries[1]) >= 0);
        compare(policy.scoreEntry("spreadsheet", testCase.entries[0]), -1);
    }

    function test_an_entry_that_is_not_there_matches_nothing() {
        compare(policy.scoreEntry("fire", null), -1);
        compare(policy.scoreEntry("fire", undefined), -1);
    }

    // --- frecency ------------------------------------------------------------

    readonly property real now: 1754000000000     // a fixed clock, so this is a test

    function test_an_app_never_launched_gets_no_boost() {
        compare(policy.frecency("firefox", ({}), ({}), testCase.now), 0);
        compare(policy.frecency("firefox", undefined, undefined, testCase.now), 0);
    }

    function test_more_launches_is_a_bigger_boost_with_diminishing_returns() {
        const stamps = { firefox: testCase.now };
        const one = policy.frecency("firefox", { firefox: 1 }, stamps, testCase.now);
        const two = policy.frecency("firefox", { firefox: 2 }, stamps, testCase.now);
        const ten = policy.frecency("firefox", { firefox: 10 }, stamps, testCase.now);
        const hundred = policy.frecency("firefox", { firefox: 100 }, stamps, testCase.now);

        verify(two > one);
        verify(ten > two);
        // The second launch moves it more than the ninetieth does.
        verify(two - one > hundred - ten);
        // ...and it is capped, so history never wins outright.
        verify(hundred <= 4);
    }

    function test_a_recent_launch_outweighs_an_old_one_of_the_same_count() {
        const uses = { firefox: 5 };
        const fresh = policy.frecency("firefox", uses, { firefox: testCase.now },
                                      testCase.now);
        const week = policy.frecency("firefox", uses,
                                     { firefox: testCase.now - 7 * 86400000 },
                                     testCase.now);
        const year = policy.frecency("firefox", uses,
                                     { firefox: testCase.now - 365 * 86400000 },
                                     testCase.now);
        verify(fresh > week);
        verify(week > year);
        // Nothing decays to nothing: a rarely-used app keeps its place.
        verify(year > 0);
    }

    function test_a_launch_bumps_the_count_and_leaves_the_rest_alone() {
        const before = { firefox: 2, kitty: 9 };
        const after = policy.bump(before, "firefox");
        compare(after.firefox, 3);
        compare(after.kitty, 9);
        // The map it was handed is untouched — SpecFile compares against it.
        compare(before.firefox, 2);
    }

    function test_a_first_launch_starts_the_count_at_one() {
        compare(policy.bump(({}), "firefox").firefox, 1);
        compare(policy.bump(undefined, "firefox").firefox, 1);
    }

    function test_a_launch_stamps_the_time() {
        const after = policy.stamp({ kitty: 1 }, "firefox", testCase.now);
        compare(after.firefox, testCase.now);
        compare(after.kitty, 1);
    }

    // --- ranking -------------------------------------------------------------

    function test_no_query_is_a_short_list_of_what_you_use() {
        const uses = { kitty: 20, firefox: 3 };
        const stamps = { kitty: testCase.now, firefox: testCase.now };
        const rows = policy.rank(testCase.entries, "", uses, stamps, testCase.now);

        compare(rows[0].id, "kitty");
        compare(rows[1].id, "firefox");
        // Capped, and short.
        verify(rows.length <= policy.recentsLimit);
    }

    function test_with_no_history_at_all_the_empty_state_is_alphabetical() {
        const rows = policy.rank(testCase.entries, "", ({}), ({}), testCase.now);
        // Not arbitrary — "Firefox", "kitty", "Meld", "Volume Control".
        compare(testCase.names(rows)[0], "firefox");
        compare(rows.length, testCase.entries.length);
    }

    function test_a_query_filters_to_what_matches() {
        const rows = policy.rank(testCase.entries, "meld", ({}), ({}), testCase.now);
        compare(testCase.names(rows), ["org.gnome.Meld"]);
    }

    function test_a_query_that_matches_nothing_returns_nothing() {
        compare(policy.rank(testCase.entries, "zzzz", ({}), ({}), testCase.now).length, 0);
    }

    function test_frecency_breaks_a_tie_between_two_matches() {
        // Both "Volume Control" and "Meld" contain the letters of "l"; use a
        // needle that genuinely matches two entries instead.
        const both = policy.rank(testCase.entries, "e", ({}), ({}), testCase.now);
        verify(both.length >= 2);

        const withHistory = policy.rank(
            testCase.entries, "e",
            { "org.pulseaudio.pavucontrol": 40 },
            { "org.pulseaudio.pavucontrol": testCase.now },
            testCase.now);
        compare(withHistory[0].id, "org.pulseaudio.pavucontrol");
    }

    function test_history_does_not_beat_a_better_match() {
        // kitty has been launched constantly; the query names Meld exactly.
        const rows = policy.rank(testCase.entries, "meld",
                                 { kitty: 500 }, { kitty: testCase.now },
                                 testCase.now);
        compare(rows[0].id, "org.gnome.Meld");
    }

    function test_ranking_an_empty_model_is_an_empty_list_not_an_error() {
        compare(policy.rank([], "fire", ({}), ({}), testCase.now).length, 0);
        compare(policy.rank(undefined, "fire", ({}), ({}), testCase.now).length, 0);
    }

    // --- geometry ------------------------------------------------------------

    function test_the_clearing_is_the_measured_one() {
        compare(policy.columnWidth, 720);
        compare(policy.rowHeight, 46);
        compare(policy.horizonFraction, 0.32);
    }

    function test_the_column_narrows_rather_than_overhanging_a_small_screen() {
        compare(policy.column(1920, 40), 720);
        compare(policy.column(1280, 40), 720);
        compare(policy.column(600, 40), 520);
        // Never absurd, however small the output.
        verify(policy.column(200, 40) >= 240);
    }

    /// What Launcher.qml leaves for anything that is not a row, token for
    /// token: the gap under the rule (space4), then below the last row the gap
    /// (space2), the overflow label, the gap above the legend (space3), the
    /// rule (hairline), the legend row, the card's bottom padding (space5) and
    /// the margin that keeps the card off the bottom edge (space6).
    readonly property real chrome: 16 + 8 + 16 + 12 + 1 + 18 + 20 + 24

    function test_the_list_stops_at_the_fold() {
        // #11 §6 measured 8 rows on a 720-tall screen at a 32% horizon, with
        // the footer clear — which is the number this has to reproduce.
        compare(policy.fold(720, testCase.chrome), 8);
        // A taller screen holds more.
        verify(policy.fold(1080, testCase.chrome) > policy.fold(720, testCase.chrome));
        // A bigger footer takes them away.
        verify(policy.fold(720, 240) < policy.fold(720, testCase.chrome));
    }

    function test_the_fold_never_collapses_to_nothing() {
        compare(policy.fold(200, 60), 3);
        compare(policy.fold(0, 0), 3);
    }

    function test_the_list_says_how_many_it_hid() {
        compare(policy.hidden(20, 8), "12 more");
        compare(policy.hidden(9, 8), "1 more");
    }

    function test_a_list_that_hid_nothing_says_nothing() {
        compare(policy.hidden(8, 8), "");
        compare(policy.hidden(0, 0), "");
        // A shown count above the total is not a negative label.
        compare(policy.hidden(3, 8), "");
    }

    function test_the_card_fits_on_a_short_screen() {
        // The defect this arithmetic had: the fold was computed without the
        // gap between the horizon and the first row, so on a short output the
        // card ran past the bottom of the screen and took the legend with it —
        // #11 §6's original bug, reintroduced by a missing term.
        //
        // Reproduced as the geometry the surface lays out: everything from the
        // horizon down has to fit in what is below the horizon.
        const heights = [1080, 800, 768, 720, 600, 520, 488, 400];
        for (const height of heights) {
            const rows = policy.fold(height, testCase.chrome);
            const below = height * (1 - policy.horizonFraction);
            const used = rows * policy.rowHeight + testCase.chrome;
            verify(used <= below || rows === 3);
        }
    }

    // --- which provider answers ----------------------------------------------

    function test_a_landed_provider_that_is_on_answers() {
        compare(policy.answers("fire", testCase.allOn), true);
        compare(policy.answers("", testCase.allOn), true);
    }

    function test_a_provider_that_has_not_landed_does_not_answer() {
        compare(policy.answers(";", testCase.allOn), false);
    }

    function test_the_providers_that_landed_with_this_ticket_answer() {
        compare(policy.answers("=2+2", testCase.allOn), true);
        compare(policy.answers(":tree", testCase.allOn), true);
        compare(policy.answers("/lock", testCase.allOn), true);
        compare(policy.answers("2+2", testCase.allOn), true);
        compare(policy.answers("?hello", testCase.allOn), true);
    }

    function test_switching_apps_off_actually_switches_apps_off() {
        // The key the settings tab already offers. Apps has no prefix to stop
        // claiming, so this is the only place it can be honoured — and without
        // it the switch turns nothing off at all.
        const noApps = { apps: false, calculator: true, clipboard: true,
                         emoji: true, actions: true, claude: true };
        compare(policy.answers("fire", noApps), false);
        compare(policy.answers("", noApps), false);
        // ...and it says so rather than showing an empty list.
        compare(policy.empty("fire", noApps, true, null).text, "Apps is switched off");
    }

    // --- the empty state -----------------------------------------------------

    function test_the_five_silences_are_told_apart() {
        // #81's lesson on a surface: one picture for five causes is how a bug
        // gets two candidate explanations.
        compare(policy.empty(";", testCase.allOn, true, null).text,
                "Clipboard lands with #53");
        compare(policy.empty("fire", testCase.allOn, false, null).text,
                "Looking for applications…");
        compare(policy.empty("fire", testCase.allOn, true, null).text, "No matches");
        compare(policy.empty("", testCase.allOn, true, null).text,
                "No applications found");
        // The fifth: the routed provider had something of its own to say.
        compare(policy.empty("=2+", testCase.allOn, true,
                             { icon: "loader", text: "Working…" }).text, "Working…");
    }

    function test_a_provider_note_outranks_no_matches_but_not_the_provider_itself() {
        const note = { icon: "loader", text: "Working…" };
        // Switched off and not landed are facts about the provider; a note is
        // the provider talking, and it cannot talk if it is not there.
        const noCalculator = { apps: true, calculator: false, clipboard: true,
                               emoji: true, actions: true, claude: true };
        compare(policy.empty(";", testCase.allOn, true, note).text,
                "Clipboard lands with #53");
        // With the calculator off, `=2+2` is not the calculator at all — it
        // falls through to apps, which is where the note stops applying.
        compare(policy.empty("=2+2", noCalculator, true, null).text, "No matches");
    }

    function test_a_non_apps_provider_is_never_waiting_on_the_apps_scan() {
        // `indexed` is a fact about the desktop-entry model. An emoji query
        // answering "Looking for applications…" would be the launcher blaming
        // a scan the query does not depend on.
        compare(policy.empty(":zzzz", testCase.allOn, false, null).text, "No matches");
    }

    function test_every_silence_brings_an_icon() {
        const cases = [
            policy.empty(";", testCase.allOn, true, null),
            policy.empty("fire", testCase.allOn, false, null),
            policy.empty("fire", testCase.allOn, true, null),
            policy.empty("", testCase.allOn, true, null),
            policy.empty(":zzzz", testCase.allOn, true, null)
        ];
        for (const answer of cases) {
            verify(answer.icon.length > 0);
            verify(answer.text.length > 0);
        }
    }

    // --- the row shape -------------------------------------------------------

    function test_a_desktop_entry_becomes_a_row() {
        const row = policy.appRow(testCase.entries[0]);
        compare(row.provider, "apps");
        compare(row.id, "app:firefox");
        compare(row.title, "Firefox");
        compare(row.subtitle, "Web Browser");
        compare(row.entryId, "firefox");
        compare(row.category, "App");
        // The icon *path* is not here: resolving one is `Quickshell.iconPath`,
        // which is the far side of the line.
        compare(row.iconSource, "");
        compare(row.copy, "");
        compare(row.run, null);
    }

    function test_a_row_with_no_generic_name_falls_back_to_the_comment() {
        compare(policy.appRow({ id: "x", name: "X", comment: "Does a thing" }).subtitle,
                "Does a thing");
        compare(policy.appRow({ id: "x", name: "X" }).subtitle, "");
        compare(policy.appRow(null), null);
    }

    // --- what the log says ---------------------------------------------------
    //
    // tools/launcher-harness.sh greps for exactly these, so the wording is the
    // contract rather than a nicety (#81).

    function test_the_log_wording_is_the_harness_contract() {
        compare(policy.indexed(66), "66 applications indexed");
        compare(policy.indexed(1), "1 application indexed");
        compare(policy.indexed(0), "0 applications indexed");
        compare(policy.launched("firefox", "firefox %u"), "firefox → firefox %u");
        compare(policy.launchedNothing("zzz"), "nothing to launch for \"zzz\"");
        compare(policy.stale("firefox"), "no desktop entry for firefox");
        compare(policy.stale(""), "asked to launch nothing at all");
        compare(policy.remembered("firefox", 3), "remembered firefox (3)");
    }
}
