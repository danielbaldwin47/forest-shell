// The OSD's window — one per screen, mapped only while there is a level to
// report (#46, topology from #12 §2 and #22 §1).
//
// One window per screen and never moved between them: moving a layer-shell
// surface between outputs means destroying and recreating it, which is the
// compositor-crash class the reference-shell survey found. What follows focus
// is the *content* — every screen has a window, and the one on the focused
// screen is the one that has anything in it, which is exactly what
// Surfaces/Notifications/Popups.qml does and for the same reason. Hyprland's
// own refocus after a monitor is removed is the whole fallback (#22 §1: no
// shell-side ranking, no per-monitor state remembered).
//
// The state, the services it watches and the IPC door are Surfaces/Osd/Osd.qml.
// This file is the window and the fade.
//
// ## The fade, and why it is here rather than in the pill
//
// #27 gives the OSD 240 in and 140 out, and that is a *surface* entering and
// leaving — so it is the window's fade, not the content's. Everything inside
// the pill is the in-place 140 (Surfaces/Osd/OsdContent.qml). The window
// outlives `Osd.shown` by exactly one exit, which is why `visible` is an OR
// rather than a binding on the state: unmapping the surface at the top of the
// fade would make the exit an instant disappearance with an animation running
// behind it.
//
// Zero idle cost (#22 §5): the window holds no content when it is not showing —
// dropped after a debounce, so the ten pops a held volume key produces cost one
// load between them — and nothing here animates, polls or wakes while the pill
// is down.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Widgets
import qs.Services.Compositor

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: window

        required property ShellScreen modelData

        /// Whether this screen is the one reporting. The focused screen only
        /// (#22 §1) — three monitors flashing the same volume is three times
        /// the fill rate for one piece of information.
        readonly property bool active: Osd.shown && Compositor.isFocused(window.modelData)

        readonly property var anchorFlags: Osd.policy.anchorsFor(Osd.position)
        readonly property var marginValues: Osd.policy.marginsFor(Osd.position, Osd.margin)

        screen: modelData

        // Outlives `active` by one exit — see the header.
        visible: window.active || pill.opacity > 0

        anchors {
            top: window.anchorFlags.top
            bottom: window.anchorFlags.bottom
            left: window.anchorFlags.left
            right: window.anchorFlags.right
        }

        margins {
            top: window.marginValues.top
            bottom: window.marginValues.bottom
            left: window.marginValues.left
            right: window.marginValues.right
        }

        // Sized to the pill rather than to the screen: QtQuick redraws a whole
        // window on any change, and fill rate is the scarce resource on the
        // T480's UHD 620 (#12 §2, #22 §6). Never zero — a layer surface with no
        // size is a protocol error.
        implicitWidth: Math.max(1, pill.implicitWidth)
        implicitHeight: Math.max(1, pill.implicitHeight)

        // Reserves nothing — an OSD does not push the desktop around — but
        // respects what does, so a top-positioned pill lands below the bar
        // instead of underneath it (#35).
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0

        // Above everything, including a fullscreen window: turning the volume
        // down during a film is exactly when this is read, and a notification's
        // reason for staying out of the way (#42) does not apply to something
        // the user just asked for.
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: Osd.layerNamespace
        // Nothing here is typed into or clicked, and taking the keyboard for a
        // readout would steal the next keystroke of whatever raised it.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // The pill is drawn, not the window: the corners of the rounded
        // rectangle show what is behind them.
        color: "transparent"

        // Not an input region of any kind: `mask` set to an empty region so a
        // click lands on whatever is underneath. An OSD that swallowed a click
        // because it happened to be over a button would be a surface that
        // punishes you for changing the volume.
        mask: Region {}

        // The fade is held on this wrapper rather than on the loaded item,
        // because the item is gone once the debounce expires and an opacity
        // animating on nothing is an exit that never finishes.
        Item {
            id: pill

            anchors.fill: parent

            // The size the window keeps whether or not the content is loaded
            // — a window that collapsed between pops would ask the compositor
            // to resize a surface on every keypress. Read from the policy for
            // the same reason OsdContent.qml reads it from there.
            implicitWidth: Osd.policy.pillWidth
            implicitHeight: Osd.policy.pillHeight

            opacity: window.active ? 1 : 0

            DebouncedLoader {
                id: content

                anchors.fill: parent
                shown: window.active
                sourceComponent: pillComponent
            }

            // #27's OSD row: 240 in, 140 out. Read off the ladder rather than
            // typed, so `reducedEffects` collapses both to the 140 opacity
            // crossfade that is all it leaves (#69) — which this already is.
            Behavior on opacity {
                NumberAnimation {
                    duration: window.active ? Theme.duration(Osd.policy.enterMs)
                                            : Theme.exitDuration(Osd.policy.enterMs)
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.fogEase
                }
            }
        }

        Component {
            id: pillComponent

            OsdContent {
                policy: Osd.policy
                channel: Osd.channel
                percent: Osd.percent
                muted: Osd.muted
            }
        }
    }
}
