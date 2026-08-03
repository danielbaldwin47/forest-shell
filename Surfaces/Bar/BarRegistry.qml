// What the bar can carry, and how a config line turns into a row of it (#9,
// #35).
//
// The bar has no hardcoded layout: `bar.modules` in settings.json is three
// lists of names, and this file is the only thing that knows which names exist.
// Adding a module is two lines — an entry here, and the file it names under
// `Modules/`. Nothing else in the bar changes, and the user's file does not
// have to either.
//
// **Presence is enablement.** There is no `enabled` flag, because a module that
// is off is a module that is not in a list, and two ways to express the same
// state is one way too many for a file people hand-edit. The off-by-default
// optional modules from the feature inventory ship as registry entries that no
// default list names.
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    id: root

    /// name → `{ file, label }`. `file` is resolved against `Modules/` by the
    /// bar; `label` is what the settings GUI (#55) will call it.
    ///
    /// The Standard-14 inventory (#9) lands across three tickets: #35 brought
    /// the two modules that make the bar usable, #36 the status cluster, the
    /// battery and the optional brightness readout, and #37 the rest — the
    /// tray, media, active window, keyboard layout and the two surface
    /// buttons, and #43 the notification indicator that completes them. #50
    /// added the system-monitor readout, which rides on the dashboard card's
    /// sampler. What is left are the two other off-by-default optionals (night
    /// light, recorder).
    ///
    /// `status` is one entry and not four: #9 groups network, bluetooth, volume
    /// and mic into a single quiet icon cluster, and four entries would let a
    /// config scatter them across three clusters of the bar.
    readonly property var modules: ({
        workspaces: { file: "Workspaces.qml", label: "Workspaces" },
        clock: { file: "Clock.qml", label: "Clock" },
        status: { file: "Status.qml", label: "Status" },
        battery: { file: "Battery.qml", label: "Battery" },
        // #37. Four readouts and two doors: the doors dispatch through
        // Core/SurfaceBus.qml to surfaces that do not exist yet (#39, #44) and
        // log a line until they do.
        launcher: { file: "LauncherButton.qml", label: "Launcher button" },
        activeWindow: { file: "ActiveWindow.qml", label: "Active window" },
        media: { file: "Media.qml", label: "Media" },
        tray: { file: "Tray.qml", label: "System tray" },
        keyboard: { file: "KeyboardLayout.qml", label: "Keyboard layout" },
        controlCenter: { file: "ControlCenterButton.qml", label: "Control centre button" },
        // #43, the fourteenth. The file is not `Notifications.qml` because the
        // modules directory is imported explicitly and a type of that name
        // would shadow the service singleton the module reads.
        notifications: { file: "NotificationIndicator.qml", label: "Notifications" },
        // Shipped, and in no default list (#9). A module that is off is a
        // module no cluster names — see the note on enablement above.
        brightness: { file: "Brightness.qml", label: "Brightness" },
        // #50, and the one optional module with a running cost: it holds a
        // subscription on Services/System/SystemStats.qml for as long as it is
        // on the bar, which is the sampler the dashboard card starts and stops.
        systemMonitor: { file: "SystemMonitor.qml", label: "System monitor" }
    })

    readonly property var clusters: ["left", "center", "right"]

    function known(name: string): bool {
        return root.modules[name] !== undefined;
    }

    /// The three clusters, cleaned: unknown names dropped, repeats dropped,
    /// order preserved.
    ///
    /// A name the shell does not have is a typo or a module from a version that
    /// is not installed. Both are reported and skipped rather than defaulted,
    /// because there is no sensible substitute for "the thing you asked for" —
    /// and a config that names one bad module still gets the rest of its bar.
    ///
    /// Repeats go because a module is a thing on the bar rather than a
    /// template: two notification indicators would disagree about which one you
    /// just clicked. The check spans clusters, so a module cannot be in two
    /// places at once either.
    function resolve(layout: var): var {
        const out = {};
        const seen = {};

        for (const cluster of root.clusters) {
            const names = (layout && layout[cluster]) || [];
            const kept = [];
            for (const name of names) {
                if (!root.known(name)) {
                    console.warn("bar: no such module:", name);
                    continue;
                }
                if (seen[name]) {
                    console.warn("bar: module listed twice:", name);
                    continue;
                }
                seen[name] = true;
                kept.push(name);
            }
            out[cluster] = kept;
        }

        return out;
    }
}
