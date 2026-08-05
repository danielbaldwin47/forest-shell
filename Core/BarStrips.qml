// Where each screen's bar currently takes input, published by the bar and read
// by the drawers (#199).
//
// This is the per-screen registry `Core/FocusGrabWindows.qml` used to be, and
// it is deliberately much less than that one was. The grab held *windows*, so
// it could only ever say "deliver clicks to these surfaces" and the compositor
// decided the rest — which is how #187 happened. This holds *rectangles*, and
// the only thing anyone does with one is subtract it from an input mask. There
// is no delivery decision left for anything else to get wrong.
//
// It exists because the drawer needs a number the bar owns. #187's fix needed
// none: the bar reserved an exclusive zone and the compositor laid the fog out
// below it, so neither surface had to know anything about the other. An
// auto-hiding bar reserves nothing, so that channel is gone and this is the
// narrowest thing that replaces it.
//
// Screen *names*, never `ShellScreen` objects: a hotplug destroys those, and a
// map holding one across it is the crash class Surfaces/Drawers/DrawerWindow.qml
// avoids for the same reason.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    /// The arithmetic, on the far side of the Quickshell import so tests/ can
    /// reach it (tests/tst_barstrips.qml).
    readonly property BarStripsPolicy policy: BarStripsPolicy {}

    /// screen name → `{ x, y, width, height, reserves, revealed }` in screen
    /// coordinates. Replaced wholesale rather than mutated, for the reason
    /// `BarStripsPolicy.withStrip` gives.
    property var strips: ({})

    function publish(screenName: string, strip: var) {
        root.strips = root.policy.withStrip(root.strips, screenName, strip);
    }

    /// A screen that went away, or a bar window that did. The drawer's window
    /// on that screen is being destroyed at about the same time, but not
    /// necessarily first — a stale rect left behind would be a hole punched
    /// over nothing on whatever screen took the name next.
    function forget(screenName: string) {
        if (root.strips[screenName] === undefined)
            return;
        root.strips = root.policy.withoutStrip(root.strips, screenName);
    }

    /// The strip on a screen, or `null`. `null` and not `undefined` so the
    /// policy has one absent case to test rather than two.
    function stripOn(screenName: string): var {
        const strip = root.strips[screenName];
        return strip === undefined ? null : strip;
    }
}
