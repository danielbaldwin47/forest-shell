// Everything the lock screen decides, as pure functions (#30, #47).
//
// Split out of the surface for the reason Core/Tokens.qml is split out of
// Core/Theme.qml: this file imports nothing but QtQuick, so tests/ can reach
// it. Quickshell's QML modules are compiled into the quickshell binary and
// qmltestrunner cannot load them, so a lock screen is otherwise only checkable
// by locking a real session — which is the argument for keeping as little as
// possible on the far side of that line.
//
// Nothing here is policy in the security sense. faillock owns lockout and the
// number of tries (#30 — the shell keeps no counts of its own); PAM owns the
// wording. These functions only decide how what PAM says is *presented*, and
// how the surface behaves between messages.
import QtQuick

QtObject {
    id: policy

    // --- type-to-summon ------------------------------------------------------

    // The lock is quiet by default: a clock over fog, no field, no prompt. Any
    // keystroke summons the field, and it retreats again after this long
    // without one — so a cat on the keyboard does not leave the shell looking
    // like a login box for the rest of the night.
    readonly property int summonTimeoutMs: 8000

    /// Whether the field may retreat back into the fog. Held open while there
    /// is something typed (retreating would silently discard it) and while PAM
    /// is mid-conversation (the surface would be lying about what it is doing).
    function mayRetreat(hasInput: bool, busy: bool): bool {
        return !hasInput && !busy;
    }

    // --- PAM results ---------------------------------------------------------

    // The `PamResult` values, as strings. `PamContext` lives in a Quickshell
    // module this file may not import, so the caller maps the enum to one of
    // these and everything downstream is testable.
    readonly property var resultKinds: ["success", "failed", "maxTries", "error"]

    /// When to open the next conversation, given how the last one ended and
    /// whether we actually answered it.
    ///
    ///   "never"    it succeeded; there is nothing left to ask.
    ///   "now"      the user answered and was refused. The normal case: the
    ///              field goes live again immediately, because the retry limit
    ///              is faillock's and not ours.
    ///   "onInput"  the conversation ended without us answering it — faillock
    ///              denying before the prompt is ever shown, or pam failing to
    ///              start at all. Re-arming *now* would complete instantly and
    ///              spin; re-arming on the next keystroke costs nothing and
    ///              keeps the field alive.
    ///
    /// The "onInput" case is the one that matters: a locked-out account
    /// completes with no prompt, and a lock screen that stops asking has
    /// stranded its user — there is no way to restart the shell from behind
    /// its own lock, and faillock's `unlock_time` will expire long before
    /// anyone can. So the shell always ends up ready to try again; it just
    /// waits to be asked.
    function rearmWhen(kind: string, answered: bool): string {
        if (kind === "success")
            return "never";
        return answered ? "now" : "onInput";
    }

    // --- Enter, and what there is to answer ----------------------------------

    // #81: the lock shipped with `submit()` opening `if (!responseRequired)
    // return;`, and a conversation that never opened made that unconditional.
    // Every Enter — right password, wrong password — did nothing and said
    // nothing, and the only way out of a secure lock is authenticating, so the
    // session was lost. The rule that replaces it: Enter always has an outcome,
    // and none of them is silence.

    /// What pressing Enter should do, given what the conversation is doing.
    ///
    ///   "send"     PAM is asking; answer it. The normal case.
    ///   "hold"     the conversation is real but is not asking *yet* — it is
    ///              starting, or re-arming between attempts. The attempt is
    ///              kept and sent when the prompt arrives, because a prompt is
    ///              milliseconds away and discarding a typed password to say
    ///              "not ready" would be its own bug.
    ///   "wait"     an answer is already in flight. Enter again is not a second
    ///              attempt.
    ///   "stalled"  there is no conversation and none is coming. This is the
    ///              broken lock, and it has to say so on screen while someone
    ///              is still there to read it.
    function submitOutcome(begun: bool, conversing: bool, responseRequired: bool, busy: bool): string {
        if (busy)
            return "wait";
        if (responseRequired)
            return "send";
        return begun ? "hold" : "stalled";
    }

    // How long a held attempt — or a freshly opened conversation — may go
    // unanswered before the surface says the lock is broken. Long enough that
    // no working PAM stack ever trips it (the `login` stack prompts in single
    // -digit milliseconds), short enough to be read as a response to the Enter
    // that was just pressed.
    readonly property int conversationTimeoutMs: 2000

    /// What to show when no prompt ever arrives.
    ///
    /// Deliberately the same words as a pam error result: from where the user
    /// is standing those are the same event, and this is not the screen on
    /// which to explain the difference. The log carries the detail.
    function stalledText(): string {
        return failureText("error", "");
    }

    /// Whether a completed attempt means the account is locked.
    ///
    /// `maxTries` is pam_faillock's own return, so it is the locale-independent
    /// half of this answer; the message match is the other half, for stacks
    /// that report a lockout as a plain failure. Either is enough.
    function lockedOutBy(kind: string, message: string): bool {
        return kind === "maxTries" || isLockout(message);
    }

    /// What to show under the field for a completed attempt.
    ///
    /// PAM's own message wins whenever there is one — including faillock's
    /// lockout text, which is the only place lockout state exists (#30). The
    /// fallbacks are for the case where PAM completed without saying anything,
    /// which would otherwise read as nothing having happened.
    function failureText(kind: string, pamMessage: string): string {
        if (pamMessage)
            return pamMessage;
        switch (kind) {
        case "failed": return "Authentication failed";
        case "maxTries": return "Too many attempts";
        case "error": return "Authentication is unavailable";
        }
        return "";
    }

    /// How the message under the field is dressed.
    ///
    /// Named rather than coloured: the colour is the surface's to pick, the
    /// decision here is which of the three states the message is in. It is a
    /// decision because lockout outranks error — faillock's text is the one
    /// message on this screen that trying again cannot answer, so it must not
    /// be dressed the same as a wrong password (#96).
    function messageTone(lockedOut: bool, isError: bool): string {
        if (lockedOut)
            return "lockout";
        return isError ? "error" : "quiet";
    }

    // faillock's voice, in the two shapes it speaks in: the refusal
    // ("Account locked due to 3 failed logins") and the countdown pam_faillock
    // adds when `unlock_time` is set ("Try again in 8 minutes"). Matched only
    // to choose a colour and to keep the message on screen — the text itself is
    // always shown verbatim, and the shell never parses a count out of it.
    readonly property var lockoutPatterns: [
        /account\s+.*lock(ed)?/i,
        /lock(ed)?\s+.*due\s+to.*fail/i,
        /try\s+again\s+in\b/i
    ]

    /// Whether a PAM message is faillock reporting a locked account.
    ///
    /// A true here buys the message ember rather than secondary, and stops the
    /// idle retreat from hiding it — it is the one thing on this screen the
    /// user cannot type their way past, so it stays up until it is answered by
    /// a successful unlock.
    ///
    /// English-only, and unavoidably so: this is pam's own text in the system's
    /// locale, with no machine-readable form behind it. That is why it is only
    /// half of `lockedOutBy` above — the `maxTries` result carries the same
    /// news in every language, and this catches the stacks that do not send it.
    function isLockout(message: string): bool {
        if (!message)
            return false;
        for (const pattern of lockoutPatterns)
            if (pattern.test(message))
                return true;
        return false;
    }

    // --- caps lock -----------------------------------------------------------

    // Caps lock has no native Quickshell binding (#4 surveyed the Hyprland
    // module: workspaces, monitors, toplevels, focus grabs — no keyboard
    // state), and the sysfs LED would have to be polled, which #22 §5 rules
    // out. So it is *inferred* from the keystroke: a letter arriving in the
    // wrong case for the shift key held is caps lock, exactly. It costs
    // nothing, it is never wrong, and it can only tell us once the user has
    // typed — which on a type-to-summon lock is the same moment the field
    // appears.
    //
    // Returns "on", "off", or "unknown" for a key that carries no information
    // (digits, Tab, Enter, dead keys, anything non-Latin). "unknown" means keep
    // whatever was last known, not "off".
    function capsFromKey(text: string, shiftHeld: bool): string {
        if (!text || text.length !== 1)
            return "unknown";
        const lower = text.toLowerCase();
        const upper = text.toUpperCase();
        if (lower === upper)   // not a cased letter
            return "unknown";
        return (text === upper) !== shiftHeld ? "on" : "off";
    }

    // --- fingerprint ---------------------------------------------------------

    // Fingerprint auth is *latent* (#30): the second PAM context only exists if
    // fprintd is installed on this machine and the user has actually enrolled a
    // finger. Enrolment UI is post-v1, so the shell asks fprintd rather than
    // asking a setting — a config key claiming a reader that is not there would
    // put a prompt on the lock screen that nothing can answer.

    /// Whether `fprintd-list $USER` says this user has an enrolled finger.
    ///
    /// It is the text and not the exit status that carries the answer:
    /// fprintd-list exits 0 whether or not anything is enrolled, and says so in
    /// prose. A missing binary or a missing reader never reaches here — the
    /// probe simply fails to produce output and the context stays unbuilt.
    function fingerprintEnrolled(fprintdListOutput: string): bool {
        if (!fprintdListOutput)
            return false;
        if (/no\s+fingers?\s+enrolled/i.test(fprintdListOutput))
            return false;
        return /fingerprints?\s+for\s+user/i.test(fprintdListOutput);
    }

    // A fingerprint attempt that fails is re-armed, because a finger landing
    // crooked is the normal case — but on a cooldown and only so many times.
    // This is a rate limit on a *device*, not a retry policy on a secret:
    // faillock still owns how many passwords may be wrong (#30), and a reader
    // that has started failing every time must not sit there re-arming a PAM
    // conversation all night on battery (#22 §5).
    readonly property int fingerprintRetryDelayMs: 1000
    readonly property int fingerprintMaxRestarts: 5

    // --- notifications -------------------------------------------------------

    /// The count, and only the count (#9 — never the contents, so a lock screen
    /// left facing a room leaks nothing). Empty string means show nothing at
    /// all, rather than a zero.
    function notificationSummary(count: int): string {
        if (!count || count < 1)
            return "";
        return count === 1 ? "1 notification" : count + " notifications";
    }

    // --- clock ---------------------------------------------------------------
    //
    // Not here any more, and deliberately not here again. This file used to hold
    // `timeFormat`/`use24Hour`/`dateFormat` of its own while the bar held a
    // different rule, which is exactly #93: the same shell read `19:26` on the
    // bar and `7:30 PM` on the lock. Core/ClockFormat.qml is the rule now,
    // `weatherTime.clock.format` is the choice, and Core/TimeFormat.qml resolves
    // the pair for every surface — LockSurface.qml reads a property.
    //
    // The line worth keeping is why the formats were ever here: a format string
    // at a call site is untestable. That argument holds — it just points at a
    // file the whole shell shares rather than at this one, and tst_lockpolicy
    // checks the copy has not grown back.
}
