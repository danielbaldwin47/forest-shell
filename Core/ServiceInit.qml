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
import qs.Services.Compositor

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
        // Compositor is named here rather than left to the bar: it subscribes
        // to Hyprland's event socket, and a shell whose bar is hidden still
        // wants that subscription live so the row is right the moment it comes
        // back.
        report("deferred", [ShellState, Compositor]);
    }

    function report(stage: string, services) {
        Logger.log("services", stage + " stage: " + services.length + " service(s) constructed");
    }
}
