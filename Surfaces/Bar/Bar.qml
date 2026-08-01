// The bar: one layer-shell window per screen (#12 §2, #22 §1, #35).
//
// Windows are created and destroyed by screen hotplug and by nothing else. A
// bar that is hidden keeps its window and drops its *content* on a debounce
// (Widgets/DebouncedLoader.qml) — the discipline the background surface
// established and every surface after it copies, because destroying and
// recreating layer-shell surfaces is the compositor-crash class the
// reference-shell survey found, and an unmapped window holding no content
// already contributes zero wakeups.
//
// Geometry is settings, not constants: flush-vs-floating, height, padding and
// module gaps all come from `bar.*` (#35). The default is the one #10 measured
// — flush, full width, 32px, 12px padding, 14px module gaps — because flushness
// turned out to be a property of the *wallpaper* rather than of the bar, and
// which failure mode to accept belongs to whoever chose the wallpaper.
//
// The axis is derived, not assumed. v1 ships `top` and `bottom` only; the
// widgets underneath are axis-agnostic, so `left`/`right` is a schema enum
// value and a test pass away rather than a rewrite.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Widgets
import qs.Services.Compositor

Scope {
    id: bar

    /// The layer-shell namespace. Hyprland matches layer rules against it, and
    /// `qs ipc call bar ...` is the other half of the same public surface.
    readonly property string layerNamespace: "forest-shell:bar"

    // Blur is the compositor's job, asked for once by the surface that wants it
    // (Services/Compositor/Compositor.qml). Unconditional: the bar is designed
    // to be legible without it, so this only ever adds depth. Deferred, because
    // it is a subprocess and the first frame is budgeted (#22 §4); the call is
    // idempotent, so arriving from either direction is fine.
    function applyBlur() {
        Compositor.blurLayer(bar.layerNamespace);
    }

    Component.onCompleted: if (Startup.deferredRan) bar.applyBlur()

    Connections {
        target: Startup
        function onDeferredStage() { bar.applyBlur(); }
    }

    Variants {
        // Stage two: the windows are built off the first painted frame, so no
        // amount of bar construction can push the wallpaper out (#12 §4). The
        // screens list is otherwise live — hotplug creates and destroys these
        // windows and nothing else does (#22 §3).
        model: Startup.deferredRan ? Quickshell.screens : []

        PanelWindow {
            id: window

            required property ShellScreen modelData

            readonly property var cfg: Config.values.bar
            readonly property bool atBottom: window.cfg.position === "bottom"
            readonly property bool vertical: window.cfg.position === "left"
                                          || window.cfg.position === "right"
            readonly property var surfaceKnobs: ModuleRegistry.spec.surface(window.cfg.surface)

            screen: modelData

            // Hidden, never destroyed. The content gate below is what actually
            // frees anything.
            visible: BarVisibility.shown

            anchors {
                top: !window.atBottom
                bottom: window.atBottom
                left: true
                right: true
            }

            implicitHeight: window.cfg.height

            // A floating bar is inset on three sides and rounded; a flush one
            // is the full width of the screen with a hairline at the edge that
            // faces the desktop. The insets are tokens, not settings — the
            // decision is "island or band", not "how big a gap".
            margins {
                top: window.cfg.floating && !window.atBottom ? Theme.space2 : 0
                bottom: window.cfg.floating && window.atBottom ? Theme.space2 : 0
                left: window.cfg.floating ? Theme.space3 : 0
                right: window.cfg.floating ? Theme.space3 : 0
            }

            // The surface paints the fill; the window itself must not, or a
            // translucent bar would sit on an opaque rectangle.
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: bar.layerNamespace
            // The bar is clickable but never takes the keyboard: focus belongs
            // to the drawers, which grab it deliberately.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Content is gated on the config being read (#12 §4 — no
            // defaults-flash-then-snap) and on the window being on screen. The
            // window itself is gated on neither.
            DebouncedLoader {
                anchors.fill: parent
                shown: window.visible && Config.ready
                sourceComponent: barContent
            }

            Component {
                id: barContent

                Item {
                    BarSurface {
                        anchors.fill: parent
                        knobs: window.surfaceKnobs
                        radius: window.cfg.floating ? Theme.radiusMd : 0
                        hairlineAtTop: window.atBottom
                        contentBehind: window.surfaceKnobs.adaptiveOpacity
                                       && Compositor.hasWindows(window.modelData)
                    }

                    BarContent {
                        anchors.fill: parent
                        barScreen: window.modelData
                        vertical: window.vertical
                        padding: window.cfg.padding
                        moduleGap: window.cfg.moduleGap
                    }
                }
            }
        }
    }
}
