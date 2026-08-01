// Offscreen visual capture — the root tools/capture-harness.sh runs (#85).
//
// Renders the shell's real surface components — Wallpaper under BarSurface,
// the composite #79 measures — and grabs the scene to a PNG with
// `Item.grabToImage`, entirely client-side. No compositor is involved: this
// runs on `QT_QPA_PLATFORM=offscreen`, where Qt renders unthrottled and the
// grab is pixel-exact at the configured screen size.
//
// Why not a compositor-level capture: #85 established that no screenshot
// protocol delivers pixels from a nested Hyprland on the current stack —
// aquamarine 0.14.0's frame scheduler wedges after the nested output's first
// commit, the compositor never presents again, and every capture path
// (wlr-screencopy, ext-image-copy, toplevel export from the outer session)
// returns either nothing or transparent black. The full diagnosis is in the
// header of tools/nested-session.sh. Client-side rendering is unaffected,
// so the pixels are taken where they are actually produced.
//
// What this seam can and cannot judge:
//   - can:    layout (#80-class overflows), colour, opacity compositing —
//             the #79 contrast measurement runs on this capture.
//   - cannot: `MultiEffect` (silently blank on the offscreen scenegraph —
//             Widgets/Icon.qml documents the measurement) and compositor
//             composition (blur behind the bar, layer stacking). Those still
//             need a real session. For #79 that makes this capture the
//             *stricter* check: compositor blur only averages the wallpaper
//             locally, so the unblurred worst-case window here bounds the
//             blurred one from below.
//
// Environment, all set by tools/capture-harness.sh:
//   CAPTURE_OUT          where to save the PNG (required)
//   CAPTURE_BAR_OPACITY  override for the fill opacity, e.g. "0.65"
//                        (defaults to the configured bar.surface.opacity)
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Core
import qs.Surfaces.Background
import qs.Surfaces.Bar

ShellRoot {
    id: root

    readonly property var screen: Quickshell.screens[0]
    readonly property string outPath: Quickshell.env("CAPTURE_OUT") ?? ""
    readonly property string opacityOverride: Quickshell.env("CAPTURE_BAR_OPACITY") ?? ""

    FloatingWindow {
        implicitWidth: root.screen.width
        implicitHeight: root.screen.height
        color: "transparent"

        Item {
            id: scene
            anchors.fill: parent

            Wallpaper {
                anchors.fill: parent
                screen: root.screen
            }

            BarSurface {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: Config.values.bar.height
                settings: Config.values.bar.surface
                fillOpacity: root.opacityOverride.length > 0
                    ? parseFloat(root.opacityOverride)
                    : Config.values.bar.surface.opacity
                hairlineAtBottom: true
            }
        }
    }

    // One timer tick rather than Component.onCompleted: the wallpaper decode
    // is synchronous (Wallpaper.qml pins it before first frame), but layout
    // and the scene graph need a pass before a grab returns anything.
    Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: {
            if (root.outPath.length === 0) {
                console.log("capture: saved=false no CAPTURE_OUT set");
                Qt.quit();
                return;
            }
            scene.grabToImage(function (result) {
                const ok = result.saveToFile(root.outPath);
                console.log("capture: saved=" + ok
                            + " " + scene.width + "x" + scene.height
                            + " bar=" + Config.values.bar.height
                            + " opacity=" + (root.opacityOverride.length > 0
                                             ? root.opacityOverride
                                             : Config.values.bar.surface.opacity)
                            + " " + root.outPath);
                Qt.quit();
            });
        }
    }

    Component.onCompleted: Logger.stage("capture harness loaded (wallpaper "
                                        + (Config.wallpaper || "unset") + ")");
}
