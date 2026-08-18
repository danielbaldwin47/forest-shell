// The calendar's keymap.
//
// A keymap has exactly three kinds of bug and this file is organised around
// them: a key that does the wrong thing, two bindings that claim the same key
// (`K` and `Ctrl+K`, `?` and `/`), and a binding that fires when the caret is
// in a text field and eats the character someone was typing. Everything else —
// the month step that has to clamp, the selection that has to wrap — is
// arithmetic, and arithmetic is checked at its boundaries.
//
// Keys are given both ways on purpose: as `Qt.Key_*` codes, which is what the
// surface will actually hand over, and as strings, which is what makes the rest
// of the file readable.
import QtQuick
import QtTest
import "../Surfaces/Calendar"

TestCase {
    id: testCase

    name: "KeyNavPolicy"

    KeyNavPolicy { id: keys }

    readonly property string anchor: "2026-08-18"

    function ctxOf(extra) {
        const base = {
            "view": "week",
            "anchorIso": testCase.anchor,
            "nowIso": "2026-08-18T13:37",
            "selectedId": "evt-2",
            "visibleEventIds": ["evt-1", "evt-2", "evt-3"],
            "overlayOpen": false,
            "typing": false
        };
        for (const k in extra)
            base[k] = extra[k];
        return base;
    }

    // --- key naming -----------------------------------------------------------

    function test_a_qt_key_code_and_its_name_are_the_same_key() {
        compare(keys.keyName(Qt.Key_D), "D");
        compare(keys.keyName(Qt.Key_Left), "Left");
        compare(keys.keyName(Qt.Key_Backspace), "Backspace");
        compare(keys.keyName(Qt.Key_Escape), "Escape");
        compare(keys.keyName(Qt.Key_Question), "Question");
        compare(keys.keyName("d"), "D");
        compare(keys.keyName("left"), "Left");
        compare(keys.keyName("esc"), "Escape");
        compare(keys.keyName("?"), "Question");
        compare(keys.keyName("/"), "Slash");
    }

    function test_the_keypad_enter_is_the_same_verb_as_return() {
        compare(keys.keyName(Qt.Key_Enter), "Return");
        compare(keys.keyName(Qt.Key_Return), "Return");
    }

    function test_a_key_the_calendar_does_not_bind_has_no_name() {
        compare(keys.keyName(Qt.Key_F7), "");
        compare(keys.keyName("hyperspace"), "");
        compare(keys.keyName(""), "");
        compare(keys.keyName(null), "");
        compare(keys.action(Qt.Key_F7, Qt.NoModifier, testCase.ctxOf({})), null);
    }

    function test_modifiers_are_a_mask_however_they_are_spelled() {
        compare(keys.modMask(Qt.ControlModifier), Qt.ControlModifier);
        compare(keys.modMask("ctrl"), Qt.ControlModifier);
        compare(keys.modMask("ctrl+shift"), Qt.ControlModifier | Qt.ShiftModifier);
        compare(keys.modMask(["Control", "Shift"]), Qt.ControlModifier | Qt.ShiftModifier);
        compare(keys.modMask(undefined), 0);
    }

    function test_the_keypad_bit_is_not_a_modifier_anyone_bound() {
        // Enter on the numeric keypad carries it, and it is still Enter.
        const a = keys.action(Qt.Key_Enter, Qt.KeypadModifier, testCase.ctxOf({}));
        compare(a.kind, "open");
        compare(a.arg, "evt-2");
    }

    // --- views and navigation -------------------------------------------------

    function test_d_w_and_m_pick_the_view() {
        compare(keys.action(Qt.Key_D, Qt.NoModifier, testCase.ctxOf({})).arg, "day");
        compare(keys.action(Qt.Key_W, Qt.NoModifier, testCase.ctxOf({})).arg, "week");
        compare(keys.action(Qt.Key_M, Qt.NoModifier, testCase.ctxOf({})).arg, "month");
        compare(keys.action("D", 0, testCase.ctxOf({})).kind, "view");
    }

    function test_digits_are_not_bound_to_views() {
        // They are what gets typed into a duration field; stealing them is the
        // bug the note in the policy exists to prevent.
        compare(keys.action(Qt.Key_1, Qt.NoModifier, testCase.ctxOf({})), null);
        compare(keys.action(Qt.Key_3, Qt.NoModifier, testCase.ctxOf({})), null);
    }

    function test_t_is_today() {
        const a = keys.action("T", 0, testCase.ctxOf({}));
        compare(a.kind, "today");
        compare(a.arg, null);
    }

    function test_j_and_left_go_back_k_and_right_go_forward() {
        compare(keys.action("J", 0, testCase.ctxOf({})).kind, "period");
        compare(keys.action("J", 0, testCase.ctxOf({})).arg, -1);
        compare(keys.action(Qt.Key_Left, 0, testCase.ctxOf({})).arg, -1);
        compare(keys.action("K", 0, testCase.ctxOf({})).arg, 1);
        compare(keys.action(Qt.Key_Right, 0, testCase.ctxOf({})).arg, 1);
    }

    // --- selection ------------------------------------------------------------

    function test_up_and_down_walk_the_visible_events() {
        compare(keys.action(Qt.Key_Down, 0, testCase.ctxOf({})).kind, "select");
        compare(keys.action(Qt.Key_Down, 0, testCase.ctxOf({})).arg, "evt-3");
        compare(keys.action(Qt.Key_Up, 0, testCase.ctxOf({})).arg, "evt-1");
    }

    function test_selection_wraps_at_both_ends() {
        compare(keys.nextSelection(["a", "b", "c"], "c", 1), "a");
        compare(keys.nextSelection(["a", "b", "c"], "a", -1), "c");
        compare(keys.nextSelection(["a", "b", "c"], "b", 0), "b");
    }

    function test_a_selection_that_is_no_longer_there_lands_at_an_end() {
        compare(keys.nextSelection(["a", "b"], "gone", 1), "a");
        compare(keys.nextSelection(["a", "b"], "gone", -1), "b");
        compare(keys.nextSelection(["a", "b"], "", 1), "a");
    }

    function test_an_empty_range_selects_nothing_rather_than_something() {
        compare(keys.nextSelection([], "a", 1), "");
        compare(keys.nextSelection(null, "a", 1), "");
        compare(keys.action(Qt.Key_Down, 0, testCase.ctxOf({ "visibleEventIds": [] })), null);
    }

    // --- create ---------------------------------------------------------------

    function test_c_creates_at_the_next_quarter_hour_when_the_anchor_is_today() {
        const a = keys.action("C", 0, testCase.ctxOf({ "nowIso": "2026-08-18T13:37" }));
        compare(a.kind, "create");
        compare(a.arg, "2026-08-18T13:45");
    }

    function test_a_quarter_hour_on_the_nose_does_not_skip_a_slot() {
        compare(keys.createStamp(testCase.ctxOf({ "nowIso": "2026-08-18T13:45" })),
                "2026-08-18T13:45");
    }

    function test_late_at_night_the_slot_stays_on_the_anchor_day() {
        compare(keys.createStamp(testCase.ctxOf({ "nowIso": "2026-08-18T23:52" })),
                "2026-08-18T23:45");
    }

    function test_a_day_that_is_not_today_creates_at_nine() {
        compare(keys.createStamp(testCase.ctxOf({ "anchorIso": "2026-08-21" })),
                "2026-08-21T09:00");
        // No clock at all is the same case: the anchor has no "now" in it.
        compare(keys.createStamp({ "anchorIso": "2026-08-21" }), "2026-08-21T09:00");
    }

    function test_no_anchor_creates_nothing() {
        compare(keys.createStamp({}), "");
        compare(keys.createStamp({ "anchorIso": "2026-02-30" }), "");
        compare(keys.action("C", 0, {}), null);
    }

    // --- open, delete, close --------------------------------------------------

    function test_enter_opens_the_selection_and_only_if_there_is_one() {
        const a = keys.action(Qt.Key_Return, 0, testCase.ctxOf({}));
        compare(a.kind, "open");
        compare(a.arg, "evt-2");
        compare(keys.action(Qt.Key_Return, 0, testCase.ctxOf({ "selectedId": "" })), null);
    }

    function test_backspace_and_delete_both_delete_the_selection() {
        compare(keys.action(Qt.Key_Backspace, 0, testCase.ctxOf({})).kind, "delete");
        compare(keys.action(Qt.Key_Delete, 0, testCase.ctxOf({})).arg, "evt-2");
        compare(keys.action(Qt.Key_Delete, 0, testCase.ctxOf({ "selectedId": "" })), null);
    }

    function test_escape_closes_the_overlay_first_and_the_window_after() {
        compare(keys.action(Qt.Key_Escape, 0, testCase.ctxOf({ "overlayOpen": true })).arg,
                "overlay");
        compare(keys.action(Qt.Key_Escape, 0, testCase.ctxOf({ "overlayOpen": false })).arg,
                "window");
    }

    // --- the three collisions -------------------------------------------------

    function test_ctrl_k_is_the_command_menu_and_bare_k_is_not() {
        compare(keys.action(Qt.Key_K, Qt.ControlModifier, testCase.ctxOf({})).kind, "command");
        compare(keys.action(Qt.Key_K, Qt.NoModifier, testCase.ctxOf({})).kind, "period");
    }

    function test_ctrl_n_creates_the_same_event_c_would() {
        const byCtrl = keys.action(Qt.Key_N, Qt.ControlModifier, testCase.ctxOf({}));
        const byLetter = keys.action(Qt.Key_C, Qt.NoModifier, testCase.ctxOf({}));
        compare(byCtrl.kind, "create");
        compare(byCtrl.arg, byLetter.arg);
        // Bare N is nothing.
        compare(keys.action(Qt.Key_N, Qt.NoModifier, testCase.ctxOf({})), null);
    }

    function test_shift_slash_is_the_shortcuts_sheet_on_either_layout() {
        compare(keys.action(Qt.Key_Question, Qt.ShiftModifier, testCase.ctxOf({})).kind,
                "shortcuts");
        compare(keys.action(Qt.Key_Slash, Qt.ShiftModifier, testCase.ctxOf({})).kind,
                "shortcuts");
        // Bare slash is a character, not a shortcut.
        compare(keys.action(Qt.Key_Slash, Qt.NoModifier, testCase.ctxOf({})), null);
    }

    function test_an_unbound_modifier_means_not_ours() {
        compare(keys.action(Qt.Key_D, Qt.AltModifier, testCase.ctxOf({})), null);
        compare(keys.action(Qt.Key_D, Qt.MetaModifier, testCase.ctxOf({})), null);
        compare(keys.action(Qt.Key_D, Qt.ShiftModifier, testCase.ctxOf({})), null);
        compare(keys.action(Qt.Key_K, Qt.ControlModifier | Qt.ShiftModifier,
                            testCase.ctxOf({})), null);
    }

    // --- the caret owns the keyboard ------------------------------------------

    function test_typing_a_title_does_not_drive_the_calendar() {
        const typing = testCase.ctxOf({ "typing": true });
        compare(keys.action(Qt.Key_D, 0, typing), null);
        compare(keys.action(Qt.Key_C, 0, typing), null);
        compare(keys.action(Qt.Key_Backspace, 0, typing), null);
        compare(keys.action(Qt.Key_Question, Qt.ShiftModifier, typing), null);
        compare(keys.action(Qt.Key_Down, 0, typing), null);
    }

    function test_escape_and_the_ctrl_pair_survive_a_text_field() {
        const typing = testCase.ctxOf({ "typing": true, "overlayOpen": true });
        compare(keys.action(Qt.Key_Escape, 0, typing).arg, "overlay");
        compare(keys.action(Qt.Key_K, Qt.ControlModifier, typing).kind, "command");
    }

    function test_a_missing_context_costs_only_the_bindings_that_need_one() {
        compare(keys.action(Qt.Key_W, 0, undefined).arg, "week");
        compare(keys.action(Qt.Key_Escape, 0, undefined).arg, "window");
        compare(keys.action(Qt.Key_Return, 0, undefined), null);
    }

    // --- shiftPeriod ----------------------------------------------------------

    function test_a_period_is_a_day_a_week_or_a_month() {
        compare(keys.shiftPeriod("day", "2026-08-18", 1), "2026-08-19");
        compare(keys.shiftPeriod("day", "2026-08-18", -1), "2026-08-17");
        compare(keys.shiftPeriod("week", "2026-08-18", 1), "2026-08-25");
        compare(keys.shiftPeriod("week", "2026-08-18", -1), "2026-08-11");
        compare(keys.shiftPeriod("month", "2026-08-18", 1), "2026-09-18");
        compare(keys.shiftPeriod("month", "2026-08-18", -1), "2026-07-18");
    }

    function test_a_month_step_clamps_the_day_rather_than_rolling_over() {
        compare(keys.shiftPeriod("month", "2026-01-31", 1), "2026-02-28");
        compare(keys.shiftPeriod("month", "2024-01-31", 1), "2024-02-29");   // leap
        compare(keys.shiftPeriod("month", "2026-03-31", -1), "2026-02-28");
        compare(keys.shiftPeriod("month", "2026-05-31", 1), "2026-06-30");
    }

    function test_a_period_step_crosses_the_year() {
        compare(keys.shiftPeriod("day", "2026-12-31", 1), "2027-01-01");
        compare(keys.shiftPeriod("week", "2026-01-01", -1), "2025-12-25");
        compare(keys.shiftPeriod("month", "2026-12-15", 1), "2027-01-15");
        compare(keys.shiftPeriod("month", "2026-01-15", -1), "2025-12-15");
        compare(keys.shiftPeriod("month", "2026-05-15", -12), "2025-05-15");
    }

    function test_a_bad_day_or_a_bad_view_shifts_to_nothing() {
        compare(keys.shiftPeriod("day", "2026-02-30", 1), "");
        compare(keys.shiftPeriod("day", "", 1), "");
        compare(keys.shiftPeriod("fortnight", "2026-08-18", 1), "");
    }

    function test_the_period_key_and_the_shift_agree() {
        const ctx = testCase.ctxOf({ "view": "month" });
        const a = keys.action(Qt.Key_Right, 0, ctx);
        compare(keys.shiftPeriod(ctx.view, ctx.anchorIso, a.arg), "2026-09-18");
    }

    // --- the sheet and the menu -----------------------------------------------

    function test_every_shortcut_row_is_complete() {
        const rows = keys.shortcutsTable();
        verify(rows.length >= 10);
        for (const row of rows) {
            verify(!!row.keys);
            verify(!!row.label);
            verify(!!row.group);
        }
    }

    function test_the_sheet_names_every_verb_the_keymap_can_return() {
        const printed = keys.shortcutsTable().map(function (r) { return r.keys; }).join(" ");
        for (const key of ["D", "W", "M", "T", "J", "K", "C", "Enter", "Esc",
                           "?", "Ctrl+K", "Ctrl+N", "Backspace"]) {
            verify(printed.indexOf(key) >= 0, "the sheet never mentions " + key);
        }
    }

    function test_the_sheet_is_a_fresh_array_each_call() {
        // A Repeater handed the same array back does not rebuild its delegates.
        verify(keys.shortcutsTable() !== keys.shortcutsTable());
    }

    function test_the_command_menu_names_the_period_after_the_current_view() {
        const week = keys.commands(testCase.ctxOf({ "view": "week" }));
        const month = keys.commands(testCase.ctxOf({ "view": "month" }));
        compare(week.filter(function (c) { return c.id === "period.next"; })[0].label,
                "Next week");
        compare(month.filter(function (c) { return c.id === "period.previous"; })[0].label,
                "Previous month");
    }

    function test_open_and_delete_appear_only_with_a_selection() {
        const withSel = keys.commands(testCase.ctxOf({ "selectedTitle": "Design sync" }));
        const without = keys.commands(testCase.ctxOf({ "selectedId": "" }));
        const ids = function (list) {
            return list.map(function (c) { return c.id; }).join(" ");
        };
        verify(ids(withSel).indexOf("event.open") >= 0);
        verify(ids(without).indexOf("event.open") < 0);
        verify(ids(without).indexOf("event.delete") < 0);
        // Named, when the name is known.
        compare(withSel.filter(function (c) { return c.id === "event.delete"; })[0].label,
                "Delete “Design sync”");
        const anonymous = keys.commands(testCase.ctxOf({}));
        compare(anonymous.filter(function (c) { return c.id === "event.open"; })[0].label,
                "Open the selected event");
    }

    function test_every_command_carries_an_id_a_label_and_its_shortcut() {
        for (const cmd of keys.commands(testCase.ctxOf({}))) {
            verify(!!cmd.id);
            verify(!!cmd.label);
            verify(!!cmd.shortcut);
        }
    }

    // --- filtering ------------------------------------------------------------

    function test_a_prefix_outranks_a_word_and_a_word_outranks_a_fuzzy_match() {
        compare(keys.rank("Day view", "da"), 3);
        compare(keys.rank("Day view", "vi"), 2);
        compare(keys.rank("Day view", "dv"), 1);
        compare(keys.rank("Day view", "zq"), 0);
        compare(keys.rank("Day view", "DA"), 3);   // case-folded
    }

    function test_filtering_puts_the_best_match_first() {
        const hits = keys.filter(keys.commands(testCase.ctxOf({})), "mo");
        compare(hits[0].id, "view.month");
    }

    function test_a_fuzzy_query_still_finds_the_command() {
        const hits = keys.filter(keys.commands(testCase.ctxOf({})), "jtd");
        compare(hits[0].id, "today");            // "Jump to today"
    }

    function test_an_id_only_match_ranks_below_every_label_match() {
        const hits = keys.filter(keys.commands(testCase.ctxOf({})), "view");
        // The three views match by label; "view.*" ids alone must not jump them.
        compare(hits[0].id, "view.day");
        compare(hits[1].id, "view.week");
        compare(hits[2].id, "view.month");
    }

    function test_an_empty_query_keeps_the_menu_in_its_own_order() {
        const all = keys.commands(testCase.ctxOf({}));
        const hits = keys.filter(all, "   ");
        compare(hits.length, all.length);
        compare(hits[0].id, all[0].id);
        compare(hits[hits.length - 1].id, all[all.length - 1].id);
    }

    function test_a_query_that_matches_nothing_filters_to_nothing() {
        compare(keys.filter(keys.commands(testCase.ctxOf({})), "zzqx").length, 0);
        compare(keys.filter(null, "day").length, 0);
    }

    // --- probes ---------------------------------------------------------------
    //
    // Written against the finished policy rather than alongside it, aimed at the
    // cases its author had no reason to think of: the shapes QML hands over that
    // JavaScript does not, both ends of a day, the inverse of every step, and the
    // claim that the sheet, the menu and the keymap are one source.

    /// A QML sequence is not a JS `Array`, and the surface will hand
    /// `visibleEventIds` over as exactly this — so it is checked as exactly this.
    readonly property list<string> sequenceIds: ["evt-1", "evt-2", "evt-3"]

    function test_probe_a_qml_sequence_walks_like_an_array() {
        compare(keys.nextSelection(testCase.sequenceIds, "evt-2", 1), "evt-3");
        compare(keys.nextSelection(testCase.sequenceIds, "evt-3", 1), "evt-1");
        const a = keys.action(Qt.Key_Down, 0,
                              testCase.ctxOf({ "visibleEventIds": testCase.sequenceIds }));
        compare(a.kind, "select");
        compare(a.arg, "evt-3");
    }

    function test_probe_modifiers_spelled_as_words_reach_the_same_binding() {
        // The calling convention promises a string or an array works wherever a
        // mask does; nothing above ever pushed one through `action` itself.
        compare(keys.action("K", "ctrl", testCase.ctxOf({})).kind, "command");
        compare(keys.action("k", ["Control"], testCase.ctxOf({})).kind, "command");
        compare(keys.action("N", "ctrl", testCase.ctxOf({})).kind, "create");
        compare(keys.action("D", "alt", testCase.ctxOf({})), null);
        compare(keys.action("D", "ctrl+shift", testCase.ctxOf({})), null);
    }

    function test_probe_every_modifier_alias_lands_on_its_bit() {
        compare(keys.modMask("super"), Qt.MetaModifier);
        compare(keys.modMask("cmd"), Qt.MetaModifier);
        compare(keys.modMask("option"), Qt.AltModifier);
        compare(keys.modMask("Control Shift"), Qt.ControlModifier | Qt.ShiftModifier);
        compare(keys.modMask("nonsense"), 0);
        // The two bits that ride along with ordinary presses are stripped.
        compare(keys.modMask(Qt.KeypadModifier | Qt.GroupSwitchModifier), 0);
        compare(keys.modMask(Qt.ControlModifier | Qt.GroupSwitchModifier), Qt.ControlModifier);
    }

    function test_probe_create_at_both_ends_of_the_day() {
        compare(keys.createStamp(testCase.ctxOf({ "nowIso": "2026-08-18T00:00" })),
                "2026-08-18T00:00");
        compare(keys.createStamp(testCase.ctxOf({ "nowIso": "2026-08-18T00:01" })),
                "2026-08-18T00:15");
        compare(keys.createStamp(testCase.ctxOf({ "nowIso": "2026-08-18T23:46" })),
                "2026-08-18T23:45");
        compare(keys.createStamp(testCase.ctxOf({ "nowIso": "2026-08-18T23:59" })),
                "2026-08-18T23:45");
        // A clock on a different day than the anchor is no clock at all,
        compare(keys.createStamp(testCase.ctxOf({ "nowIso": "2026-08-17T13:37" })),
                "2026-08-18T09:00");
        // and neither is a day string where a stamp belongs.
        compare(keys.createStamp(testCase.ctxOf({ "nowIso": "2026-08-18" })),
                "2026-08-18T09:00");
    }

    function test_probe_a_month_step_and_its_inverse_come_home() {
        // Nothing moves on a zero step, including the day the clamp watches.
        compare(keys.shiftPeriod("day", "2026-08-31", 0), "2026-08-31");
        compare(keys.shiftPeriod("week", "2026-08-31", 0), "2026-08-31");
        compare(keys.shiftPeriod("month", "2026-08-31", 0), "2026-08-31");
        // A year out and back, every step, from a day that survives the clamp.
        for (let i = -14; i <= 14; i++) {
            const out = keys.shiftPeriod("month", "2026-08-15", i);
            compare(keys.shiftPeriod("month", out, -i), "2026-08-15",
                    "month step " + i + " via " + out);
        }
        // The clamp is one-way on purpose: a leap day has nowhere else to land.
        compare(keys.shiftPeriod("month", "2024-02-29", 12), "2025-02-28");
        compare(keys.shiftPeriod("month", "2024-02-29", -12), "2023-02-28");
        compare(keys.shiftPeriod("month", "2026-08-31", -18), "2025-02-28");
    }

    function test_probe_escape_under_the_window_managers_modifiers() {
        const ctx = testCase.ctxOf({ "overlayOpen": true });
        // Alt+Esc and Super+Esc belong to the compositor, not to the calendar.
        compare(keys.action(Qt.Key_Escape, Qt.AltModifier, ctx), null);
        compare(keys.action(Qt.Key_Escape, Qt.MetaModifier, ctx), null);
        // Ctrl+Esc is not a binding either: the Ctrl branch owns exactly two keys.
        compare(keys.action(Qt.Key_Escape, Qt.ControlModifier, ctx), null);
        // Shift+Esc is still Esc — a shifted dismissal is a dismissal.
        compare(keys.action(Qt.Key_Escape, Qt.ShiftModifier, ctx).arg, "overlay");
    }

    function test_probe_every_command_shortcut_runs_its_own_command() {
        // The file's claim is that the sheet, the menu and the keymap are one
        // source. Feeding each menu entry's printed shortcut back through the
        // keymap is the only way to check that rather than assume it.
        const ctx = testCase.ctxOf({});
        const expected = {
            "view.day": "view", "view.week": "view", "view.month": "view",
            "today": "today", "period.previous": "period", "period.next": "period",
            "event.create": "create", "event.open": "open",
            "event.delete": "delete", "help.shortcuts": "shortcuts"
        };
        const cmds = keys.commands(ctx);
        compare(cmds.length, 10);
        for (const cmd of cmds) {
            const a = keys.action(cmd.shortcut, 0, ctx);
            verify(a !== null, cmd.id + " prints " + cmd.shortcut + ", which does nothing");
            compare(a.kind, expected[cmd.id], cmd.id + " via " + cmd.shortcut);
        }
    }

    function test_probe_a_punctuation_query_neither_matches_nor_throws() {
        const cmds = keys.commands(testCase.ctxOf({ "selectedTitle": "Design sync" }));
        compare(keys.rank("Day view", "("), 0);
        compare(keys.rank("Day view", ".*"), 0);
        compare(keys.filter(cmds, "((").length, 0);
        // A title in curly quotes is still a word the menu can be searched by.
        compare(keys.rank("Delete “Design sync”", "design"), 2);
        const hits = keys.filter(cmds, "design");
        compare(hits.length, 2);
        compare(hits[0].id, "event.open");
    }

    function test_probe_a_key_of_the_wrong_type_is_simply_not_ours() {
        compare(keys.keyName(undefined), "");
        compare(keys.keyName({}), "");
        compare(keys.keyName(["D"]), "");
        compare(keys.keyName("  d  "), "D");
        compare(keys.keyName("ESC"), "Escape");
        compare(keys.action(undefined, 0, testCase.ctxOf({})), null);
    }

    function test_probe_the_keys_a_calendar_must_not_steal() {
        // Tab has to reach the focus chain and Space has to reach the button
        // under it; neither is a binding, and a later row in the table that
        // claims one would break the window without breaking a picture.
        for (const key of [Qt.Key_Tab, Qt.Key_Backtab, Qt.Key_Space, Qt.Key_Home,
                           Qt.Key_End, Qt.Key_PageUp, Qt.Key_PageDown, Qt.Key_F1])
            compare(keys.action(key, 0, testCase.ctxOf({})), null,
                    "key " + key + " is bound and should not be");
    }

    function test_probe_a_question_mark_that_needs_no_shift() {
        // Shift+/ is the US answer. On layouts where `?` is unshifted the key
        // arrives as Key_Question with no modifier at all, and bare `/` is still
        // a character either way.
        compare(keys.action(Qt.Key_Question, 0, testCase.ctxOf({})).kind, "shortcuts");
        compare(keys.action("?", 0, testCase.ctxOf({})).kind, "shortcuts");
        compare(keys.action("/", 0, testCase.ctxOf({})), null);
    }

    function test_probe_a_single_event_range_reselects_itself() {
        compare(keys.nextSelection(["only"], "only", 1), "only");
        compare(keys.nextSelection(["only"], "only", -1), "only");
        const ctx = testCase.ctxOf({ "visibleEventIds": ["only"], "selectedId": "only" });
        compare(keys.action(Qt.Key_Down, 0, ctx).arg, "only");
    }

    function test_probe_the_arguments_a_caller_leaves_off() {
        // "or nothing at all for none" is in the calling convention; a view that
        // has no modifiers to report should not have to invent a zero.
        compare(keys.action("W").arg, "week");
        compare(keys.action("W", undefined).arg, "week");
        compare(keys.modMask(), 0);
        compare(keys.createStamp(), "");
        compare(keys.selectAction(undefined, 1), null);
    }
}
