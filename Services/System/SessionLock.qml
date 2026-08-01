pragma Singleton

// Whether the session is locked, and the one door into locking it (#30, #47).
//
// Every path to the lock converges here — the session menu (#44), `qs ipc call
// lock lock`, the idle ladder and the pre-suspend hook (#48) — so that there is
// exactly one place that decides the session is locked, and the surface has
// exactly one thing to follow. The surface owns none of this: it binds to
// `locked` and reports back what the compositor confirmed.
//
// Deliberately free of Quickshell.Wayland. Nothing here knows what a lock
// *surface* is, which is what lets #48 drive it from a logind signal without
// reaching into Surfaces/.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import qs.Core

Singleton {
    id: root

    /// Whether the session should be locked. Written only through `lock()` and
    /// `unlock()` below — Surfaces/Lock/Lock.qml binds its `WlSessionLock` to
    /// this, so assigning it from anywhere else would be assigning the
    /// compositor's lock state from anywhere else.
    readonly property alias locked: priv.locked

    /// What asked for the lock, for the log: "ipc", "menu", "idle", "sleep".
    /// Free-form on purpose — this is evidence, not a state machine input.
    readonly property alias reason: priv.reason

    /// The compositor's own confirmation that every screen is covered, mirrored
    /// back from `WlSessionLock.secure`. This is the property #48's
    /// pre-suspend hook must wait on before it releases its sleep inhibitor:
    /// `locked` is our intent, `secure` is the guarantee.
    ///
    /// Note that `secure` is read-only in Quickshell 0.3.0 — the capability
    /// survey (#4) recorded it as a settable "keep the lock up if the shell
    /// dies" mode, and it is not. That behaviour is the ext-session-lock-v1
    /// protocol's own: a conformant compositor keeps the screen locked if the
    /// client dies without unlocking, whatever we set.
    property bool secure: false

    /// How many notifications are waiting, shown on the lock as a count and
    /// never as contents (#9). A seam: the notification service (#42) owns the
    /// number and writes it here. Until then it is zero and the lock shows
    /// nothing, which is the correct rendering of "nothing is waiting".
    property int notificationCount: 0

    /// Raise the lock. Returns whether this call is what locked the session —
    /// false means it was already locked, which is not a failure and is why
    /// every caller can be a dumb "lock now" button.
    function lock(reason: string): bool {
        if (priv.locked)
            return false;
        priv.reason = reason || "unknown";
        priv.locked = true;
        Logger.log("lock", "locking (" + priv.reason + ")");
        return true;
    }

    /// Drop the lock. Called by the lock surface on a successful
    /// authentication, and by nothing else — there is no unlock path that does
    /// not go through PAM.
    function unlock(): bool {
        if (!priv.locked)
            return false;
        priv.locked = false;
        priv.reason = "";
        root.secure = false;
        Logger.log("lock", "unlocked");
        return true;
    }

    // `locked` and `reason` are held one level down so the properties above can
    // be readonly aliases: locking is the thing that must have exactly one
    // door, and this is what makes `lock()` and `unlock()` that door.
    //
    // `secure` and `notificationCount` are deliberately *not* behind it. They
    // are inbound seams — facts about the session written by the one object
    // that knows them (the lock surface, and #42's notification service) and
    // read by everyone else. Putting a setter in front of a fact would buy
    // nothing.
    QtObject {
        id: priv
        property bool locked: false
        property string reason: ""
    }
}
