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
import qs.Services.Screenshot
import qs.Services.Recorder
import qs.Services.Weather
import qs.Services.Theming

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
        // Claude (#41) is the calculator's argument twice over: it probes
        // `claude auth status` once, and it has a directory to create before
        // the first turn can run in it. Constructed on the first `?`, the
        // panel would take a question, spawn into a working directory that
        // does not exist yet, and fail in the shape of a missing binary.
        // The control centre's three (#44) are here for two different reasons.
        // PowerProfiles and Vpn each read their state with a subprocess and
        // never poll after it, so constructing them when the drawer opens would
        // put a `powerprofilesctl` and an `nmcli` in flight while the grid was
        // already on screen — the tile would be absent for the first frames of
        // every first open, which reads as a machine that has no such hardware.
        // NightLight is the sharper case: it is the only one of the three whose
        // state does not survive the session it was set in, so it has to *act*
        // at startup rather than merely be read — a shell restarted with the
        // toggle on leaves a 6500K screen under a tile that says 4000 until
        // something re-runs the command (Services/Hardware/NightLight.qml).
        //
        // KeepAwake is deliberately not here: it holds no client and spawns
        // nothing, and the control centre is the only thing that reads it. Its
        // window is created by the toggle, which is the one moment it matters.
        //
        // The idle ladder and the logind bridge (#48) are the sharpest case on
        // this list. Nothing reads either of them: the ladder is four
        // `IdleMonitor`s that only ever *fire*, and the bridge is a helper
        // process and a delay inhibitor that only ever *hear*. Without a name
        // here neither would be constructed at all, and the failure would be
        // silent in the worst possible way — a machine that never locks, and a
        // suspend that never waits for the lock it did not take.
        //
        // Weather (#50) is here for what it does *not* do. Naming it constructs
        // it, and construction reads the cached forecast out of `state.json` —
        // a file read, no network. The first request waits for the card to
        // appear over a stale reading, which is what keeps the shell's startup
        // free of network cost and keeps a poll from running behind a closed
        // drawer (#22 §5). Without a line here the cache would only be read the
        // first time a dashboard opened, so the first open of every session
        // would show an empty card while a fetch was in flight.
        //
        // Services/System/SystemStats.qml is deliberately *not* on this list,
        // and it is the sharpest case for the rule cutting the other way: it is
        // the one service in this shell that costs something continuously, it
        // does nothing at all until a surface subscribes, and there is no
        // startup work for a force-touch to bring forward. The dashboard card
        // and the optional bar module construct it by using it.
        //
        // Deferred rather than sync, because the first stage is minutes away and
        // the wallpaper is not: the only cost of arriving a frame late is a
        // ladder that starts counting a frame late.
        // Screenshot (#51) is here for the same reason the lock is: nothing in
        // the shell reads it, and naming it is what registers `qs ipc call
        // screenshot …` and probes for `wl-copy`. A keybind aimed at a target
        // that was never constructed is the #81 shape — a key that does
        // nothing, with no line in the log saying why.
        //
        // Recorder (#52) is here for that reason and one more: naming it is
        // what runs the two encoder probes, so the control centre can say
        // whether this machine records on the GPU or in software before
        // anybody presses the tile.
        // Themes (#56) is Screenshot's argument in Core: nothing in the shell
        // reads it until the Appearance tab is opened, and naming it is what
        // registers `qs ipc call theme …` — the door a keybind that swaps skins
        // goes through, and the one tools/theme-harness.sh drives. It reads the
        // undo slot on construction, which is a file read and no more.
        // Theming (#58) is the list's original argument in its purest form:
        // *nothing* references it. It publishes through the settings file, so
        // no surface has a reason to name it, and without a line here the
        // wallpaper-coupled accent would simply never be computed — the mode
        // would be selectable in the settings window and do nothing.
        //
        // Deferred and not sync on purpose. The first frame paints the accent
        // already in the settings file, which is the one this machine sampled
        // last session; quantizing the wallpaper to confirm it is not worth a
        // frame, and doing it before the wallpaper would delay the thing it is
        // reading.
        report("deferred", [ShellState, Themes, Theming, Notifications, Compositor,
                            Audio, Networking, Bluetooth, Power, Backlight,
                            SystemTray, Mpris, Apps, Calculator, Claude,
                            PowerProfiles, NightLight, Vpn,
                            LogindBridge, Idle, Weather, Screenshot, Recorder]);
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
