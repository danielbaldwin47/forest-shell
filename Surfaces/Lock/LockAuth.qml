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
        priv.fingerprintRestarts = 0;
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
        Logger.log("lock", "opening pam conversation (config "
                   + Config.values.system.lock.pamConfig + ")");
        password.start();
        conversationWatchdog.restart();
        if (Config.values.system.lock.fingerprint)
            fingerprintProbe.running = true;
    }

    /// Close them again, on unlock or when the shell is going away. PAM
    /// contexts left running would hold a conversation open against a session
    /// that no longer has a lock on it.
    function end() {
        priv.begun = false;
        priv.conversing = false;
        priv.pendingSubmit = false;
        conversationWatchdog.stop();
        fingerprintRetry.stop();
        password.abort();
        fingerprint.abort();
        priv.fingerprintActive = false;
        priv.fingerprintMessage = "";
        // The latch dies with the lock it was raised on (#164). Both success
        // paths — password and fingerprint — come through here, and a lockout
        // promoted mid-conversation would otherwise stand until the next
        // `begin()` cleared it: a fingerprint can let someone in while
        // pam_faillock is still refusing their password.
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
        if (fields.fingerprintMessage !== undefined)
            priv.fingerprintMessage = fields.fingerprintMessage;
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

        onPamMessage: {
            if (fingerprint.message)
                priv.fingerprintMessage = fingerprint.message;
        }

        onCompleted: result => {
            if (result === PamResult.Success) {
                Logger.log("lock", "authenticated (fingerprint)");
                root.end();
                SessionLock.unlock();
                return;
            }

            // A finger landing crooked is the normal case, so re-arm — but on a
            // cooldown and only so many times, so a reader that has started
            // failing every time does not spin (#22 §5).
            priv.fingerprintRestarts += 1;
            if (priv.begun && result !== PamResult.MaxTries
                    && priv.fingerprintRestarts < policy.fingerprintMaxRestarts) {
                fingerprintRetry.restart();
            } else {
                priv.fingerprintActive = false;
                priv.fingerprintMessage = "";
                Logger.log("lock", "fingerprint conversation closed after "
                           + priv.fingerprintRestarts + " attempt(s)");
            }
        }

        onError: error => {
            // The likely one by far is StartFailed: fprintd is installed but
            // its pam config is not where we looked. Not worth shouting about —
            // the password field is right there.
            priv.fingerprintActive = false;
            priv.fingerprintMessage = "";
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

        stdout: StdioCollector {
            onStreamFinished: {
                if (!priv.begun || !policy.fingerprintEnrolled(this.text))
                    return;
                priv.fingerprintActive = true;
                priv.fingerprintRestarts = 0;
                fingerprint.start();
                Logger.log("lock", "fingerprint enrolled — parallel context started");
            }
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

    Timer {
        id: fingerprintRetry
        interval: policy.fingerprintRetryDelayMs
        onTriggered: if (priv.begun && priv.fingerprintActive) fingerprint.start()
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
        property int fingerprintRestarts: 0
    }
}
