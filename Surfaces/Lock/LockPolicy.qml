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
    ///
    /// `seenLockout` is the latch: faillock speaks twice per refusal and only
    /// the first line names the lockout, so the caller carries "some message in
    /// this conversation read as a lockout" forward and the last message does
    /// not get to overrule it (#161). Omitted means no latch.
    function lockedOutBy(kind: string, message: string, seenLockout: bool): bool {
        return kind === "maxTries" || seenLockout || isLockout(message);
    }

    /// Whether something PAM said belongs under the field.
    ///
    /// The prompt itself ("Password: ") does not — the field is the prompt, and
    /// captioning it would be the shell talking over PAM. Anything else does,
    /// including an error raised while a prompt is still standing.
    function worthShowing(message: string, isError: bool, isPrompt: bool): bool {
        return !!message && (isError || !isPrompt);
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

    // faillock's voice, in the shapes it speaks in: the refusal ("Account
    // locked due to 3 failed logins") and the countdown pam_faillock adds when
    // `unlock_time` is set. Matched only to choose a colour and to keep the
    // message on screen — the text itself is always shown verbatim, and the
    // shell never parses a count out of it.
    //
    // The countdown wording is upstream Linux-PAM's own, read off pam_faillock.c
    // rather than guessed: `_("(%d minutes left to unlock)")`. A stock Arch
    // install says exactly that and nothing else, and the guessed "Try again in
    // N minutes" matched none of it — which is #161, a lockout painted as an
    // ordinary error and cleared by the idle retreat. Both spellings stay: the
    // guess costs one pattern and some stack somewhere may yet speak it.
    readonly property var lockoutPatterns: [
        /account\s+.*lock(ed)?/i,
        /lock(ed)?\s+.*due\s+to.*fail/i,
        /try\s+again\s+in\b/i,
        /left\s+to\s+unlock\b/i
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

    /// What one run of the probe actually established (#188). Three outcomes,
    /// where the surface used to see two.
    ///
    /// "ran and found nothing" and "could not run" were the same empty string,
    /// and after a resume they are emphatically not the same thing. This
    /// machine's driver stack (`open-fprintd` + `python-validity`) is restarted
    /// on every resume by `python3-validity-suspend-hotfix.service`
    /// (`WantedBy=suspend.target`), so a probe fired the instant the machine
    /// comes back races that restart and asks a bus name nothing is serving
    /// yet: `fprintd-list` exits non-zero, says its piece on stderr, and leaves
    /// stdout empty. Read as "no reader" that is a fingerprint offer thrown
    /// away for a reader that was about to be there.
    ///
    /// A zero exit with nothing on stdout is the same conclusion by a different
    /// road — the tool cannot succeed and stay silent — so it is "failed" too.
    function fingerprintProbeOutcome(exitCode: int, output: string): string {
        if (exitCode !== 0)
            return "failed";
        if (!output)
            return "failed";
        return fingerprintEnrolled(output) ? "enrolled" : "none";
    }

    // How long to let the driver come back, and how many times to ask.
    //
    // The restart above is `systemctl --no-block restart`, so it is in flight
    // while logind is still handing out resume notifications. These two are a
    // settle window for that, and they are *not* a retry of anything the user
    // does: no touch is spent here, and pam_fprintd's own budget is untouched
    // (#169's refusal stands — see `fingerprintTouchBudget`). The thing being
    // retried is a question about the machine, asked before any offer exists.
    readonly property int fingerprintProbeRetryMs: 750
    readonly property int fingerprintProbeRetries: 4

    /// Whether a probe that could not run is worth asking again.
    function fingerprintProbeShouldRetry(outcome: string, attempt: int): bool {
        return outcome === "failed" && attempt < fingerprintProbeRetries;
    }

    /// Whether a probe that never ran should say so on the lock screen.
    ///
    /// Silence is right the first time a machine is asked: a desktop with the
    /// setting on and no reader in it would otherwise grow a line about
    /// hardware it does not have. It stops being right once we know better —
    /// after a resume, or once a reader has already answered during this lock —
    /// because that is exactly #188's screen, and saying nothing there is how
    /// a stranded reader gets read as a wrong finger.
    function fingerprintProbeSpeaks(outcome: string, everEnrolled: bool,
                                    afterResume: bool): bool {
        if (outcome !== "failed")
            return false;
        return everEnrolled || afterResume;
    }

    // How many wrong touches the reader gives you — and whose number that is.
    //
    // It is pam_fprintd's, not ours (#169). The module re-prompts *inside* a
    // single PAM conversation, `max-tries` times, whose default and documented
    // minimum are both 3, and then answers PAM_MAXTRIES. Measured against
    // fprintd: three `Failed to match fingerprint` messages about 1.1s apart,
    // then result 11, with open-fprintd logging exactly three
    // VerifyStart/VerifyStop cycles before Release. The shell had its own
    // re-arm on top of this and it never once ran, because the branch it lived
    // behind excluded the only result the module ever returns.
    //
    // So the shell does not re-arm at all: the budget is the module's, and the
    // way to change it would be to pass `max-tries=` where the context is
    // opened. Re-arming *through* PAM_MAXTRIES is the other option and is a
    // different, heavier decision — overriding an authentication module's own
    // refusal — which #169 declined to take without a ticket that says so. The
    // password path treats faillock's refusal as authoritative for the same
    // reason (#161, #164).
    //
    // The number can still change under us, since it is configured in a file
    // this shell does not own, and nothing at seam 1 can ask pam_fprintd what
    // it is today. Two things bind it instead. This constant cannot be edited
    // without a recorded conversation that spends the new number, because
    // `fingerprintTouchesSpent` scores a transcribed hardware run against it in
    // tests/tst_lockpolicy.qml. And a *live* conversation that disagrees is
    // caught where a live conversation can be seen: LockAuth warns, and the run
    // sheet's §3 says that warning is the finding.
    readonly property int fingerprintTouchBudget: 3

    /// How many touches a fingerprint conversation spent, counted out of the
    /// messages it emitted. Every touch is a pair — a prompt and then its
    /// answer — and only a failed match is a touch that cost something.
    ///
    /// Scores a whole conversation at once, which is what a recorded one at
    /// seam 1 is; LockAuth counts the same thing a message at a time, through
    /// `fingerprintTouchMissed` below, because it hears them as they arrive.
    function fingerprintTouchesSpent(messages: var): int {
        let spent = 0;
        for (let i = 0; i < messages.length; i += 1) {
            if (fingerprintTouchMissed(messages[i]))
                spent += 1;
        }
        return spent;
    }

    /// Whether one fingerprint message is the reader saying it is not there —
    /// a device it could not claim, a bus name nothing is serving, a driver
    /// mid-restart (#188). PAM_ERROR_MSG carries these on the same channel as a
    /// failed match, and the old code's comment named this gap without closing
    /// it.
    ///
    /// Only negative forms are listed. "device" alone would swallow the
    /// reader's own prompt, and a pattern that eats prompts spends the budget
    /// twice as fast as the hardware does.
    function fingerprintDeviceUnavailable(text: string): bool {
        if (!text)
            return false;
        return /no such device|(could not|cannot|can't|failed to|unable to)\s+(claim|open|access)\b|device (was )?not claimed|device (is )?busy|device (is )?disconnected|device not (ready|available)|no (fingerprint )?(devices?|readers?) (available|found)|impossible to enumerate|communication with the device failed|not provided by any|failed to activate service|reader (is )?(unavailable|not available|not ready)/i.test(text);
    }

    /// Whether one fingerprint message is a touch that missed. Read out of the
    /// prose, as §2's faillock lines are: PAM_ERROR_MSG is also how the module
    /// reports a reader it could not claim, which is not a spent touch.
    function fingerprintTouchMissed(text: string): bool {
        if (!text)
            return false;
        if (fingerprintDeviceUnavailable(text))
            return false;
        return /failed to match|match failed/i.test(text);
    }

    /// Whether an arriving message may actually charge the user a touch.
    ///
    /// The prose above catches a reader that admits it is missing. #188 is the
    /// case where it does not admit it: a conversation opened before a suspend
    /// and left holding a D-Bus name that got restarted underneath it reports
    /// "Failed to match fingerprint" three times, in the same words a wrong
    /// finger produces, while the sensor's illuminator never comes on. No
    /// regex can separate those two strings, because they are one string.
    ///
    /// So the lifecycle separates them instead. `live` is false from the moment
    /// a sleep is announced until the offer has been rebuilt on the other side,
    /// and nothing said across that gap is chargeable — the user was not in the
    /// room, so no touch of theirs is in the transcript.
    function fingerprintTouchCharged(text: string, live: bool): bool {
        if (!live)
            return false;
        return fingerprintTouchMissed(text);
    }

    /// Whether a fingerprint conversation that closed had spent the budget,
    /// rather than ending some other way. `maxTries` is the module saying so
    /// itself and settles it alone; the count is the fallback for a context
    /// that goes away without an answer.
    function fingerprintBudgetSpent(maxTries: bool, touches: int): bool {
        return maxTries || touches >= fingerprintTouchBudget;
    }

    /// The same question asked of a conversation that has just closed, which is
    /// the only caller that knows *how* it closed (#188).
    ///
    /// `kind` is the PAM result named the way the password path names it:
    /// "maxTries", "error", "failed". The error case is the whole point. A
    /// `PamResult.Error` is the module never getting as far as the reader, and
    /// the old code did not branch on it at all — it fell through to the count,
    /// so an error arriving on top of three unchargeable messages produced "Out
    /// of fingerprint tries" for a sensor that never lit up. An error is never
    /// a spent budget, whatever the count says.
    function fingerprintClosedSpent(kind: string, touches: int): bool {
        if (kind === "error")
            return false;
        return fingerprintBudgetSpent(kind === "maxTries", touches);
    }

    /// What the fingerprint line says once its conversation is over (#169).
    ///
    /// Before this it said nothing: the line came down, the reader's light went
    /// out, and the light is the hardware rather than the shell. Three wrong
    /// touches withdrew the offer in silence, with the password field still
    /// working and nothing on screen to say so. The two cases are worth
    /// separating — "out of tries" is a lie about a reader that was never
    /// asked, which is what a PAM error on startup leaves behind.
    function fingerprintClosingMessage(spentBudget: bool): string {
        return spentBudget
            ? "Out of fingerprint tries — use your password"
            : "Fingerprint unavailable — use your password";
    }

    // A failed match is the whole feedback channel for a wrong finger, and
    // pam_fprintd overwrites it faster than the screen can draw it (#168,
    // measured on hardware): "Failed to match fingerprint" survives 9.7ms
    // before the re-prompt lands, where a 60Hz frame is 16.7ms. So a failure
    // holds the line for a spell of its own, long enough to read a short line
    // and short enough that the reader's own prompt is not gone for long.
    readonly property int fingerprintErrorDwellMs: 1500

    /// Whether an arriving fingerprint message may replace the one on screen.
    ///
    /// `sinceMs` is how long the current message has been up, and matters only
    /// while an error is holding: a later error is a second event and replaces
    /// the first at once, and a message arriving over an ordinary prompt has
    /// nothing to wait for.
    ///
    /// Unlike §2's faillock lines, pam_fprintd's failure genuinely is a
    /// `PAM_ERROR_MSG`, so `PamContext.messageIsError` is what the caller
    /// passes for both flags.
    function fingerprintMessageWins(currentIsError: bool, sinceMs: int,
                                    incomingIsError: bool): bool {
        if (incomingIsError || !currentIsError)
            return true;
        return sinceMs >= fingerprintErrorDwellMs;
    }

    /// How long a message that lost must be held before it may be shown. It is
    /// held rather than dropped — the surface still has to end up saying what
    /// the reader wants next — so this is the interval that flush waits.
    function fingerprintDwellRemainingMs(sinceMs: int): int {
        const remaining = fingerprintErrorDwellMs - sinceMs;
        return remaining > 0 ? remaining : 0;
    }

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
