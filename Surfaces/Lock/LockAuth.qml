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

    /// The last thing PAM said about the password, shown verbatim under the
    /// field. Empty means say nothing.
    readonly property alias message: priv.message
    readonly property alias messageIsError: priv.messageIsError

    /// faillock reporting a locked account. Presentation only: it paints the
    /// message ember and keeps it on screen. The shell does not act on it, has
    /// no idea how long it lasts, and never counts anything itself.
    readonly property bool lockedOut: policy.isLockout(priv.message)

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
        root.clear();
        password.start();
        if (Config.values.system.lock.fingerprint)
            fingerprintProbe.running = true;
    }

    /// Close them again, on unlock or when the shell is going away. PAM
    /// contexts left running would hold a conversation open against a session
    /// that no longer has a lock on it.
    function end() {
        priv.begun = false;
        fingerprintRetry.stop();
        password.abort();
        fingerprint.abort();
        priv.fingerprintActive = false;
        priv.fingerprintMessage = "";
        root.clear();
    }

    /// Answer the password prompt. A no-op unless PAM is actually asking —
    /// pressing Enter into a conversation that is mid-answer must not queue a
    /// second response.
    function submit() {
        if (!priv.responseRequired || priv.busy)
            return;
        const response = root.buffer;
        root.clear();
        priv.busy = true;
        priv.message = "";
        password.respond(response);
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
            priv.responseRequired = password.responseRequired;
            priv.responseVisible = password.responseVisible;
            // The prompt itself ("Password: ") is not worth showing — the field
            // is the prompt. Anything else PAM says is.
            if (password.message && (password.messageIsError || !password.responseRequired)) {
                priv.message = password.message;
                priv.messageIsError = password.messageIsError;
            }
            if (password.responseRequired)
                priv.busy = false;
        }

        onCompleted: result => {
            priv.busy = false;
            priv.responseRequired = false;

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
            Logger.log("lock", "password attempt " + kind
                       + (root.lockedOut ? " (faillock: locked out)" : ""));
            root.failed();

            // Re-arm for the next attempt. The limit is faillock's — it keeps
            // refusing through this same conversation, and its refusal is what
            // the user reads.
            if (priv.begun && policy.retryable(kind))
                password.start();
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

    Timer {
        id: fingerprintRetry
        interval: policy.fingerprintRetryDelayMs
        onTriggered: if (priv.begun && priv.fingerprintActive) fingerprint.start()
    }

    QtObject {
        id: priv

        property bool begun: false
        property bool busy: false
        property bool responseRequired: false
        property bool responseVisible: false
        property string message: ""
        property bool messageIsError: false

        property bool fingerprintActive: false
        property string fingerprintMessage: ""
        property int fingerprintRestarts: 0
    }
}
