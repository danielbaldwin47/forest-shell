// The surface Keep Awake's idle inhibitor hangs on (#44).
//
// `zwp_idle_inhibit_manager_v1` inhibits idling *for a surface*, so the
// inhibitor needs a window — and it must be one that outlives the control
// centre, which closes a second after the tile is pressed. This is that window:
// one pixel, transparent, taking no input, on the background layer.
//
// ## Why this is its own file
//
// A `PanelWindow` cannot be *compiled* without a window backend, and there is
// no backend under `QT_QPA_PLATFORM=offscreen` — which is where
// `tools/capture-harness.sh` renders and where every seam-3 measurement is
// taken. Declared inline in KeepAwake.qml, this window made that singleton
// unloadable offscreen, and with it every file that transitively imports
// Services/Hardware: the whole shell, including surfaces that have nothing to
// do with idling.
//
// A `Loader` with a *string* `source` is what fixes it. An inline `Component`
// is compiled with its enclosing file; a URL is resolved and compiled when the
// loader activates, which offscreen never does — the toggle is off, so the file
// is never read.
//
// It is a layer-shell surface for something invisible, which #22 §5 would
// normally refuse. It earns it by existing *only* while the user has asked to
// be kept awake: an idle shell has no such window, and the one case where it
// does is the case where the machine is deliberately not idling anyway.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: window

    /// Whether the compositor actually took it. Read back by KeepAwake.qml: a
    /// compositor with no `zwp_idle_inhibit_manager_v1` binds nothing, and a
    /// tile lit over a machine that will still blank is the silent failure #81
    /// is about.
    readonly property bool inhibiting: inhibitor.enabled

    // Anchored to nothing, so the compositor puts it wherever it likes.
    implicitWidth: 1
    implicitHeight: 1
    color: "transparent"

    // Reserves nothing and respects nothing: there is no picture here to lay
    // anything out around.
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "forest-shell:keep-awake"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Nothing may click it, which also means nothing can click *through* to it
    // and lose a press meant for the desktop.
    mask: Region { width: 0; height: 0 }

    IdleInhibitor {
        id: inhibitor

        window: window
        enabled: true
    }
}
