pragma Singleton

// Whether the bar is on screen, and the two ways to say so (#12 §7).
//
// A surface declares its own IPC target and its own keybinds, in its own
// directory — there is no central IPC file. The target is the surface name,
// lowercase, and query functions return JSON strings:
//
//     qs ipc call bar toggle
//     bind = SUPER, B, global, forest-shell:bar-toggle
//
// This is one singleton rather than a property on the window because there is
// one bar across every screen: hiding it hides all of them, and an IpcHandler
// declared inside `Variants` would try to register the same target once per
// monitor.
//
// Hiding is *not* destroying. The window stays mapped-capable and alive; only
// its content is dropped, on a debounce, by the DebouncedLoader in Bar.qml
// (#12 §2, #22 §5) — surface create/destroy churn is the compositor-crash class
// the reference-shell survey found, and an unmapped window with no content
// contributes zero wakeups, which is the cheaper half of what destroying it
// would have bought.
//
// Session-scoped on purpose: this is situational, not intent, so it is neither
// config nor state (#21). A restarted shell has its bar back.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Core

Singleton {
    id: root

    property bool shown: true

    function show() { root.shown = true; }
    function hide() { root.shown = false; }
    function toggle() { root.shown = !root.shown; }

    IpcHandler {
        target: "bar"

        function show(): void { root.show(); }
        function hide(): void { root.hide(); }
        function toggle(): void { root.toggle(); }
        function status(): string { return JSON.stringify({ shown: root.shown }); }
    }

    GlobalShortcut {
        appid: "forest-shell"
        name: "bar-toggle"
        description: "Show or hide the bar"
        onPressed: root.toggle()
    }

    onShownChanged: Logger.log("bar", root.shown ? "shown" : "hidden (windows kept, content unloading)")
}
