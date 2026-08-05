// Everything the backlight wrapper decides, as pure functions (#36).
//
// Brightness is the one genuine gap in Quickshell's service set (#4 §2.6: no
// brightness or backlight type anywhere in the module set), so it is the one
// place in this ticket that runs a subprocess. The rule from #12 is that the
// subprocess is an implementation detail of a single singleton; the rule from
// #78 is that what came back is *read*, because a wrapper that logs "applied"
// off a process merely having exited reports failure as success.
//
// Reading and writing are deliberately different mechanisms: the value is a
// file under /sys and costs nothing to read live, while writing it needs a
// binary that is either setuid or udev-blessed. So `brightnessctl` is only ever
// asked to *set*, and to say once which device is the panel.
import QtQuick

QtObject {
    id: policy

    /// One nudge, in percent of the panel's range.
    readonly property int step: 5

    /// The floor. 0% on an intel backlight is a black screen — including the
    /// slider you would use to turn it back up — so the bottom of the range is
    /// one step of light rather than none.
    readonly property int minPercent: 1

    /// Ask which backlight is the panel.
    ///
    /// The class filter is load-bearing: without it the first device on a
    /// ThinkPad is `tpacpi::kbd_backlight`, and the shell would spend the
    /// session dimming the keyboard.
    function probeCommand(): var {
        return ["brightnessctl", "-m", "-c", "backlight", "info"];
    }

    /// The panel, from `brightnessctl -m` output, or null on a machine with no
    /// backlight — a desktop, or a laptop driven over DDC (#4: `ddcutil` is the
    /// same singleton's other backend, and post-v1).
    ///
    /// One line per device, `name,class,current,percent,max`. Only a
    /// `backlight`-class line with a real range counts; everything else,
    /// including brightnessctl's own "Device 'x' not found." prose, is not a
    /// device.
    function parse(reply: string): var {
        for (const line of (reply || "").split("\n")) {
            const fields = line.split(",");
            if (fields.length < 5 || fields[1] !== "backlight")
                continue;
            const max = policy.number(fields[4]);
            if (max <= 0)
                continue;
            return { name: fields[0], current: policy.number(fields[2]), max: max };
        }
        return null;
    }

    /// A raw sysfs value as a percent of the device's range.
    function percent(current: real, max: real): int {
        if (!isFinite(current) || !isFinite(max) || max <= 0)
            return 0;
        return Math.round(Math.max(0, Math.min(1, current / max)) * 100);
    }

    /// The percent one step up (`direction` 1) or down (-1) from here, snapped
    /// to the step grid so a level nudged from 43% reaches round numbers rather
    /// than 48, 53, 58.
    function stepped(percent: int, direction: int): int {
        const base = percent / policy.step;
        const grid = direction > 0 ? Math.floor(base + 1e-9) : Math.ceil(base - 1e-9);
        return policy.clamp((grid + (direction > 0 ? 1 : -1)) * policy.step);
    }

    function clamp(percent: int): int {
        if (!isFinite(percent))
            return policy.minPercent;
        return Math.max(policy.minPercent, Math.min(100, Math.round(percent)));
    }

    /// Set the panel, by name.
    ///
    /// Named rather than defaulted, because the probe already answered which
    /// backlight is the panel and re-guessing per call is how the keyboard LED
    /// gets dimmed instead. `-q` because the reply is not read on success —
    /// the sysfs value is, and it is the truth rather than a report of it.
    function setCommand(device: string, percent: int): var {
        return ["brightnessctl", "-d", device, "-q", "set", policy.clamp(percent) + "%"];
    }

    /// Whether a finished `brightnessctl` did what it was asked.
    ///
    /// Unlike hyprctl (#78, which answers `ok` to rules it refuses), the exit
    /// status here is the whole answer: 1 and a line on stderr for a device it
    /// cannot find, 0 when it worked.
    function accepted(exitCode: int): bool {
        return exitCode === 0;
    }

    // Both outcomes get a line, and both name the value: a state change with no
    // log line is one no harness can assert on (#81), and a failure logged
    // without what was attempted is one nobody can reproduce.
    function applied(device: string, percent: int): string {
        return "backlight " + device + " set to " + policy.clamp(percent) + "%";
    }

    function complaint(device: string, percent: int, exitCode: int, stderr: string): string {
        return "backlight " + device + " refused " + policy.clamp(percent) + "% — exit "
            + exitCode + (stderr ? ": " + stderr.trim() : "");
    }

    /// What the panel is *doing*, rather than what was last asked of it — the
    /// two differ while a fade is in flight, and on hardware that clamps.
    function valuePath(device: string): string {
        return device ? "/sys/class/backlight/" + device + "/actual_brightness" : "";
    }

    /// A sysfs read, which arrives as text with a trailing newline and can
    /// arrive as nothing at all while the FileView is still catching up.
    function number(text: string): int {
        const value = parseInt((text || "").trim(), 10);
        return isNaN(value) ? 0 : value;
    }

    // --- freshness (#186) ----------------------------------------------------
    //
    // The file view asks to watch the panel's value and cannot be told, because
    // a sysfs attribute change arrives as a `sysfs_notify` poll() wakeup and not
    // as an inotify event. So a brightness the shell did not set — a terminal
    // `brightnessctl`, a compositor keybind, firmware — was invisible to it
    // until the shell next wrote brightness itself, and every surface then
    // showed a level twelve minutes old while the next key press stepped from
    // it.
    //
    // The cure is to re-read on demand rather than to keep reading: what is due
    // and when anything ticks at all is decided here, and the facade next door
    // only owns the read.

    /// How long a read stays trusted. Short, because the point is that anything
    /// may have moved the panel; long enough that a drawer and a bar module
    /// appearing in the same frame are one read rather than two.
    readonly property int staleMs: 250

    /// How often to re-read while a surface is displaying a level. Only ever
    /// armed while one is — see `pollRunning`.
    readonly property int pollMs: 2000

    /// Whether a value stamped at `lastReadAt` needs reading again.
    ///
    /// A stamp of 0 is "never read", and its value is the facade's pre-read 0%.
    /// A stamp in the future is a clock that moved — suspend and resume, which
    /// is exactly the transition most likely to have changed the panel behind
    /// the shell's back — and is read rather than trusted.
    function readDue(nowMs: real, lastReadAt: real): bool {
        if (!isFinite(nowMs) || !isFinite(lastReadAt) || lastReadAt <= 0)
            return true;
        if (nowMs < lastReadAt)
            return true;
        return nowMs - lastReadAt >= policy.staleMs;
    }

    /// Whether the re-read timer should be running.
    ///
    /// #186's constraint, and the reason this is a count rather than a flag:
    /// nothing new may tick while no surface is showing brightness, and the
    /// drawer and the bar module can each be showing one at the same time. A
    /// count below zero is a release that ran twice and arms nothing.
    function pollRunning(watchers: int, available: bool): bool {
        return available === true && watchers > 0;
    }

    /// #81: a subscription that logs nothing is a wakeup nobody can account for
    /// later — and both edges get a line, because "it stopped when the drawer
    /// closed" is the half a harness can only see by reading for it.
    function watching(watchers: int, intervalMs: int): string {
        return "re-reading every " + intervalMs + "ms for " + watchers + " watcher(s)";
    }

    function idle(): string {
        return "nothing showing brightness — stopped re-reading";
    }
}
