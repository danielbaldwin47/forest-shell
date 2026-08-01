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
//   qs-upstream -p lock-harness.qml   # inside the nested display
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
                conversing: lock.auth.conversing
            });
        }
    }
}
