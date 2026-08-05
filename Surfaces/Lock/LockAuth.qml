// The PAM side of the lock (#30, #47) — one instance for the whole session,
// not one per screen.
//
// Two contexts run in parallel, hyprlock-style:
//
//   password    always, against the system `login` stack. Using the distro's
//               own stack rather than a config we install is the whole point:
//               faillock, pam_unix, pam_systemd, whatever else the machine
//               already trusts, and nothing written to /etc.
//   fingerprint only when fprintd is installed *and* a finger is enrolled.
//               Probed at lock time, never assumed, because the prompt it puts
//               on screen has to be answerable (enrolment UI is post-v1).
//
// The shell keeps no count of failed attempts and imposes no retry limit of its
// own. faillock owns lockout; PAM's messages are shown verbatim, including
// faillock's, and that is the entire lockout implementation (#30).
//
// Lives with the surface rather than under Services/ because only the surface
// uses it (#12 §3), but it is *shared* by every screen's surface: the password
// buffer, the conversation and the messages are session state, not screen
// state, and a second monitor must not get its own half-typed password.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import qs.Core
import qs.Services.System

Scope {
    id: root

    // --- what the surface reads ---------------------------------------------

    /// What the user has typed, mirrored across every screen's field. Held here
    /// rather than in the field so that typing on one monitor and pressing
    /// Enter on another is the same attempt.
    property string buffer: ""

    /// A PAM conversation is mid-answer — the field is disabled and the summon
    /// timeout is held open while this is true.
    readonly property alias busy: priv.busy

    /// PAM has spoken to us at least once since `begin()` — the conversation is
    /// real and Enter has somewhere to go. False here after `begin()` is the
    /// #81 failure: a lock that looks right and cannot be answered.
    readonly property alias conversing: priv.conversing

    /// The last thing PAM said about the password, shown verbatim under the
    /// field. Empty means say nothing.
    readonly property alias message: priv.message
    readonly property alias messageIsError: priv.messageIsError

    /// faillock reporting a locked account. Presentation only: it paints the
    /// message ember and keeps it on screen. The shell does not act on it, has
    /// no idea how long it lasts, and never counts anything itself — in
    /// particular it keeps asking, because faillock decides when to start
    /// saying yes again and the shell has no way to know when that was.
    readonly property alias lockedOut: priv.lockedOut

    /// Whether PAM wants the answer shown rather than dotted — an OTP or a
    /// device prompt rather than a password.
    readonly property alias responseVisible: priv.responseVisible

    /// The parallel fingerprint conversation: whether it exists at all on this
    /// machine, and whatever it last said ("Place your finger on the reader",
    /// "Failed to match fingerprint"). Kept separate from `message` so the two
    /// conversations never overwrite each other on screen.
    readonly property alias fingerprintActive: priv.fingerprintActive
    readonly property alias fingerprintMessage: priv.fingerprintMessage

    /// How many touches the running offer has been charged, and whether it is
    /// in a state where a touch *can* be charged (#188). Exposed because the
    /// claim a suspend/resume run has to make is about the count — an offer
    /// rebuilt with three touches already on it is the bug, and a harness that
    /// can only see `fingerprintActive` cannot tell that from a good rebuild.
    readonly property alias fingerprintTouches: priv.fingerprintTouches
    readonly property alias fingerprintLive: priv.fingerprintLive

    /// A completed attempt that was not a success — the surface's cue to shake
    /// the field and pulse the fog.
    signal failed()

    /// The buffer was emptied from here (submitted, or cleared after a
    /// failure). Fields listen for this because a `TextInput` the user has
    /// typed into no longer follows a binding.
    signal cleared()

    // --- what the lock calls -------------------------------------------------

    /// Open the conversations. Called when the lock surface comes up.
    function begin() {
        if (priv.begun)
            return;
        priv.begun = true;
        priv.message = "";
        priv.messageIsError = false;
        priv.fingerprintTouches = 0;
        priv.lockedOut = false;
        priv.lockoutSeen = false;
        priv.rearmOnInput = false;
        priv.answered = false;
        priv.conversing = false;
        priv.pendingSubmit = false;
        root.clear();
        // Logged either side of the call, because #81 could not tell from the
        // logs whether the conversation had failed to start or had never been
        // asked to: three silent steps produced one silent lock.
        priv.afterResume = false;
        priv.fingerprintEverEnrolled = false;
        Logger.log("lock", "opening pam conversation (config "
                   + Config.values.system.lock.pamConfig + ")");
        password.start();
        conversationWatchdog.restart();
        root.probeFingerprint();
    }

    /// Put the conversations back, without ending the lock (#188).
    ///
    /// Distinct from `rearm()` below, which is the keystroke re-arm for a
    /// conversation that ended without asking anything: that one reopens the
    /// password context in the state it was left in, where this one throws the
    /// state away. A suspend is not a conversation that went quiet.
    ///
    /// `begin()` cannot do this either. Its guard is there so that a lock surface
    /// re-created mid-lock does not open a second conversation on top of the
    /// first, and that guard is right — but it made the state after a suspend
    /// unreachable, because the session stays locked across the whole thing and
    /// `end()` only runs on unlock. So the machine came back to whatever the
    /// stranded conversations had become, and no code path could say otherwise.
    ///
    /// Everything a fresh `begin()` would clear is cleared here too, minus the
    /// buffer decision: the typed characters are dropped, because a password
    /// half-typed before a lid closed is not something the user is still in the
    /// middle of.
    function rebuildConversations(reason: string): void {
        if (!priv.begun)
            return;
        Logger.log("lock", "rebuilding pam conversations (" + reason + ")");

        // The password half (#188 acceptance 8). Stranded exactly as the
        // fingerprint one is, and the more serious version of the bug: a lock
        // screen that will not take a password after a resume has no other way
        // out.
        conversationWatchdog.stop();
        password.abort();
        priv.conversing = false;
        priv.pendingSubmit = false;
        priv.responseRequired = false;
        priv.responseVisible = false;
        priv.busy = false;
        priv.answered = false;
        priv.rearmOnInput = false;
        root.clear();
        password.start();
        conversationWatchdog.restart();

        root.tearDownFingerprint("rebuilding");
        root.probeFingerprint();
    }

    /// Take the fingerprint conversation down and make sure nothing it says
    /// afterwards can cost anything (#188).
    ///
    /// `fingerprintLive` going false is the load-bearing line. A PAM context
    /// that is aborted while its module is mid-verify still gets to emit — and
    /// after a suspend what it emits is "Failed to match fingerprint", in the
    /// same words a wrong finger produces. Nothing said from here until the
    /// next successful probe is chargeable.
    function tearDownFingerprint(reason: string): void {
        fingerprintProbeRetry.stop();
        priv.fingerprintLive = false;
        if (!priv.fingerprintActive && !priv.fingerprintTouches)
            return;
        fingerprint.abort();
        priv.fingerprintActive = false;
        priv.fingerprintTouches = 0;
        root.clearFingerprintMessage();
        Logger.log("lock", "fingerprint offer torn down (" + reason
                   + ") — touches discarded");
    }

    /// Ask the machine whether there is a finger to read, from the top.
    function probeFingerprint(): void {
        if (!Config.values.system.lock.fingerprint)
            return;
        priv.probeAttempt = 0;
        fingerprintProbe.running = true;
    }

    /// Act on a finished probe — once both halves of it have finished.
    ///
    /// The exit status and the last of stdout arrive on two different signals
    /// with no ordering between them, and the whole point of #188's change is
    /// that the exit status is now part of the answer. So neither signal
    /// decides anything on its own; the second one to arrive calls this.
    function settleProbe(): void {
        if (!priv.probeExited || !priv.probeStreamDone)
            return;
        if (!priv.begun || priv.sleeping)
            return;

        const outcome = policy.fingerprintProbeOutcome(priv.probeExitCode,
                                                       fingerprintProbeOut.text);
        priv.probeAttempt += 1;

        if (outcome === "enrolled") {
            priv.fingerprintEverEnrolled = true;
            priv.fingerprintActive = true;
            priv.fingerprintLive = true;
            priv.fingerprintTouches = 0;
            root.clearFingerprintMessage();
            fingerprint.start();
            Logger.log("lock", "fingerprint enrolled — parallel context started");
            return;
        }

        if (policy.fingerprintProbeShouldRetry(outcome, priv.probeAttempt)) {
            // The settle window (#188). This machine restarts open-fprintd and
            // python-validity on every resume, with `--no-block`, so the bus
            // name the probe wants can still be unowned when logind says we are
            // back. Asking again a moment later is the difference between an
            // offer and a phantom refusal.
            Logger.log("lock", "fingerprint probe could not run (attempt "
                       + priv.probeAttempt + ") — retrying in "
                       + policy.fingerprintProbeRetryMs + "ms");
            fingerprintProbeRetry.restart();
            return;
        }

        // Out of asks, or a machine that answered and has nothing enrolled.
        // Either way there is no offer; the only question left is whether the
        // screen should hear about it.
        Logger.log("lock", "fingerprint probe settled: " + outcome
                   + " after " + priv.probeAttempt + " attempt(s)");
        if (policy.fingerprintProbeSpeaks(outcome, priv.fingerprintEverEnrolled,
                                          priv.afterResume)) {
            // Said once, promptly, and with no fake failure in front of it —
            // which is the whole of what the shell can fix if the reader really
            // does not come back (#188 acceptance 1).
            priv.fingerprintActive = true;
            priv.fingerprintLive = false;
            root.withdrawFingerprint(false);
        }
    }

    /// Close them again, on unlock or when the shell is going away. PAM
    /// contexts left running would hold a conversation open against a session
    /// that no longer has a lock on it.
    function end() {
        priv.begun = false;
        priv.conversing = false;
        priv.pendingSubmit = false;
        conversationWatchdog.stop();
        password.abort();
        fingerprint.abort();
        fingerprintProbeRetry.stop();
        priv.fingerprintActive = false;
        // Nothing an aborted context says on its way out may be charged (#188).
        priv.fingerprintLive = false;
        root.clearFingerprintMessage();
        // The latch dies with the lock it was raised on (#164). Both success
        // paths — password and fingerprint — come through here, and a lockout
        // promoted mid-conversation would otherwise stand until the next
        // `begin()` cleared it: a fingerprint can let someone in while
        // pam_faillock is still refusing their password.
        //
        // Logged for the same reason #161 logged the raising: from a real
        // session's log, "heard a lockout" and "still showing one" are two
        // different questions, and a flag that is only ever set in the log
        // answers neither.
        if (priv.lockedOut)
            Logger.log("lock", "faillock lockout dropped with the lock");
        priv.lockedOut = false;
        priv.lockoutSeen = false;
        root.clear();
    }

    /// Answer the password prompt. Every outcome is visible: this is the
    /// function that used to return silently when PAM had not asked yet, which
    /// is how #81 turned a lock into a lockout — Enter did nothing, said
    /// nothing, and the only door out of a secure lock is through here.
    function submit() {
        switch (policy.submitOutcome(priv.begun, priv.conversing,
                                     priv.responseRequired, priv.busy)) {
        case "send":
            root.send();
            return;
        case "hold":
            // Keep the attempt and answer the prompt when it arrives. The
            // field shows busy meanwhile, so Enter visibly did *something*,
            // and the watchdog below turns a prompt that never comes into a
            // message rather than into silence.
            priv.pendingSubmit = true;
            priv.busy = true;
            conversationWatchdog.restart();
            Logger.log("lock", "enter held — no prompt open yet");
            return;
        case "stalled":
            root.stall("enter with no conversation at all");
            return;
        }
        // "wait" — an answer is already in flight. The field is read-only and
        // the horizon is lit; pressing Enter again is not a second attempt.
    }

    // The actual send, shared by Enter and by a held attempt being flushed.
    function send() {
        const response = root.buffer;
        root.clear();
        priv.pendingSubmit = false;
        priv.busy = true;
        priv.answered = true;
        priv.message = "";
        conversationWatchdog.stop();
        password.respond(response);
    }

    // A lock that cannot authenticate is the one bug that strands a user, so it
    // is never allowed to look like a lock that is thinking.
    function stall(why: string) {
        priv.pendingSubmit = false;
        priv.busy = false;
        priv.message = policy.stalledText();
        priv.messageIsError = true;
        Logger.warn("lock", "no pam conversation to answer — " + why);
        root.failed();
    }

    /// Called by the surface on every keystroke. Almost always a no-op — the
    /// one case it exists for is a conversation that ended without ever asking
    /// us anything, which is what a locked-out account looks like from here.
    /// Re-arming that on a timer would spin against faillock; re-arming it on
    /// the keystroke that means someone is standing there costs one PAM start
    /// and is what keeps the field from going dead for good.
    function rearm() {
        if (!priv.begun || !priv.rearmOnInput || priv.busy)
            return;
        priv.rearmOnInput = false;
        priv.answered = false;
        password.start();
        conversationWatchdog.restart();
    }

    function clear() {
        root.buffer = "";
        root.cleared();
    }

    /// Forget the last message, so the surface can go quiet again. Refuses to
    /// forget a lockout: that message is the only place the user can read that
    /// the account is locked at all, and hiding it after a timeout would leave
    /// them typing into a field that cannot succeed.
    function clearMessage() {
        if (root.lockedOut)
            return;
        priv.message = "";
        priv.messageIsError = false;
    }

    /// Take one thing PAM said: latch it if it is a lockout, show it if it is
    /// worth showing.
    ///
    /// The latch is #161. pam_faillock speaks twice per refusal — "Account
    /// locked due to N failed logins", then "(10 minutes left to unlock)" — and
    /// only the first reads as a lockout. `message` remembers whichever came
    /// last, so the completed attempt has to ask this flag instead, or a real
    /// lockout completes as an ordinary failure: white text that the idle
    /// retreat then clears.
    ///
    /// The showing rule is unchanged: the prompt itself ("Password: ") is not
    /// worth showing, because the field is the prompt. Anything else PAM says
    /// is.
    ///
    /// A separate function because it is also the seam the nested harness
    /// drives (`locktest say`): a two-message refusal takes a real faillock
    /// lockout to produce, which is the one thing a harness must not do to the
    /// machine it is running on.
    function noteMessage(text: string, isError: bool, isPrompt: bool): void {
        root.latchLockout(text);
        if (policy.worthShowing(text, isError, isPrompt)) {
            priv.message = text;
            priv.messageIsError = isError;
        }
    }

    /// Remember that faillock has refused, for the rest of this conversation —
    /// and say so on screen from this moment rather than from the completion of
    /// whatever attempt is in flight.
    ///
    /// Split out of `noteMessage` because it is the half that cannot wait: the
    /// message handler below returns early on a held Enter, and a lockout heard
    /// on that path would otherwise be forgotten before the attempt completes.
    ///
    /// Presentation is promoted here too (#164). faillock announces a locked
    /// account in pam_faillock's *preauth* phase — before pam_unix puts up the
    /// password prompt — so leaving `lockedOut` for `onCompleted` left the whole
    /// span in which the user types their password believing the account was
    /// open: the lockout line came up `quiet` (a pam_info is not a
    /// `PAM_ERROR_MSG`, so `messageTone` had nothing else to go on) and
    /// `clearMessage` was free to retreat it. That window is however long
    /// someone takes to type, and it is exactly the window in which they are
    /// deciding whether to bother.
    ///
    /// `onCompleted` re-decides this flag below and is not fighting this: it
    /// passes `lockoutSeen`, which is still true when it asks.
    function latchLockout(text: string): void {
        if (priv.lockoutSeen || !policy.isLockout(text))
            return;
        priv.lockoutSeen = true;
        priv.lockedOut = true;
        // Logged because #161 was diagnosed from a log that could not
        // distinguish "faillock never said it" from "we did not hear it":
        // ~60 attempts, every one logged `password attempt failed`.
        Logger.log("lock", "faillock lockout recognised in a pam message");
    }

    /// Take one thing the fingerprint conversation said, and decide whether it
    /// may replace what is already on that line.
    ///
    /// It cannot simply be an assignment (#168). Driven directly on hardware,
    /// pam_fprintd re-prompts 9.7ms after it reports a failed match — less than
    /// one frame at 60Hz — so the last message always won and the last message
    /// is always the re-prompt. A wrong finger and a finger the reader never
    /// saw were the same screen, which leaves nothing to suggest trying a
    /// different finger.
    ///
    /// So a failure holds the line for `fingerprintErrorDwellMs`, and a message
    /// that loses is *held* rather than dropped: the timer below puts it up
    /// when the dwell expires, so the reader's prompt still comes back. Which
    /// message wins is LockPolicy's decision — the seam it can be tested at.
    function noteFingerprintMessage(text: string, isError: bool): void {
        if (!text)
            return;
        // Counted here rather than at the close, because the close is handed a
        // result and never sees the messages: the module's re-prompts happen
        // inside the conversation, so the messages are the only place the
        // touches are visible (#169).
        // Two things can stop this counting (#188). The prose, where the reader
        // admits it is missing; and `fingerprintLive`, for the case where it
        // does not — a conversation stranded across a suspend says "Failed to
        // match fingerprint" in the wrong finger's exact words while the
        // sensor's light never comes on, so the transcript cannot be read and
        // the lifecycle has to answer instead.
        if (policy.fingerprintTouchCharged(text, priv.fingerprintLive))
            priv.fingerprintTouches += 1;
        else if (priv.fingerprintActive && policy.fingerprintTouchMissed(text))
            Logger.log("lock", "fingerprint failure not charged — offer is not live");
        const sinceMs = Date.now() - priv.fingerprintMessageAt;
        if (policy.fingerprintMessageWins(priv.fingerprintMessageIsError,
                                          sinceMs, isError)) {
            fingerprintDwell.stop();
            priv.fingerprintHeld = "";
            root.showFingerprintMessage(text, isError);
            return;
        }
        priv.fingerprintHeld = text;
        priv.fingerprintHeldIsError = isError;
        fingerprintDwell.interval = policy.fingerprintDwellRemainingMs(sinceMs);
        fingerprintDwell.restart();
        // Logged for #81's reason: this is a new lifecycle — a message
        // suppressed now and put up as much as a dwell later — and on hardware
        // a fingerprint line stuck on a stale failure and a fingerprint line
        // nothing ever sent to are the same screen without this.
        Logger.log("lock", "fingerprint message held " + fingerprintDwell.interval
                   + "ms behind a failure");
    }

    /// Put a fingerprint message on screen, remembering what it was and when —
    /// both of which the next message has to ask about.
    function showFingerprintMessage(text: string, isError: bool): void {
        priv.fingerprintMessage = text;
        priv.fingerprintMessageIsError = isError;
        priv.fingerprintMessageAt = Date.now();
    }

    /// Take the fingerprint line down, including anything waiting to go up on
    /// it. Called wherever the conversation stops existing — a message flushed
    /// onto a closed context would be a line about a reader nothing is reading.
    function clearFingerprintMessage(): void {
        fingerprintDwell.stop();
        priv.fingerprintHeld = "";
        priv.fingerprintHeldIsError = false;
        priv.fingerprintMessage = "";
        priv.fingerprintMessageIsError = false;
        priv.fingerprintMessageAt = 0;
    }

    /// End the fingerprint offer, and leave a line saying so (#169).
    ///
    /// The line deliberately outlives the conversation. Closing used to take it
    /// down, which left the reader's light as the only word on the subject —
    /// and that light is the hardware's, not the shell's. It stands until the
    /// lock ends or is taken down and put back up, both of which come through
    /// `end()` and clear it there.
    function withdrawFingerprint(spentBudget: bool): void {
        if (!priv.fingerprintActive)
            return;
        priv.fingerprintActive = false;
        // The queued message goes, but the dwell does not (#168): the touch
        // that spent the budget is a failure like any other, and withdrawing
        // on top of it would wipe the last one inside a frame — the exact
        // thing #168 fixed, re-created by the fix for #169. So the closing
        // line goes through the same arbitration every other message does, and
        // waits out whatever is left of the failure's spell.
        fingerprintDwell.stop();
        priv.fingerprintHeld = "";
        priv.fingerprintHeldIsError = false;
        root.noteFingerprintMessage(policy.fingerprintClosingMessage(spentBudget),
                                    false);
        // #81's rule, and the one line that carries the module's real budget:
        // logged here rather than at the completion because this is the state
        // change — every way the offer ends comes through this function, and a
        // withdrawal that left no trace is how #169 went a week looking like a
        // dead reader. Says "offer withdrawn" and not "conversation closed",
        // because the error path below withdraws an offer whose conversation
        // never opened.
        Logger.log("lock", "fingerprint offer withdrawn after "
                   + priv.fingerprintTouches + " touch(es) ("
                   + (spentBudget ? "budget spent" : "budget not spent") + ")");
    }

    /// Pose the failure path rather than produce it (#96).
    ///
    /// A real refusal takes a real PAM stack, a real keyboard and a compositor
    /// that presents — the capture seam has none of the three, and the nested
    /// one never presents (#85). But the *picture* of a refusal is five
    /// presentation flags, each one written from the far side of a PAM callback
    /// the harness cannot reach, so the harness writes them here instead. Same
    /// trick as `tools/lock-harness.sh` writing `buffer` to stand in for typing.
    ///
    /// Nothing in the shell calls this, and nothing it sets can let anyone in:
    /// `lockedOut` is presentation only (#30) and the rest is text. The pose is
    /// logged so a photographed lockout can never be read back as a real one.
    function pose(fields: var): void {
        if (fields.message !== undefined)
            priv.message = fields.message;
        if (fields.messageIsError !== undefined)
            priv.messageIsError = fields.messageIsError;
        if (fields.lockedOut !== undefined)
            priv.lockedOut = fields.lockedOut;
        if (fields.fingerprintActive !== undefined)
            priv.fingerprintActive = fields.fingerprintActive;
        // Poseable because the count is what the close reports, and a posed
        // offer that inherited a previous one's tally would put a number in the
        // log that no conversation ever spent (#169).
        if (fields.fingerprintTouches !== undefined)
            priv.fingerprintTouches = fields.fingerprintTouches;
        // Posed alongside `fingerprintActive`, because after #188 those are two
        // different facts: an offer can be on screen and not chargeable, which
        // is exactly the state a suspend leaves behind.
        if (fields.fingerprintLive !== undefined)
            priv.fingerprintLive = fields.fingerprintLive;
        // Through the same door a real message uses, so a posed one is not a
        // message with no stamp beside it (#168): `fingerprintMessageAt` is
        // what the *next* message asks about, and two writers of one state
        // where only one keeps the books is how an invariant survives by
        // accident.
        if (fields.fingerprintMessage !== undefined)
            root.showFingerprintMessage(fields.fingerprintMessage,
                                        fields.fingerprintMessageIsError === true);
        Logger.log("lock", "posed " + JSON.stringify(fields));
    }

    // --- the conversations ---------------------------------------------------
    //
    // Declared as plain children: `Scope`'s default property is `children`, and
    // none of these is a visible Item, which is the one thing a Scope may not
    // hold.

    LockPolicy { id: policy }

    PamContext {
        id: password

        // The distro's own stack (#30). Overridable because "login" is an
        // Arch/Debian assumption rather than a law, but it is not a knob anyone
        // should need to touch.
        config: Config.values.system.lock.pamConfig
        configDirectory: "/etc/pam.d"

        onPamMessage: {
            if (!priv.conversing) {
                priv.conversing = true;
                Logger.log("lock", "pam conversation open");
            }
            priv.responseRequired = password.responseRequired;
            priv.responseVisible = password.responseVisible;
            // Before anything can return past it (#161). Only the latch is
            // hoisted: what gets *shown* stays where it was, on the far side of
            // the held-Enter return below.
            root.latchLockout(password.message);
            if (password.responseRequired) {
                conversationWatchdog.stop();
                // An Enter that arrived before the prompt did. Sending it here
                // rather than making the user type it again is the difference
                // between a lock that feels instant and one that eats the first
                // attempt of every unlock.
                if (priv.pendingSubmit) {
                    root.send();
                    return;
                }
            }
            root.noteMessage(password.message, password.messageIsError,
                             password.responseRequired);
            if (password.responseRequired)
                priv.busy = false;
        }

        onCompleted: result => {
            priv.busy = false;
            priv.responseRequired = false;
            // The next attempt needs its own prompt, so this is a fresh
            // conversation again as far as Enter is concerned.
            priv.conversing = false;

            if (result === PamResult.Success) {
                Logger.log("lock", "authenticated (password)");
                root.end();
                SessionLock.unlock();
                return;
            }

            const kind = result === PamResult.MaxTries ? "maxTries"
                       : result === PamResult.Error ? "error" : "failed";
            priv.message = policy.failureText(kind, password.message);
            priv.messageIsError = true;
            priv.lockedOut = policy.lockedOutBy(kind, priv.message,
                                                priv.lockoutSeen);
            // Spent: the next attempt is its own conversation and has to earn
            // its own lockout. faillock repeats itself while the account is
            // locked, so nothing is lost by not carrying this across.
            priv.lockoutSeen = false;
            Logger.log("lock", "password attempt " + kind
                       + (priv.lockedOut ? " (faillock: locked out)" : ""));
            root.failed();

            // Re-arm for the next attempt. The limit is faillock's — it keeps
            // refusing, and its refusal is what the user reads. The only
            // question is *when*: immediately if the user answered, and
            // otherwise on their next keystroke, because a conversation that
            // completed without prompting would complete again just as fast.
            if (!priv.begun)
                return;
            const rearm = policy.rearmWhen(kind, priv.answered);
            priv.answered = false;
            if (rearm === "now") {
                password.start();
                conversationWatchdog.restart();
            } else {
                priv.rearmOnInput = rearm === "onInput";
            }
        }

        onError: error => {
            // Distinct from a failed authentication: this is pam itself not
            // working. Logged loudly, because a lock screen that cannot
            // authenticate is the one bug that strands a user.
            Logger.warn("lock", "pam error: " + error);
        }
    }

    // The latent second conversation (#30). Never started unless the probe
    // below finds a finger enrolled to answer it with.
    PamContext {
        id: fingerprint

        config: Config.values.system.lock.fingerprintPamConfig
        configDirectory: "/etc/pam.d"

        onPamMessage: root.noteFingerprintMessage(fingerprint.message,
                                                  fingerprint.messageIsError)

        onCompleted: result => {
            if (result === PamResult.Success) {
                Logger.log("lock", "authenticated (fingerprint)");
                root.end();
                SessionLock.unlock();
                return;
            }

            // This conversation was the whole offer (#169). pam_fprintd spent
            // its own re-prompts inside it, so there is nothing left to re-arm
            // — the shell used to try, behind a branch that excluded
            // PAM_MAXTRIES and was therefore never taken.
            const maxTries = result === PamResult.MaxTries;
            // Named the way the password path above names its results, because
            // #188 was the fingerprint path having no name for the error one at
            // all: `PamResult.Error` fell through to the count, so a reader that
            // was never asked closed with "Out of fingerprint tries".
            const kind = maxTries ? "maxTries"
                       : result === PamResult.Error ? "error" : "failed";
            // Logged either side of the withdrawal, as `begin()` is: what PAM
            // said and what the surface did about it are two facts, and a
            // result with no withdrawal beside it is the pair #81 needed.
            Logger.log("lock", "fingerprint pam result " + result + " (" + kind + ")");
            priv.fingerprintLive = false;
            root.withdrawFingerprint(
                policy.fingerprintClosedSpent(kind, priv.fingerprintTouches));
            // The budget is a number in someone else's config file, so notice
            // out loud when the module stops spending the one we document.
            if (maxTries && priv.fingerprintTouches !== policy.fingerprintTouchBudget)
                Logger.warn("lock", "pam_fprintd spent " + priv.fingerprintTouches
                            + " touch(es), not the " + policy.fingerprintTouchBudget
                            + " LockPolicy documents");
        }

        onError: error => {
            // The likely one by far is StartFailed: fprintd is installed but
            // its pam config is not where we looked. Not worth shouting about —
            // the password field is right there, and now says so.
            priv.fingerprintLive = false;
            root.withdrawFingerprint(false);
            Logger.log("lock", "fingerprint unavailable (pam error " + error + ")");
        }
    }

    // Is there a finger to read? Asked at lock time rather than at startup,
    // because enrolment can change while the shell runs and because a
    // subprocess on the path to the first frame is exactly what staged startup
    // exists to prevent (#12 §4).
    Process {
        id: fingerprintProbe

        command: ["fprintd-list", Quickshell.env("USER") ?? ""]

        onRunningChanged: {
            if (!fingerprintProbe.running)
                return;
            priv.probeExited = false;
            priv.probeStreamDone = false;
            priv.probeExitCode = 0;
        }

        // The exit status is half the answer now (#188): "ran and found
        // nothing" and "could not reach the bus" both leave stdout empty, and
        // only one of them means this machine has no reader.
        onExited: (exitCode, exitStatus) => {
            priv.probeExitCode = exitCode;
            priv.probeExited = true;
            root.settleProbe();
        }

        stdout: StdioCollector {
            id: fingerprintProbeOut
            onStreamFinished: {
                priv.probeStreamDone = true;
                root.settleProbe();
            }
        }
    }

    // The other half of the settle window (#188). Separate from the probe so
    // that a teardown can stop it: a retry that fires after a sleep has been
    // announced would open an offer into a suspend, which is the bug.
    Timer {
        id: fingerprintProbeRetry
        interval: policy.fingerprintProbeRetryMs
        onTriggered: {
            if (!priv.begun || priv.sleeping)
                return;
            fingerprintProbe.running = true;
        }
    }

    // #188: the two ends of a suspend, heard from the bridge that already
    // announces them. Referencing LogindBridge here is also what brings the
    // singleton up in a harness that would otherwise never touch it, which is
    // how seam 2 gets to drive `logind sleep` and `logind resume` against a
    // lock surface.
    Connections {
        target: LogindBridge

        // Inside logind's delay lock, before the lock surface exists. Whatever
        // is standing here is what gets carried into the suspend, so nothing
        // fingerprint-shaped is left standing.
        function onSleeping(): void {
            priv.sleeping = true;
            Logger.log("lock", "sleep announced — standing conversations down");
            fingerprintProbeRetry.stop();
            root.tearDownFingerprint("sleep announced");
        }

        // The machine is back, and the session was locked the whole time — so
        // `begin()` was never going to run again and its guard was never going
        // to let it.
        function onResumed(): void {
            priv.sleeping = false;
            if (!priv.begun)
                return;
            priv.afterResume = true;
            Logger.log("lock", "resume observed — re-arming the lock conversations");
            root.rebuildConversations("resume");
        }
    }

    // The lock's own dead-man's switch (#81). A conversation that opens and is
    // never asked anything looks exactly like a conversation that is thinking,
    // and the user has no way to tell them apart and nowhere to go if they
    // guess wrong. Started whenever a conversation is opened or an attempt is
    // held; stopped by the first prompt.
    Timer {
        id: conversationWatchdog

        interval: policy.conversationTimeoutMs
        onTriggered: {
            if (!priv.begun || priv.conversing)
                return;
            root.stall("no prompt within " + policy.conversationTimeoutMs + "ms of starting");
        }
    }

    // The other half of the dwell (#168): the message that was held while a
    // failure was being read, put up once the failure has had its spell. Its
    // interval is set at the moment something loses, because what is left of
    // the dwell depends on when the failure landed.
    Timer {
        id: fingerprintDwell
        onTriggered: {
            if (!priv.fingerprintHeld)
                return;
            root.showFingerprintMessage(priv.fingerprintHeld,
                                        priv.fingerprintHeldIsError);
            priv.fingerprintHeld = "";
            priv.fingerprintHeldIsError = false;
        }
    }

    QtObject {
        id: priv

        property bool begun: false
        property bool busy: false
        property bool conversing: false
        property bool responseRequired: false
        property bool responseVisible: false
        property string message: ""
        property bool messageIsError: false
        property bool lockedOut: false

        // The latch (#161): any message in the running conversation that read
        // as faillock's refusal, remembered until that conversation completes.
        // Not the same thing as `lockedOut`, which is what the completed
        // attempt decided and what the surface reads.
        property bool lockoutSeen: false

        // Whether we answered the conversation that is running, and whether the
        // last one ended unanswered and is waiting for a keystroke to reopen.
        property bool answered: false
        property bool rearmOnInput: false

        // An Enter that landed before PAM had asked anything, waiting for the
        // prompt it will answer.
        property bool pendingSubmit: false

        property bool fingerprintActive: false
        property string fingerprintMessage: ""

        // Wrong touches spent in the conversation that is running (#169).
        // Counted rather than assumed: the budget belongs to pam_fprintd, so
        // the only way to notice it changing is to keep the module's own tally
        // beside the number LockPolicy documents.
        property int fingerprintTouches: 0

        // #188. `fingerprintLive` is the one that stops a touch being charged:
        // an offer is live only between a probe that found a finger and the
        // conversation ending, and a suspend takes it out of that window from
        // the moment logind says the machine is going. `sleeping` covers the
        // gap in between, when the lock is being raised *into* a suspend and
        // must not arm anything. `afterResume` and `fingerprintEverEnrolled`
        // are what let a failed probe stay quiet on a desktop that has no
        // reader and speak up on a laptop whose reader just went away.
        property bool fingerprintLive: false
        property bool sleeping: false
        property bool afterResume: false
        property bool fingerprintEverEnrolled: false

        // The probe's two halves and its attempt count — see `settleProbe`.
        property int probeAttempt: 0
        property int probeExitCode: 0
        property bool probeExited: false
        property bool probeStreamDone: false

        // The dwell (#168): what the fingerprint line is saying and when it
        // started saying it, plus whatever arrived too soon to replace it.
        // `fingerprintMessageAt` is a wall-clock stamp rather than a Timer's
        // remaining time, because the question a new message asks is how long
        // the *current* one has been up.
        property bool fingerprintMessageIsError: false
        property real fingerprintMessageAt: 0
        property string fingerprintHeld: ""
        property bool fingerprintHeldIsError: false
    }
}
