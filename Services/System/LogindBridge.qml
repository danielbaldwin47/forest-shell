pragma Singleton

// The logind bridge (#48; the design is #30's resolution) — the half of the
// session that lives outside this process.
//
//     LogindBridge.listening    // the helper is really running
//     LogindBridge.inhibiting   // the sleep delay lock is really held
//     LogindBridge.lockSession()  // the session menu's Lock, routed through logind
//
// Three things happen here, and they are all the same guarantee seen from
// different sides: **the machine does not sleep on an unlocked session.**
//
//   1. A `systemd-inhibit --mode=delay` child is held from startup. A *delay*
//      lock and not a block: it does not refuse the suspend, it makes logind
//      wait — up to `InhibitDelayMaxSec`, 5 s by default — for whoever holds it
//      to be ready.
//   2. `tools/logind-bridge.sh` turns the two logind signals Quickshell cannot
//      hear (#4 §2.8: no arbitrary DBus client) into one word a line. On
//      `sleep`, the shell raises the lock and holds the delay lock until the
//      *compositor* confirms every screen is covered — `SessionLock.secure`,
//      which is the guarantee, where `SessionLock.locked` is only the intent.
//      Then it lets go, and the machine sleeps.
//   3. `loginctl lock-session` therefore locks this shell, and the session
//      menu's Lock goes out through logind rather than straight to the surface,
//      so logind's own idea of the session state stays true.
//
// The one thing to keep in mind reading this file: **it is not part of the idle
// ladder.** Keep Awake freezes the ladder (Services/System/Idle.qml) and does
// not touch anything here — a caffeinated machine whose lid is closed still
// suspends, because that was the user closing the lid, and it still locks
// first.
//
// Nothing here decides anything: the timings, the log lines and the helper's
// protocol are Services/System/IdlePolicy.qml, which `tests/` can reach.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core

Singleton {
    id: root

    // Held as its own property rather than declared inline — see Core/Config.qml.
    readonly property IdlePolicy policy: IdlePolicy {}

    /// Whether the helper is really running. Not "was started": a machine with
    /// no `gdbus` runs it, watches it exit 127, and must not then believe that
    /// `loginctl lock-session` will reach the shell (#78).
    property bool listening: false

    /// Whether the sleep delay lock is really held. Same argument one process
    /// along, and it is the one that matters most: a shell that *believes* it
    /// holds a delay lock will happily take its time raising the lock while the
    /// machine suspends underneath it.
    property bool inhibiting: false

    /// The machine came back. Services/System/Idle.qml listens for this to put
    /// the screen back on — DPMS state does not survive a suspend, and neither
    /// does the ladder's idea of what it had already done.
    /// Surfaces/Lock/LockAuth.qml listens for it to rebuild its conversations,
    /// which do not survive one either (#188).
    signal resumed()

    /// The machine is about to go, and we are still holding the delay lock —
    /// so there is time to put things down before it does (#188).
    ///
    /// Emitted from `sleep()` below, *before* the lock is raised, because the
    /// lock is what opens the PAM conversations and the whole point is that
    /// none of them should be carried into a suspend. Anything that must not
    /// be live on the other side listens here; there is no second sleep
    /// detection path, for the same reason there is no second resume one.
    signal sleeping()

    // --- the delay lock -------------------------------------------------------

    /// `cat` and not `sleep infinity`, which is not a style choice: the lock is
    /// held for as long as the child lives, and the clean way to end a child
    /// from QML is to close its stdin. Killing `systemd-inhibit` instead leaves
    /// its child orphaned to init — once per suspend, for the life of the
    /// session.
    Process {
        id: inhibitor

        command: ["systemd-inhibit", "--what=sleep", "--mode=delay",
                  "--who=forest-shell", "--why=Lock the session before it sleeps",
                  "cat"]
        stdinEnabled: true
        running: true

        onStarted: {
            root.inhibiting = true;
            Logger.log("logind", root.policy.inhibitorHeld("delay, what=sleep"));
        }

        onExited: (exitCode, exitStatus) => {
            const wasHeld = root.inhibiting;
            root.inhibiting = false;
            if (wasHeld)
                return;
            // Never started at all — no `systemd-inhibit`, or logind refusing
            // the lock. Said out loud, because the failure is otherwise
            // invisible until the day the machine sleeps mid-lock (#78).
            Logger.warn("logind", root.policy.inhibitorRefused(
                "systemd-inhibit exited " + exitCode));
        }
    }

    /// Let the machine sleep. Both halves are needed, and the harness is what
    /// established that: closing stdin alone leaves `cat` running — Quickshell
    /// 0.3.0's `stdinEnabled = false` stops *writing* to the child rather than
    /// closing its input — so the lock outlived the sleep it was meant to
    /// delay, and the shell reported itself still holding one. Terminating is
    /// what actually ends it; closing stdin first is what stops the `cat`
    /// outliving its parent as an orphan.
    function release(why: string): void {
        if (!root.inhibiting)
            return;
        Logger.log("logind", root.policy.inhibitorReleased(why));
        inhibitor.stdinEnabled = false;
        inhibitor.running = false;
    }

    /// Take it again on the way back up. A delay lock is consumed by the sleep
    /// it delayed, so this is not optional — without it the *second* suspend of
    /// a session would not wait for the lock.
    ///
    /// Nothing is logged here on purpose: the line that says a lock is held is
    /// `onStarted`'s, because that is the only moment it is true (#78). What is
    /// logged here is the case where there is nothing to retake, which would
    /// otherwise be a shell quietly holding one lock and believing it held two.
    function retake(): void {
        if (inhibitor.running) {
            Logger.warn("logind", "resumed while still holding a sleep inhibitor "
                        + "— not taking a second one");
            return;
        }
        inhibitor.stdinEnabled = true;
        inhibitor.running = true;
    }

    // --- the helper -----------------------------------------------------------

    Process {
        id: helper

        command: [Paths.shellDir + "/tools/logind-bridge.sh"]
        running: true

        onStarted: {
            root.listening = true;
            Logger.log("logind", "bridge listening");
        }

        onExited: (exitCode, exitStatus) => {
            root.listening = false;
            Logger.warn("logind", root.policy.bridgeRefused(
                "tools/logind-bridge.sh exited " + exitCode));
        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root.handle(line)
        }

        /// The helper says which session it is watching, and why it could not
        /// watch one. Logged rather than swallowed: "the lock never came up" and
        /// "logind never told us to lock" are different bugs with the same
        /// symptom.
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const text = String(line ?? "").trim();
                if (text !== "")
                    Logger.log("logind", "helper: " + text);
            }
        }
    }

    /// One line from the helper. The words it may say are the policy's, so a
    /// line that is not one of them is ignored rather than guessed at.
    function handle(line: string): void {
        const event = root.policy.event(line);
        if (event === "")
            return;

        Logger.log("logind", root.policy.bridgeLine(event));

        switch (event) {
        case "lock":
            SessionLock.lock("logind");
            break;
        case "unlock":
            // Deliberately nothing. `loginctl unlock-session` is a request from
            // outside the shell to drop the lock without authenticating, and
            // there is no such path (#30, #47): the only way out of the lock
            // surface is through PAM. Logged above, so that a user wondering why
            // the command did nothing can find out that it was heard.
            break;
        case "sleep":
            root.sleep();
            break;
        case "resume":
            root.retake();
            root.resumed();
            break;
        }
    }

    // --- the lock-before-sleep hook ------------------------------------------

    /// When the lock was asked for, so the confirmation can be logged with the
    /// time it took — the number that says whether the 5 s logind allows is
    /// comfortable or nearly spent.
    property real askedAt: 0
    property bool waiting: false

    function sleep(): void {
        Logger.log("logind", root.policy.sleeping(SessionLock.locked));
        root.askedAt = Date.now();

        // Announced before the lock is raised (#188). A lock raised here opens
        // the PAM conversations, and a conversation opened on this side of the
        // suspend is the bug: whoever needs to stand down has to hear about it
        // first, not be handed a fresh conversation to strand.
        root.sleeping();

        if (root.policy.mustLockFirst(SessionLock.locked))
            SessionLock.lock("sleep");

        if (SessionLock.secure) {
            root.confirmed();
            return;
        }

        root.waiting = true;
        confirm.restart();
    }

    function confirmed(): void {
        root.waiting = false;
        confirm.stop();
        Logger.log("logind", root.policy.lockConfirmed(Date.now() - root.askedAt));
        root.release("lock confirmed");
    }

    Connections {
        target: SessionLock
        function onSecureChanged(): void {
            if (root.waiting && SessionLock.secure)
                root.confirmed();
        }
    }

    /// The shell gives up before logind does. `InhibitDelayMaxSec` is 5 s and
    /// logind does not ask twice — past it the machine sleeps whether or not the
    /// lock is up, so the choice is between saying so and being overruled in
    /// silence.
    Timer {
        id: confirm

        interval: root.policy.lockConfirmTimeoutMs
        repeat: false

        onTriggered: {
            root.waiting = false;
            Logger.warn("logind", root.policy.lockUnconfirmed(root.policy.lockConfirmTimeoutMs));
            root.release("gave up waiting for the compositor");
        }
    }

    // --- locking, the way logind should hear about it -------------------------

    /// Lock through logind rather than in-process (#30). The difference is not
    /// cosmetic: `loginctl lock-session` makes logind's own `LockedHint` true,
    /// which is what anything else on the machine reads to find out that this
    /// session is locked. Calling `SessionLock.lock()` directly leaves logind
    /// believing the session is live.
    ///
    /// Falls back to the direct call whenever the round trip cannot work — no
    /// helper listening, or `loginctl` refusing — because a Lock button whose
    /// failure mode is an unlocked screen is the wrong trade every time.
    function lockSession(reason: string): void {
        if (!root.listening) {
            Logger.warn("logind", "no bridge — locking directly (" + reason + ")");
            SessionLock.lock(reason);
            return;
        }
        lockRequest.reason = reason;
        lockRequest.running = true;
    }

    Process {
        id: lockRequest

        property string reason: "session menu"

        command: ["loginctl", "lock-session"]
        stderr: StdioCollector { id: lockRequestErr }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                return;
            // #78 again: a refused command must not read as a lock that
            // happened. The direct call is the fallback, and it is announced.
            Logger.warn("logind", "loginctl lock-session exited " + exitCode
                        + " — locking directly ("
                        + String(lockRequestErr.text ?? "").trim() + ")");
            SessionLock.lock(lockRequest.reason);
        }
    }

    // --- the door -------------------------------------------------------------
    //
    // For tools/idle-harness.sh, which cannot make a real machine suspend: this
    // is the same `sleep()` the helper's `sleep` line calls, so what the harness
    // drives is the shipped path and not a copy of it. `sleep` and not `suspend`
    // — nothing here spawns `systemctl suspend`, and a name that suggested it
    // would be a dangerous thing to type at a live session.

    IpcHandler {
        target: "logind"

        function sleep(): void { root.sleep(); }
        function resume(): void { root.handle("resume"); }
        function isInhibiting(): bool { return root.inhibiting; }
        function isListening(): bool { return root.listening; }
    }

    Component.onCompleted: Logger.log("logind", "bridge starting (ipc target: logind)")
}
