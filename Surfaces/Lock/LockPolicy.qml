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

    /// Whether to start another authentication attempt after this result.
    ///
    /// A wrong password is the normal case and gets another try immediately —
    /// the retry limit is faillock's, not ours. `maxTries` is PAM saying this
    /// method is spent, and `error` means the conversation never really
    /// happened; re-arming either would spin.
    function retryable(kind: string): bool {
        return kind === "failed";
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

    // The one serif touch in the shell (#8: Newsreader Light, clock only, used
    // once and never twice). Format strings live here rather than at the call
    // site so they are testable, and because the weather-and-time ticket (#50)
    // owns clock formatting for real — when it lands with a `weatherTime` key
    // it replaces `use24Hour` below, and nothing else about this file changes.
    function timeFormat(use24Hour: bool): string {
        return use24Hour ? "HH:mm" : "h:mm AP";
    }

    readonly property string dateFormat: "dddd, d MMMM"

    /// Whether the user's locale writes time on a 24-hour clock, read off the
    /// locale's own short-time format rather than a config key we would then
    /// have to migrate when #50 adds the real one.
    ///
    /// Qt time formats are built from h/H/m/s/z, t for the zone and AP/ap for
    /// the meridiem, so the presence of an `a` is exactly the 12-hour signal.
    function use24Hour(localeTimeFormat: string): bool {
        return !localeTimeFormat || localeTimeFormat.toLowerCase().indexOf("a") < 0;
    }

    // --- battery -------------------------------------------------------------

    // The lid is usually shut between locking and unlocking, so the first thing
    // worth knowing on waking a locked laptop is whether it is still on mains.
    // Shown only while discharging — on AC it is noise (#30).

    /// `UPowerDevice.percentage` is a 0–1 fraction (energy / energyCapacity),
    /// not 0–100. Clamped, because a battery reporting 101% should not widen
    /// the pill.
    function batteryPercent(fraction: real): int {
        if (!isFinite(fraction))
            return 0;
        return Math.round(Math.max(0, Math.min(1, fraction)) * 100);
    }

    // Below this the pill turns ember — the "plug me in before you walk away"
    // threshold, matched to the point where suspend-on-battery becomes a real
    // risk to unsaved work.
    readonly property real batteryLowFraction: 0.20

    function batteryLow(fraction: real): bool {
        return isFinite(fraction) && fraction <= batteryLowFraction;
    }
}
