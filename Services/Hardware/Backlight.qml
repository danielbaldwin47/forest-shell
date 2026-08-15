pragma Singleton

// The backlight facade (#36, #12 §3): screen brightness, and the only
// subprocess this ticket owns.
//
//     Backlight.available     // false on a desktop, or with no brightnessctl
//     Backlight.percent       // 0-100, live, read straight from /sys
//     Backlight.setPercent(40)
//     Backlight.step(1)       // one notch up
//     Backlight.watch() / Backlight.release()   // while a level is on screen
//
// Named `Backlight` rather than `Brightness` for one flat reason: the bar
// module is `Surfaces/Bar/Modules/Brightness.qml`, and two QML types with the
// same name in two modules is a resolution the shell has already been bitten by
// (Core/Config.qml, on a singleton called `State`). It is also the more honest
// name — this drives the kernel's backlight class, and the external-monitor
// backend that would drive DDC (#4: `ddcutil`, ~100ms per call, post-v1) sits
// behind the same door.
//
// **Reading and writing are different mechanisms, on purpose.** The value is a
// file under /sys: reading it costs nothing, needs no permission and is always
// the truth, so `FileView` does that. Writing it needs a binary that is setuid
// or udev-blessed, which is the entire reason `brightnessctl` is here — so it
// is only ever asked to *set*, and once at startup to say which device is the
// panel.
//
// **Reading it is free but not automatic.** A sysfs attribute change is
// delivered by `sysfs_notify`, a poll() wakeup rather than an inotify event, so
// the FileView's `watchChanges` never fires for the panel — which meant every
// brightness the shell did not set was invisible to it until the shell next
// wrote one (#186: a panel at 94%, a shell still showing 61% twelve minutes
// later, and a key press that stepped from the 61%). So the value is re-read on
// demand: `watch()`/`release()` while a surface is showing a level, and a read
// before a step that is not already ramping. Nothing ticks while no surface is
// showing brightness, and the read itself is synchronous — see the FileView.
//
// Two things this file does that #78 paid for:
//
//   - the exit status is read, and a non-zero one is logged as a refusal rather
//     than as an application. A wrapper that reports failure as success is the
//     bug that cost four PRs;
//   - there is one `Process`, and a second `set` arriving while the first is in
//     flight **coalesces** rather than overwriting `command` — measured on the
//     compositor facade, assigning a command to a running Process kills the run
//     in progress. Holding a key down is exactly that case, ten times a second.
//
// Every decision — the probe, its parsing, the step grid, the floor, what the
// log lines say — is in Services/Hardware/BacklightPolicy.qml, which imports
// nothing but QtQuick so tests/ can reach it. This file is the subprocess.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core

Singleton {
    id: root

    // Held as its own property rather than declared inline — see Core/Config.qml.
    readonly property BacklightPolicy policy: BacklightPolicy {}

    /// The panel, as the kernel names it — "intel_backlight" on the T480.
    /// Empty until the probe answers, and on a machine with no backlight.
    property string device: ""

    /// The device's own range. From the probe rather than a second file read:
    /// it cannot change while the machine is up.
    property int max: 0

    readonly property bool available: root.device !== "" && root.max > 0

    /// What the panel is actually doing, live. `actual_brightness` rather than
    /// `brightness` — the first is the hardware's answer, the second is what
    /// was last asked of it, and they differ while a fade is in flight.
    readonly property int raw: root.policy.number(sysfs.text())
    readonly property int percent: root.policy.percent(root.raw, root.max)

    // --- setting it ----------------------------------------------------------

    /// The percent a set is waiting to apply, or -1 for none. A held key sends
    /// ten of these a second and only the last one matters — a queue would
    /// replay the whole ramp after the key came up.
    property int queued: -1

    function setPercent(percent: int) {
        if (!root.available) {
            Logger.warn("backlight", "no backlight device — ignoring set " + percent + "%");
            return;
        }
        root.queued = root.policy.clamp(percent);
        root.applyQueued();
    }

    function step(direction: int) {
        if (root.queued >= 0) {
            // Stepped off the *queued* value while one is in flight, so holding
            // the key ramps instead of fighting the sysfs value it has outrun.
            root.setPercent(root.policy.stepped(root.queued, direction));
            return;
        }
        // Idle, so the cached value is only as good as the last read — and #186
        // is the case where it is not good at all, because anything may have
        // moved the panel since. Ask first, and step from the answer rather
        // than from `percent`: the read is synchronous but the *binding* on it
        // is not (measured — after a blocking `reload()`, `text()` is the new
        // contents while a property bound to it is still the old one), so a
        // step off `percent` here would be a step off the value the read was
        // for. Unconditional, not `refreshIfStale()`: a step is exactly the
        // caller that must not be handed a remembered value.
        root.readNow();
        root.setPercent(root.policy.stepped(root.reading(), direction));
    }

    /// The level the panel is on its way to, or -1 when nothing is in flight.
    ///
    /// On the facade rather than inlined in a caller, because the two halves of
    /// "in flight" live here: a write that has not started yet is `queued`, and
    /// one that has is the process still running. A caller that computes from
    /// the level needs both — while either is true `actual_brightness` is
    /// between two levels and is neither of them, so a read taken then is not a
    /// level anybody chose. #208 is the caller: the idle dim, capturing what to
    /// restore.
    ///
    /// Where this stops, stated rather than left to be discovered: the process
    /// exiting is the *write* landing, not the panel arriving. A panel that
    /// fades is still moving after this answers -1, and a read taken inside
    /// that window is a level nobody chose either. Not guarded, because the
    /// guard would be a wait — and the caller is a rung firing on a machine
    /// nobody has touched for minutes, where the last write is long over.
    function aimingAt(): int {
        if (root.queued >= 0)
            return root.queued;
        return apply.running ? apply.target : -1;
    }

    function applyQueued() {
        if (apply.running || root.queued < 0)
            return;
        apply.target = root.queued;
        root.queued = -1;
        apply.command = root.policy.setCommand(root.device, apply.target);
        apply.running = true;
    }

    Process {
        id: apply

        // What is in flight, kept for the log line: the reply arrives after the
        // call and says nothing about which value it is answering.
        property int target: 0

        stderr: StdioCollector { id: applyErr }

        onExited: (exitCode, exitStatus) => {
            if (root.policy.accepted(exitCode)) {
                Logger.log("backlight", root.policy.applied(root.device, apply.target));
                // The write went to `brightness`; this is the read of
                // `actual_brightness` that follows it. Explicit, because
                // inotify does not fire for a sysfs attribute — `watchChanges`
                // below catches an external change on the drivers that do
                // notify, and this catches every change the shell makes.
                root.lastReadAt = Date.now();
                sysfs.reload();
            } else {
                Logger.warn("backlight", root.policy.complaint(root.device, apply.target,
                                                               exitCode, applyErr.text));
            }
            root.applyQueued();
        }
    }

    // --- keeping it true (#186) ----------------------------------------------
    //
    // `watchChanges` below cannot deliver an external change, so the value is
    // re-read on demand instead. Three demands:
    //
    //     Backlight.watch() / Backlight.release()   // a surface that comes and goes
    //     Backlight.refreshIfStale()                // a readout, as it appears
    //     — and a step, which reads before it computes its next notch.
    //
    // The subscription is the same shape as SystemStats and Weather —
    // `Component.onCompleted` / `Component.onDestruction` on the surface — and
    // it is a count rather than a flag because two surfaces can be showing a
    // level at once.
    //
    // What holds one is the part worth stating: a surface that *comes and
    // goes*, which in practice is the control centre. A bar module is never not
    // on screen, so a subscription there would be a timer running for the life
    // of the session — measured at 5.57 context switches/s against a budget of
    // 5, up from 1.9 (tools/idle-budget.sh, with the module in the bar). The
    // permanent readout therefore reads as it appears and lives off the reads
    // everything else causes.

    /// When the panel was last read, as a millisecond clock, or 0 for never.
    property real lastReadAt: 0

    /// How many surfaces are currently displaying a level.
    property int watchers: 0

    /// The panel's level as the file says it is *now*, rather than as the
    /// bindings have caught up with. Same arithmetic as `percent`, off the same
    /// read; what differs is only that this one cannot be a frame behind.
    function reading(): int {
        return root.policy.percent(root.policy.number(sysfs.text()), root.max);
    }

    /// Read the panel, and remember when. Synchronous — `reading()` is the new
    /// value the moment this returns.
    function readNow(): void {
        if (!root.available)
            return;
        root.lastReadAt = Date.now();
        sysfs.reload();
    }

    /// Read the panel unless the last read is recent enough to still be worth
    /// trusting. What a subscription does on arrival and on every tick, so that
    /// several surfaces appearing in the same frame are one read; a step does
    /// not use this, because a step is the one caller that must not be handed a
    /// remembered value.
    function refreshIfStale(): void {
        if (root.policy.readDue(Date.now(), root.lastReadAt))
            root.readNow();
    }

    function watch(): void {
        root.watchers += 1;
        if (root.watchers === 1)
            Logger.log("backlight", root.policy.watching(root.watchers, root.policy.pollMs));
        // The level on screen the moment the surface appears is the one #186
        // was reported against: a drawer opened after an external change showed
        // whatever the shell last happened to write.
        root.refreshIfStale();
    }

    function release(): void {
        root.watchers = Math.max(0, root.watchers - 1);
        // Both edges are logged, and both are a policy line: "it stopped when
        // the drawer closed" is the half of the subscription a harness can only
        // see by reading for it (Services/README.md, and SystemStats next door).
        if (root.watchers === 0)
            Logger.log("backlight", root.policy.idle());
    }

    Timer {
        // Armed only while something is displaying a level, which is the whole
        // of #186's "nothing new runs at rest": with no brightness on screen
        // this never ticks, and the shell's idle budget is unchanged.
        running: root.policy.pollRunning(root.watchers, root.available)
        interval: root.policy.pollMs
        repeat: true
        onTriggered: root.refreshIfStale()
    }

    // --- finding the panel ---------------------------------------------------

    Process {
        id: probe

        command: root.policy.probeCommand()
        // A `Process` does nothing until it is told to run — there is no
        // autostart, and a probe that only ever *declared* its command is a
        // service that stays inert while looking configured.
        running: true
        stdout: StdioCollector { id: probeOut }

        onExited: (exitCode, exitStatus) => {
            const found = root.policy.accepted(exitCode) ? root.policy.parse(probeOut.text) : null;
            if (!found) {
                // Not a failure worth a warning on a desktop, and not one worth
                // hiding either: the brightness module is off by default (#9),
                // and this line is why it stays off.
                Logger.log("backlight", "no backlight device — facade inert");
                return;
            }
            root.device = found.name;
            root.max = found.max;
            Logger.log("backlight", "panel " + root.device + " (max " + root.max
                       + "), at " + root.policy.percent(found.current, found.max) + "%");
        }
    }

    FileView {
        id: sysfs

        path: root.policy.valuePath(root.device)
        // Best-effort: a sysfs attribute change is delivered by `sysfs_notify`,
        // which is a poll() wakeup rather than an inotify event, so this only
        // catches drivers that also touch the file. Every change the shell
        // makes is picked up by the explicit reload above regardless — this is
        // for the brightness keys a compositor keybind handled before the shell
        // owned them. #186 is what the gap costs, and `refresh()` above is the
        // answer: the value is re-read on demand rather than waited for.
        watchChanges: true
        printErrors: false

        // Read on this thread rather than on a pool one, which is what makes
        // `refresh()` answer rather than promise: measured, a `reload()` without
        // this is asynchronous even with `blockLoading` set — `text()`
        // immediately after it still returns the previous contents and the new
        // one arrives with `loaded`, so a step would compute from exactly the
        // stale value the read was for. Blocking is affordable because the file
        // is one kernel attribute, four bytes of it, already in memory; the
        // thread hop it avoids is the more expensive half.
        blockAllReads: true
    }

    onPercentChanged: if (root.available)
        Logger.log("backlight", "panel at " + root.percent + "%")

    Component.onCompleted: Logger.log("backlight", "probing for a backlight")
}
