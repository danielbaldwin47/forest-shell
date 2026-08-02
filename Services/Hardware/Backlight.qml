pragma Singleton

// The backlight facade (#36, #12 §3): screen brightness, and the only
// subprocess this ticket owns.
//
//     Backlight.available     // false on a desktop, or with no brightnessctl
//     Backlight.percent       // 0-100, live, read straight from /sys
//     Backlight.setPercent(40)
//     Backlight.step(1)       // one notch up
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
        // Stepped off the *queued* value while one is in flight, so holding the
        // key ramps instead of fighting the sysfs value it has outrun.
        const from = root.queued >= 0 ? root.queued : root.percent;
        root.setPercent(root.policy.stepped(from, direction));
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
                sysfs.reload();
            } else {
                Logger.warn("backlight", root.policy.complaint(root.device, apply.target,
                                                               exitCode, applyErr.text));
            }
            root.applyQueued();
        }
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
        // owned them.
        watchChanges: true
        printErrors: false
    }

    onPercentChanged: if (root.available)
        Logger.log("backlight", "panel at " + root.percent + "%")

    Component.onCompleted: Logger.log("backlight", "probing for a backlight")
}
