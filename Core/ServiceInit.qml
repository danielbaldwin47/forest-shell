pragma Singleton

// Force-touches the services that must run whether or not any surface is
// looking at them (#12 §4): a QML singleton nothing references is never
// constructed, so a service that only listens — battery, notifications, idle —
// would silently never start.
//
// Naming a singleton in one of the lists below is what constructs it, and the
// lists are built *inside* the functions on purpose: a `property var` holding
// them would be evaluated when this singleton is created, which is stage one —
// and the whole point of the deferred list is that it is not.
//
// Nearly empty — the shell has no services yet. Later tickets add a name per
// line to the right list and touch nothing else.
import QtQuick
import Quickshell
import qs.Services.Notifications
import qs.Services.Compositor
import qs.Services.Media
import qs.Services.Networking
import qs.Services.Hardware
import qs.Services.System
import qs.Services.Launcher

Singleton {
    id: root

    // Stage one, before the first frame. Keep this nearly empty: everything
    // here is on the critical path to the wallpaper.
    function initSync() {
        report("sync", []);
    }

    // Stage two, after the first frame: tray, weather, stats sampling, Claude
    // warmup.
    //
    //   report("deferred", [SystemTray, Weather]);
    function initDeferred() {
        // ShellState is not a service, but it has the same problem: it is
        // written by whoever touches it and read by nobody at startup, so
        // without a name here its file would only be read the first time some
        // surface happened to ask (#33). Deferred, because nothing in it is
        // worth a frame.
        //
        // Notifications is the archetype the list exists for: it is a daemon.
        // Nothing references it until something has already been notified, so
        // without this line the shell would take the bus name only once a
        // surface asked — which is to say, after the first notification had
        // already been lost (#42).
        //
        // Compositor is here because the bar's Hyprland layerrule has to be
        // pushed whether or not anything on the bar is currently reading
        // workspaces — a bar carrying only a clock would otherwise never
        // construct the facade, and would sit unblurred (#35).
        //
        // The five system services (#36) are here for the reason the list
        // exists, and one more: each of the native backends only *starts*
        // when something first touches its singleton, and each then takes
        // about a second to answer (measured — UPower, NetworkManager and
        // BlueZ all populate ~1s after first access). A service constructed
        // when the user first opens the control centre would spend that
        // second showing a shell that owns no radios and has no battery. Off
        // the critical path, because none of it is worth a frame: the
        // wallpaper does not depend on the volume.
        // The tray and MPRIS (#37) are here for a sharper version of the same
        // reason. Both upstream clients are lazy: nothing takes the
        // `org.kde.StatusNotifierWatcher` name until something in QML first
        // touches the tray singleton, and an application that registered its
        // icon before that has to be restarted to get it back. A tray that
        // only started when the bar happened to carry the module would lose
        // every icon on a bar configured without it — and worse, would lose
        // them on a bar that has it, since the modules load a beat after the
        // services do.
        // Apps (#39) is the same lazy-backend argument as the tray, measured
        // rather than assumed: `DesktopEntries.applications` does not begin its
        // scan until something observes it, and it then fills in one entry at a
        // time over some tens of milliseconds. Constructed when the user first
        // presses Super+Space, the launcher would open onto an empty list and
        // populate under their hands. Deferred, because 190 desktop files are
        // not worth a frame.
        // Calculator (#40) is here for a narrower reason than the rest: it
        // probes for `qalc` once, and the answer is what the launcher shows
        // instead of a result on a machine without it. Constructed on the
        // first `=`, the probe would still be in flight while the user typed
        // the sum — so the first thing they saw would be "Working…" followed
        // by "qalc is not installed", which is a worse way to learn it than
        // being told immediately. It spawns one short-lived process and reads
        // nothing else, so it is the cheapest entry on this list.
        report("deferred", [ShellState, Notifications, Compositor,
                            Audio, Networking, Bluetooth, Power, Backlight,
                            SystemTray, Mpris, Apps, Calculator]);
    }

    // Surfaces have the same problem for a different reason: a window nothing
    // has opened yet still has to *exist* enough to register its IPC target and
    // its global shortcut, or the keybind that would open it has nothing to
    // call. Passed in by the caller rather than named here, because these live
    // under `Surfaces/` and Core does not import upwards.
    //
    //   ServiceInit.initSurfaces([SettingsWindow]);
    function initSurfaces(surfaces) {
        report("surface", surfaces);
    }

    function report(stage: string, services) {
        Logger.log("services", stage + " stage: " + services.length + " object(s) constructed");
    }
}
