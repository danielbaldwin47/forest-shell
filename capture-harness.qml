// Visual capture of the real surfaces, client-side — the entry point
// tools/capture-harness.sh runs (#85, extended for #73).
//
// Renders a shell surface — the bar over the wallpaper, the lock, the settings
// window — and grabs it to a PNG with `Item.grabToImage`, entirely client-side.
// No screenshot protocol is involved, which is the whole point: #85 established
// that no capture protocol delivers pixels from a nested Hyprland on the
// current stack (aquamarine 0.14.0 wedges after the nested output's first
// commit; full diagnosis in the header of tools/nested-session.sh). Grabbing
// where the pixels are produced sidesteps that entirely.
//
// Two rendering modes, and the difference between them is `MultiEffect`:
//
//   offscreen  `QT_QPA_PLATFORM=offscreen`, the default. Deterministic and
//              sessionless — CI can run it. But `MultiEffect` draws *nothing*
//              on the offscreen scenegraph, silently (Widgets/Icon.qml), so
//              every Lucide glyph in the capture is missing. Layout, colour
//              and opacity compositing are still exact, which is what #79 and
//              #80 need.
//   session    a real compositor via the caller's `WAYLAND_DISPLAY`. The scene
//              is a fixed-size Item inside an ordinary toplevel; the grab
//              renders the whole item even when the window manager sizes the
//              window smaller, so the capture geometry is ours and not the
//              compositor's. `MultiEffect` renders here, which is the only way
//              #73's "status strip icons and settings chrome visually judged"
//              can be answered at all.
//
// The scene's size in logical pixels is the caller's; the PNG comes back at
// whatever scale the scene is drawn at — 1:1 offscreen, the output's scale on
// a session. Nothing is resampled either way, and the harness script derives
// the factor from the saved file rather than trusting a reported DPR.
//
// What neither mode judges: compositor composition — blur behind the bar,
// layer stacking, frame pacing. Those are the compositor's own pixels, not the
// client's, and stay real-session work (#78).
//
// Environment, all set by tools/capture-harness.sh:
//   CAPTURE_OUT          where to save the PNG (required)
//   CAPTURE_SURFACE      bar | lock | settings   (default bar)
//   CAPTURE_W/CAPTURE_H  scene size in logical px (default 1280x800)
//   CAPTURE_BAR_OPACITY  override for the bar fill opacity, e.g. "0.65"
//                        (defaults to the configured bar.surface.opacity)
//   CAPTURE_LOCK_STATE   quiet | summoned  (default quiet) — the lock is a
//                        different picture before and after a key is pressed
//   CAPTURE_SETTINGS_TAB which settings tab to open (default: the state file's)
//   CAPTURE_DELAY_MS     settle time before the grab (default 600)
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Core
import qs.Surfaces.Background
import qs.Surfaces.Bar
import qs.Surfaces.Lock
import qs.Surfaces.Settings

ShellRoot {
    id: root

    readonly property var screen: Quickshell.screens[0]
    readonly property string outPath: Quickshell.env("CAPTURE_OUT") ?? ""
    readonly property string surfaceName: Quickshell.env("CAPTURE_SURFACE") || "bar"
    readonly property string opacityOverride: Quickshell.env("CAPTURE_BAR_OPACITY") ?? ""
    readonly property string lockState: Quickshell.env("CAPTURE_LOCK_STATE") || "quiet"
    readonly property string settingsTab: Quickshell.env("CAPTURE_SETTINGS_TAB") ?? ""
    readonly property int sceneWidth: parseInt(Quickshell.env("CAPTURE_W") || "1280")
    readonly property int sceneHeight: parseInt(Quickshell.env("CAPTURE_H") || "800")
    readonly property int delayMs: parseInt(Quickshell.env("CAPTURE_DELAY_MS") || "600")

    /// The settings surface is its own toplevel — it cannot be nested inside
    /// the scene below, so it is built as itself and its content item is what
    /// gets grabbed. Everything else renders into the scene.
    readonly property bool isSettings: root.surfaceName === "settings"

    /// One line describing what was rendered, appended to the saved= log line.
    /// The harness script parses `bar=` out of it, and a human reading a failed
    /// run wants to know which picture failed.
    property string sceneDescription: ""

    // The one PAM object the lock shares between screens. Constructed but never
    // begun: `LockAuth.begin()` is what opens a conversation, and a capture
    // wants the surface, not an authentication attempt against the session
    // running the harness.
    LockAuth { id: lockAuth }

    FloatingWindow {
        id: shell

        // The window only has to be big enough to exist. In session mode the
        // compositor sizes it however it likes and the grab is unaffected; in
        // offscreen mode nothing sees it at all.
        implicitWidth: root.sceneWidth
        implicitHeight: root.sceneHeight
        color: "transparent"
        visible: !root.isSettings

        Item {
            id: scene

            // Fixed, not `anchors.fill`: the capture's geometry is a property
            // of the test, not of whatever the window manager decided.
            width: root.sceneWidth
            height: root.sceneHeight

            Loader {
                anchors.fill: parent
                active: !root.isSettings
                sourceComponent: {
                    switch (root.surfaceName) {
                    case "lock":     return lockScene;
                    case "bar-full": return barFullScene;
                    default:         return barScene;
                    }
                }
            }
        }
    }

    // --- the pictures ---------------------------------------------------------

    /// #79 and #10: the bar's fill over the wallpaper, which is the composite
    /// the contrast measurement samples. Without compositor blur this is the
    /// *stricter* case — blur only averages the wallpaper locally, so a window
    /// that passes unblurred passes blurred.
    Component {
        id: barScene

        Item {
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

            Component.onCompleted: root.sceneDescription =
                "bar=" + Config.values.bar.height
                + " opacity=" + (root.opacityOverride.length > 0
                                 ? root.opacityOverride
                                 : Config.values.bar.surface.opacity)
        }
    }

    /// The whole bar — `BarContent`, so the registry, the module clusters and
    /// the surface they sit on, over the wallpaper. This is the picture that
    /// would have caught #73's own worst find: `WorkspaceSlots` was not a type,
    /// the workspaces module dropped out of every start, and the only sign was
    /// one warning. A missing cluster is obvious here and invisible to
    /// `tests/`. Modules that read the compositor need `--session` to have
    /// anything to say.
    Component {
        id: barFullScene

        Item {
            Wallpaper {
                anchors.fill: parent
                screen: root.screen
            }

            BarContent {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: Config.values.bar.height
                screen: root.screen
            }

            Component.onCompleted: root.sceneDescription =
                "bar=" + Config.values.bar.height
                + " modules=" + JSON.stringify(Config.values.bar.modules.left)
                + "/" + JSON.stringify(Config.values.bar.modules.center)
                + "/" + JSON.stringify(Config.values.bar.modules.right)
        }
    }

    /// #73: the lock's status strip is one of the two `MultiEffect` surfaces
    /// the ticket says have never rendered anywhere. The real LockSurface and
    /// the real shared LockAuth — the only thing standing in for the session is
    /// the keystroke, written into the buffer the way tools/lock-harness.sh
    /// does it.
    Component {
        id: lockScene

        LockSurface {
            screen: root.screen
            auth: lockAuth

            Component.onCompleted: {
                if (root.lockState === "summoned") {
                    // What a keystroke does, minus the keyboard: a non-empty
                    // buffer is what `summoned` is derived from.
                    lockAuth.buffer = "hunter2";
                }
                root.sceneDescription = "lock=" + root.lockState;
            }
        }
    }

    /// #73's other `MultiEffect` surface: the settings chrome. A toplevel of
    /// its own, so it is grabbed through its content item rather than nested
    /// into the scene.
    Loader {
        id: settingsLoader

        active: root.isSettings
        sourceComponent: SettingsView {}

        onLoaded: {
            if (root.settingsTab.length > 0)
                settingsLoader.item.selectTab(root.settingsTab);
            root.sceneDescription = "tab=" + settingsLoader.item.currentTab;
        }
    }

    // --- the grab -------------------------------------------------------------

    /// The item whose subtree becomes the PNG. For the settings window that is
    /// the layout *inside* the content item, not the content item itself:
    /// Quickshell's `ProxyWindowContentItem` is created without a QML engine
    /// and `grabToImage` refuses it ("item has no QML engine"). Its one child
    /// is the window's whole content, so nothing is left out.
    readonly property Item target: {
        if (!root.isSettings)
            return scene;
        const content = settingsLoader.item ? settingsLoader.item.contentItem : null;
        return content && content.children.length > 0 ? content.children[0] : null;
    }

    // A timer rather than Component.onCompleted: the wallpaper decode is
    // synchronous (Wallpaper.qml pins it before first frame), but layout and
    // the scene graph need a pass before a grab returns anything — and in
    // session mode the toplevel needs a round trip with the compositor first.
    Timer {
        interval: root.delayMs
        running: true
        repeat: false
        onTriggered: {
            if (root.outPath.length === 0) {
                console.log("capture: saved=false no CAPTURE_OUT set");
                Qt.quit();
                return;
            }
            if (!root.target) {
                console.log("capture: saved=false nothing to grab for surface="
                            + root.surfaceName);
                Qt.quit();
                return;
            }

            // The settings window is sized by whoever is managing it. Assigning
            // over that binding is what makes the capture the same size every
            // run: the content fills the content item, and the grab below
            // renders the whole item whether or not the window is that big.
            if (root.isSettings) {
                const content = settingsLoader.item.contentItem;
                content.width = root.sceneWidth;
                content.height = root.sceneHeight;
            }

            // No target size: the grab renders the item at the scale the scene
            // is actually drawn at — 1:1 offscreen, the output's scale on a
            // session (1280x800 comes back as 1920x1200 at scale 1.5). That is
            // a native render, not a resample, which is what #85's "no
            // outer-display scaling applied" is really asking for; the harness
            // script derives the factor from the file and scales measurement
            // regions by it. Passing a target size instead would mean trusting
            // `Screen.devicePixelRatio`, which reports 2 on a 1.5-scale display
            // — the lie Widgets/Icon.qml documents, on this exact machine.
            root.target.grabToImage(function (result) {
                const ok = result.saveToFile(root.outPath);
                console.log("capture: saved=" + ok
                            + " " + root.sceneWidth + "x" + root.sceneHeight
                            + " surface=" + root.surfaceName
                            + " " + root.sceneDescription
                            + " " + root.outPath);
                Qt.quit();
            });
        }
    }

    Component.onCompleted: Logger.stage("capture harness loaded (surface "
                                        + root.surfaceName + ", wallpaper "
                                        + (Config.wallpaper || "unset") + ")");
}
