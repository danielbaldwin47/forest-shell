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
import qs.Surfaces.Bar

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

    // Stage two. The bar declares itself here but builds its windows off the
    // first painted frame — the gate is inside Bar.qml, on the `Variants`
    // model, so the surface stays one declaration rather than a Loader holding
    // a window.
    Bar {}

    // Stage two. Surfaces and services added by later tickets hook in here.
    Connections {
        target: Startup
        function onDeferredStage() {
            ServiceInit.initDeferred();
        }
    }
}
