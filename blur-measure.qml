// A shell root built to be photographed: the real bar over a wallpaper the
// compositor cannot help but blur visibly (#97).
//
// #78 proved Hyprland *accepts* the bar's layer rule. Nothing has ever proved
// the bar is blurred, because the compositor's `ok` is a reply and every seam
// in this repo is blind to what is composited behind a surface:
// tools/capture-harness.sh renders the shell's own surfaces client-side, the
// nested session cannot present at all (#85), and the one real session it was
// tried on had `decoration:blur:enabled = 0`, so nothing blurred anywhere.
//
// This entry point is the other end of that: run on a *real* session,
// screenshot it with grim, and measure the pair. So it is deliberately
// self-contained about the picture —
//
//   * a background-layer wallpaper of assets/noise.png tiled 1:1, which is the
//     highest-frequency image on disk here and therefore the one whose detail a
//     low-pass filter removes most visibly;
//   * the real Bar, unmodified, pushing its own rule;
//   * an ordinary toplevel window, translucent, over the same wallpaper — the
//     control that answers "does blur work on this machine at all" before the
//     bar is judged. #78 could not tell "the rule did nothing" from "blur
//     renders nowhere here", and that ambiguity cost the ticket a session.
//
// tools/blur-measure.sh drives it. A second entry point at the repo root
// rather than a file under tools/, for blur-harness.qml's reason: Quickshell
// takes the entry point's directory as the config root, and only from here
// does `qs.Surfaces.Bar` resolve to the real bar.
//
//   qs -p blur-measure.qml   # on a real Wayland session, not a nested one
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Core
import qs.Services.Compositor
import qs.Surfaces.Bar

ShellRoot {
    id: harness

    Component.onCompleted: Logger.log("harness", "blur measure harness ready");

    /// Startup's own timeline, logged where a harness can read it. The bar
    /// pushes its rule from `Startup.deferredStage`, and whether the compositor
    /// facade is up *by then* is the difference between a rule and a warning —
    /// on a real session the facade takes seconds to attach, where in a nested
    /// one it is there immediately. A run that photographs an unblurred bar
    /// needs to be able to tell those two apart without guessing.
    Connections {
        target: Startup
        function onDeferredStage() {
            Logger.log("harness", "deferred stage: compositor available="
                       + Compositor.available);
        }
    }

    /// The wallpaper, one per screen. Not qs.Surfaces.Background: that reads a
    /// user's own wallpaper out of config, and the measurement wants a known
    /// texture — grain at one pixel per pixel, which is pure high frequency and
    /// so the largest possible signal for "was this low-passed".
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: backdrop

            required property var modelData

            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "forest-shell:blur-measure-backdrop"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "black"

            Image {
                anchors.fill: parent
                source: Qt.resolvedUrl("assets/noise.png")
                fillMode: Image.Tile
                // 1:1 device pixels. Any smoothing here would pre-blur the
                // wallpaper and shrink the very difference being measured.
                smooth: false
                mipmap: false
            }
        }
    }

    /// The control: an ordinary xdg-toplevel, translucent, so Hyprland's own
    /// window blur — no layer rule anywhere near it — is visible behind it or
    /// is not. Hidden until asked for, so it is never in the bar's shot.
    FloatingWindow {
        id: probe

        visible: false
        title: "forest-shell blur probe"
        implicitWidth: 480
        implicitHeight: 320
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            // Translucent on purpose: an opaque window has nothing behind it to
            // show, blurred or not.
            color: Qt.rgba(0.09, 0.11, 0.10, 0.45)
        }
    }

    Bar { id: realBar }

    IpcHandler {
        target: "measure"

        /// Whether the facade found a compositor at all — the same guard
        /// tools/blur-harness.sh opens with. A measurement taken against an
        /// inert facade would photograph a bar that never asked for blur.
        function available(): bool {
            return Compositor.available;
        }

        /// Flip `bar.surface.blur` the way the settings window does:
        /// `bar.surface` is one grouped key, so the knob is a read-modify-write
        /// of the group and never a bare `{ blur: … }`, which would drop every
        /// other knob in it (Surfaces/Settings/Controls/ConfigBinding.qml).
        ///
        /// A real write to settings.json — the harness gives the shell its own
        /// XDG_CONFIG_HOME so it is never the caller's.
        function blur(on: bool): bool {
            const group = Object.assign({}, Config.get("bar.surface") ?? {});
            group.blur = on;
            return Config.set("bar.surface", group);
        }

        /// Push the bar's own rule by hand, on demand.
        function push(): bool {
            realBar.applyBlurRule();
            return true;
        }

        /// Show or hide the ordinary-window control.
        function probeWindow(on: bool): bool {
            probe.visible = on;
            return probe.visible === on;
        }

        /// What the bar's fill is set to, so the harness can report the
        /// measurement next to the opacity it was taken at — 14% of the
        /// wallpaper reaches the camera at the default 0.86, and that factor is
        /// most of why the numbers are the size they are.
        function fillOpacity(): real {
            return Config.get("bar.surface")?.opacity ?? -1;
        }
    }
}
