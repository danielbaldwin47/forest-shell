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
// Geometry is now the whole of it, and for a while it was not enough on its own
// — see `keyboardFocus` below, which is where #187 actually lived. There was a
// `HyprlandFocusGrab` here as well, with the bar's windows in it so that a click
// on a bar icon would be delivered rather than eaten; it is gone too, for the
// reason the header of Drawers.qml gives. What is left is this: the fog stops
// where the bar's reserved strip starts, so a click on the bar reaches the bar
// and a click anywhere else reaches this window's own mask.
//
// The one case the geometry does not cover is an auto-hidden bar, which
// reserves nothing to be laid out around; there the fog does cover the strip,
// and #199 is what that cost — every row of #187's table failed again, because
// the two `WlrLayer.Top` surfaces are ordered by map order and this one maps
// second, so the revealed bar sits *under* the fog rather than over it.
//
// What covers it instead is a hole in this window's input mask over the bar's
// current rect, which the bar publishes per screen through Core/BarStrips.qml
// and Core/BarStripsPolicy.qml decides the shape of. Geometry is still the
// mechanism wherever geometry reaches; the hole is only ever cut in the case
// where it does not.
//
// ## Why every screen gets one
//
// The fog is drawn on the drawer's own screen and nowhere else, but the window
// is *mapped* on all of them while a drawer is open, with an input mask and
// nothing to look at. That is the grab's last job inherited: clicking a second
// monitor used to dismiss, because the grab consumed clicks everywhere it did
// not name, and a drawer you cannot see is one you have already left. An empty
// full-screen mask says the same thing without the grab's cost — and it costs
// nothing at rest, because it is mapped only while something is open (#22 §5).
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

        /// Whether *any* screen has a drawer open. What the input mask follows,
        /// so a click on a screen this drawer is not on still puts it away —
        /// see the header.
        readonly property bool anyOpen: Drawers.current !== ""

        // Mapped only while there is something open or something leaving, which
        // is the ticket's ask and also #22 §5: an idle shell has no drawer
        // surface anywhere. The exit animation needs the window for as long as
        // it runs, so this outlives `drawer` by one fade.
        visible: window.anyOpen || window.live.length > 0 || scrim.visible

        // Reserves nothing — a drawer does not push the desktop around — but
        // respects what does. See the header: this is what puts the fog below
        // the bar rather than under it.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: Drawers.layerNamespace
        // A drawer is typed into — Escape closes it, the session menu answers
        // the arrow keys, and the launcher (#39) lands a text field in this
        // window — so it takes the keyboard while it is open.
        //
        // **`OnDemand` and not `Exclusive`, and that is #187's fix.** An
        // exclusive layer surface does not merely hold the keyboard: Hyprland
        // routes every *pointer* event to one too. `CInputManager::
        // mouseMoveUnified` hit-tests among the exclusive surfaces alone and,
        // finding the cursor over none of them, falls back to the first one —
        // "forced above all", and it is not a bug. So while a drawer was
        // exclusive, a click on the bar was delivered to the drawer's surface
        // at a coordinate translated by the bar's reserved strip, landing
        // outside the fog's own content: it reached neither the bar button
        // under the cursor nor the dismiss catcher, which is exactly what #187
        // reported. Measured at seam 2 with a virtual pointer — the bar's
        // surface took a `Leave` the instant a drawer opened and never got
        // another `Enter`.
        //
        // What `OnDemand` costs is nothing this window used it for. Hyprland
        // focuses a keyboard-interactive layer surface as it maps either way,
        // so Escape and the launcher's text field are unchanged; what it gives
        // up is the right to keep the keyboard when the user deliberately
        // clicks something else, which is not a right a drawer should have.
        //
        // Only while it is *open*: `visible` outlives that by one fade, and a
        // window that is leaving has no business holding the keyboard away from
        // whatever the user is about to type into.
        WlrLayershell.keyboardFocus: window.drawer !== "" ? WlrKeyboardFocus.OnDemand
                                                          : WlrKeyboardFocus.None

        // The fog is drawn, not the window.
        color: "transparent"

        /// The bar's own input rect on this screen, cut back out of the fog
        /// (#199). A zero rect for every case #187's geometry already covers —
        /// see Core/BarStripsPolicy.qml for which those are.
        readonly property var barCutout: BarStrips.policy.cutout(
            BarStrips.stripOn(window.modelData.name),
            window.width, window.height,
            window.modelData.width, window.modelData.height)

        // Input over the whole screen while a drawer is open *anywhere*, and
        // none at all while one is leaving: a fog that is fading out has
        // already stopped being a thing to click on.
        //
        // Less the bar's strip, when there is one to subtract. That is the
        // auto-hide case the header calls out: a bar that reserves nothing is
        // not laid out around, so the fog covers it and only a hole in this
        // region puts the clicks back (#199). The hole follows the bar as it
        // reveals and hides — it is a pixel at the screen edge while the bar is
        // away, which is what keeps hover-to-reveal working through the fog.
        mask: Region {
            width: window.anyOpen ? window.width : 0
            height: window.anyOpen ? window.height : 0

            Region {
                intersection: Intersection.Subtract

                x: window.barCutout.x
                y: window.barCutout.y
                // Only while something is open. The outer region is already
                // empty otherwise, and subtracting from nothing is at best a
                // no-op the compositor still has to be told about.
                width: window.anyOpen ? window.barCutout.width : 0
                height: window.anyOpen ? window.barCutout.height : 0
            }
        }

        // The hole is a state change worth a line of its own: #187's lesson was
        // that a click check can pass for the wrong reason, so seam 2 asserts
        // the hole exists before it asserts what a click through it did.
        onBarCutoutChanged: {
            const line = BarStrips.policy.cutoutLine(window.modelData.name,
                                                     window.barCutout);
            if (line !== window.lastCutoutLine) {
                window.lastCutoutLine = line;
                Logger.log("drawers", line);
            }
        }

        // The cutout is recomputed on every bar reveal, hide and reflow, and
        // most of those land on the same rect. Logging the rect rather than the
        // recompute keeps the line meaningful.
        property string lastCutoutLine: ""

        onDrawerChanged: {
            if (window.drawer === "")
                return;

            if (window.live.indexOf(window.drawer) < 0)
                window.live = window.live.concat([window.drawer]);
        }

        FogScrim {
            id: scrim

            anchors.fill: parent
            shown: window.drawer !== ""
        }

        // Clicking the fog closes the drawer — on this screen, where there is
        // fog to click, and on every other screen, where the window is mapped
        // and empty for exactly this. The only thing it does not cover is the
        // bar's own strip, which the bar routes itself (#187).
        MouseArea {
            anchors.fill: parent
            enabled: window.anyOpen
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
