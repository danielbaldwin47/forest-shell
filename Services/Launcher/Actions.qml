pragma Singleton

// The actions provider (#40) — `/` in, a shell that has done something out.
//
//     Actions.rows("dark")        what the launcher should show
//     Actions.run(descriptor)     do it
//
// The table is ActionsPolicy.qml next door, where `tests/` can reach it. What
// is here is the four doors it dispatches through, and each one is somebody
// else's: the theme's mode, the lock, the surface bus, the settings window.
// This file owns none of them and adds no state of its own — an action provider
// that held its own idea of whether the shell is in dark mode would be a second
// answer to a question Core/Theme.qml already answers.
//
// ## It imports a surface, which nothing else in Services/ does
//
// `qs.Surfaces.Settings`, for `SettingsWindow.show()` and for the tab registry.
// Two things make that the right call rather than a layering slip:
//
//   - Surfaces/Settings/SettingsWindow.qml documents this exact caller in its
//     own header — `SettingsWindow.show("launcher")  a launcher action (#40)` —
//     and Core/SurfaceBusPolicy.qml explains why settings is deliberately *not*
//     on the surface bus: it is reached as a QML singleton by everything inside
//     the shell, because unlike the launcher and the control centre it already
//     exists. The bus is for surfaces that do not.
//   - Nothing under Surfaces/Settings/ imports `qs.Services.*`, so there is no
//     cycle to walk into. That is checked by reading the imports, and it is the
//     thing to re-check before adding a second surface import here.
//
// The alternative — a signal this emits and the launcher surface connects to
// `SettingsWindow.show()` — was the first draft. It buys nothing: an action
// fired from anywhere but the launcher would then reach a door with nobody
// behind it, which is the opposite of the "scriptable spine" the ticket asks
// for.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import qs.Core
import qs.Services.Screenshot
import qs.Services.Recorder
import qs.Services.System
import qs.Surfaces.Settings

Singleton {
    id: root

    readonly property ActionsPolicy policy: ActionsPolicy {}

    /// The settings window's own tab list, instantiated rather than copied —
    /// ActionsPolicy takes it as an argument precisely so that this file is the
    /// only one that has to know where it lives.
    readonly property SettingsTabs tabs: SettingsTabs {}

    /// What the table is built against right now. A binding, so flipping the
    /// mode from anywhere re-titles the row while the launcher is open.
    readonly property var context: ({ dark: Theme.dark, settingsTabs: root.tabs.tabs })

    function rows(query: string): var {
        return root.policy.rows(query, root.context);
    }

    function silence(query: string): var {
        return root.policy.silence(query);
    }

    // --- running -------------------------------------------------------------

    /// Do what a row's descriptor says. Takes the descriptor the row carried
    /// rather than an id to look up: the table is rebuilt per keystroke, and an
    /// id resolved a second time is an id resolved against a different list.
    ///
    /// Returns whether anything happened, which is what
    /// launcher-harness.qml asserts on — an action that quietly did nothing is
    /// the #81 shape, and the log line below is the other half of not having it.
    function run(descriptor: var): bool {
        const it = descriptor ?? {};
        const id = String(it.id ?? "");

        switch (String(it.kind ?? "")) {
        case "theme": {
            const next = !Theme.dark;
            Theme.setDark(next);
            Logger.log("launcher", root.policy.ran(id, next ? "dark" : "light"));
            return true;
        }
        case "lock":
            Logger.log("launcher", root.policy.ran(id, "the shell's own lock"));
            SessionLock.lock("launcher action");
            return true;
        case "screenshot":
            // Held back by the drawer's own close duration, because the freeze
            // is a photograph of the screen and the launcher is still on it:
            // opened immediately, the shot contains the surface that asked for
            // it, half-faded. The number is the drawer's, which is why it is
            // passed from here rather than assumed over there.
            Logger.log("launcher", root.policy.ran(id, "the region picker"));
            Screenshot.openAfter("launcher action", Theme.motionFast);
            return true;
        case "recording": {
            // The region variant carries the launcher's own close duration for
            // the same reason the screenshot row does — the picker's freeze is
            // a photograph, and the launcher is still on the screen. The
            // whole-screen variant needs no delay: both encoders capture the
            // output live, so a launcher halfway through its fade is a fraction
            // of a second at the head of the file rather than a surface baked
            // into a still.
            if (String(it.arg ?? "") === "region") {
                Logger.log("launcher", root.policy.ran(id, "a recorded region"));
                Recorder.startRegionAfter("launcher action", Theme.motionFast);
                return true;
            }
            Logger.log("launcher", root.policy.ran(id, "the screen recorder"));
            Recorder.toggle("launcher action");
            return true;
        }
        case "surface":
            // Through the bus, not through `Drawers` directly: the bus is what
            // keeps "which surfaces may be asked for" a table rather than an
            // import (Core/SurfaceBusPolicy.qml), and it already logs the ask.
            Logger.log("launcher", root.policy.ran(id, String(it.arg ?? "")));
            SurfaceBus.toggle(String(it.arg ?? ""));
            return true;
        case "settings": {
            const tab = String(it.arg ?? "");
            Logger.log("launcher", root.policy.ran(id, tab !== "" ? tab : "last tab"));
            // `show("")` is the window's own "open where you left it"; the
            // verb the descriptor names for the CLI is `open` for that case and
            // `showTab` for a named one, and neither is `show` (#77).
            SettingsWindow.show(tab);
            return true;
        }
        }

        Logger.warn("launcher", root.policy.unknown(id));
        return false;
    }

    Component.onCompleted: Logger.stage("actions provider armed")
}
