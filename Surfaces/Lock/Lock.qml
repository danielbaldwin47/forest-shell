// The lock, as the compositor sees it (#30, #47).
//
// `WlSessionLock` is real `ext-session-lock-v1`, not a fullscreen window
// pretending: the compositor stops delivering input to anything else, covers
// every output itself, and — this is the part a fake overlay can never do —
// keeps the screen locked if the shell process dies without unlocking. That
// last property is why `secure` is read-only here and why nothing in this file
// tries to set it: it is the protocol's guarantee, reported back to us, not a
// mode we opt into.
//
// Everything about *when* to lock lives in Services/System/SessionLock.qml.
// This file binds to it and reports back what the compositor confirmed, so the
// idle ladder and the pre-suspend hook (#48) never have to know a lock surface
// exists.
//
// The IPC target is declared here rather than in a central IPC file, per #12 §7
// — each surface owns its own, named after itself, lowercase.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Core
import qs.Services.System

Scope {
    id: root

    // One conversation for the whole session, outside the surface component:
    // the per-screen surfaces come and go with the lock and must not each get
    // their own PAM context or their own half-typed password.
    LockAuth { id: pamAuth }

    /// The conversation, for the harness in tools/ to drive. Nothing in the
    /// shell reads it: the surfaces are handed `pamAuth` directly below.
    readonly property alias auth: pamAuth

    WlSessionLock {
        id: sessionLock

        locked: SessionLock.locked

        // The compositor confirming every output is covered. #48's pre-suspend
        // hook waits on this before releasing its sleep inhibitor — `locked` is
        // our intent, this is the guarantee — so it is mirrored back onto the
        // service where that hook can see it without reaching in here.
        onSecureChanged: {
            SessionLock.secure = sessionLock.secure;
            if (sessionLock.secure)
                Logger.log("lock", "compositor confirms all screens covered");
        }

        WlSessionLockSurface {
            id: lockSurface

            // Painted before the content loads, so an output that comes up
            // mid-lock is never a flash of white (the default is white).
            color: Theme.bgBase

            // One line per surface, so seam 2 can count them (#98). A lock is
            // the one surface set where a screen arriving or leaving *while it
            // is up* is a correctness question rather than a cosmetic one:
            // an output that comes up mid-lock must be covered, and one that
            // goes away must not leave its surface behind. Neither of those is
            // visible to a script any other way.
            //
            // Announced from a `screen` change rather than from
            // `Component.onCompleted`, and the name is kept: the compositor
            // hands the surface its output *after* the component is built
            // (measured — completion sees `screen` null), and takes it away
            // before destruction, so neither end of the lifetime can read the
            // name at the moment it needs it.
            property string screenName: ""

            onScreenChanged: {
                if (lockSurface.screen && lockSurface.screenName === "") {
                    lockSurface.screenName = lockSurface.screen.name;
                    Logger.log("lock", "surface up on " + lockSurface.screenName);
                }
            }

            Component.onDestruction: {
                if (lockSurface.screenName !== "")
                    Logger.log("lock", "surface gone from " + lockSurface.screenName);
            }

            LockSurface {
                anchors.fill: parent
                screen: lockSurface.screen
                auth: pamAuth
            }
        }
    }

    // Opening and closing the PAM conversations is tied to the session being
    // locked rather than to any one surface being built, because there are as
    // many surfaces as there are screens and exactly one conversation.
    //
    // Driven off the *service* rather than off `sessionLock.locked`, and that
    // is not a style choice (#81). `WlSessionLock.locked` reads correctly but
    // does not notify when it goes true: Quickshell 0.3.0's `setLocked()` hands
    // off to `realizeLockTarget()`, which takes the compositor lock and builds
    // the surfaces without emitting `lockStateChanged` — only the *unlock* path
    // emits. So a handler hung on it fires on unlock and never on lock, which
    // is how #47 shipped a lock that never opened a PAM conversation and could
    // not be answered. `SessionLock.locked` is an ordinary QML property and
    // notifies both ways.
    Connections {
        target: SessionLock

        function onLockedChanged() {
            if (SessionLock.locked)
                pamAuth.begin();
            else
                pamAuth.end();
        }
    }

    // Scripting and keybinds:
    //
    //   qs ipc call lock lock
    //   qs ipc call lock isLocked
    //
    // A Hyprland bind uses the survival idiom from #12 §7, so the compositor
    // stays usable when the shell is down:
    //
    //   bind = SUPER, L, exec, qs ipc call lock lock || loginctl lock-session
    //
    // No `unlock` target, and there will not be one: the only way out of this
    // surface is through PAM.
    IpcHandler {
        target: "lock"

        function lock(): bool {
            return SessionLock.lock("ipc");
        }

        function isLocked(): bool {
            return SessionLock.locked;
        }
    }
}
