pragma Singleton

// The windows a drawer's focus grab has to include (#38).
//
//     FocusGrabWindows.keep(window)      // from the surface, on construction
//     FocusGrabWindows.release(window)   // and on destruction
//
// A `HyprlandFocusGrab` is a grab: while one is up, a click anywhere outside
// the windows it names dismisses it and is *consumed* getting there. That is
// exactly what a drawer wants from the desktop — click away, drawer closes —
// and exactly what it must not do to the bar. #27 settled that the bar renders
// above the fog and stays clickable, with "clicking another bar icon triggers
// the cross-drawer transition directly" as the reason: a bar whose buttons only
// dismiss cannot start that transition, and the anchoring cue it exists to make
// legible never reads.
//
// So the bar's windows join the grab. They cannot be reached for directly:
// Surfaces/Bar/Bar.qml is a `Scope` instantiated inline in shell.qml, one
// `PanelWindow` per screen inside a `Variants`, created and destroyed by
// hotplug — there is nothing for the drawer to hold a reference to and nothing
// that would stay valid if there were. A registry the windows announce
// themselves to is what survives that, and it is in Core for the reason
// Core/SurfaceBus.qml is: it is wiring between two surfaces, and knows nothing
// about the machine.
//
// Deliberately not a general "windows that stay clickable" list. Anything that
// wants to be in a drawer's grab has to want the drawer's *focus* semantics
// too, and there is one such surface — the bar. A second caller should have to
// say why in this comment.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell

Singleton {
    id: root

    /// The live list, replaced rather than mutated: an in-place edit of a `var`
    /// notifies nothing and `HyprlandFocusGrab.windows` is a binding.
    property var windows: []

    function keep(window: var): void {
        if (!window || root.windows.indexOf(window) >= 0)
            return;
        root.windows = root.windows.concat([window]);
    }

    function release(window: var): void {
        const index = root.windows.indexOf(window);
        if (index < 0)
            return;
        const next = root.windows.slice();
        next.splice(index, 1);
        root.windows = next;
    }
}
