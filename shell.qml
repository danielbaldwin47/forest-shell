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
//   stage 1, synchronous — Config, Theme, Background, Bar. #22 §4 budgets the
//                          first frame as "wallpaper *and bar* rendered", so
//                          both surfaces are here; nothing else belongs.
//   stage 2, deferred    — chained off the first painted frame, so no service
//                          construction can delay it.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Core
import qs.Surfaces.Background
import qs.Surfaces.Settings
import qs.Surfaces.Lock
import qs.Surfaces.Notifications
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

    // Stage one. Both are one window per screen, created and destroyed by
    // screen hotplug and by nothing else (#22 §1, §3).
    Background {}
    Bar {}

    // Stage two. Surfaces and services added by later tickets hook in here.
    //
    // Notification popups are a surface, not a service: the daemon behind them
    // starts with ServiceInit below, and these are the windows it draws into
    // (#42). Held in a LazyLoader so their per-screen layer surfaces are created
    // after the first frame rather than on the way to it.
    LazyLoader {
        id: notificationPopups
        component: Popups {}
    }

    Connections {
        target: Startup
        function onDeferredStage() {
            ServiceInit.initDeferred();
            // Naming the singleton is what constructs it, and constructing it
            // is what registers `qs ipc call settings …`. The window itself is
            // not built until something opens it (#54).
            ServiceInit.initSurfaces([SettingsWindow]);
            lock.active = true;
            notificationPopups.active = true;
        }
    }

    // The lock (#47). It maps no Wayland surface and opens no PAM conversation
    // until something locks the session, so what is being deferred here is only
    // the cost of building it — but it is also what registers the `lock` IPC
    // target, so it must be up by the time the shell calls itself interactive
    // (#22 §4). `active` rather than `loading`: interactive is a claim about
    // what is reachable, and a target still loading in a frame gap is not.
    LazyLoader {
        id: lock
        active: false
        Lock {}
    }
}
