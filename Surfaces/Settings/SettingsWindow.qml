pragma Singleton

// The settings window's entry points (#54) — who may open it, and how.
//
// The window itself is `SettingsView.qml`; this is the handle everything else
// holds. There are three callers named in the ticket and they all end up here:
//
//   SettingsWindow.toggle()             the control centre's gear (#45)
//   SettingsWindow.show("launcher")     a launcher action (#40) — `/settings …`
//   qs ipc call settings show launcher  a keybind, a script, the shell switcher
//
// The IPC target is `settings`, lowercase, matching the surface name — the
// convention the shell-switch contract fixes for `launcher` and every other
// surface with an external entry point.
//
// Neither the control centre nor the launcher exists yet (#39, #45), so the IPC
// handler is not a convenience here: it is the only way to open the window, and
// therefore the way this ticket's first acceptance criterion is exercised until
// those surfaces land and call the same three functions.
//
// The window is built when it is first opened and destroyed when it is closed.
// It is not a panel — nothing about it needs to survive being hidden, and every
// page is a pure view over `Config`, so a reopened window is rebuilt from the
// file and shows exactly what it showed before. The tab it opens on is the one
// thing that has to outlive it, and that is in the state file.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core

Singleton {
    id: root

    readonly property bool open: loader.active

    /// Opens the window, or brings the caller's tab to the front of one that is
    /// already open. An unknown tab id opens the first tab rather than failing:
    /// the caller may be a keybind typed by hand, and an empty window would be
    /// a worse answer than the wrong one.
    function show(tab: string): void {
        loader.active = true;
        if (tab !== "" && loader.item)
            loader.item.selectTab(tab);
    }

    function close(): void {
        loader.active = false;
    }

    function toggle(): void {
        if (root.open)
            close();
        else
            show("");
    }

    LazyLoader {
        id: loader

        component: Component {
            SettingsView {
                // The compositor's own close button — the only place in the
                // shell where a window is dismissed by something outside it, and
                // the reason the loader is driven by a signal rather than only
                // by the functions above.
                onCloseRequested: loader.active = false
            }
        }
    }

    // Functions need explicit signatures to be callable over IPC, and `qs ipc
    // show target settings` lists exactly what is below — so this is also the
    // window's documented external surface, not just its plumbing.
    IpcHandler {
        target: "settings"

        function open(): void { root.show(""); }
        function show(tab: string): void { root.show(tab); }
        function close(): void { root.close(); }
        function toggle(): void { root.toggle(); }
    }

    Component.onCompleted: Logger.stage("settings window armed (ipc target: settings)")
}
