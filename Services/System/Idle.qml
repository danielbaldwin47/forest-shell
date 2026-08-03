pragma Singleton

// The idle ladder (#48; the ladder itself is #30's resolution) — four stages,
// four `IdleRung`s, and what each one does when the machine goes quiet.
//
//     dim      2.5 min battery / 5 min ac    backlight down to 10%
//     lock     5 / 10                        SessionLock.lock("idle")
//     dpms     6 / 12  (30 s while locked)   the compositor blanks the screen
//     suspend  15 / off                      the session's suspend command
//
// Native, and that word is doing work: `Quickshell.Wayland.IdleMonitor` speaks
// `ext-idle-notify-v1` to the compositor, which is the same protocol hypridle
// uses and the same one a video player's inhibitor is answered by. There is no
// idle daemon in this stack, no polling, and no timer running while the machine
// is in use — a monitor costs one Wayland object and wakes the shell exactly
// when it fires (#22 §5).
//
// ## What holds the ladder, and what does not
//
// `respectInhibitors` is on every stage, always (#30). A browser playing a film
// takes `zwp_idle_inhibit_manager_v1` itself, the compositor stops counting, and
// none of these fire — the shell never has to know what a film is. Keep Awake
// (#44) is the user's own version of the same thing and freezes all four stages.
//
// The suspend stage has one gate the others do not: an un-corked PipeWire output
// stream blocks it (`Audio.playing`). Music keeps playing while the screen dims,
// locks and blanks; the machine does not sleep under the person listening to it.
//
// ## Lock before sleep
//
// Not here. The guarantee lives in Services/System/LogindBridge.qml, which holds
// a logind delay inhibitor and releases it only once the compositor has
// confirmed the lock — that is the path a lid close and a `systemctl suspend`
// typed in a terminal both take, and neither of them goes past this file. What
// *this* file owes it is the other half: the ladder's own suspend rung locks
// first and waits for the same confirmation before it runs anything.
//
// Every decision — which stages are armed, at what timeout, on which power
// source, what blocks what — is Services/System/IdlePolicy.qml, which imports
// nothing but QtQuick so `tests/` can reach it. This file is the wiring.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Services.Hardware
import qs.Services.Media

Singleton {
    id: root

    // Held as its own property rather than declared inline — see Core/Config.qml.
    readonly property IdlePolicy policy: IdlePolicy {}

    readonly property var settings: Config.values.system.idle

    /// Which column of #30's table applies. A desktop has no battery and is
    /// therefore always on the AC ladder, which is the correct reading of "no
    /// battery" rather than a special case.
    readonly property bool onBattery: Power.hasBattery && !Power.onMains

    /// Keep Awake freezes every stage (#30). Deliberately not the logind bridge:
    /// a caffeinated machine whose lid is closed still suspends, and still locks
    /// on the way down.
    readonly property bool frozen: KeepAwake.on

    /// The whole ladder as it stands. One binding, so the four monitors and the
    /// log line cannot disagree about what is armed.
    readonly property var rows: root.policy.ladder(root.settings, root.onBattery,
                                                   root.frozen)

    readonly property var dimRow: root.policy.row(root.settings, "dim",
                                                  root.onBattery, root.frozen)
    readonly property var lockRow: root.policy.row(root.settings, "lock",
                                                   root.onBattery, root.frozen)
    readonly property var dpmsRow: root.policy.row(root.settings, "dpms",
                                                   root.onBattery, root.frozen)
    readonly property var suspendRow: root.policy.row(root.settings, "suspend",
                                                      root.onBattery, root.frozen)

    /// What the screen is doing because of this file, so that undoing it is
    /// possible and so that a harness can ask. `dimmedFrom` is -1 for "the
    /// backlight is the user's", and a percentage otherwise — the level to put
    /// back, captured before the dim rather than derived after it.
    property int dimmedFrom: -1
    readonly property bool dimmed: root.dimmedFrom >= 0
    property bool blanked: false

    // --- dim ------------------------------------------------------------------

    IdleRung {
        id: dimStage

        armed: root.dimRow.enabled
        seconds: root.dimRow.seconds
        respectInhibitors: root.policy.respectInhibitors

        onIsIdleChanged: dimStage.isIdle ? root.dim() : root.undim()
        onRearmed: Logger.log("idle", root.policy.armed("dim", dimStage.seconds))
    }

    function dim(): void {
        if (root.dimmed)
            return;
        if (!Backlight.available) {
            Logger.log("idle", root.policy.blocked("dim", "no backlight on this machine"));
            return;
        }
        root.dimmedFrom = Backlight.percent;
        const level = root.policy.dimLevel(root.settings);
        Backlight.setPercent(level);
        Logger.log("idle", root.policy.reached("dim", "backlight " + root.dimmedFrom
                                               + "% → " + level + "%"));
    }

    /// Put the backlight back where the user left it. The remembered level and
    /// not "up to full": a screen that was at 30% before the dim is one somebody
    /// chose, and restoring to 100% would be the shell overruling them once a
    /// coffee.
    function undim(): void {
        if (!root.dimmed)
            return;
        const restore = root.dimmedFrom;
        root.dimmedFrom = -1;
        Backlight.setPercent(restore);
        Logger.log("idle", root.policy.woke("dim", "backlight back to " + restore + "%"));
    }

    // --- lock -----------------------------------------------------------------

    IdleRung {
        id: lockStage

        armed: root.lockRow.enabled
        seconds: root.lockRow.seconds
        respectInhibitors: root.policy.respectInhibitors

        onIsIdleChanged: {
            if (!lockStage.isIdle)
                return;
            Logger.log("idle", root.policy.reached("lock", ""));
            // Through the service and not through logind: this is the shell's
            // own idle timer, the shell is up, and a round trip through
            // `loginctl` would only add a way for it to fail. The session menu's
            // Lock is the case that wants the round trip (LogindBridge.qml).
            SessionLock.lock("idle");
        }

        onRearmed: Logger.log("idle", root.policy.armed("lock", lockStage.seconds))
    }

    // --- dpms -----------------------------------------------------------------
    //
    // The compositor blanks the screen; the shell only asks. A command and not a
    // protocol call because there is no protocol for it — and because what
    // blanks a screen differs by compositor, which is the same argument
    // `system.session.commands` and the night light's commands make.

    IdleRung {
        id: dpmsStage

        armed: root.dpmsRow.enabled
        // The one stage whose timeout depends on something other than the power
        // source: a locked screen has nothing on it worth keeping lit, so #30
        // tightens this to 30 s while locked, and the tighter clock starts when
        // the lock goes up. That re-arm is IdleRung's doing, not the monitor's —
        // a bare `IdleMonitor` ignores a new timeout (#139), so this stage was
        // keeping the unlocked clock through a lock until that was fixed.
        seconds: root.policy.dpmsSeconds(root.settings, root.onBattery,
                                         SessionLock.locked)
        respectInhibitors: root.policy.respectInhibitors

        onIsIdleChanged: dpmsStage.isIdle ? root.blank() : root.unblank("activity")
        onRearmed: Logger.log("idle", root.policy.armed("dpms", dpmsStage.seconds))
    }

    function blank(): void {
        if (root.blanked)
            return;
        const argv = root.policy.argv(root.settings.dpms?.offCommand ?? "");
        if (argv.length === 0) {
            Logger.warn("idle", root.policy.blocked(
                "dpms", "nothing to run (set system.idle.dpms.offCommand)"));
            return;
        }
        root.blanked = true;
        dpmsRunner.turningOff = true;
        Logger.log("idle", root.policy.reached("dpms", "screen off"));
        dpmsRunner.exec(argv);
    }

    /// Back on. Called by activity, and by the logind bridge on resume — DPMS
    /// state does not survive a suspend, and a shell that assumed it did would
    /// leave the screen black on a machine that had just been opened.
    function unblank(why: string): void {
        if (!root.blanked)
            return;
        root.blanked = false;
        const argv = root.policy.argv(root.settings.dpms?.onCommand ?? "");
        if (argv.length === 0) {
            Logger.warn("idle", root.policy.blocked(
                "dpms", "nothing to run (set system.idle.dpms.onCommand)"));
            return;
        }
        dpmsRunner.turningOff = false;
        Logger.log("idle", root.policy.woke("dpms", "screen on (" + why + ")"));
        dpmsRunner.exec(argv);
    }

    /// One process, and the exit status is read: a `hyprctl` that refused must
    /// not be logged as a screen that blanked (#78). Two of these can never be
    /// in flight at once — the screen is either going off or coming on, and both
    /// calls return in single-digit milliseconds.
    ///
    /// A refusal also takes `blanked` back to what it was. The flag is what the
    /// next call reads to decide whether there is anything to do, so leaving it
    /// at "off" after a command that did not turn anything off would make the
    /// following activity a no-op — the screen dark, and the shell certain it
    /// had already put it back on.
    Process {
        id: dpmsRunner

        /// Which direction the run in flight was going, for the line and for the
        /// flag it puts back.
        property bool turningOff: false

        stderr: StdioCollector { id: dpmsErr }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                return;
            root.blanked = !dpmsRunner.turningOff;
            Logger.warn("idle", root.policy.blocked(
                "dpms", "the screen is still " + (dpmsRunner.turningOff ? "on" : "off")
                + " — the command exited " + exitCode + " ("
                + String(dpmsErr.text ?? "").trim() + ")"));
        }
    }

    // --- suspend --------------------------------------------------------------

    IdleRung {
        id: suspendStage

        armed: root.suspendRow.enabled
        seconds: root.suspendRow.seconds
        respectInhibitors: root.policy.respectInhibitors

        // Activity cancels a suspend that is still waiting for the compositor to
        // confirm the lock. Without this the machine sleeps under somebody who
        // came back during the wait — they are at a locked screen by then, which
        // is correct, but the suspend was decided when nobody was there and must
        // not outlive that.
        onIsIdleChanged: suspendStage.isIdle ? root.suspend()
                                             : root.cancelSuspend("activity")
        onRearmed: Logger.log("idle", root.policy.armed("suspend", suspendStage.seconds))
    }

    /// Whether a suspend is waiting for the compositor to confirm the lock.
    property bool suspendPending: false

    function suspend(): void {
        // The gate, and it is this stage's alone: music through headphones is
        // exactly the case where the screen should be off and the machine should
        // not be (#30).
        if (root.policy.suspendBlocked(Audio.playing)) {
            Logger.log("idle", root.policy.blocked("suspend", "audio is playing"));
            return;
        }

        const command = root.policy.argv(
            Config.values.system.session.commands?.suspend ?? "");
        if (command.length === 0) {
            Logger.warn("idle", root.policy.blocked(
                "suspend", "nothing to run (set system.session.commands.suspend)"));
            return;
        }

        Logger.log("idle", root.policy.reached(
            "suspend", SessionLock.locked ? "already locked" : "locking first"));

        if (root.policy.mustLockFirst(SessionLock.locked))
            SessionLock.lock("idle suspend");

        if (SessionLock.secure) {
            root.runSuspend();
            return;
        }
        root.suspendPending = true;
        suspendWait.restart();
    }

    /// Call off a suspend that has not run yet. Called by activity and by
    /// freezing the ladder — both are somebody saying they are here.
    function cancelSuspend(why: string): void {
        if (!root.suspendPending)
            return;
        root.suspendPending = false;
        suspendWait.stop();
        Logger.log("idle", root.policy.woke("suspend", "called off (" + why + ")"));
    }

    function runSuspend(): void {
        root.suspendPending = false;
        suspendWait.stop();
        const command = root.policy.argv(
            Config.values.system.session.commands?.suspend ?? "");
        if (command.length === 0)
            return;
        Logger.log("idle", root.policy.reached("suspend", "locked — " + command.join(" ")));
        suspendRunner.exec(command);
    }

    Connections {
        target: SessionLock
        function onSecureChanged(): void {
            if (root.suspendPending && SessionLock.secure)
                root.runSuspend();
        }
    }

    /// The compositor never confirmed. **The machine stays awake**, which is the
    /// opposite of what the bridge does on the same timeout and is right for the
    /// same reason: logind's delay lock expires whether we like it or not, so
    /// there the choice is between sleeping and being overruled — here there is
    /// no clock but ours, and an idle machine that stayed on is a great deal
    /// safer than a suspended one nobody locked.
    Timer {
        id: suspendWait

        interval: root.policy.lockConfirmTimeoutMs
        repeat: false

        onTriggered: {
            root.suspendPending = false;
            Logger.warn("idle", root.policy.blocked(
                "suspend", "the compositor did not confirm the lock within "
                + root.policy.lockConfirmTimeoutMs + "ms — staying awake"));
        }
    }

    Process { id: suspendRunner }

    // --- coming back ----------------------------------------------------------

    Connections {
        target: LogindBridge
        function onResumed(): void {
            // Nothing about the screen survives a suspend, and the ladder's idea
            // of what it had already done does not either.
            root.unblank("resume");
            root.undim();
        }
    }

    /// Freezing the ladder must also undo what it has already done — a Keep
    /// Awake pressed at a dimmed screen is a user asking for their screen back,
    /// not for it to stay dark until they touch the mouse.
    onFrozenChanged: {
        Logger.log("idle", root.policy.frozenLine(root.frozen));
        if (root.frozen) {
            root.undim();
            root.unblank("keep awake");
            root.cancelSuspend("keep awake");
        }
    }

    // --- what a harness reads -------------------------------------------------
    //
    // The ladder, every time it changes: plugging in the charger, toggling Keep
    // Awake and editing settings.json all move it, and each of those is a
    // different reason for a stage not to fire (#81 — a lifecycle nothing logged
    // cost a session).

    onRowsChanged: Logger.log("idle", root.policy.ladderLine(root.rows, root.onBattery))

    // --- the door -------------------------------------------------------------
    //
    // For tools/idle-harness.sh. `fire` runs the same function the monitor's own
    // `isIdle` runs, so what a harness drives is the shipped path — the monitors
    // themselves are exercised by the timeouts in the scratch config, which is
    // the half of this that only a compositor can answer.

    IpcHandler {
        target: "idle"

        function ladder(): string {
            return root.policy.ladderLine(root.rows, root.onBattery);
        }

        function fire(stage: string): string {
            switch (stage) {
            case "dim": root.dim(); return "dim";
            case "lock": SessionLock.lock("idle"); return "lock";
            case "dpms": root.blank(); return "dpms";
            case "suspend": root.suspend(); return "suspend";
            }
            return "no such stage: " + stage;
        }

        function wake(): string {
            root.undim();
            root.unblank("ipc");
            return "awake";
        }

        function isDimmed(): bool { return root.dimmed; }
        function isBlanked(): bool { return root.blanked; }
        function onBattery(): bool { return root.onBattery; }
        function isFrozen(): bool { return root.frozen; }
        function isPlaying(): bool { return Audio.playing; }
    }

    Component.onCompleted: Logger.log("idle", "ladder armed (ipc target: idle) — "
                                      + root.policy.ladderLine(root.rows, root.onBattery))
}
