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
        report("deferred", [ShellState, Notifications]);
    }

    function report(stage: string, services) {
        Logger.log("services", stage + " stage: " + services.length + " service(s) constructed");
    }
}
