// The wallpaper: one background-layer window per screen.
//
// Part of startup stage one — the wallpaper has to be on the first frame (#32),
// so nothing here is lazy except the content gate on `Config.ready`, which is
// already true by the time the window exists. Windows are created and destroyed
// only by screen hotplug (#22 §3), never to hide them.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Widgets

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: window

        required property ShellScreen modelData

        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }

        // The desktop is not a control: no exclusive zone, no input, no focus.
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}

        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "forest-shell:background"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Painted before any content loads, so the first frame is never white.
        color: Theme.bgBase

        Item {
            id: content
            anchors.fill: parent

            readonly property var backingWindow: content.Window.window

            // Real paint evidence for the startup budget — and what the
            // deferred stage chains off (Core/Startup.qml). Disconnected once
            // the frame is in: this fires at the display refresh rate, on every
            // screen, for as long as the shell runs (#22 §5 — idle wakeups).
            Connections {
                target: content.backingWindow
                enabled: !Startup.firstFramePainted
                function onFrameSwapped() { Startup.markFirstFrame(); }
            }

            // Content gated on the config being read (#12 §4 — no
            // defaults-flash-then-snap), and dropped again if this window ever
            // hides. The window itself is not gated: #12 §2 and #22 §1 want it
            // created once per screen and kept, so the gate is on what the
            // window holds, not on whether it exists. The background never
            // hides, but the discipline is the one every later surface copies.
            DebouncedLoader {
                anchors.fill: parent
                shown: Config.ready
                sourceComponent: wallpaperComponent
            }

            Component {
                id: wallpaperComponent
                Wallpaper { screen: window.modelData }
            }
        }
    }
}
