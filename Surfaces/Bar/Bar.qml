// The bar: one layer-shell window per screen, kept alive for the life of the
// shell (#12 §2, #22 §1).
//
// Windows are created and destroyed by screen hotplug and by nothing else. Not
// by auto-hide, not by a settings change, not by the drawers opening over the
// top — destroying and recreating layer surfaces is the compositor-crash class
// the reference-shell survey found, and the whole window discipline exists to
// avoid it. Hiding drops the *content* instead, after a debounce
// (Widgets/DebouncedLoader.qml), so a reveal inside the delay costs nothing and
// a hidden bar contributes zero wakeups.
//
// Uniform per screen with no per-monitor keys, per #22 §1: both target machines
// are single-monitor, so multi-monitor is a correctness tier that must not
// break and gets no tuning. A "bar on primary only" setting would be a dead
// setting on every machine this runs on.
//
// The bar is on the critical path to the first frame (#22 §4 — "first frame
// (wallpaper + bar rendered) ≤ 1.5 s"), so it is a direct child of the shell
// root rather than deferred. Its content still gates on `Config.ready` like
// every other surface, so nothing flashes a default and snaps (#12 §4).
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Services.Compositor
import qs.Widgets

Scope {
    id: bar

    // The layer-shell namespace, and so the handle every Hyprland rule for the
    // bar is written against.
    readonly property string layerNamespace: "forest-shell:bar"

    readonly property var settings: Config.values.bar

    // Blur is the compositor's job (#22 §6 forbids QML-side full-screen blur
    // outright), and a layerrule is how it is asked for. Pushed live rather
    // than left to the user's hyprland.conf so the bar looks the way it was
    // measured on a fresh install — and re-pushed when the setting changes,
    // because the fill is translucent enough that turning it off is visible.
    //
    // Deferred: the first frame does not wait on a subprocess. The shell must
    // look correct with blur off, so there is nothing to gate on it.
    Connections {
        target: Startup
        function onDeferredStage() { bar.applyBlurRule(); }
    }

    Connections {
        target: Config
        function onKeyChanged(path) {
            if (Startup.deferredRan
                    && (path === "bar.surface" || path === "appearance.reducedEffects"))
                bar.applyBlurRule();
        }
    }

    function applyBlurRule() {
        // `reducedEffects` turns the compositor blur off first, at the top of
        // its cost ladder (#22 §7).
        const wanted = bar.settings.surface.blur && !Config.values.appearance.reducedEffects;
        // `unset` clears every layer rule on the namespace, not only ours —
        // which is right, because the namespace is ours. A rule a user wants to
        // keep belongs on a namespace they own.
        Compositor.setLayerRule(wanted ? "blur" : "unset", bar.layerNamespace);
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: window

            required property ShellScreen modelData

            readonly property var settings: bar.settings
            readonly property bool atTop: settings.position === "top"

            // Whether the bar is showing. Always true unless auto-hide is on,
            // in which case the reveal strip drives it.
            readonly property bool revealed: !settings.autoHide || hover.hovered || linger.running

            screen: modelData

            anchors {
                top: window.atTop
                bottom: !window.atTop
                left: true
                right: true
            }

            margins {
                top: settings.floating && window.atTop ? settings.floatMarginV : 0
                bottom: settings.floating && !window.atTop ? settings.floatMarginV : 0
                left: settings.floating ? settings.floatMarginH : 0
                right: settings.floating ? settings.floatMarginH : 0
            }

            implicitHeight: settings.height

            // An auto-hiding bar does not reserve space — that is the point of
            // it. A pinned one does, and lets the compositor tile under it.
            exclusionMode: settings.autoHide ? ExclusionMode.Ignore : ExclusionMode.Auto

            // The window paints nothing itself: the surface material is content
            // (Surfaces/Bar/BarSurface.qml), and while hidden there is
            // deliberately nothing there at all.
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: bar.layerNamespace
            // The bar is clicked, never typed into. #38 puts the drawers' fog
            // *below* this window so the bar stays clickable over it.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Input is masked to what is actually there: the whole bar while
            // it is showing, and a one-pixel reveal strip along the screen edge
            // while it is hidden. Without the mask a hidden auto-hide bar would
            // still swallow clicks meant for the window underneath it.
            mask: Region {
                item: window.revealed ? content : revealStrip
            }

            Item {
                id: revealStrip

                anchors {
                    left: parent.left
                    right: parent.right
                    top: window.atTop ? parent.top : undefined
                    bottom: window.atTop ? undefined : parent.bottom
                }
                height: 1
            }

            // Pointer anywhere in the window keeps the bar out; leaving starts
            // the linger, so crossing the bar on the way somewhere else does
            // not make it flap.
            HoverHandler {
                id: hover
                enabled: window.settings.autoHide
            }

            // No handler: the timer *running* is the state, and it stopping is
            // what re-evaluates `revealed`.
            Timer {
                id: linger
                interval: 400
            }

            Connections {
                target: hover
                function onHoveredChanged() {
                    if (hover.hovered)
                        linger.stop();
                    else if (window.settings.autoHide)
                        linger.restart();
                }
            }

            Item {
                id: content

                anchors.fill: parent

                // Slides out of the window rather than shrinking it: the window
                // keeps its geometry, so nothing about the surface changes and
                // the compositor is not asked to resize anything.
                y: window.revealed ? 0 : (window.atTop ? -height : height)

                Behavior on y {
                    NumberAnimation {
                        duration: Config.values.appearance.reducedEffects
                            ? Theme.motionFast : Theme.motionStandard
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.fogEase
                    }
                }

                DebouncedLoader {
                    anchors.fill: parent
                    // Gated on the config, like every surface (#12 §4), and
                    // dropped again a beat after the bar hides.
                    shown: Config.ready && window.revealed
                    sourceComponent: contentComponent
                }

                Component {
                    id: contentComponent
                    BarContent { screen: window.modelData }
                }
            }
        }
    }
}
