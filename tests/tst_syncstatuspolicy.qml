// What the calendar says about its Google half — the sidebar row's mode and
// words, and the toolbar control's colour.
//
// The interesting cases are all *rank*: which of two true things a surface
// says. A person mid-consent whose account is already in error, a shell that is
// enabled but has never connected, an error that must not erase the last good
// sync time. The pretty middle — idle, connected, synced — is checked once and
// left alone.
import QtQuick
import QtTest
import "../Surfaces/Calendar"

TestCase {
    id: testCase

    name: "SyncStatusPolicy"

    SyncStatusPolicy { id: policy }

    readonly property var connected: ({
        "status": "idle", "account": "rowan@example.com",
        "lastSync": "2026-08-18T13:12:04.000Z", "ago": "3 min ago",
        "error": "", "connecting": false
    })

    function withState(changes) {
        const state = {};
        for (const key in testCase.connected)
            state[key] = testCase.connected[key];
        for (const key in changes)
            state[key] = changes[key];
        return state;
    }

    // --- the block ------------------------------------------------------------

    function test_the_setting_being_off_removes_the_block_rather_than_greying_it() {
        const block = policy.block(testCase.withState({ "status": "off" }));
        compare(block.visible, false);
        compare(block.mode, "off");
        // And nothing to draw if a view ignored `visible`.
        compare(block.title, "");
        compare(block.subtitle, "");
        compare(block.action, "");
    }

    // The rank, which is the decision this file exists to hold: the line that
    // changes is the line that carries weight, and the address — which never
    // changes and cannot be acted on — is the dim one under it. The row is
    // *This device*'s twin, so the two sources read alike.
    function test_the_sync_time_outranks_the_address_it_belongs_to() {
        const block = policy.block(testCase.connected);
        compare(block.visible, true);
        compare(block.mode, "account");
        compare(block.title, "Synced 3 min ago");
        compare(block.subtitle, "rowan@example.com");
        compare(block.tone, "muted");
        // No button on the row: a manual round is the toolbar's control.
        compare(block.action, "");
    }

    function test_the_helpers_auth_state_asks_for_a_connection() {
        const block = policy.block(testCase.withState({ "status": "auth" }));
        compare(block.mode, "connect");
        compare(block.title, "Not connected");
        compare(block.action, "Connect");
        // The second line names the service rather than repeating the state:
        // "Not connected · synced 3 min ago" is two answers to one question,
        // and the stale one is the louder.
        compare(block.subtitle, "Google Calendar");
    }

    function test_switched_on_and_never_connected_is_the_same_block_as_auth() {
        // The state a fresh machine is in: enabled, idle, nothing ever ran.
        const block = policy.block(testCase.withState({
            "account": "", "lastSync": "", "ago": ""
        }));
        compare(block.mode, "connect");
        compare(block.title, "Not connected");
        compare(block.action, "Connect");
    }

    function test_consent_in_flight_outranks_whatever_came_before_it() {
        // Mid-consent while the previous state was an error: the person just
        // clicked Connect, so the block answers *that*.
        const block = policy.block(testCase.withState({
            "status": "error", "error": "403", "connecting": true
        }));
        compare(block.mode, "connecting");
        compare(block.title, "Waiting for browser…");
        compare(block.subtitle, "Google Calendar");
        // And no button, because a second click only logs "already running".
        compare(block.action, "");
    }

    function test_an_error_keeps_the_last_good_sync_time_and_adds_the_code() {
        const block = policy.block(testCase.withState({
            "status": "error", "error": "rateLimitExceeded"
        }));
        compare(block.mode, "account");
        // The time above stays the last good one — "synced 3 min ago, and
        // failing since" is the reading — and the failure takes the second
        // line off the address, which is the line worth least.
        compare(block.title, "Synced 3 min ago");
        compare(block.subtitle, "Sync failed · rateLimitExceeded");
        compare(block.tone, "error");
    }

    function test_an_error_with_no_code_still_says_something() {
        const block = policy.block(testCase.withState({ "status": "error", "error": "" }));
        compare(block.subtitle, "Sync failed · sync failed");
        compare(block.tone, "error");
    }

    function test_a_round_in_flight_replaces_the_time_rather_than_the_account() {
        const block = policy.block(testCase.withState({ "status": "syncing" }));
        compare(block.mode, "account");
        compare(block.title, "Syncing…");
        compare(block.subtitle, "rowan@example.com");
    }

    function test_a_token_that_answered_but_never_named_the_account() {
        const block = policy.block(testCase.withState({ "account": "" }));
        compare(block.mode, "account");
        compare(block.title, "Synced 3 min ago");
        compare(block.subtitle, "Google Calendar");
    }

    function test_a_first_round_that_has_not_landed_says_so() {
        compare(policy.syncedLine("idle", ""), "Not synced yet");
        compare(policy.syncedLine("idle", "2 hr ago"), "Synced 2 hr ago");
        compare(policy.syncedLine("syncing", "2 hr ago"), "Syncing…");
    }

    function test_nothing_at_all_is_the_off_block() {
        // A view that read the singleton a frame early hands in undefined.
        compare(policy.block(undefined).visible, false);
        compare(policy.dot(undefined).visible, false);
    }

    // --- the toolbar control ----------------------------------------------------

    function test_the_control_is_gone_when_the_setting_is_off() {
        const dot = policy.dot(testCase.withState({ "status": "off" }));
        compare(dot.visible, false);
        compare(dot.actionable, false);
    }

    function test_idle_is_the_quietest_ink_rather_than_a_faded_one() {
        const dot = policy.dot(testCase.connected);
        compare(dot.visible, true);
        // A role, at full ink. The 40% dot this replaced measured 1.84:1
        // against the chrome band — a mark under 3:1 is not a quiet mark.
        compare(dot.role, "textMuted");
        compare(dot.pulse, false);
        compare(dot.actionable, true);
    }

    function test_only_a_round_in_flight_pulses() {
        const syncing = policy.dot(testCase.withState({ "status": "syncing" }));
        compare(syncing.role, "accentPrimary");
        compare(syncing.pulse, true);
        // A round already running is still a round you may ask for again.
        compare(syncing.actionable, true);
        // Consent is a round in flight as far as the toolbar is concerned.
        const consent = policy.dot(testCase.withState({ "connecting": true }));
        compare(consent.role, "accentPrimary");
        compare(consent.pulse, true);
    }

    function test_the_two_states_worth_looking_at_are_told_apart_by_colour() {
        const failing = policy.dot(testCase.withState({ "status": "error" }));
        compare(failing.role, "accentEmber");
        compare(failing.pulse, false);
        compare(failing.actionable, true);
        // Not the same colour: nothing is broken, an account is simply missing.
        const missing = policy.dot(testCase.withState({ "status": "auth" }));
        compare(missing.role, "accentWarm");
        compare(missing.pulse, false);
    }

    // Nothing to sync against, so no refresh button — the rail's row is
    // carrying *Connect*, and a control that could only fail is worse than no
    // control. Both states the row answers with a button answer false here.
    function test_a_press_that_could_do_nothing_is_not_offered() {
        compare(policy.dot(testCase.withState({ "status": "auth" })).actionable, false);
        compare(policy.dot(testCase.withState({ "connecting": true })).actionable, false);
        compare(policy.dot(testCase.withState({
            "account": "", "lastSync": "", "ago": ""
        })).actionable, false);
    }

    // --- the tooltip ----------------------------------------------------------

    function test_the_tooltip_always_names_the_service() {
        compare(policy.dotTitle(testCase.connected),
                "Google Calendar · synced 3 min ago");
        compare(policy.dotTitle(testCase.withState({ "status": "syncing" })),
                "Google Calendar · syncing…");
        compare(policy.dotTitle(testCase.withState({ "status": "auth" })),
                "Google Calendar · not connected");
        compare(policy.dotTitle(testCase.withState({ "connecting": true })),
                "Google Calendar · waiting for the browser");
    }

    function test_the_tooltip_carries_the_error_the_helper_gave() {
        compare(policy.dotTitle(testCase.withState({
            "status": "error", "error": "invalid_grant"
        })), "Google Calendar · invalid_grant");
        compare(policy.dotTitle(testCase.withState({ "status": "error", "error": "" })),
                "Google Calendar · sync failed");
    }

    function test_a_shell_that_has_never_synced_says_so_rather_than_nothing() {
        compare(policy.dotTitle(testCase.withState({ "ago": "" })),
                "Google Calendar · not synced yet");
    }
}
