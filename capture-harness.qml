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
//   CAPTURE_SURFACE      bar | bar-full | lock | settings | drawer  (default bar)
//   CAPTURE_W/CAPTURE_H  scene size in logical px (default 1280x800)
//   CAPTURE_BAR_OPACITY  override for the bar fill opacity, e.g. "0.65"
//                        (defaults to the configured bar.surface.opacity)
//   CAPTURE_LOCK_STATE   what the lock is showing, comma-separated: `quiet`,
//                        or any of `summoned`, `caps`, `notify:N`
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
import qs.Surfaces.Drawers
import qs.Services.Launcher
import qs.Services.Notifications
import qs.Services.System
import Quickshell.Services.UPower

ShellRoot {
    id: root

    readonly property var screen: Quickshell.screens[0]
    readonly property string outPath: Quickshell.env("CAPTURE_OUT") ?? ""
    readonly property string surfaceName: Quickshell.env("CAPTURE_SURFACE") || "bar"
    readonly property string opacityOverride: Quickshell.env("CAPTURE_BAR_OPACITY") ?? ""
    readonly property string settingsTab: Quickshell.env("CAPTURE_SETTINGS_TAB") ?? ""
    readonly property int sceneWidth: parseInt(Quickshell.env("CAPTURE_W") || "1280")
    readonly property int sceneHeight: parseInt(Quickshell.env("CAPTURE_H") || "800")
    readonly property int delayMs: parseInt(Quickshell.env("CAPTURE_DELAY_MS") || "600")

    /// What is typed into the launcher, prefix and all. Empty is the recents
    /// state, which is a different picture from a filtered one and the one
    /// #39's fold criterion is easiest to read on.
    readonly property string launcherQuery: Quickshell.env("CAPTURE_LAUNCHER_QUERY") ?? ""

    /// A posed Ask Claude transcript (#41), as `speaker|text` turns separated
    /// by `~`. Posed rather than asked, for the reason every other value here
    /// is: a capture that spent a real API turn would photograph whatever the
    /// model happened to say that afternoon, at whatever length, which is not
    /// a layout this file can make a criterion out of.
    ///
    /// What it is for is the measurement the prototype made and this ticket
    /// inherits: 720px is too wide for prose, so the text inside the column is
    /// capped to 600. That cap, the wrap, the caps turn labels and the denial
    /// chip are all pictures — seam 3's job — and none of them is reachable
    /// from tools/launcher-harness.sh, which has no surface in it.
    ///
    ///     tools/capture-harness.sh out.png --surface launcher --session \
    ///         --query '?' --transcript 'you|why is the sky blue~claude|Rayleigh…'
    readonly property string claudeTranscript:
        Quickshell.env("CAPTURE_CLAUDE_TRANSCRIPT") ?? ""

    /// What the lock is showing, as a comma-separated set — `quiet` on its own,
    /// or any of `summoned`, `caps`, `notify:N`. Every item in the lock's status
    /// strip is gated on something about the machine (a discharging battery, a
    /// caps-lock key, notifications waiting), so a capture that does not pin
    /// them photographs whatever this laptop happened to be doing. #73's
    /// criterion is about the icons, and an empty strip answers nothing.
    readonly property var lockState: (Quickshell.env("CAPTURE_LOCK_STATE") || "quiet").split(",")

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

        Item {
            id: scene

            // Fixed, not `anchors.fill`: the capture's geometry is a property
            // of the test, not of whatever the window manager decided. This is
            // always the item that is grabbed, whatever the surface — the
            // settings content is moved into it rather than photographed where
            // it was built.
            width: root.sceneWidth
            height: root.sceneHeight

            Loader {
                anchors.fill: parent
                active: !root.isSettings
                sourceComponent: {
                    switch (root.surfaceName) {
                    case "lock":     return lockScene;
                    case "bar-full": return barFullScene;
                    case "drawer":   return drawerScene;
                    case "launcher": return launcherScene;
                    case "center":   return centerScene;
                    default:         return barScene;
                    }
                }
            }

            // What the settings window paints under its content, and the reason
            // the content is brought here rather than grabbed in place: the fill
            // is the *window's* `color`, not part of the content item, so a grab
            // of the content alone comes back with a transparent page — every
            // pixel the rail does not cover reading (0,0,0,0). It looks right
            // against a dark image viewer and is not what the shell shows.
            Rectangle {
                id: settingsBacking
                anchors.fill: parent
                visible: root.isSettings
                color: Theme.bgBase
            }
        }
    }

    // --- the pictures ---------------------------------------------------------

    /// The wallpaper every bar picture sits on, so that "what is behind the bar"
    /// is stated once. Inline components live on the file's root object.
    component Backdrop: Item {
        Wallpaper {
            anchors.fill: parent
            screen: root.screen
        }
    }

    /// #79 and #10: the bar's fill over the wallpaper, which is the composite
    /// the contrast measurement samples. Without compositor blur this is the
    /// *stricter* case — blur only averages the wallpaper locally, so a window
    /// that passes unblurred passes blurred.
    Component {
        id: barScene

        Backdrop {
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

        Backdrop {
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

    /// #38: the fog scrim with a drawer in it, over the wallpaper, with the bar
    /// on top of it.
    ///
    /// The layout is the compositor's, reproduced: the real window reserves
    /// nothing and respects what does (`ExclusionMode.Normal`, zero zone), so
    /// Hyprland lays the fog out *below* the bar's exclusive strip rather than
    /// under it — measured at 32px on a 32px bar in tools/drawer-harness.sh.
    /// The top margin here is that, and it is what makes this picture answer
    /// "the bar renders above the fog": the strip at the top of the frame is
    /// the bar's own pixels, not fog over them.
    ///
    /// The fog is `shown` from the first frame rather than animated into: a
    /// still frame of a surface at rest is what this seam takes, and the
    /// transitions are #27's, checked as durations in `tests/`.
    ///
    /// Needs `--session` to be worth looking at — the session menu is five rows
    /// of Lucide glyphs, and `MultiEffect` draws nothing offscreen
    /// (Widgets/Icon.qml). Offscreen still measures the wash, which is the
    /// number in the acceptance criteria.
    Component {
        id: drawerScene

        Backdrop {
            id: drawerBackdrop

            FogScrim {
                anchors {
                    top: parent.top
                    topMargin: Config.values.bar.height
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                shown: true
            }

            SessionMenu {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: Config.values.bar.height / 2
            }

            // Last, so it is over the fog — the stacking the compositor gives
            // the real windows.
            BarSurface {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: Config.values.bar.height
                settings: Config.values.bar.surface
                fillOpacity: Config.values.bar.surface.opacity
                hairlineAtBottom: true
            }

            Component.onCompleted: root.sceneDescription =
                "scrim=" + Theme.fogWashOpacity
                + " wash=" + Theme.fogWash
                + " bar=" + Config.values.bar.height
        }
    }

    /// The launcher as a clearing (#39): the fog, the card at the 32% horizon,
    /// and the bar above both. This is the picture #39's layout criterion is
    /// about — horizon fraction, 720px column, 46px rows, the fold — and the
    /// one the contrast criterion is measured from.
    ///
    /// `--query` is what poses it, and the fold is only legible with one set.
    /// An empty query is the recents list, which is capped at six rows well
    /// short of the fold, so the `N more` label never appears and the card
    /// never reaches its full height. To read the fold, ask for something that
    /// matches broadly:
    ///
    ///     tools/capture-harness.sh out.png --surface launcher --query e
    ///
    /// Two things it reports that the script needs. `card=` and `legend=` are
    /// the two regions `--contrast` samples: the card's fill over the wallpaper
    /// is what every row's text sits on, and the legend sits at the bottom of
    /// the same card over a different part of the wallpaper, which on a
    /// top-lit gradient is not the same measurement. Reported from the scene
    /// rather than recomputed in bash for the reason `bar=` is — the geometry
    /// is a property of what was rendered, not of what the script assumed.
    ///
    /// Needs `--session` to be worth *looking* at: every row's app icon is an
    /// `Image` behind a `MultiEffect`, which draws nothing offscreen
    /// (Widgets/Icon.qml). Offscreen still measures the fills, which is what
    /// the contrast criterion is — and is the stricter case, since a real
    /// icon only ever adds contrast to the row it is on.
    Component {
        id: launcherScene

        Backdrop {
            id: launcherBackdrop

            FogScrim {
                anchors {
                    top: parent.top
                    topMargin: Config.values.bar.height
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                shown: true
            }

            Launcher {
                id: clearing

                anchors {
                    top: parent.top
                    topMargin: Config.values.bar.height
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }

                query: root.launcherQuery

                // Posed straight into the provider's own model, so the
                // delegate under test is the shipped one rather than a copy
                // of it living in this file.
                Component.onCompleted: {
                    if (root.claudeTranscript === "")
                        return;
                    for (const turn of root.claudeTranscript.split("~")) {
                        const split = turn.indexOf("|");
                        if (split < 0)
                            continue;
                        Claude.turns.append({
                            speaker: turn.slice(0, split),
                            text: turn.slice(split + 1),
                            // A denial is a picture too, and it is the one
                            // that only appears on a turn that had one — so it
                            // is posed by asking for it in the text rather
                            // than by a second variable nothing else uses.
                            note: turn.indexOf("[denied]") >= 0
                                  ? Claude.policy.denialNote(["WebSearch"]) : ""
                        });
                    }
                }
            }

            BarSurface {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: Config.values.bar.height
                settings: Config.values.bar.surface
                fillOpacity: Config.values.bar.surface.opacity
                hairlineAtBottom: true
            }

            // Read once the scene has settled rather than at completion: the
            // desktop-entry scan streams in, so the card is still growing a row
            // at a time for the first second of the capture's life and its
            // height at `Component.onCompleted` is the height of an empty one.
            function describe(): void {
                root.sceneDescription =
                    "query=\"" + root.launcherQuery + "\""
                    + " rows=" + clearing.rows.length
                    + " of=" + clearing.matches.length
                    + " fold=" + clearing.maxRows
                    + " apps=" + Apps.count
                    + " card=" + root.region(clearing.cardItem, launcherBackdrop)
                    + " legend=" + root.region(clearing.legendItem, launcherBackdrop)
                    + " bar=" + Config.values.bar.height;
            }

            Component.onCompleted: root.describeScene = launcherBackdrop.describe
        }
    }

    /// The notification centre (#43), posed with a history nobody would enjoy
    /// receiving: a long app name, a body several lines past what a toast would
    /// show, a critical row, and a group deep enough to need its count. That is
    /// the picture worth taking — the centre laid out over rows it was designed
    /// for tells nobody anything, and the failure this seam catches is #80's:
    /// text that runs out of the panel it is in.
    ///
    ///     tools/capture-harness.sh out.png --surface center --session
    ///
    /// `--session`, because every row has a Lucide glyph in it — the dismiss
    /// `x`, and the bell that stands in for an app with no icon — and
    /// `MultiEffect` draws nothing on the offscreen scenegraph (Widgets/Icon
    /// .qml). Offscreen still measures the fills and the layout, which is what
    /// an overflow is.
    ///
    /// History is posed by assignment rather than by a fake service: the panel
    /// binds to `Notifications.groups`, which is derived from `history`, so
    /// writing the list is enough to drive the shipped grouping code rather
    /// than a copy of it living in this file.
    Component {
        id: centerScene

        Backdrop {
            id: centerBackdrop

            FogScrim {
                anchors {
                    top: parent.top
                    topMargin: Config.values.bar.height
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                shown: true
            }

            NotificationCenter {
                id: centre

                anchors {
                    top: parent.top
                    topMargin: Config.values.bar.height
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }

                // One group open, because the collapsed panel and the expanded
                // one are two different layouts and only one of them has a
                // notification body in it to overflow.
                expanded: "org.example.chat"
            }

            Component.onCompleted: {
                const now = Date.now();
                Notifications.history = [
                    { time: now - 30000, seq: 6, appKey: "org.example.chat",
                      appName: "Chat", summary: "Ada Lovelace",
                      body: "Right — so the analytical engine's whole trick is that the "
                            + "cards describe the operation as well as the number, which is "
                            + "the part everyone keeps missing when they call it a calculator.",
                      urgency: "normal" },
                    { time: now - 400000, seq: 5, appKey: "org.example.chat",
                      appName: "Chat", summary: "Ada Lovelace",
                      body: "Are you there?", urgency: "normal" },
                    { time: now - 900000, seq: 4, appKey: "org.example.chat",
                      appName: "Chat",
                      summary: "A summary long enough to want the whole width of the panel "
                               + "and then some more besides",
                      body: "", urgency: "low" },
                    { time: now - 3600000, seq: 3, appKey: "org.freedesktop.systemupdates",
                      appName: "System updates, and a name no client should have sent",
                      summary: "Battery critically low", body: "3% remaining.",
                      urgency: "critical" },
                    { time: now - 86400000 * 2, seq: 1, appKey: "", appName: "",
                      summary: "Something with no app id at all", body: "",
                      urgency: "normal" }
                ].map(row => Notifications.policy.record(row));

                root.describeScene = centerBackdrop.describe;
            }

            BarSurface {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: Config.values.bar.height
                settings: Config.values.bar.surface
                fillOpacity: Config.values.bar.surface.opacity
                hairlineAtBottom: true
            }

            function describe(): void {
                root.sceneDescription =
                    "groups=" + Notifications.groups.length
                    + " rows=" + Notifications.history.length
                    + " expanded=\"" + centre.expanded + "\""
                    + " panel=" + centre.panelWidth + "x" + centre.maxPanelHeight
                    + " bar=" + Config.values.bar.height;
            }

            Component.onDestruction: Notifications.history = []
        }
    }

    /// #73: the lock's status strip is one of the two `MultiEffect` surfaces
    /// the ticket says have never rendered anywhere. The real LockSurface and
    /// the real shared LockAuth — what stands in for the session is the state
    /// the strip is gated on, set the way tools/lock-harness.sh sets the buffer.
    Component {
        id: lockScene

        LockSurface {
            id: lockSurface

            screen: root.screen
            auth: lockAuth

            Component.onCompleted: {
                for (const token of root.lockState) {
                    if (token === "summoned") {
                        // What a keystroke does, minus the keyboard: a non-empty
                        // buffer is what `summoned` is derived from. Its
                        // *length* is the number of dots in the field, so a
                        // seven-character word is a seven-dot picture.
                        lockAuth.buffer = "hunter2";
                    } else if (token === "caps") {
                        // Normally inferred from a keystroke — LockPolicy
                        // .capsFromKey — which there is no keyboard to press.
                        lockSurface.capsLock = true;
                    } else if (token.startsWith("notify:")) {
                        // The bell is gated on the count *and* on the setting
                        // that allows it to be shown at all, so both are set:
                        // pinning one and photographing the other is how #73's
                        // strip came back empty the first time.
                        SessionLock.notificationCount = parseInt(token.slice(7));
                        Config.set("system.lock.notificationCount", true);
                    }
                }
                root.sceneDescription = "lock=" + root.lockState.join("+");
            }
        }
    }

    /// #73's other `MultiEffect` surface: the settings chrome. The real
    /// `SettingsView`, which is a toplevel of its own — so it is built as
    /// itself and its content is then moved onto `settingsBacking`, where the
    /// scene can be grabbed like any other surface. Grabbing it where it was
    /// built gives a transparent page (the fill is the window's `color`) and
    /// runs into Quickshell's `ProxyWindowContentItem`, which `grabToImage`
    /// refuses outright: "item has no QML engine".
    Loader {
        id: settingsLoader

        active: root.isSettings
        sourceComponent: SettingsView {}

        onLoaded: {
            if (root.settingsTab.length > 0)
                settingsLoader.item.selectTab(root.settingsTab);

            const content = settingsLoader.item.contentItem;
            if (content.children.length !== 1) {
                // The move below takes one child. If the window ever grows a
                // second, a silent half-capture is the worst outcome available.
                console.warn("capture: settings content has "
                             + content.children.length + " children, expected 1");
            }
            // Sized here rather than left to the window manager: the page fills
            // its parent, so this is what makes the capture the same shape on
            // every run and under any compositor.
            const page = content.children[0];
            page.parent = settingsBacking;
            page.anchors.fill = settingsBacking;

            root.sceneDescription = "tab=" + settingsLoader.item.currentTab;
        }
    }

    /// A scene's own last word, called just before the grab rather than at
    /// completion. Set by a scene whose description depends on layout that is
    /// still settling — the launcher's card grows a row at a time as the
    /// desktop-entry scan streams in, so its height at `Component.onCompleted`
    /// is the height of an empty card.
    property var describeScene: null

    /// An item's bounds in the grabbed scene's coordinates, as `x,y,WxH` —
    /// the spelling tools/measure-contrast.py takes for `--region`.
    ///
    /// Logical pixels, because that is what the scene is laid out in; the
    /// harness script scales them by the factor it derives from the saved file,
    /// the same way it does for the bar.
    function region(item: Item, within: Item): string {
        if (!item || !within)
            return "0,0,0x0";
        const at = item.mapToItem(within, 0, 0);
        return Math.round(at.x) + "," + Math.round(at.y)
             + "," + Math.round(item.width) + "x" + Math.round(item.height);
    }

    // --- the grab -------------------------------------------------------------

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
            if (root.describeScene)
                root.describeScene();

            // No target size: the grab renders the item at the scale the scene
            // is actually drawn at — 1:1 offscreen, the output's scale on a
            // session (1280x800 comes back as 1920x1200 at scale 1.5). That is
            // a native render, not a resample, which is what #85's "no
            // outer-display scaling applied" is really asking for; the harness
            // script derives the factor from the file and scales measurement
            // regions by it. Passing a target size instead would mean trusting
            // `Screen.devicePixelRatio`, which reports 2 on a 1.5-scale display
            // — the lie Widgets/Icon.qml documents, on this exact machine.
            scene.grabToImage(function (result) {
                const ok = result.saveToFile(root.outPath);
                // The battery item in the lock's strip is the one thing here
                // that cannot be posed — it reads `UPower.onBattery` off the
                // real machine — so what it was doing is reported rather than
                // set. Read at the grab and not at build, because UPower has
                // not necessarily answered by the time the surface is up.
                const battery = root.surfaceName === "lock"
                    ? " battery=" + (UPower.onBattery ? "discharging" : "on-mains")
                    : "";
                console.log("capture: saved=" + ok
                            + " " + root.sceneWidth + "x" + root.sceneHeight
                            + " surface=" + root.surfaceName
                            + " " + root.sceneDescription + battery
                            + " " + root.outPath);
                Qt.quit();
            });
        }
    }

    Component.onCompleted: Logger.stage("capture harness loaded (surface "
                                        + root.surfaceName + ", wallpaper "
                                        + (Config.wallpaper || "unset") + ")");
}
