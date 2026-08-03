// forest-shell — entry point.
//
//   qs -p ~/repos/forest-shell/shell.qml
//
// The repo root is the Quickshell config dir (#12 §3): this file is the config,
// layer directories are imported through the `qs.` namespace, and there is no
// symlink into ~/.config/quickshell — the launch is the direct path, which #12
// settled and the #13 assembly refinements closed. That is also what
// shell-switch is registered with and what the keybinds call over IPC.
//
// The runtime is upstream Quickshell >= 0.3.0 at plain `qs`. #57 retired the
// side-by-side `qs-upstream` prefix (#14/#15) that stood in while /usr/bin/qs
// was still the noctalia fork. See integration/README.md.
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
import qs.Surfaces.Drawers
import qs.Surfaces.Osd
import qs.Surfaces.Screenshot

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

    // The shared drawer window (#38) — one per screen, mapped only while a
    // drawer is open, so an idle shell has no surface here at all. Deferred for
    // the same reason the popups are: per-screen layer surfaces are created
    // after the first frame rather than on the way to it.
    LazyLoader {
        id: drawerWindows
        component: DrawerWindow {}
    }

    // The OSD's windows (#46) — one per screen, mapped only while there is a
    // level to report, so an idle shell has no surface here either. Deferred
    // for the same reason the two above are: per-screen layer surfaces are
    // created after the first frame rather than on the way to it.
    //
    // The state and the three services it watches are the `Osd` singleton,
    // constructed in the deferred stage below — naming it is what arms the
    // watchers and registers `qs ipc call osd …`.
    LazyLoader {
        id: osdWindows
        component: OsdWindow {}
    }

    // The region picker's windows (#51) — one per screen, mapped only while a
    // selection is being made, so an idle shell has no surface here either.
    // Deferred for the same reason the three above are.
    //
    // The state behind it is the `Screenshot` singleton, constructed in the
    // deferred stage below; that is what registers `qs ipc call screenshot …`,
    // and it is what this window binds to.
    LazyLoader {
        id: pickerWindows
        component: PickerWindow {}
    }

    Connections {
        target: Startup
        function onDeferredStage() {
            ServiceInit.initDeferred();
            // Naming the singleton is what constructs it, and constructing it
            // is what registers `qs ipc call settings …`. The window itself is
            // not built until something opens it (#54).
            ServiceInit.initSurfaces([SettingsWindow, Drawers, Osd]);
            lock.active = true;
            notificationPopups.active = true;
            drawerWindows.active = true;
            osdWindows.active = true;
            pickerWindows.active = true;
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
