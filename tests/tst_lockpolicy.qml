// The lock screen's decisions (#30, #47): retry, lockout presentation, caps
// lock inference, the notification count, and the clock's format strings.
//
// The rest of the lock — `WlSessionLock`, `PamContext`, the fprintd probe —
// imports Quickshell and so cannot be loaded here; those are verified by
// locking a real session (see the ticket's acceptance criteria).
import QtQuick
import QtTest
import "../Surfaces/Lock"

TestCase {
    name: "LockPolicy"

    LockPolicy { id: policy }

    // --- type-to-summon ------------------------------------------------------

    function test_the_field_only_retreats_when_there_is_nothing_to_lose() {
        verify(policy.mayRetreat(false, false));
        // Something typed: retreating would discard it silently.
        verify(!policy.mayRetreat(true, false));
        // Mid-conversation with PAM: the surface would be lying.
        verify(!policy.mayRetreat(false, true));
        verify(!policy.mayRetreat(true, true));
    }

    // --- PAM results ---------------------------------------------------------

    function test_only_a_wrong_password_is_retried() {
        // The retry limit is faillock's, not ours (#30) — a plain failure
        // re-arms immediately and forever.
        verify(policy.retryable("failed"));
        // PAM saying the method is spent, or that the conversation never
        // happened: re-arming either spins.
        verify(!policy.retryable("maxTries"));
        verify(!policy.retryable("error"));
        verify(!policy.retryable("success"));
    }

    function test_pam_owns_the_wording() {
        // Whatever PAM said, verbatim — including faillock's lockout text,
        // which is the only place lockout state exists.
        compare(policy.failureText("failed", "Account locked due to 3 failed logins"),
                "Account locked due to 3 failed logins");
        compare(policy.failureText("error", "Authentication token is no longer valid"),
                "Authentication token is no longer valid");
    }

    function test_a_silent_pam_still_says_something() {
        // A completed attempt that showed nothing would read as no attempt.
        compare(policy.failureText("failed", ""), "Authentication failed");
        compare(policy.failureText("maxTries", ""), "Too many attempts");
        compare(policy.failureText("error", ""), "Authentication is unavailable");
        compare(policy.failureText("success", ""), "");
    }

    function test_faillock_is_recognised_in_both_of_its_voices() {
        // The refusal…
        verify(policy.isLockout("Account locked due to 3 failed logins"));
        verify(policy.isLockout("The account is temporarily locked"));
        // …and the countdown pam_faillock adds when unlock_time is set.
        verify(policy.isLockout("(Account locked due to 4 failed logins) Try again in 8 minutes"));
    }

    function test_an_ordinary_failure_is_not_a_lockout() {
        // A lockout keeps the message on screen and paints it ember, so a
        // false positive would make every typo look unrecoverable.
        verify(!policy.isLockout("Authentication failure"));
        verify(!policy.isLockout("Password: "));
        verify(!policy.isLockout("Place your finger on the reader"));
        verify(!policy.isLockout(""));
    }

    // --- caps lock -----------------------------------------------------------

    function test_caps_lock_is_read_off_the_keystroke() {
        // Uppercase with no shift, or lowercase with shift, is caps lock —
        // exactly, with no polling and no LED (#22 §5).
        compare(policy.capsFromKey("A", false), "on");
        compare(policy.capsFromKey("a", true), "on");
        compare(policy.capsFromKey("a", false), "off");
        compare(policy.capsFromKey("A", true), "off");
    }

    function test_keys_that_carry_no_case_say_nothing() {
        // "unknown" means keep the last known state, not "off" — otherwise a
        // digit in the middle of a password would clear a real warning.
        compare(policy.capsFromKey("4", false), "unknown");
        compare(policy.capsFromKey("-", true), "unknown");
        compare(policy.capsFromKey(" ", false), "unknown");
        compare(policy.capsFromKey("", false), "unknown");
        compare(policy.capsFromKey("ab", false), "unknown");
    }

    function test_accented_letters_still_carry_case() {
        compare(policy.capsFromKey("É", false), "on");
        compare(policy.capsFromKey("é", false), "off");
    }

    // --- fingerprint ---------------------------------------------------------

    function test_an_enrolled_finger_is_read_out_of_fprintd_list() {
        verify(policy.fingerprintEnrolled(
            "found 1 devices\nUsing device /net/reactivated/Fprint/Device/0\n"
            + "Fingerprints for user daniel: right-index-finger"));
    }

    function test_a_reader_with_nothing_enrolled_is_not_offered() {
        // fprintd-list exits 0 either way, so the prose is the answer. A
        // fingerprint prompt nothing can answer is worse than no prompt (#30 —
        // enrolment UI is post-v1).
        verify(!policy.fingerprintEnrolled(
            "found 1 devices\nUser daniel has no fingers enrolled for Synaptics Sensors"));
        verify(!policy.fingerprintEnrolled("found 0 devices"));
        verify(!policy.fingerprintEnrolled(""));
    }

    function test_the_fingerprint_re_arm_is_bounded() {
        // A reader that has started failing every time must not re-arm a PAM
        // conversation all night on battery (#22 §5).
        verify(policy.fingerprintRetryDelayMs > 0);
        verify(policy.fingerprintMaxRestarts > 0);
    }

    // --- notifications -------------------------------------------------------

    function test_the_count_is_all_that_is_ever_shown() {
        compare(policy.notificationSummary(1), "1 notification");
        compare(policy.notificationSummary(4), "4 notifications");
    }

    function test_nothing_waiting_shows_nothing() {
        // Not "0 notifications" — an empty lock screen is the quiet one.
        compare(policy.notificationSummary(0), "");
        compare(policy.notificationSummary(-1), "");
    }

    // --- clock ---------------------------------------------------------------

    function test_the_clock_follows_the_locale_rather_than_a_setting() {
        // #50 owns clock formatting for real; until it lands the locale is a
        // better answer than a key that would have to be migrated away.
        verify(policy.use24Hour("HH:mm"));
        verify(policy.use24Hour("hh:mm:ss"));
        verify(!policy.use24Hour("h:mm AP"));
        verify(!policy.use24Hour("h:mm ap"));
    }

    function test_the_two_clock_formats() {
        compare(policy.timeFormat(true), "HH:mm");
        compare(policy.timeFormat(false), "h:mm AP");
        // Rendered by Qt, not by us — this only checks the format is one Qt
        // reads as time and date rather than something literal.
        const noon = new Date(2026, 7, 1, 12, 34);
        compare(Qt.formatDateTime(noon, policy.timeFormat(true)), "12:34");
        compare(Qt.formatDateTime(noon, policy.dateFormat), "Saturday, 1 August");
    }

    // --- battery -------------------------------------------------------------

    function test_upower_reports_a_fraction_not_a_percentage() {
        compare(policy.batteryPercent(0.62), 62);
        compare(policy.batteryPercent(1), 100);
        compare(policy.batteryPercent(0), 0);
    }

    function test_a_battery_out_of_range_does_not_widen_the_pill() {
        compare(policy.batteryPercent(1.4), 100);
        compare(policy.batteryPercent(-0.2), 0);
        compare(policy.batteryPercent(NaN), 0);
    }

    function test_the_low_threshold() {
        verify(policy.batteryLow(0.2));
        verify(policy.batteryLow(0.05));
        verify(!policy.batteryLow(0.21));
        verify(!policy.batteryLow(NaN));
    }
}
