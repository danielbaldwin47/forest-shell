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

    function test_an_answered_refusal_re_arms_at_once() {
        // The retry limit is faillock's, not ours (#30) — a wrong password
        // makes the field live again immediately, forever.
        compare(policy.rearmWhen("failed", true), "now");
        compare(policy.rearmWhen("maxTries", true), "now");
        compare(policy.rearmWhen("error", true), "now");
    }

    function test_a_conversation_that_never_asked_waits_for_a_keystroke() {
        // A locked-out account completes without ever prompting. Re-arming that
        // on the spot would complete just as fast and spin; not re-arming it at
        // all would strand the user behind a lock they cannot restart. So the
        // next keystroke reopens it.
        compare(policy.rearmWhen("maxTries", false), "onInput");
        compare(policy.rearmWhen("failed", false), "onInput");
        compare(policy.rearmWhen("error", false), "onInput");
    }

    // --- Enter (#81) ---------------------------------------------------------

    function test_enter_answers_a_live_prompt() {
        compare(policy.submitOutcome(true, true, true, false), "send");
    }

    function test_enter_is_held_until_the_prompt_arrives() {
        // The conversation is open but has not asked yet: milliseconds, in
        // practice. Discarding the password to say "not ready" would eat the
        // first attempt of every unlock.
        compare(policy.submitOutcome(true, false, false, false), "hold");
        // Between attempts, after a refusal re-armed the conversation.
        compare(policy.submitOutcome(true, true, false, false), "hold");
    }

    function test_enter_does_not_queue_a_second_answer() {
        compare(policy.submitOutcome(true, true, true, true), "wait");
        compare(policy.submitOutcome(true, false, false, true), "wait");
    }

    function test_enter_with_no_conversation_is_never_silent() {
        // The #81 lockout: the lock never opened a conversation, so every
        // Enter — right password, wrong password — returned without a word,
        // and a secure lock has no other way out. "stalled" is what puts
        // something on screen.
        compare(policy.submitOutcome(false, false, false, false), "stalled");
        verify(policy.stalledText() !== "");
    }

    function test_success_asks_nothing_further() {
        compare(policy.rearmWhen("success", true), "never");
        compare(policy.rearmWhen("success", false), "never");
    }

    function test_lockout_is_recognised_without_reading_english() {
        // pam_faillock's own return carries the news in every locale; the
        // message match is the fallback for stacks that report a lockout as a
        // plain failure.
        verify(policy.lockedOutBy("maxTries", ""));
        verify(policy.lockedOutBy("maxTries", "Conta bloqueada"));
        verify(policy.lockedOutBy("failed", "Account locked due to 3 failed logins"));
        verify(!policy.lockedOutBy("failed", "Authentication failure"));
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

    function test_faillock_phrases_its_countdown_backwards() {
        // What a stock Arch pam_faillock actually says (#161): upstream
        // Linux-PAM's `_("(%d minutes left to unlock)")`, not the
        // "Try again in N minutes" the first guess at this pattern assumed.
        verify(policy.isLockout("(10 minutes left to unlock)"));
        verify(policy.isLockout("(1 minute left to unlock)"));
        verify(policy.lockedOutBy("failed", "(10 minutes left to unlock)"));
    }

    function test_a_lockout_latches_for_the_conversation() {
        // faillock sends two messages and the second one is the unhelpful one:
        // the refusal, which reads as a lockout, then the countdown. Whichever
        // arrived last must not be the whole answer, or a lockout announced in
        // the first message is forgotten by the time the attempt completes.
        verify(policy.lockedOutBy("failed", "Authentication failure", true));
        verify(policy.lockedOutBy("failed", "", true));
        // …and the latch is the only thing that arm adds: a conversation that
        // never saw one is still not a lockout.
        verify(!policy.lockedOutBy("failed", "Authentication failure", false));
    }

    function test_the_prompt_is_not_a_caption() {
        // The field is the prompt, so PAM's "Password: " is the one thing it
        // says that the surface stays quiet about. Everything else it says
        // belongs on screen — including an error raised while the prompt is
        // still standing, which is how faillock announces itself.
        verify(!policy.worthShowing("Password: ", false, true));
        verify(policy.worthShowing("Account locked due to 3 failed logins", true, true));
        verify(policy.worthShowing("Place your finger on the reader", false, false));
        verify(!policy.worthShowing("", true, false));
    }

    function test_an_ordinary_failure_is_not_a_lockout() {
        // A lockout keeps the message on screen and paints it ember, so a
        // false positive would make every typo look unrecoverable.
        verify(!policy.isLockout("Authentication failure"));
        verify(!policy.isLockout("Password: "));
        verify(!policy.isLockout("Place your finger on the reader"));
        verify(!policy.isLockout(""));
    }

    function test_a_lockout_never_reads_as_an_ordinary_error() {
        // The three dressings the message has, and the order that matters: a
        // locked account and a wrong password are both errors, and if they wore
        // the same colour the one message trying again cannot answer would look
        // like the one it can (#96).
        compare(policy.messageTone(true, true), "lockout");
        compare(policy.messageTone(true, false), "lockout");
        compare(policy.messageTone(false, true), "error");
        compare(policy.messageTone(false, false), "quiet");
    }

    function test_the_posed_lockout_is_a_lockout() {
        // capture-harness.qml's `--lock-state lockout` poses this line, and the
        // picture it takes is only worth anything if the shell would have
        // painted the real thing the same way. Keep the two in step: this is
        // the literal in `lockPosedText`.
        const posed = "Account locked due to 3 failed logins";
        verify(policy.isLockout(posed));
        verify(policy.lockedOutBy("failed", posed));
        compare(policy.messageTone(policy.lockedOutBy("failed", posed), true),
                "lockout");
        // …and the posed refusal is deliberately *not* one, or the two pictures
        // would be the same picture.
        verify(!policy.isLockout("Authentication failure"));
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

    // What fprintd says about a failed match is the whole feedback channel for
    // a wrong finger, and pam_fprintd overwrites it faster than a frame (#168).

    function test_a_re_prompt_cannot_wipe_a_failure_within_one_frame() {
        // The measured case: "Failed to match fingerprint" at 10915.5ms,
        // "Place your finger on the fingerprint reader" at 10925.2ms — 9.7ms
        // later, where a 60Hz frame is 16.7ms. The prompt loses.
        verify(!policy.fingerprintMessageWins(true, 10, false));
        verify(!policy.fingerprintMessageWins(true, 0, false));
    }

    function test_a_later_failure_replaces_an_earlier_one_at_once() {
        // Two wrong fingers in a row are two events, and the dwell is there to
        // make failures readable, not to hide the second one.
        verify(policy.fingerprintMessageWins(true, 0, true));
        verify(policy.fingerprintMessageWins(true, 10, true));
    }

    function test_the_prompt_returns_once_the_failure_has_been_read() {
        // Held, not dropped: the surface still has to end up saying what the
        // reader wants next.
        verify(policy.fingerprintMessageWins(
            true, policy.fingerprintErrorDwellMs, false));
        verify(policy.fingerprintMessageWins(
            true, policy.fingerprintErrorDwellMs + 500, false));
    }

    function test_an_ordinary_prompt_waits_for_nothing_else() {
        // Nothing is being held, so the first prompt of a conversation — and
        // every prompt after an ordinary one — shows immediately.
        verify(policy.fingerprintMessageWins(false, 0, false));
        verify(policy.fingerprintMessageWins(false, 10, true));
    }

    function test_the_dwell_outlasts_a_frame_and_ends() {
        // Longer than 16.7ms or it buys nothing; bounded, or a failure early in
        // a conversation would sit on top of every prompt after it.
        verify(policy.fingerprintErrorDwellMs > 17);
        verify(policy.fingerprintErrorDwellMs <= 3000);
    }

    function test_a_held_message_knows_how_long_it_waits() {
        compare(policy.fingerprintDwellRemainingMs(10),
                policy.fingerprintErrorDwellMs - 10);
        // Never negative: a Timer given a negative interval fires on a schedule
        // nobody chose.
        compare(policy.fingerprintDwellRemainingMs(
            policy.fingerprintErrorDwellMs), 0);
        compare(policy.fingerprintDwellRemainingMs(
            policy.fingerprintErrorDwellMs + 5000), 0);
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

    function test_the_lock_holds_no_clock_format_of_its_own() {
        // This file used to check `use24Hour`/`timeFormat`/`dateFormat` here,
        // and the bar answered differently — which is #93. The rule moved to
        // Core/ClockFormat.qml and tst_clockformat.qml covers it; what is left
        // to check on this side is that it did not quietly grow back, because a
        // second copy is the bug rather than a wrong one.
        compare(typeof policy.use24Hour, "undefined");
        compare(typeof policy.timeFormat, "undefined");
        compare(typeof policy.dateFormat, "undefined");
    }
}
