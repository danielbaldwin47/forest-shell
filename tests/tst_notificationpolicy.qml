// Every decision the notification service makes about one arriving
// notification (#42): which per-app rule applies, whether it pops, whether it
// is remembered, and for how long it stays up.
//
// Services/Notifications/Notifications.qml itself imports Quickshell and so
// cannot be loaded here; what it adds over this file is the server wiring, the
// popup list and the state write, which the shell verifies by running (see the
// ticket's acceptance criteria).
import QtQuick
import QtTest
import "../Services/Notifications"

TestCase {
    name: "NotificationPolicy"

    NotificationPolicy { id: policy }

    // The authored defaults, as the schema declares them. Written out rather
    // than read from SettingsSchema so a test failure says which side moved.
    readonly property var settings: ({
        timeouts: { low: 5000, normal: 8000, critical: 0 },
        honorClientTimeout: false,
        historyLimit: 100,
        maxVisible: 3,
        apps: ({})
    })

    function context(overrides) {
        const base = {
            rule: "normal",
            urgency: policy.urgencyNormal,
            transient: false,
            dnd: false,
            fullscreen: false,
            centerOpen: false
        };
        for (const key in overrides)
            base[key] = overrides[key];
        return base;
    }

    // --- urgency -------------------------------------------------------------

    function test_urgency_names_mirror_the_freedesktop_levels() {
        // The numbers are the wire protocol's, not ours: 0/1/2 is what a client
        // puts on the bus and what NotificationUrgency exposes.
        compare(policy.urgencyLow, 0);
        compare(policy.urgencyNormal, 1);
        compare(policy.urgencyCritical, 2);
        compare(policy.urgencyName(0), "low");
        compare(policy.urgencyName(1), "normal");
        compare(policy.urgencyName(2), "critical");
    }

    function test_an_unknown_urgency_reads_as_normal() {
        // A client may send anything; an unrecognised level must not decide
        // that a notification is critical, and must not fall off the table.
        for (const value of [3, -1, undefined, null, "critical"])
            compare(policy.urgencyName(value), "normal");
    }

    // --- app identity --------------------------------------------------------

    function test_the_app_key_prefers_the_desktop_entry() {
        // `appName` is the localized display string a client passes; the
        // desktop entry is the stable id. A rule set on one machine's locale
        // has to keep matching on another's.
        compare(policy.appKey("org.telegram.desktop", "Telegram"), "org.telegram.desktop");
        compare(policy.appKey("", "Telegram"), "telegram");
        compare(policy.appKey(undefined, "  Spotify  "), "spotify");
    }

    function test_an_app_with_no_identity_at_all_has_no_key() {
        // notify-send with an empty app name is legal. Such a notification is
        // simply not rule-able, which is different from being blocked.
        compare(policy.appKey("", ""), "");
        compare(policy.appKey(null, undefined), "");
    }

    function test_the_key_is_case_folded_once_so_lookups_need_no_casing() {
        compare(policy.appKey("Org.Gnome.Nautilus", "Files"), "org.gnome.nautilus");
    }

    // --- per-app rules -------------------------------------------------------

    function test_an_app_with_no_rule_is_normal() {
        compare(policy.ruleFor({}, "telegram"), "normal");
        compare(policy.ruleFor(undefined, "telegram"), "normal");
        compare(policy.ruleFor({ telegram: "blocked" }, ""), "normal");
    }

    function test_the_three_rules_are_the_whole_vocabulary() {
        compare(policy.rules, ["normal", "silent", "blocked"]);
        for (const rule of policy.rules)
            compare(policy.ruleFor({ telegram: rule }, "telegram"), rule);
    }

    function test_a_hand_edited_rule_that_is_not_a_rule_falls_back_to_normal() {
        // `notifications.apps` is a free-form object in settings.json — it
        // arrives unvalidated, and the safe reading of nonsense is "notify",
        // never "silence this app".
        ignoreWarning(/not a notification rule/);
        compare(policy.ruleFor({ telegram: "mute" }, "telegram"), "normal");
        ignoreWarning(/not a notification rule/);
        compare(policy.ruleFor({ telegram: true }, "telegram"), "normal");
    }

    function test_a_rule_written_with_different_casing_still_matches() {
        // The key is what a user hand-types into settings.json, so it is
        // matched the same way it is built.
        compare(policy.ruleFor({ "Telegram": "silent" }, "telegram"), "silent");
        compare(policy.ruleFor({ "telegram": "SILENT" }, "telegram"), "silent");
    }

    // --- timeouts ------------------------------------------------------------

    function test_each_urgency_gets_its_authored_timeout() {
        compare(policy.timeoutMs(policy.urgencyLow, -1, settings), 5000);
        compare(policy.timeoutMs(policy.urgencyNormal, -1, settings), 8000);
        // Critical is 0 — it stays until it is acknowledged.
        compare(policy.timeoutMs(policy.urgencyCritical, -1, settings), 0);
    }

    function test_the_clients_own_timeout_is_ignored_by_default() {
        // Almost every client passes a hardcoded 5000 it never thought about,
        // which would make the urgency table dead settings.
        compare(policy.timeoutMs(policy.urgencyNormal, 5000, settings), 8000);
        compare(policy.timeoutMs(policy.urgencyLow, 30000, settings), 5000);
    }

    function test_the_clients_timeout_wins_when_the_user_asks_for_it() {
        const honoring = Object.assign({}, settings, { honorClientTimeout: true });
        // `Notification.expireTimeout` is **milliseconds**, measured on a live
        // session (#74) — the capability survey said seconds and was wrong, and
        // the 1000× it cost is why these cases are written out in the client's
        // own units.
        compare(policy.timeoutMs(policy.urgencyNormal, 5000, honoring), 5000);
        compare(policy.timeoutMs(policy.urgencyNormal, 2500, honoring), 2500);
        // The freedesktop "never expire" sentinel — not "expire now".
        compare(policy.timeoutMs(policy.urgencyNormal, 0, honoring), 0);
        // -1 is "server decides", which is the authored default.
        compare(policy.timeoutMs(policy.urgencyNormal, -1, honoring), 8000);
    }

    function test_the_honored_timeout_is_read_as_milliseconds_not_seconds() {
        // The regression #74 found: `notify-send -t 4000` asks for four
        // seconds, and under the seconds reading became 4 000 000 ms, clamped
        // to the five-minute ceiling. `-t 3` is the decisive case — three
        // milliseconds is below the floor, where the seconds reading would have
        // given a live 3 s popup.
        const honoring = Object.assign({}, settings, { honorClientTimeout: true });
        compare(policy.timeoutMs(policy.urgencyNormal, 4000, honoring), 4000);
        compare(policy.timeoutMs(policy.urgencyNormal, 3, honoring), policy.minTimeoutMs);
    }

    function test_an_honored_client_timeout_is_still_bounded() {
        // A client asking for an hour on screen does not get one.
        const honoring = Object.assign({}, settings, { honorClientTimeout: true });
        compare(policy.timeoutMs(policy.urgencyNormal, 3600000, honoring), policy.maxTimeoutMs);
        // Nor does one asking for a frame.
        compare(policy.timeoutMs(policy.urgencyNormal, 50, honoring), policy.minTimeoutMs);
    }

    function test_a_missing_settings_object_still_yields_a_timeout() {
        // The service reads these through Config, which always resolves every
        // leaf — but a timeout of `undefined` is a Timer that never fires, so
        // this is the one place worth belt-and-braces.
        verify(policy.timeoutMs(policy.urgencyNormal, -1, undefined) > 0);
        verify(policy.timeoutMs(policy.urgencyNormal, -1, {}) > 0);
    }

    // --- the delivery decision -----------------------------------------------

    function test_a_normal_notification_pops_and_is_remembered() {
        const decision = policy.decide(context({}));
        compare(decision.popup, true);
        compare(decision.history, true);
        compare(decision.reason, "");
    }

    function test_a_blocked_app_gets_nothing_at_all() {
        // Blocked is the only outcome that leaves no trace: not a popup, not a
        // history row (#43 — "blocked app → nothing").
        const decision = policy.decide(context({ rule: "blocked" }));
        compare(decision.popup, false);
        compare(decision.history, false);
        compare(decision.reason, "blocked");
    }

    function test_a_blocked_app_is_blocked_even_when_critical() {
        // The user said no. Urgency is the sender's opinion of itself.
        const decision = policy.decide(context({ rule: "blocked", urgency: policy.urgencyCritical }));
        compare(decision.popup, false);
        compare(decision.history, false);
    }

    function test_a_silent_app_is_history_only() {
        const decision = policy.decide(context({ rule: "silent" }));
        compare(decision.popup, false);
        compare(decision.history, true);
        compare(decision.reason, "silent");
    }

    function test_dnd_suppresses_the_popup_and_keeps_the_history() {
        const decision = policy.decide(context({ dnd: true }));
        compare(decision.popup, false);
        compare(decision.history, true);
        compare(decision.reason, "dnd");
    }

    function test_critical_breaks_through_dnd() {
        const decision = policy.decide(context({ dnd: true, urgency: policy.urgencyCritical }));
        compare(decision.popup, true);
        compare(decision.reason, "");
    }

    function test_a_fullscreen_focus_suppresses_the_popup() {
        const decision = policy.decide(context({ fullscreen: true }));
        compare(decision.popup, false);
        compare(decision.history, true);
        compare(decision.reason, "fullscreen");
    }

    function test_an_open_notification_center_suppresses_the_popup() {
        // The notification is already on screen, in the center (#43). A toast
        // over the top of it would be the same thing twice.
        const decision = policy.decide(context({ centerOpen: true }));
        compare(decision.popup, false);
        compare(decision.history, true);
        compare(decision.reason, "center");
    }

    function test_critical_does_not_break_through_fullscreen_or_the_center() {
        // #9 grants critical exactly one exemption, and names it: DND. A
        // fullscreen game and an open center are both cases where the user is
        // looking at something the shell would be covering.
        compare(policy.decide(context({ fullscreen: true, urgency: policy.urgencyCritical })).popup, false);
        compare(policy.decide(context({ centerOpen: true, urgency: policy.urgencyCritical })).popup, false);
    }

    function test_a_transient_notification_pops_without_being_remembered() {
        // The freedesktop `transient` hint is how a client says "this is a
        // progress blip, not news" — honouring it is what keeps history from
        // filling with volume steps.
        const decision = policy.decide(context({ transient: true }));
        compare(decision.popup, true);
        compare(decision.history, false);
    }

    function test_a_silenced_transient_notification_is_simply_dropped() {
        const decision = policy.decide(context({ rule: "silent", transient: true }));
        compare(decision.popup, false);
        compare(decision.history, false);
    }

    function test_the_situational_reasons_are_asked_for_on_their_own() {
        // The service reports this one live, for the bar indicator to explain
        // itself with — so it has to answer without a notification in hand.
        compare(policy.suppressionOf(context({})), "");
        compare(policy.suppressionOf(context({ dnd: true })), "dnd");
        compare(policy.suppressionOf(context({ fullscreen: true })), "fullscreen");
        compare(policy.suppressionOf(context({ centerOpen: true })), "center");
        // Critical's one exemption holds here too, since this is the cascade
        // `decide` runs.
        compare(policy.suppressionOf(context({ dnd: true, urgency: policy.urgencyCritical })), "");
    }

    function test_dnd_is_reported_ahead_of_the_others() {
        // One reason is reported, and it is the first that applies: the log
        // line and the indicator both want "the reason", not a list.
        compare(policy.suppressionOf(context({ dnd: true, fullscreen: true, centerOpen: true })),
                "dnd");
        compare(policy.suppressionOf(context({ fullscreen: true, centerOpen: true })), "fullscreen");
    }

    // --- history records -----------------------------------------------------

    function test_a_record_carries_what_the_center_has_to_render() {
        const record = policy.record({
            serverId: 7,
            seq: 3,
            time: 1000,
            appKey: "telegram",
            appName: "Telegram",
            appIcon: "telegram",
            image: "/tmp/avatar.png",
            summary: "Ada",
            body: "on my way",
            urgency: policy.urgencyNormal
        });
        compare(record.serverId, 7);
        compare(record.seq, 3);
        compare(record.time, 1000);
        compare(record.appKey, "telegram");
        compare(record.appName, "Telegram");
        compare(record.summary, "Ada");
        compare(record.body, "on my way");
        compare(record.urgency, "normal");
        compare(record.image, "/tmp/avatar.png");
    }

    function test_a_record_stores_the_urgency_by_name() {
        // The record outlives the build that wrote it. A name survives an
        // enum renumbering; a 2 does not.
        compare(policy.record({ urgency: policy.urgencyCritical }).urgency, "critical");
        compare(policy.record({}).urgency, "normal");
    }

    function test_a_record_never_keeps_a_pixmap_url() {
        // Inline image data lives in Quickshell's image provider, keyed by a
        // notification that will not exist after a restart. Persisting that URL
        // would give the center a permanently broken image; a file path is
        // still on disk tomorrow.
        compare(policy.record({ image: "image://qsimage/notification/7" }).image, "");
        compare(policy.record({ image: "file:///tmp/a.png" }).image, "file:///tmp/a.png");
        compare(policy.record({ image: "/tmp/a.png" }).image, "/tmp/a.png");
    }

    // --- row identity (#76) ---------------------------------------------------

    function test_two_notifications_with_the_same_daemon_id_get_different_keys() {
        // The daemon's id counter restarts at 1 with every server, and history
        // does not — so a shell restart used to put two different rows in the
        // list under the same id (#76). The row key may not be borrowed from
        // the daemon.
        const before = policy.record({ serverId: 1, seq: 12, time: 1000, summary: "old" });
        const after = policy.record({ serverId: 1, seq: 13, time: 2000, summary: "new" });
        verify(before.key !== after.key, "keys collided: " + before.key);
        // The daemon id is still there, under a name that says whose it is.
        compare(before.serverId, 1);
        compare(after.serverId, 1);
    }

    function test_a_key_is_unique_even_within_one_millisecond() {
        // A burst arrives faster than the clock ticks, so the timestamp alone
        // is not an identity.
        const a = policy.record({ seq: 1, time: 1000, appKey: "telegram" });
        const b = policy.record({ seq: 2, time: 1000, appKey: "telegram" });
        verify(a.key !== b.key, "keys collided: " + a.key);
    }

    function test_a_key_is_the_same_value_every_time_it_is_derived() {
        // The center keys its delegates on this. A key that changed on reload
        // would rebuild every row.
        const fields = { serverId: 4, seq: 9, time: 1234, appKey: "telegram" };
        compare(policy.record(fields).key, policy.record(fields).key);
        verify(policy.record(fields).key.length > 0);
    }

    function test_the_next_sequence_number_clears_the_history_in_hand() {
        compare(policy.nextSeq([], 0), 1);
        compare(policy.nextSeq(undefined, undefined), 1);
        compare(policy.nextSeq([policy.record({ seq: 12 }), policy.record({ seq: 11 })], 0), 13);
    }

    function test_the_next_sequence_number_clears_the_persisted_counter_too() {
        // The list on its own is not a high-water mark: the center dismisses
        // single rows (#43) and a lowered historyLimit truncates it, so the
        // highest number issued can leave the list entirely (#76).
        compare(policy.nextSeq([], 40), 41);
        compare(policy.nextSeq([policy.record({ seq: 2 })], 40), 41);
        // And the counter is not enough on its own either — state.json is read
        // lazily, so a row can be remembered before the floor has arrived.
        compare(policy.nextSeq([policy.record({ seq: 99 })], 40), 100);
    }

    function test_a_row_with_no_sequence_number_does_not_hold_the_counter_back() {
        // Hand-edited, or written by a build that predates the key (#76).
        compare(policy.nextSeq([{ time: 1 }, policy.record({ seq: 4 })], 0), 5);
        compare(policy.nextSeq(["nonsense", null], 0), 1);
    }

    function test_a_run_of_arrivals_never_repeats_a_key() {
        // The service's own loop: ask for the next seq, build, remember. The
        // limit is well under the run, so the list keeps losing the numbers it
        // was asked for — which is the case the persisted counter is for.
        let history = [];
        let counter = 0;
        const keys = {};
        for (let i = 0; i < 20; i++) {
            counter = policy.nextSeq(history, counter);
            const entry = policy.record({
                serverId: (i % 5) + 1,   // the daemon's counter, restarting
                seq: counter,
                time: 1000,              // one millisecond, worst case
                appKey: "telegram"
            });
            verify(keys[entry.key] === undefined, "repeated key " + entry.key);
            keys[entry.key] = true;
            history = policy.remember(history, entry, 5);
        }
    }

    function test_dismissing_the_newest_row_does_not_reissue_its_number() {
        // What #43's center does, and what the list alone cannot survive: the
        // row holding the highest number is removed, and the next arrival must
        // still not land on a number that has been used.
        let counter = policy.nextSeq([], 0);
        const first = policy.record({ seq: counter, time: 1000, appKey: "telegram" });
        let history = policy.remember([], first, 100);

        history = history.filter(row => row.key !== first.key);   // dismissed
        counter = policy.nextSeq(history, counter);
        const second = policy.record({ seq: counter, time: 1000, appKey: "telegram" });

        verify(second.key !== first.key, "reissued " + first.key + " after a dismissal");
    }

    function test_records_are_strings_whatever_the_client_sent() {
        const record = policy.record({ summary: undefined, body: null, appName: 12 });
        compare(record.summary, "");
        compare(record.body, "");
        compare(record.appName, "12");
    }

    // --- the history list ----------------------------------------------------

    function test_history_is_newest_first_and_bounded() {
        let history = [];
        for (let i = 0; i < 5; i++)
            history = policy.remember(history, policy.record({ serverId: i, seq: i, summary: "n" + i }), 3);
        compare(history.length, 3);
        compare(history[0].summary, "n4");
        compare(history[2].summary, "n2");
    }

    function test_a_zero_limit_keeps_no_history() {
        // The user's way of saying "do not write my notifications to disk".
        const history = policy.remember([], policy.record({ summary: "n" }), 0);
        compare(history.length, 0);
    }

    function test_remembering_does_not_mutate_the_list_it_was_given() {
        // The service hands its live array in and binds to the result; an
        // in-place push would change the value under a binding that never
        // re-evaluates.
        const before = [policy.record({ summary: "old" })];
        const after = policy.remember(before, policy.record({ summary: "new" }), 10);
        compare(before.length, 1);
        compare(after.length, 2);
    }

    // --- reading the state file back -----------------------------------------

    function test_a_hand_wrecked_history_file_costs_only_the_bad_rows() {
        // state.json is disposable and hand-editable (#21). Anything that is
        // not a record is dropped; the rest of the list still loads.
        const loaded = policy.readHistory([
            policy.record({ summary: "good" }),
            "not a record",
            null,
            { summary: "no timestamp" },
            42
        ], 100);
        compare(loaded.length, 1);
        compare(loaded[0].summary, "good");
    }

    function test_reading_a_history_that_is_not_a_list_yields_no_history() {
        compare(policy.readHistory(undefined, 100).length, 0);
        compare(policy.readHistory({ }, 100).length, 0);
        compare(policy.readHistory("[]", 100).length, 0);
    }

    function test_reading_applies_the_current_limit() {
        // The limit may have been lowered since the file was written.
        const history = [];
        for (let i = 0; i < 10; i++)
            history.push(policy.record({ serverId: i, seq: i, summary: "n" + i }));
        compare(policy.readHistory(history, 4).length, 4);
        compare(policy.readHistory(history, 4)[0].summary, "n0");
    }

    function test_a_loaded_record_is_normalized_the_same_way_a_new_one_is() {
        // A record written by an older build may be missing fields the center
        // binds to; `undefined` in a Text is a warning per frame.
        const loaded = policy.readHistory([{ time: 5, summary: "s" }], 10);
        compare(loaded[0].body, "");
        compare(loaded[0].appName, "");
        compare(loaded[0].urgency, "normal");
    }

    function test_a_row_keeps_its_key_across_a_read_back() {
        // The key is what the center's delegates are keyed on, so it has to be
        // the same value before the write and after the read (#76).
        const written = policy.record({ serverId: 1, seq: 7, time: 1000, appKey: "telegram" });
        const loaded = policy.readHistory([written], 10);
        compare(loaded[0].key, written.key);
        compare(loaded[0].seq, 7);
        compare(loaded[0].serverId, 1);
    }

    function test_a_hand_added_row_is_given_a_key_nothing_else_holds() {
        // state.json is hand-editable (#21), so a row can arrive with no
        // sequence number at all — including into a file whose other rows have
        // one. The numbers issued here have to clear those (#76).
        const loaded = policy.readHistory([
            { time: 3000, appKey: "harness", summary: "hand-added" },
            policy.record({ seq: 5, time: 2000, appKey: "telegram", summary: "written" }),
            { time: 1000, appKey: "harness", summary: "also hand-added" }
        ], 100);

        compare(loaded.length, 3);
        const seen = {};
        for (const row of loaded) {
            verify(row.seq > 0, "row kept a zero sequence number");
            verify(seen[row.key] === undefined, "duplicate key " + row.key);
            seen[row.key] = true;
        }
        // Newest first, so the head still holds the highest number.
        verify(loaded[0].seq > loaded[2].seq);
    }

    function test_a_loaded_history_has_no_duplicate_keys_across_a_restart() {
        // The shape #76 measured: twelve rows, a restart, one more — the daemon
        // id counter starts again at 1, the history does not.
        let history = [];
        let counter = 0;
        for (let i = 0; i < 12; i++) {
            counter = policy.nextSeq(history, counter);
            history = policy.remember(history, policy.record({
                serverId: i + 1, seq: counter, time: 1000 + i, appKey: "telegram"
            }), 100);
        }

        // The restart: the file is read back, the counter comes back with it,
        // and the next notification is from a server whose ids start at 1.
        const restored = policy.readHistory(history, 100);
        const after = policy.remember(restored, policy.record({
            serverId: 1, seq: policy.nextSeq(restored, counter), time: 2000, appKey: "telegram"
        }), 100);

        compare(after.length, 13);
        const seen = {};
        for (const row of after) {
            verify(seen[row.key] === undefined, "duplicate key " + row.key);
            seen[row.key] = true;
        }
    }

    // --- what history says (#71) ---------------------------------------------

    function rows(specs) {
        return specs.map(spec => policy.record(spec));
    }

    function test_the_apps_history_has_seen_are_listed_once_each_and_sorted() {
        // The settings tab's list of "every app that has ever notified" (#54).
        // Sorted, so a row does not move because an app notified again; unique,
        // because the tab draws one row per app and not one per notification.
        const history = rows([
            { time: 3000, appKey: "telegram" },
            { time: 2000, appKey: "firefox" },
            { time: 1000, appKey: "telegram" }
        ]);
        compare(policy.knownApps(history), ["firefox", "telegram"]);
    }

    function test_an_app_with_no_key_is_not_listed() {
        // A client that supplies neither a desktop entry nor an app name cannot
        // be ruled on (see `appKey`), so a row for it would be a row whose
        // three-way control writes nothing.
        const history = rows([{ time: 1000, appKey: "" }, { time: 2000, appKey: "firefox" }]);
        compare(policy.knownApps(history), ["firefox"]);
    }

    function test_a_wrecked_history_yields_no_apps() {
        compare(policy.knownApps(undefined), []);
        compare(policy.knownApps("nonsense"), []);
        compare(policy.knownApps([null, 7, {}]), []);
    }

    function test_the_lock_counts_what_arrived_since_it_went_up() {
        // The lock's count is over history rather than over a tally of its own,
        // so it is right after a hot reload and right for a notification that
        // arrived in the same millisecond the lock did.
        const history = rows([
            { time: 5000, appKey: "telegram" },
            { time: 4000, appKey: "firefox" },
            { time: 1000, appKey: "firefox" }
        ]);
        compare(policy.countSince(history, 4000), 2);
        compare(policy.countSince(history, 1000), 3);
        compare(policy.countSince(history, 6000), 0);
    }

    function test_an_unlocked_session_counts_nothing() {
        // Zero is "the lock is not up", which is not the same question as "how
        // much has ever arrived" — a 0 floor there would show the whole history
        // on the strip the moment the lock came up.
        const history = rows([{ time: 5000, appKey: "telegram" }]);
        compare(policy.countSince(history, 0), 0);
        compare(policy.countSince(history, -1), 0);
        compare(policy.countSince(history, undefined), 0);
    }

    function test_counting_survives_a_wrecked_history() {
        compare(policy.countSince(undefined, 1000), 0);
        compare(policy.countSince([null, { time: "soon" }, { time: 2000 }], 1000), 1);
    }

    // --- what the center shows (#43) -----------------------------------------

    function test_history_groups_by_app_newest_app_first() {
        // The centre draws one group per app, in the order the apps appear in
        // history — which, history being newest first, is "whoever notified
        // last is at the top". Rows inside a group keep that order too.
        const history = rows([
            { time: 5000, appKey: "firefox", appName: "Firefox", summary: "three" },
            { time: 4000, appKey: "telegram", appName: "Telegram", summary: "two" },
            { time: 1000, appKey: "firefox", appName: "Firefox", summary: "one" }
        ]);
        const groups = policy.groups(history);

        compare(groups.length, 2);
        compare(groups[0].appKey, "firefox");
        compare(groups[0].count, 2);
        compare(groups[0].latest, 5000);
        compare(groups[0].rows.map(row => row.summary), ["three", "one"]);
        compare(groups[1].appKey, "telegram");
        compare(groups[1].count, 1);
    }

    function test_a_group_describes_itself_as_its_newest_row_does() {
        // An app that has renamed itself, or started sending an icon, is drawn
        // the way it describes itself now rather than the way it did first.
        const history = rows([
            { time: 5000, appKey: "chat", appName: "Chat 2", appIcon: "new" },
            { time: 1000, appKey: "chat", appName: "Chat", appIcon: "old" }
        ]);
        const group = policy.groups(history)[0];

        compare(group.appName, "Chat 2");
        compare(group.appIcon, "new");
    }

    function test_rows_with_no_app_key_are_still_grouped() {
        // They cannot be *ruled* on — `knownApps` drops them for exactly that
        // reason — but they are in history, and a row the centre never draws is
        // a row nothing can clear.
        const history = rows([{ time: 2000, appKey: "", appName: "" },
                              { time: 1000, appKey: "firefox" }]);
        const groups = policy.groups(history);

        compare(groups.length, 2);
        compare(groups[0].appKey, "");
        compare(groups[0].count, 1);
    }

    function test_grouping_survives_a_wrecked_history() {
        compare(policy.groups(undefined).length, 0);
        compare(policy.groups([null, "nonsense", { time: 1000, appKey: "x" }]).length, 1);
    }

    function test_clearing_an_app_takes_its_rows_and_only_its_rows() {
        const history = rows([
            { time: 3000, appKey: "firefox" },
            { time: 2000, appKey: "telegram" },
            { time: 1000, appKey: "firefox" }
        ]);
        const after = policy.withoutApp(history, "firefox");

        compare(after.length, 1);
        compare(after[0].appKey, "telegram");
        // A new list: the service binds to its history, and an in-place splice
        // would change the value under a binding that never re-evaluates.
        compare(history.length, 3);
    }

    function test_clearing_an_app_folds_the_key_the_way_a_rule_does() {
        // `notifications.apps` is hand-editable and matched case-insensitively,
        // so the key the centre hands back can be any casing of the row's.
        const history = rows([{ time: 1000, appKey: "firefox" }]);
        compare(policy.withoutApp(history, "  FireFox "), []);
    }

    function test_dismissing_a_row_goes_by_the_row_key() {
        // Not the daemon's id, which restarts at 1 with every server (#76):
        // dismissing one row must never take an unrelated one with it.
        const history = rows([
            { time: 2000, seq: 2, appKey: "firefox", serverId: 1 },
            { time: 1000, seq: 1, appKey: "telegram", serverId: 1 }
        ]);
        const after = policy.withoutRow(history, history[0].key);

        compare(after.length, 1);
        compare(after[0].appKey, "telegram");
    }

    function test_dismissing_a_row_that_is_already_gone_changes_nothing() {
        // It may have fallen off the end of `historyLimit` between the frame
        // that drew it and the click. The user's intent is satisfied either way.
        const history = rows([{ time: 1000, seq: 1, appKey: "firefox" }]);
        compare(policy.withoutRow(history, "nope").length, 1);
    }

    // --- the bar's unread count (#43) ----------------------------------------

    function test_unread_is_what_arrived_since_the_centre_was_last_open() {
        const history = rows([
            { time: 5000, appKey: "firefox" },
            { time: 4000, appKey: "telegram" },
            { time: 1000, appKey: "firefox" }
        ]);
        compare(policy.unreadSince(history, 4000), 2);
        compare(policy.unreadSince(history, 5001), 0);
    }

    function test_a_centre_never_opened_leaves_everything_unread() {
        // The opposite of the lock's floor, and deliberately: a `since` of 0
        // means "the lock is not up" and counts nothing, where a `seenAt` of 0
        // means "you have never looked" and counts everything. A badge that
        // never lit on a first day would be the worse failure of the two.
        const history = rows([{ time: 5000, appKey: "firefox" },
                              { time: 1000, appKey: "telegram" }]);
        compare(policy.unreadSince(history, 0), 2);
        compare(policy.unreadSince(history, undefined), 2);
        compare(policy.unreadSince([], 0), 0);
    }

    function test_the_count_stops_being_a_number_past_ninety_nine() {
        // Past there the exact number is not information, and a wide module
        // pushes the clock off the centre of the bar (the #80 class).
        compare(policy.countLabel(0), "");
        compare(policy.countLabel(-3), "");
        compare(policy.countLabel(1), "1");
        compare(policy.countLabel(99), "99");
        compare(policy.countLabel(100), "99+");
        compare(policy.countLabel(undefined), "");
    }

    function test_a_timestamp_is_coarse_on_purpose() {
        // The clock ticks once a minute (Core/Time.qml), and a row that counted
        // seconds under the pointer would be movement the shell has not earned.
        const now = 1000000000;
        compare(policy.relativeTime(now, now), "now");
        compare(policy.relativeTime(now - 59000, now), "now");
        compare(policy.relativeTime(now - 60000, now), "1m");
        compare(policy.relativeTime(now - 3600000, now), "1h");
        compare(policy.relativeTime(now - 90000000, now), "1d");
        // A row from the future is a clock that moved, not a row to argue with.
        compare(policy.relativeTime(now + 5000, now), "now");
        compare(policy.relativeTime(0, now), "");
        compare(policy.relativeTime(undefined, now), "");
    }
}
