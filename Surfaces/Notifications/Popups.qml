// Notification popups: their own window, top-right, on the focused screen (#42).
//
// One window per screen and never moved between them (#22 §1) — moving a
// layer-shell surface between outputs means destroying and recreating it, which
// is the compositor-crash class the reference-shell survey found. What follows
// focus is the *content*: every screen has a window, and the one on the focused
// screen is the one that has anything in it.
//
// The window is sized to its cards rather than covering the corner of the
// screen, because QtQuick redraws a whole window on any change and fill rate is
// the scarce resource on the T480's UHD 620 (#12 §2, #22 §6). It maps only
// while there is something to show, and its content is dropped again after a
// debounce, so an idle shell has no popup content anywhere (#22 §5).
//
// The motion is #27's toast row, and no more than it: cards condense in place
// over 240ms, fade out over 140, and the stack-shift when one leaves or arrives
// is the only translate animation in the shell.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Widgets
import qs.Services.Compositor
import qs.Services.Notifications

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: window

        required property ShellScreen modelData

        /// Popups belong on the focused screen only, and there is no reason for
        /// this window to be mapped at all with nothing in it.
        readonly property bool active: Compositor.isFocused(window.modelData)
                                       && Notifications.popups.count > 0

        /// The width of a card, and so of the window. A component dimension, not
        /// a token: the design system fixes spacing and radii, and leaves the
        /// size of a thing to the ticket that builds it (#8).
        readonly property int cardWidth: 380

        screen: modelData
        visible: window.active

        anchors { top: true; right: true }
        margins { top: Theme.space4; right: Theme.space4 }

        implicitWidth: window.cardWidth
        // Never zero: a layer surface with no size is a protocol error, and
        // this is 1px of nothing behind `visible: false`.
        implicitHeight: Math.max(1, content.implicitHeight)

        // Reserves nothing — a notification does not push the desktop around —
        // but respects what does, so the stack starts below the bar (#35)
        // instead of underneath it.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0

        // Above everything: a popup that ends up behind another surface has
        // failed at the one thing it does. Not covering a fullscreen window is
        // a policy the service enforces by not showing the popup at all (#9),
        // which is a decision, where stacking would be an accident.
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "forest-shell:notifications"
        // Cards are clickable, but a notification never takes the keyboard away
        // from what the user is typing in.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // The cards are drawn, not the window: everything behind the gaps
        // between them shows through.
        color: "transparent"

        // No input mask. The window is only ever exactly as big as the cards
        // plus the hairline gaps between them, and only mapped while they are
        // there — masking would buy back 8px strips nobody is aiming at.
        DebouncedLoader {
            id: content

            // Anchored on one axis only. The window's height comes from this
            // item's implicit height, so anchoring the other way round would be
            // a binding loop.
            width: parent.width
            shown: window.active
            sourceComponent: stackComponent
        }

        Component {
            id: stackComponent

            Column {
                id: stack

                width: content.width
                spacing: Theme.space2

                // The stack-shift: when a card is inserted at the top or leaves
                // from the middle, the others travel to their new place. #27
                // grants the shell exactly one translate animation, and this is
                // it. Entrances and exits are the card's own business, so there
                // is no `add` transition here to fight them.
                //
                // Being the shell's one translate makes it the clearest thing
                // reduced effects takes away: the cards below a dismissed one
                // arrive at their new place rather than travelling to it (#69).
                move: Transition {
                    enabled: Theme.animateTransforms
                    NumberAnimation {
                        properties: "y"
                        duration: Theme.duration(Theme.motionFast)
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.fogEase
                    }
                }

                // The card declares `toast` as required, so the model's row
                // lands on it with nothing to wire up here.
                Repeater {
                    model: Notifications.popups

                    NotificationCard { width: stack.width }
                }
            }
        }
    }
}
