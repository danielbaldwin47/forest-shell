// forest-shell — entry point.
//
//   qs-upstream -p ~/repos/forest-shell/shell.qml
//
// The repo root is the Quickshell config dir (#12 §3): this file is the config,
// layer directories are imported through the `qs.` namespace, and there is no
// symlink into ~/.config/quickshell. `qs-upstream` is the dev wrapper for the
// side-by-side upstream 0.3.0 prefix (#14) — the runtime swap ticket (#57)
// retires it.
//
// Startup is staged (Core/Startup.qml):
//   stage 1, synchronous — Config, Theme, Background. The wallpaper is on the
//                          first frame; nothing else belongs here.
//   stage 2, deferred    — chained off the first painted frame, so no service
//                          construction can delay it.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Core
import qs.Surfaces.Background

ShellRoot {
    id: shell

    Component.onCompleted: {
        // Runs after the children below are complete, so by now Config has been
        // read synchronously and the wallpaper is resolved — this line is the
        // log evidence of that, not what causes it.
        Logger.stage("shell root loaded (config " + (Config.ready ? "ready" : "pending")
                     + ", theme " + Theme.fontUi + ")");
        ServiceInit.initSync();
    }

    // Stage one.
    Background {}

    // Stage two. Surfaces and services added by later tickets hook in here.
    Connections {
        target: Startup
        function onDeferredStage() {
            ServiceInit.initDeferred();
        }
    }
}
