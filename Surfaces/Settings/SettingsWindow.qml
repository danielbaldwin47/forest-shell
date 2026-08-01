pragma Singleton

// The settings window's entry points (#54) — who may open it, and how.
//
// The window itself is `SettingsView.qml`; this is the handle everything else
// holds. There are three callers named in the ticket and they all end up here:
//
//   SettingsWindow.toggle()               the control centre's gear (#45)
//   SettingsWindow.show("launcher")       a launcher action (#40) — `/settings …`
//   qs ipc call settings open             a keybind, a script, the shell switcher
//   qs ipc call settings showTab launcher the same, on a named tab
//
// The IPC target is `settings`, lowercase, matching the surface name — the
// convention the shell-switch contract fixes for `launcher` and every other
// surface with an external entry point.
//
// There is deliberately no IPC `show`, which is #77 and is a Quickshell CLI
// collision rather than a preference. `show` is also a subcommand of `ipc`
// itself, and the client's argument parser takes the literal token: every form
// of `qs ipc call settings show` — with an argument, without one, after `--` —
// is parsed as `qs ipc show` and prints the target listing instead of calling
// anything, and exits 0 while doing it. Measured against this shell in
// tools/settings-harness.sh, which asserts the name stays off the surface: an
// advertised function nobody can call is worse than no function, because it is
// the one everybody types first.
//
// So `open` is the no-argument door and `showTab` is the one that takes a tab.
// The QML-facing `show(tab)` below is untouched — #40 and #45 call it, and it
// never goes near the CLI.
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

    /// Whether the window exists. Named `shown` and not `open` because `open()`
    /// is one of the verbs below, and a property and a function that differ only
    /// by parentheses are a bug waiting for a hurried reader.
    readonly property bool shown: loader.active

    /// Opens the window, or brings the caller's tab to the front of one that is
    /// already open. An unknown tab id opens the first tab rather than failing:
    /// the caller may be a keybind typed by hand, and an empty window would be
    /// a worse answer than the wrong one.
    function show(tab: string): void {
        const wasShown = root.shown;
        loader.active = true;
        if (!loader.item)
            return;

        if (tab !== "")
            loader.item.selectTab(tab);

        // One line per state change worth asserting on, which is what makes the
        // window drivable from tools/settings-harness.sh — #81's lifecycle bug
        // was silent for a week for want of exactly this.
        Logger.log("settings", (wasShown ? "window raised" : "window opened")
                   + " (tab " + loader.item.currentTab + ")");

        // Pressing the gear with the window already open but buried under other
        // windows has to bring it forward, or it reads as a dead button. Asking
        // is all the shell may do — whether the request is honoured is the
        // compositor's call, and under Hyprland's focus rules it may not be.
        // Guarded because raising a toplevel is not part of the surface's
        // documented API; where it is absent this degrades to what it did
        // before, which is nothing.
        if (typeof loader.item.requestActivate === "function")
            loader.item.requestActivate();
    }

    /// Closes the window. `reason` is for the log and may be omitted by a
    /// caller that has nothing to add — #45's gear will.
    function close(reason: string): void {
        if (root.shown)
            Logger.log("settings", "window closed (" + (reason ? reason : "request") + ")");
        loader.active = false;
    }

    function toggle(): void {
        if (root.shown)
            close("toggle");
        else
            show("");
    }

    LazyLoader {
        id: loader

        component: Component {
            SettingsView {
                // Closed by something that is not one of the functions above:
                // the compositor's own close button, or Escape inside the
                // window (#77). The reason travels with the signal so the log
                // says which — a window that vanished and a window that was
                // dismissed look identical afterwards.
                onCloseRequested: reason => root.close(reason)
            }
        }
    }

    // Functions need explicit signatures to be callable over IPC, and `qs ipc
    // show target settings` lists exactly what is below — so this is also the
    // window's documented external surface, not just its plumbing.
    IpcHandler {
        target: "settings"

        // The window, on the tab it was left on. The one to bind a key to.
        function open(): void { root.show(""); }
        // ...and on a named tab. Not `show(tab)`: see the header.
        function showTab(tab: string): void { root.show(tab); }
        function close(): void { root.close("ipc"); }
        function toggle(): void { root.toggle(); }
    }

    Component.onCompleted: Logger.stage("settings window armed (ipc target: settings)")
}
