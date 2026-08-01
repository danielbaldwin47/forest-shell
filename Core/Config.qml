// User settings, read from ~/.config/forest-shell/settings.json.
//
// STUB — the config engine ticket (#33) replaces the internals with the spec
// table, the state file, sparse writes and migrations. What is settled here and
// must not change under it: the file location, `Config.ready` as the gate every
// surface waits on (#12 §4 — no defaults-flash-then-snap), defaults merged
// under user values, and a bad file leaving the last good config in place.
//
// Reading is *synchronous* on purpose: it is stage one of startup, and the
// background surface needs the configured wallpaper for the very first frame.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Nested by section, mirroring the GUI tabs to come (#12 §5).
    readonly property var defaults: ({
        settingsVersion: 1,
        background: {
            // Empty means "no wallpaper set" — the background surface then
            // renders its own gradient rather than a black hole.
            wallpaper: ""
        }
    })

    // Defaults with the user's file merged over them. Never null, so bindings
    // formed before the first read still resolve.
    property var settings: defaults

    // False until the first read settles (found, missing, or broken). Surfaces
    // gate content instantiation on this.
    property bool ready: false

    signal reloaded()

    readonly property string wallpaper: settings.background?.wallpaper ?? ""

    function load() {
        const result = json.parse(file.text());
        if (!result.ok) {
            // Keep the last good config; never rewrite a file we failed to
            // understand. (#33 turns this into a user-visible notice.)
            Logger.warn("config", "ignoring " + Paths.settingsFile + ": " + result.error);
            return;
        }
        root.settings = json.merge(root.defaults, result.value);
        if (root.ready)
            Logger.log("config", "reloaded " + Paths.settingsFile);
        root.reloaded();
    }

    Component.onCompleted: {
        load();
        ready = true;
        Logger.stage("config ready");
    }

    JsonMerge { id: json }

    FileView {
        id: file
        path: Paths.settingsFile
        blockLoading: true   // stage one: the wallpaper depends on this
        watchChanges: true
        printErrors: false   // a missing settings file is the normal first run

        onFileChanged: reload()
        // Skip the load that the startup read itself triggers.
        onLoaded: if (root.ready) root.load()
    }
}
