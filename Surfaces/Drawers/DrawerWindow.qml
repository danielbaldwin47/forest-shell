// The shared drawer window — one per screen, mapped only while a drawer is
// open (#38, topology from #12 §3).
//
// One window per screen and never moved between them (#22 §1): moving a
// layer-shell surface between outputs means destroying and recreating it, which
// is the compositor-crash class the reference-shell survey found. What follows
// the focused screen is which window has anything in it, and that is
// `Drawers.screen` — a name, so nothing here holds a `ShellScreen` across a
// hotplug.
//
// ## Why the bar stays clickable
//
// `ExclusionMode.Normal` with a zero exclusive zone: the window reserves
// nothing and respects what does, so the compositor lays the fog out *below*
// the bar's reserved strip rather than underneath it — the same thing
// Surfaces/Notifications/Popups.qml does for the toast stack. #27's "the bar
// renders above the fog and stays clickable" then holds by geometry, which is a
// stronger guarantee than stacking order within a layer: two `WlrLayer.Top`
// surfaces are ordered by the compositor, and the drawer maps second.
//
// Geometry is not the whole of it — a click has to reach the bar as well as
// miss the fog, and while a `HyprlandFocusGrab` is up a click outside the
// grabbed windows is consumed dismissing it. The bar's windows are in the grab
// for exactly that reason (Core/FocusGrabWindows.qml).
//
// The one case the geometry does not cover is an auto-hidden bar, which
// reserves nothing to be laid out around; there the fog does cover the strip
// and the bar is a revealed window over it.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: window

        required property ShellScreen modelData

        /// The drawer this window is showing, or `""`. Drawers are globally
        /// exclusive, so at most one window on one screen ever answers with a
        /// name.
        readonly property string drawer: Drawers.screen === window.modelData.name
                                         ? Drawers.current : ""

        /// The drawers with something still on screen — the open one, plus any
        /// that is still fading out. Two of these is #27's cross-drawer
        /// overlap; the slot drops itself when its exit finishes.
        property var live: []

        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }

        // Mapped only while there is fog to draw, which is the ticket's ask and
        // also #22 §5: an idle shell has no drawer surface anywhere. The exit
        // animation needs the window for as long as it runs, so this outlives
        // `drawer` by one fade.
        visible: window.drawer !== "" || window.live.length > 0 || scrim.visible

        // Reserves nothing — a drawer does not push the desktop around — but
        // respects what does. See the header: this is what puts the fog below
        // the bar rather than under it.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: Drawers.layerNamespace
        // A drawer is typed into — Escape closes it, the session menu answers
        // the arrow keys, and the launcher (#39) lands a text field in this
        // window — so it takes the keyboard outright while it is open, the way
        // the launcher prototype did.
        //
        // Only while it is *open*: `visible` outlives that by one fade, and a
        // window that is leaving has no business holding the keyboard away from
        // whatever the user is about to type into.
        WlrLayershell.keyboardFocus: window.drawer !== "" ? WlrKeyboardFocus.Exclusive
                                                          : WlrKeyboardFocus.None

        // The fog is drawn, not the window.
        color: "transparent"

        // Input over the whole screen while a drawer is open, and none at all
        // while one is leaving: a fog that is fading out has already stopped
        // being a thing to click on.
        mask: Region {
            width: window.drawer !== "" ? window.width : 0
            height: window.drawer !== "" ? window.height : 0
        }

        onDrawerChanged: {
            if (window.drawer === "")
                return;

            // The window announces itself for the shared grab as it opens; see
            // the header of Drawers.qml for why it arrives that way round.
            Drawers.grabWindow = window;

            if (window.live.indexOf(window.drawer) < 0)
                window.live = window.live.concat([window.drawer]);
        }

        FogScrim {
            id: scrim

            anchors.fill: parent
            shown: window.drawer !== ""
        }

        // Clicking the fog closes the drawer. The focus grab covers clicking
        // anything that is *not* this window; this covers the part of the
        // screen that is.
        MouseArea {
            anchors.fill: parent
            enabled: window.drawer !== ""
            onClicked: Drawers.close("clicked away")
        }

        // Escape, from anywhere in the window that has not claimed the key
        // itself. `focus: true` on the scope rather than on a control, because
        // which control wants the keyboard is the tenant's business.
        FocusScope {
            id: keys

            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: event => {
                Drawers.close("escape");
                event.accepted = true;
            }

            Repeater {
                model: window.live

                DrawerSlot {
                    required property string modelData

                    name: modelData
                    policy: Drawers.policy
                    shown: modelData === window.drawer
                    switching: window.live.length > 1

                    onRetired: {
                        const next = window.live.slice();
                        const index = next.indexOf(modelData);
                        if (index < 0)
                            return;
                        next.splice(index, 1);
                        window.live = next;
                    }
                }
            }
        }
    }
}
