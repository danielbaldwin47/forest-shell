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
// Empty for now — the skeleton has no services yet. Later tickets add a name
// per line to the right list and touch nothing else.
pragma Singleton
import QtQuick
import Quickshell

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
        report("deferred", []);
    }

    function report(stage: string, services) {
        Logger.log("services", stage + " stage: " + services.length + " service(s) constructed");
    }
}
