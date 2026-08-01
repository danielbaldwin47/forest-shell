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
        compare(policy.timeoutMs(policy.urgencyNormal, 5, settings), 8000);
        compare(policy.timeoutMs(policy.urgencyLow, 30, settings), 5000);
    }

    function test_the_clients_timeout_wins_when_the_user_asks_for_it() {
        const honoring = Object.assign({}, settings, { honorClientTimeout: true });
        // Quickshell hands the hint over in seconds; the shell works in ms.
        compare(policy.timeoutMs(policy.urgencyNormal, 5, honoring), 5000);
        compare(policy.timeoutMs(policy.urgencyNormal, 2.5, honoring), 2500);
        // 0 means "never expire" in the freedesktop spec, not "expire now".
        compare(policy.timeoutMs(policy.urgencyNormal, 0, honoring), 0);
        // -1 is "server decides", which is the authored default.
        compare(policy.timeoutMs(policy.urgencyNormal, -1, honoring), 8000);
    }

    function test_an_honored_client_timeout_is_still_bounded() {
        // A client asking for an hour on screen does not get one.
        const honoring = Object.assign({}, settings, { honorClientTimeout: true });
        compare(policy.timeoutMs(policy.urgencyNormal, 3600, honoring), policy.maxTimeoutMs);
        // Nor does one asking for a frame.
        compare(policy.timeoutMs(policy.urgencyNormal, 0.05, honoring), policy.minTimeoutMs);
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
            id: 7,
            time: 1000,
            appKey: "telegram",
            appName: "Telegram",
            appIcon: "telegram",
            image: "/tmp/avatar.png",
            summary: "Ada",
            body: "on my way",
            urgency: policy.urgencyNormal
        });
        compare(record.id, 7);
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
            history = policy.remember(history, policy.record({ id: i, summary: "n" + i }), 3);
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
            history.push(policy.record({ id: i, summary: "n" + i }));
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
}
