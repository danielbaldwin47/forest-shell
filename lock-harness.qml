// A shell root that is *only* the lock, plus a way to drive it from a script
// (#81).
//
// The lock is the one surface that cannot be tested by using it: a lock that
// will not open costs the session it is running on. So it is tested inside a
// nested Hyprland — tools/lock-harness.sh brings one up, runs this config in
// it, and talks to the `locktest` handler below. A lock that will not open is
// then a window that can be closed.
//
// This is a harness, not a shell: shell.qml never loads it, and the `locktest`
// IPC target exists nowhere else. Everything under test — Lock.qml's lifecycle,
// LockAuth's conversation, the surface — is the real code, unmodified.
//
// A second entry point at the repo root rather than a file under `tools/`, for
// gallery.qml's reason: Quickshell takes the entry point's directory as the
// config root, and only from here does `qs.Surfaces.Lock` resolve to the real
// lock.
//
//   qs -p lock-harness.qml   # inside the nested display
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Surfaces.Lock
import qs.Services.System

ShellRoot {
    id: harness

    Component.onCompleted: Logger.log("harness", "lock harness ready");

    Lock { id: lock }

    // Standing in for a keyboard, because there is no keyboard to stand in for:
    // the nested compositor has no seat we can type into from a script, and the
    // lock takes keys through a `TextInput` on a session-lock surface. So the
    // buffer is written and `submit()` called directly — the same two things a
    // keystroke and an Enter do.
    //
    // What that does *not* cover is focus: whether the field would have
    // received the keystroke at all. Lock.qml logs that separately
    // (`lock: field focus …`) precisely because this seam cannot see it.
    IpcHandler {
        target: "locktest"

        /// Type into the shared buffer, as a keystroke would.
        function type(text: string): bool {
            lock.auth.buffer = text;
            return true;
        }

        /// Press Enter, as the field's `onAccepted` would.
        function enter(): bool {
            lock.auth.submit();
            return true;
        }

        /// Say something to the lock as PAM would, mid-conversation (#161).
        ///
        /// The message faillock sends first — "Account locked due to N failed
        /// logins" — only arrives after N real failed logins against the real
        /// account of whoever is running this, which is the one experiment a
        /// harness must not perform on its own machine. So the script speaks
        /// faillock's lines and the real `noteMessage` hears them; the
        /// completion that follows is a real PAM completion.
        ///
        /// It cannot let anyone in: the only state it reaches is the message
        /// under the field and the lockout latch, and a latched lockout makes
        /// the lock *refuse* harder (#30 — `lockedOut` is presentation).
        ///
        /// Not an error message, which is faillock's own doing: it announces a
        /// locked account with `pam_info` and not `PAM_ERROR_MSG`. Said as an
        /// error here, the harness would hand the surface a colour the real
        /// thing never gives it, and #164 — a lockout dressed `quiet` for as
        /// long as it takes to type a password — would be unreachable from this
        /// seam.
        function say(text: string): bool {
            lock.auth.noteMessage(text, false, false);
            return true;
        }

        /// Say something to the lock as *fprintd* would (#168).
        ///
        /// Same argument as `say` above, for a different unreachable thing: the
        /// fingerprint conversation needs a reader and a finger, so no nested
        /// session can produce one. But which of two messages the surface ends
        /// up showing is decided in `noteFingerprintMessage`, and that hears
        /// text — so the script replays the two lines the hardware trace
        /// recorded, 9.7ms apart, and the real arbitration answers them.
        ///
        /// `isError` is real here, unlike faillock's: pam_fprintd reports a
        /// failed match as a `PAM_ERROR_MSG`, which is the whole reason the
        /// decision has a flag to go on.
        function fingersay(text: string, isError: bool): bool {
            lock.auth.noteFingerprintMessage(text, isError);
            return true;
        }

        /// Open the fingerprint offer, as the enrolment probe does (#169).
        ///
        /// The probe runs `fprintd-list` against a reader this seam does not
        /// have, so the offer can only be posed — but everything after it is
        /// real: the touch count, the arbitration, and the withdrawal below all
        /// run on the offer being open.
        /// `fingerprintLive` is posed too since #188: an offer that is on
        /// screen and an offer that may charge the user a touch stopped being
        /// the same fact when a suspend was found to leave one without the
        /// other.
        function fingeroffer(): bool {
            lock.auth.pose({
                fingerprintActive: true,
                fingerprintLive: true,
                fingerprintTouches: 0
            });
            return true;
        }

        /// Close it again, as a completed or failed PAM conversation does.
        ///
        /// `spent` is the difference between the budget running out and the
        /// context never getting started, which is the one thing the closing
        /// line has to get right. The withdrawal itself is real: what #169 was
        /// about is that the line has to survive the conversation that put it
        /// there, and that survival is what a script can watch.
        function fingerwithdraw(spent: bool): bool {
            lock.auth.withdrawFingerprint(spent);
            return true;
        }

        /// The clearing half of the idle retreat, which is what took #161's
        /// lockout off the screen. Called from here because the retreat itself
        /// is a timer on the surface and this seam cannot wait one out; the
        /// surface checks `lockedOut` again before it gets this far, so a
        /// message that survives this call survives the real retreat too.
        function clearmessage(): bool {
            lock.auth.clearMessage();
            return true;
        }

        /// Everything a script needs to assert on, in one round trip.
        function state(): string {
            return JSON.stringify({
                locked: SessionLock.locked,
                secure: SessionLock.secure,
                busy: lock.auth.busy,
                buffer: lock.auth.buffer,
                message: lock.auth.message,
                messageIsError: lock.auth.messageIsError,
                lockedOut: lock.auth.lockedOut,
                conversing: lock.auth.conversing,
                fingerprintMessage: lock.auth.fingerprintMessage,
                fingerprintActive: lock.auth.fingerprintActive,
                // #188: the claim a suspend/resume run makes is about the
                // count. An offer rebuilt with touches already on it and a good
                // rebuild look identical without these two.
                fingerprintTouches: lock.auth.fingerprintTouches,
                fingerprintLive: lock.auth.fingerprintLive
            });
        }
    }
}
