pragma Singleton

// The OSD's state, and the three services it watches (#46, topology from
// #12 §3).
//
//     qs ipc call osd pop volume 45     from a harness, or a script
//     qs ipc call osd hide
//
// What this is *for*: the machine's volume, microphone and backlight change
// from four directions — the keys, the control centre's sliders, a `wpctl` in a
// terminal, and an application setting its own stream — and the answer to "what
// did that do" has to be the same in all four. So nothing here listens for a
// keypress. It watches the three facades, which are already the one place each
// value is true, and pops on a *change*. A volume key bound to `wpctl` in
// hyprland.conf pops this surface without the shell having heard the key.
//
// ## What to bind the keys to
//
// Audio is free: PipeWire pushes every change to every client, so any tool that
// moves the volume moves this. **Brightness is not.** The value is a sysfs
// attribute, and a change to one is delivered by `sysfs_notify` — a poll()
// wakeup rather than an inotify event — so `FileView.watchChanges` only catches
// the drivers that also touch the file (Services/Hardware/Backlight.qml says so
// where the watcher is). A key bound straight to `brightnessctl` may therefore
// move the panel without this ever hearing about it. The shell's own door does
// not have that problem, because setting the value is what re-reads it:
//
//     bind = , XF86AudioRaiseVolume,  exec, qs ipc call controlcenter nudge volume 1
//     bind = , XF86AudioLowerVolume,  exec, qs ipc call controlcenter nudge volume -1
//     bind = , XF86AudioMute,         exec, qs ipc call controlcenter mute volume
//     bind = , XF86AudioMicMute,      exec, qs ipc call controlcenter mute mic
//     bind = , XF86MonBrightnessUp,   exec, qs ipc call controlcenter nudge brightness 1
//     bind = , XF86MonBrightnessDown, exec, qs ipc call controlcenter nudge brightness -1
//
// Those are the control centre's own routing table (#44), which is the point:
// one table, so a key and a finger on the slider do the same thing and this
// surface reports both.
//
// ## The arming rule, which is the whole reason there is a policy
//
// Every channel's first reading is a jump from nothing to whatever the machine
// was already at: PipeWire answers a frame or two after the shell starts, the
// backlight probe answers after that, and both look exactly like the user
// pressing a key. Same again when a device goes away and comes back — plugging
// headphones in brings a different sink at its own level. Those *arm* the
// channel rather than pop it, and Surfaces/Osd/OsdPolicy.qml decides which is
// which so `tests/` can check it without a compositor.
//
// ## Zero idle cost (#22 §5)
//
// Nothing here polls and nothing here animates. The snapshots below are
// bindings on properties PipeWire and the sysfs watcher *push*; the dismiss
// timer runs only while the pill is up; the windows (Surfaces/Osd/OsdWindow.qml)
// are one per screen, mapped only while `shown`, and hold no content when they
// are not (Widgets/DebouncedLoader.qml).
//
// The windows are deliberately not owned here: they are one per screen inside a
// `Variants`, created and destroyed by hotplug, and a singleton holding
// references to those is the dangling-`ShellScreen` bug
// Surfaces/Drawers/Drawers.qml refuses to have for the same reason.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Services.Media
import qs.Services.Hardware
import qs.Services.System
import qs.Surfaces.Drawers

Singleton {
    id: root

    readonly property OsdPolicy policy: OsdPolicy {}

    /// The layer-shell namespace, and so the handle any Hyprland rule for this
    /// surface is written against.
    readonly property string layerNamespace: "forest-shell:osd"

    /// What the pill is showing, or `""`. Written by `pop()` and `hide()` and
    /// by nothing else — those two are where the log lines live, and a state
    /// change that did not go through them is one the harness cannot see (#81).
    property string channel: ""
    property int percent: 0
    property bool muted: false

    /// Whether there is a pill on screen. The window binds its `visible` to
    /// this plus its own fade, so this is "the OSD is up" and not "a surface is
    /// mapped".
    property bool shown: false

    // --- the settings (#46: geometry and timeout are authored defaults) ------
    //
    // Under `controlCenter` because that is the section that owns these three
    // channels' controls — Core/SettingsSchema.qml argues it at length, and the
    // short version is that #21 fixes the section list at nine.

    readonly property var settings: Config.values.controlCenter.osd
    readonly property int timeoutMs: root.policy.timeoutMs(root.settings.timeout)
    readonly property string position: root.settings.position
    readonly property int margin: root.settings.margin

    // --- what the three services are doing -----------------------------------
    //
    // One snapshot per channel, each a binding on the facade. A `var` object
    // rebuilt on every dependency change, so its `onChanged` is exactly "one of
    // these three numbers moved" — which is the event, and the only event.

    readonly property var volumeState: ({
        available: Audio.hasSink, percent: Audio.percent, muted: Audio.muted
    })

    // The mic's level has no whole-number readout on the facade — the bar never
    // needed one, because a mic has no indicator, only a mute glyph — so it is
    // rounded here rather than by reaching through `Audio` into its policy,
    // which is a call that would keep working if the service stopped answering.
    readonly property var micState: ({
        available: Audio.hasSource,
        percent: root.policy.clampPercent(Audio.sourceVolume * 100),
        muted: Audio.sourceMuted
    })

    readonly property var brightnessState: ({
        available: Backlight.available, percent: Backlight.percent, muted: false
    })

    onVolumeStateChanged: root.observe("volume", root.volumeState)
    onMicStateChanged: root.observe("mic", root.micState)
    onBrightnessStateChanged: root.observe("brightness", root.brightnessState)

    /// The last reading of each channel, by name, stamped with the moment that
    /// channel was armed. A plain object mutated in place: nothing binds to it,
    /// and replacing it wholesale on every volume tick would be an allocation
    /// per keypress for no notification anyone wants.
    property var seen: ({})

    function observe(channel: string, state: var): void {
        const previous = root.seen[channel] ?? null;
        const now = Date.now();
        const verdict = root.policy.observe(previous, state, now);
        root.seen[channel] = root.policy.record(previous, state, now);

        if (verdict === "arm")
            // Logged, because "the OSD did not pop" has two causes — armed, or
            // broken — and seam 2 has to be able to tell them apart (#81).
            Logger.log("osd", root.policy.armed(channel, state.percent));
        else if (verdict === "pop")
            root.pop(channel, state.percent, state.muted);
    }

    // --- showing it -----------------------------------------------------------

    /// Put the pill up, or replace what is in it. Called on every change, so a
    /// held volume key lands here ten times a second: each call restarts the
    /// dismiss timer and moves the level *in place* — the window is already
    /// mapped and stays mapped, which is what #27's "in-place value update at
    /// 140" means in lifecycle terms.
    function pop(channel: string, percent: var, muted: bool): void {
        if (!root.policy.known(channel)) {
            Logger.warn("osd", root.policy.refused(channel));
            return;
        }

        if (root.policy.suppressed(Drawers.current, SessionLock.locked)) {
            Logger.log("osd", root.policy.suppressedBy(
                SessionLock.locked ? "lock" : Drawers.current));
            return;
        }

        root.channel = channel;
        root.percent = root.policy.clampPercent(percent);
        root.muted = muted === true;
        root.shown = true;
        dismiss.restart();

        Logger.log("osd", root.policy.shown(root.channel, root.percent, root.muted));
    }

    function hide(reason: string): void {
        if (!root.shown)
            return;
        dismiss.stop();
        root.shown = false;
        Logger.log("osd", root.policy.hidden(reason));
    }

    /// The dismiss. Explicitly started and stopped rather than bound to
    /// `shown`, because a second pop while the pill is up has to restart it —
    /// a `running:` binding would leave the first keypress's countdown in
    /// charge of the tenth's.
    Timer {
        id: dismiss
        interval: root.timeoutMs
        repeat: false
        onTriggered: root.hide("timeout")
    }

    // Something that answers the same question better took the screen. The pill
    // goes away rather than sitting on top of the control the user just opened
    // — and the OSD is the thing that yields, because the drawer and the lock
    // were both asked for and this was not.
    Connections {
        target: Drawers
        function onCurrentChanged(): void {
            if (root.shown && root.policy.suppressed(Drawers.current, SessionLock.locked))
                root.hide("suppressed");
        }
    }

    Connections {
        target: SessionLock
        function onLockedChanged(): void {
            if (root.shown && SessionLock.locked)
                root.hide("suppressed");
        }
    }

    // --- the door -------------------------------------------------------------
    //
    // For seam 2 first and for scripts second. `pop` and `hide` and not `show`:
    // `qs ipc call osd show …` is parsed as `qs ipc show` and prints the target
    // listing instead (#77, and Core/SurfaceBusPolicy.qml). Functions need
    // explicit signatures to be callable over IPC.
    //
    // What this buys the harness is a pill on the screen without touching the
    // machine: the nested session shares the host's PipeWire and the host's
    // backlight, so a seam-2 check that drove the *real* path would be one that
    // changed the volume of the session running it.
    IpcHandler {
        target: "osd"

        function pop(channel: string, percent: int): void {
            root.pop(channel, percent, false);
        }

        function popMuted(channel: string, percent: int): void {
            root.pop(channel, percent, true);
        }

        function hide(): void { root.hide("ipc"); }

        function isShown(): bool { return root.shown; }
        function channel(): string { return root.channel; }
        function level(): int { return root.percent; }
        function readout(): string {
            return root.channel === "" ? ""
                 : root.policy.readout(root.channel, root.percent, root.muted);
        }
    }

    Component.onCompleted: Logger.log("osd", "osd armed (ipc target: osd, "
                                      + root.position + ", " + root.timeoutMs + "ms)")
}
