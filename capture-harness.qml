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
//   CAPTURE_SURFACE      bar | bar-full | lock | settings | drawer | launcher |
//                        center | controlcenter | dashboard | osd  (default bar)
//   CAPTURE_W/CAPTURE_H  scene size in logical px (default 1280x800)
//   CAPTURE_BAR_OPACITY  override for the bar fill opacity, e.g. "0.65"
//                        (defaults to the configured bar.surface.opacity)
//   CAPTURE_LOCK_STATE   what the lock is showing, comma-separated: `quiet`,
//                        or any of `summoned`, `caps`, `notify:N`
//   CAPTURE_SETTINGS_TAB which settings tab to open (default: the state file's)
//   CAPTURE_DELAY_MS     settle time before the grab (default 600)
//   CAPTURE_OSD          the OSD pill's state as `channel[:percent[:muted]]`,
//                        e.g. `volume:45` or `mic:60:muted` (default volume:45)
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Core
import qs.Surfaces.Background
import qs.Surfaces.Bar
import qs.Surfaces.Lock
import qs.Surfaces.Settings
import qs.Surfaces.Calendar
import qs.Surfaces.Drawers
import qs.Surfaces.Osd
import qs.Surfaces.Screenshot
import qs.Services.Calendar
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

    /// Whether the bar's legibility clamp (#79) is in force, as it is in the
    /// shell. Off is how the pre-#79 numbers are reproduced — what the fill
    /// *would* measure if the setting were the only thing deciding it — and is
    /// the only way to see the failure the clamp exists to prevent.
    readonly property bool clampLegibility: (Quickshell.env("CAPTURE_BAR_CLAMP") ?? "1") !== "0"
    readonly property string settingsTab: Quickshell.env("CAPTURE_SETTINGS_TAB") ?? ""

    /// How far down the settings page to scroll before grabbing, in px. The
    /// System tab (#55) is several windows tall and its lower half — the idle
    /// ladder and the session commands — is exactly the #80 class this seam
    /// exists to catch, so "the top of the page" is not the whole surface.
    /// Clamped to what there is to scroll, so a number past the bottom lands on
    /// the bottom rather than on blank.
    readonly property int settingsScroll:
        Number(Quickshell.env("CAPTURE_SETTINGS_SCROLL") ?? "0") || 0

    /// Which control-centre detail view to open before the grab (#45), or "" for
    /// the grid. `wifi`, `bluetooth`, `audio`, `vpn`, `wallpaper`.
    readonly property string drillPanel: Quickshell.env("CAPTURE_DRILL") ?? ""
    /// What the OSD pill is reporting (#46), as `channel[:percent[:muted]]`.
    /// Posed rather than read off the machine, for the same reason every other
    /// fact here is: a capture driven by the real services is a picture of
    /// whatever this laptop's volume happened to be.
    readonly property var osdState: (Quickshell.env("CAPTURE_OSD") || "volume:45").split(":")

    /// What the region picker is doing (#51): `region` is a drawn selection
    /// with its readout, `window` is the hover state a click would take. Posed
    /// rather than driven, for the reason everything else here is — a capture
    /// that ran the real picker would photograph whatever this laptop's desktop
    /// happened to be, and could not run offscreen at all, since the freeze is
    /// a `grim` capture of a session this mode does not have.
    readonly property string pickState: Quickshell.env("CAPTURE_PICK") || "region"

    /// The calendar's pose. `--cal-view` picks day, week or month; `--cal-date`
    /// is the day the view is built around; `--cal-state` names an overlay or
    /// an interaction to pose: `drag-create`, `drag-move` and `resize` pose a
    /// gesture on the week grid; `command` (empty query) and `command-filtered`
    /// (`to` typed) and `shortcuts` open the two
    /// keyboard overlays. (`guests` and `popover` are named and refused by
    /// tools/capture-harness.sh until they exist, so the knob never renders a
    /// plain view and calls it a pose.)
    ///
    /// `CAL_NOW` is the one that is not a convenience. The now-line is drawn
    /// from the wall clock, so without a frozen one no two captures of this
    /// surface are ever the same picture and a diff between two runs is
    /// unreadable — exactly the argument `--lock-state` makes for posing PAM.
    readonly property string calView: Quickshell.env("CAL_VIEW") || "week"
    readonly property string calState: Quickshell.env("CAL_STATE") ?? ""
    readonly property string calDate: Quickshell.env("CAL_DATE") || "2026-08-18"
    readonly property string calNow: Quickshell.env("CAL_NOW") || "2026-08-18T13:40"

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
    /// or any of `summoned`, `caps`, `notify:N`, `failed`, `lockout`,
    /// `fingerprint`, `fingerprintdone`. Every item in the lock's status strip
    /// is gated on something about the machine (a discharging battery, a
    /// caps-lock key, notifications waiting), so a capture that does not pin
    /// them photographs whatever this laptop happened to be doing. #73's
    /// criterion is about the icons, and an empty strip answers nothing.
    ///
    /// The last four are #96's half of the failure path: each is gated on a
    /// PAM answer this seam cannot produce, so they are posed through
    /// `LockAuth.pose`. The four of them take an optional `:text` suffix
    /// (`failed:Permission denied`) — no commas in it, since commas separate
    /// the tokens.
    readonly property var lockState: (Quickshell.env("CAPTURE_LOCK_STATE") || "quiet").split(",")

    /// What a posed failure says when the caller did not say. Real sentences
    /// from real stacks rather than placeholders, because the message is shown
    /// *verbatim* and its width is the thing the picture is checking; the
    /// lockout line is deliberately one `LockPolicy.isLockout` recognises, and
    /// tests/tst_lockpolicy.qml holds it to that.
    readonly property var lockPosedText: ({
        "failed": "Authentication failure",
        "lockout": "Account locked due to 3 failed logins",
        "fingerprint": "Place your finger on the reader"
    })

    readonly property bool isSettings: root.surfaceName === "settings"

    /// The calendar is the settings window's shape and not the bar's: a
    /// `FloatingWindow` of its own, so it is built as itself and its content is
    /// moved onto the backing below rather than returned from the switch. See
    /// `calendarLoader` for why grabbing it where it was built cannot work.
    readonly property bool isCalendar: root.surfaceName === "calendar"

    readonly property bool isWindowSurface: root.isSettings || root.isCalendar

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
                active: !root.isWindowSurface
                sourceComponent: {
                    switch (root.surfaceName) {
                    // `settings` and `calendar` are absent on purpose: both are
                    // toplevels of their own and neither can be a child here.
                    case "lock":     return lockScene;
                    case "bar-full": return barFullScene;
                    case "drawer":   return drawerScene;
                    case "launcher": return launcherScene;
                    case "center":   return centerScene;
                    case "controlcenter": return controlCenterScene;
                    case "dashboard": return dashboardScene;
                    case "osd":      return osdScene;
                    case "screenshot": return screenshotScene;
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

            /// The same, for the calendar window. A second rectangle rather
            /// than one shared with the settings' because each is the fill of a
            /// different window, and a window that later paints something other
            /// than `bgBase` would otherwise quietly change the other's
            /// picture.
            Rectangle {
                id: calendarBacking
                anchors.fill: parent
                visible: root.isCalendar
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
            id: barBackdrop

            /// The setting, before the wallpaper gets a say.
            readonly property real requested: root.opacityOverride.length > 0
                ? parseFloat(root.opacityOverride)
                : Config.values.bar.surface.opacity

            /// What the bar actually paints — the setting raised to the
            /// legibility floor, exactly as Surfaces/Bar/BarContent.qml does
            /// it. Measuring the setting instead would measure a bar the shell
            /// does not draw, which is how #68's floor came to be believed.
            readonly property real painted: root.clampLegibility
                ? opacityPolicy.effectiveOpacity(barBackdrop.requested,
                                                 legibility.item ? legibility.item.floor : NaN)
                : barBackdrop.requested

            SurfaceOpacity { id: opacityPolicy }

            Loader {
                id: legibility
                active: root.clampLegibility
                // The scene size, not the screen's: the Backdrop above draws the
                // wallpaper into `scene`, so that is the item PreserveAspectCrop
                // is resolved against and that is the crop this picture shows.
                // Left to assume the screen, the clamp would solve for a
                // different crop of the same file and the gate would be grading
                // a mismatched pair.
                Component.onCompleted: {
                    if (active)
                        setSource(Qt.resolvedUrl("Surfaces/Bar/BarLegibility.qml"),
                                  { screen: root.screen,
                                    viewWidth: root.sceneWidth,
                                    viewHeight: root.sceneHeight });
                }
            }

            BarSurface {
                id: barFill

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: Config.values.bar.height
                settings: Config.values.bar.surface
                fillOpacity: barBackdrop.painted
                hairlineAtBottom: true
            }

            function describe() {
                root.sceneDescription = "bar=" + Config.values.bar.height
                    + " opacity=" + barBackdrop.requested.toFixed(2)
                    + " painted=" + barBackdrop.painted.toFixed(3)
                    + " clamp=" + (root.clampLegibility ? "on" : "off");
            }

            Component.onCompleted: {
                root.describeScene = barBackdrop.describe;
                // The clamp is a wallpaper read, so it lands after the first
                // frame by construction. Grabbing before it does would
                // photograph the unclamped fill and call it the shipped one.
                //
                // And waiting on the *decision* is not enough: the fill fades to
                // it over `motionSlow`, so a grab taken the moment the floor is
                // known catches the fade. Three runs on one wallpaper at one
                // identical `painted` read 5.05:1, 4.76:1 and 4.45:1 that way —
                // a gate that reports a different answer each time it is asked,
                // which is worse than one that is merely wrong. Waiting for the
                // fill to settle at the value it was told is what makes the
                // measurement a measurement.
                root.sceneReady = () => !root.clampLegibility
                    || (legibility.item && legibility.item.ready
                        && Math.abs(barFill.paintedOpacity - barBackdrop.painted) < 0.002);
            }
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
            // This one is the real BarContent, so its clamp reads the *screen's*
            // crop of the wallpaper while the Backdrop draws the scene's. The
            // fill-only scene above is told the difference because it is the
            // contrast gate; this scene is refused `--contrast` outright
            // (tools/capture-harness.sh), so the floor it lands on only has to
            // be a plausible one for the layout picture, not the measured one.
            BarContent {
                id: fullBar

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: Config.values.bar.height
                screen: root.screen
            }

            Component.onCompleted: {
                // Same wait as the fill-only scene: this is the real
                // BarContent, so its fill is clamped too and grabbing early
                // would photograph the unclamped one (#79).
                root.sceneReady = () => fullBar.legibilitySettled;
                root.sceneDescription = "bar=" + Config.values.bar.height
                    + " modules=" + JSON.stringify(Config.values.bar.modules.left)
                    + "/" + JSON.stringify(Config.values.bar.modules.center)
                    + "/" + JSON.stringify(Config.values.bar.modules.right);
            }
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

    /// The control centre (#44), posed with a machine that has everything: all
    /// three sliders, all nine tiles, a battery with an estimate, and the
    /// longest strings any of those fields can actually carry — a 32-character
    /// SSID (the limit the spec allows), a vendor power profile and a VPN
    /// profile named like a real one. That is the picture worth taking, and the
    /// failure this seam catches is #80's: a row whose text column starves
    /// because something beside it grew.
    ///
    ///     tools/capture-harness.sh out.png --surface controlcenter --session
    ///     tools/capture-harness.sh out.png --surface controlcenter --light
    ///
    /// `--session` for the picture, because every tile and every slider has a
    /// Lucide glyph in it and `MultiEffect` draws nothing on the offscreen
    /// scenegraph (Widgets/Icon.qml). Offscreen still measures the fills and
    /// the layout, which is what an overflow is — and an overflow is what this
    /// surface is captured for: the first run of it cut four of nine tile
    /// labels to "Do Not Di…", which is the #80 shape exactly.
    ///
    /// `--contrast` is *refused* here, and tools/capture-harness.sh says why at
    /// length: this panel is opaque throughout, so its ratios are arithmetic
    /// over two palette constants rather than a composite over a wallpaper. The
    /// light-palette gate #44 owes lives in tests/tst_tokens.qml instead, where
    /// it covers both modes and every role pair.
    ///
    /// The facts are *assigned* rather than left to the services: the panel
    /// binds to real hardware, and a capture of that is a picture of whichever
    /// machine ran it. Assigning replaces the binding and drives the shipped
    /// policy — the tiles, the reflow and the strip are all still the real
    /// code, working off a machine this one is pretending to be.
    Component {
        id: controlCenterScene

        Backdrop {
            id: controlBackdrop

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

            ControlCenter {
                id: centre

                anchors {
                    top: parent.top
                    topMargin: Config.values.bar.height
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }

                facts: ({
                    wifi: { available: true, on: true,
                            label: "PUMPKINCURRY-5GHz-guest-net" },
                    bluetooth: { present: true, on: true, label: "2 devices" },
                    dnd: { on: true },
                    nightlight: { available: true, on: true, temperature: 4000 },
                    keepawake: { on: true },
                    dark: Theme.dark,
                    powerprofile: { available: true, profile: "power-saver" },
                    vpn: { available: true, on: true, name: "work-eu-frankfurt-1" },
                    volume: { available: true, percent: 45, muted: false },
                    mic: { available: true, percent: 80, muted: true },
                    brightness: { available: true, percent: 60 },
                    // #52's tenth tile, posed idle. It is what makes the grid
                    // 3x3 plus one, so leaving it out of this fixture would
                    // mean the short last row — the only #80-class question
                    // this change raises — was never in a picture.
                    recording: { available: true, on: false, detail: "GPU" },
                    battery: { hasBattery: true, label: "84%",
                               state: "discharging", timeRemaining: "3h 20m" }
                })
            }

            function describe(): void {
                root.sceneDescription =
                    // Off the latched models (#192, #195), which is also what
                    // the panel draws from. `centre.sliderRows` was left
                    // behind by #192's latch and read `undefined` here.
                    "tiles=" + (centre.tileIds ?? []).length
                    + " rows=" + centre.tileIdRows.length
                    + " sliders=" + (centre.sliderIds ?? []).length
                    + " mode=" + (Theme.dark ? "dark" : "light")
                    + " drill=" + (ControlCenterActions.panel || "none")
                    + " panel=" + root.region(centre.panelItem, controlBackdrop)
                    + " strip=" + root.region(centre.stripItem, controlBackdrop)
                    + " tile=" + root.region(centre.litTileItem, controlBackdrop)
                    + " bar=" + Config.values.bar.height;
            }

            // The drill-ins (#45), when one is asked for. Driven through the
            // same door the IPC handler and the tiles use, so what is captured
            // is the panel a press produces and not a component posed by name.
            //
            // The four list panels are captured against *real* services and so
            // against whatever this machine has — unlike the grid above, whose
            // facts are assigned. That is deliberate and it is the honest
            // limit of this seam for them: a network list is a picture of a
            // radio, and there is no way to pose one from here. What the
            // capture is worth is the #80 check — that a row with a long name
            // in it does not starve the column beside it — and an empty list
            // still answers the layout half of that through the chrome. The
            // wallpaper picker is the one that poses fully, because its
            // contents are files and `--wallpaper-folder` can point at any.
            Component.onCompleted: {
                root.describeScene = controlBackdrop.describe;
                if (root.drillPanel !== "")
                    ControlCenterActions.drill(root.drillPanel);
            }

            // Left at the root again, so a harness run cannot leave a scanner
            // running on the machine that ran it.
            Component.onDestruction: ControlCenterActions.back("capture")

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
        }
    }

    /// The dashboard (#49), hanging from the bar's clock, posed with a day and
    /// a player.
    ///
    ///     tools/capture-harness.sh out.png --surface dashboard --session
    ///     tools/capture-harness.sh out.png --surface dashboard --light
    ///
    /// `--session` for the picture: the transport buttons, the calendar's
    /// chevrons and the cover-art placeholder are all Lucide glyphs, and
    /// `MultiEffect` draws nothing on the offscreen scenegraph
    /// (Widgets/Icon.qml). Offscreen still measures the fills and the layout,
    /// which is what this surface is captured for — a seven-column grid inside a
    /// 380px panel and a track title of arbitrary length beside it are both the
    /// #80 shape waiting to happen.
    ///
    /// Everything is *posed*, and this surface needs it more than any other:
    /// the calendar draws today, so an unposed capture is a different picture
    /// every day and the same one is never taken twice; the media card draws
    /// whatever this machine is playing, which on the machine running a capture
    /// is usually nothing at all — and "nothing" removes the card entirely.
    /// The date is #93's own example minute, so a dashboard capture and a
    /// bar-full one can be read side by side.
    ///
    /// The two images are the scratch wallpaper the harness generated, used as
    /// cover art and as the account picture. A real file rather than a
    /// placeholder, because what is being judged is the *clipping* — album art
    /// is the one arbitrary image this shell puts on screen, and a square
    /// corner poking out of a rounded card is only visible with something in
    /// it.
    Component {
        id: dashboardScene

        Backdrop {
            id: dashboardBackdrop

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

            Dashboard {
                id: dash

                anchors {
                    top: parent.top
                    topMargin: Config.values.bar.height
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }

                facts: ({
                    now: new Date(2026, 7, 1, 19, 26),
                    profile: { name: "Daniel",
                               avatar: Config.values.wallpaper.path },
                    // The weather (#50), posed for the same reason the calendar
                    // is: the live card is a picture of the sky over whoever
                    // ran the capture, on the day they ran it, and on a machine
                    // with no network it is a line of small print. An overcast
                    // afternoon with rain coming is the layout worth
                    // photographing — four columns of two temperatures each
                    // inside a 380px panel is the #80 shape.
                    weather: {
                        status: "ready",
                        label: "Boston, Massachusetts, US",
                        message: "",
                        // Posed with the rest of the reading rather than read
                        // from the settings: a capture taken on a machine
                        // configured in Fahrenheit would otherwise draw "12
                        // mph" under these Celsius numbers.
                        units: "metric",
                        current: { temperature: 24.3, feelsLike: 25.1,
                                   humidity: 61, wind: 12.4, code: 3, day: true },
                        days: [
                            { date: "2026-08-01", code: 3, high: 26.4, low: 18.2 },
                            { date: "2026-08-02", code: 61, high: 22.1, low: 17.0 },
                            { date: "2026-08-03", code: 0, high: 27.9, low: 19.4 },
                            { date: "2026-08-04", code: 95, high: 24.6, low: 18.8 }
                        ]
                    },
                    // The machine, posed as the sampler's own two values rather
                    // than as finished rows — the card runs them through the
                    // same policy the live one does, so a capture cannot pass
                    // against row rules the shell does not use.
                    system: {
                        sample: { cpu: 0.42, memory: 0.61, disk: 0.53,
                                  temperature: 62.5,
                                  memoryUsedKb: 9993420, memoryTotalKb: 16384000,
                                  diskUsedKb: 491470000, diskTotalKb: 982940000 },
                        history: {
                            cpu: root.wave(0.42, 0.30, 7),
                            memory: root.wave(0.61, 0.05, 3),
                            disk: root.wave(0.53, 0.00, 1),
                            // A machine whose first samples are missing, which
                            // is what every freshly-opened card looks like —
                            // the gap at the left of the row is in the picture
                            // on purpose.
                            temperature: root.wave(0.50, 0.18, 5, 12)
                        }
                    },
                    media: {
                        showing: true,
                        // The longest thing this row ever carries, which is the
                        // overflow worth photographing: a title from another
                        // application, next to a 64px cover.
                        title: "It's Not Just Me, It's Everybody",
                        artist: "Weyes Blood",
                        art: Config.values.wallpaper.path,
                        playing: true,
                        canGoBack: true,
                        canToggle: true,
                        // A player that will not skip, so the dimmed state of a
                        // transport button is in the picture too.
                        canSkip: false,
                        position: 128,
                        length: 372,
                        scrubbable: true
                    }
                })
            }

            function describe(): void {
                root.sceneDescription =
                    "cards=" + dash.cards.length
                    + " (" + (dash.cards.join(",") || "none") + ")"
                    + " mode=" + (Theme.dark ? "dark" : "light")
                    + " panel=" + root.region(dash.panelItem, dashboardBackdrop)
                    + " bar=" + Config.values.bar.height;
            }

            // Deferred, like the control centre's: the panel is sized from a
            // column of cards that are still loading at `onCompleted`, so a
            // region reported there is the header's alone.
            Component.onCompleted: root.describeScene = dashboardBackdrop.describe

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
        }
    }

    /// The OSD pill (#46), over the wallpaper it floats on, at the position the
    /// settings put it.
    ///
    ///     tools/capture-harness.sh out.png --surface osd --session
    ///     tools/capture-harness.sh out.png --surface osd --session --osd mic:60:muted
    ///
    /// `--session`, because the pill is a glyph, a track and a reading, and
    /// `MultiEffect` draws nothing on the offscreen scenegraph
    /// (Widgets/Icon.qml) — an offscreen capture is the same picture with the
    /// speaker missing. Offscreen still measures the fills and the layout,
    /// which is what an overflow is: the readout is a fixed column beside a
    /// track that takes the rest, and "Muted" is the longest thing that column
    /// ever holds.
    ///
    /// The real OsdContent, posed by assignment. What is *not* here is the
    /// window: `Surfaces/Osd/OsdWindow.qml` is a layer surface, and where a
    /// compositor puts it is seam 2's business (tools/osd-harness.sh) — so the
    /// pill is placed here the way the anchor table says it would be, from the
    /// same policy the window reads.
    Component {
        id: osdScene

        Backdrop {
            id: osdBackdrop

            readonly property string channel: root.osdState[0]
            readonly property int percent: root.osdState.length > 1
                ? parseInt(root.osdState[1]) : 45
            readonly property bool muted: root.osdState.length > 2
                && root.osdState[2] === "muted"

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

            OsdContent {
                id: pill

                readonly property var anchorFlags: Osd.policy.anchorsFor(Osd.position)
                readonly property var marginValues:
                    Osd.policy.marginsFor(Osd.position, Osd.margin)

                // The layer-shell rule, drawn: an anchored edge is that edge
                // plus its margin, and an unanchored axis is centred.
                x: anchorFlags.left ? marginValues.left
                 : anchorFlags.right ? parent.width - width - marginValues.right
                 : (parent.width - width) / 2
                y: anchorFlags.top ? marginValues.top
                 : anchorFlags.bottom ? parent.height - height - marginValues.bottom
                 : (parent.height - height) / 2

                width: implicitWidth
                height: implicitHeight

                policy: Osd.policy
                channel: osdBackdrop.channel
                percent: osdBackdrop.percent
                muted: osdBackdrop.muted
            }

            Component.onCompleted: root.sceneDescription =
                "osd=" + osdBackdrop.channel + ":" + osdBackdrop.percent
                + (osdBackdrop.muted ? ":muted" : "") + " at=" + Osd.position
        }
    }

    /// #51: the region picker over a frozen screen — the veil, the marquee and
    /// its readout, or the window highlight a click would take.
    ///
    /// The wallpaper stands in for the freeze, which is the honest substitution
    /// rather than a convenient one: on a real session the freeze is a PNG of
    /// the whole output and the overlay stretches it edge to edge, which is
    /// exactly what `Backdrop`'s `Wallpaper` does here. What is being judged is
    /// the picker's own chrome against a photograph — whether the veil is dark
    /// enough to read the selection out of, and whether the readout stays
    /// legible over an arbitrary picture.
    ///
    /// Every part of it is Rectangle, Image and Text, so this is one of the
    /// surfaces the default offscreen mode judges completely — there is no
    /// glyph in the picker to lose.
    Component {
        id: screenshotScene

        Backdrop {
            id: pickBackdrop

            // A posed desktop, in the same logical coordinates the real picker
            // works in. Two windows, one inside the other, so the hover state
            // shows the smallest-wins rule rather than a single obvious box.
            readonly property var posedWindows: [
                { x: 40, y: 60, width: 620, height: 460, title: "kitty", appId: "kitty" },
                { x: 700, y: 60, width: 540, height: 680, title: "Firefox", appId: "firefox" },
                { x: 160, y: 180, width: 300, height: 200, title: "Preferences", appId: "kitty" }
            ]

            readonly property bool hovering: root.pickState === "window"

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

            PickerOverlay {
                id: picker
                anchors.fill: parent

                // Not `freezeSource`: the wallpaper behind this item is already
                // standing in for the freeze, and pointing the overlay at it a
                // second time would composite the picture over itself.
                freezeSource: ""

                windows: pickBackdrop.posedWindows
                outputScale: 1.5

                selection: pickBackdrop.hovering
                    ? Qt.rect(0, 0, 0, 0)
                    : Qt.rect(160, 180, 500, 340)
                hovered: pickBackdrop.hovering ? pickBackdrop.posedWindows[2] : null
            }

            Component.onCompleted: root.sceneDescription =
                "pick=" + root.pickState
                + " selection=" + picker.selection.width + "x" + picker.selection.height
                + " windows=" + pickBackdrop.posedWindows.length
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
                    // Every token is `kind` or `kind:text`, split once here so
                    // no branch has to say its own name twice.
                    const colon = token.indexOf(":");
                    const kind = colon === -1 ? token : token.slice(0, colon);
                    const text = colon === -1 ? "" : token.slice(colon + 1);
                    if (kind === "summoned") {
                        // What a keystroke does, minus the keyboard: a non-empty
                        // buffer is what `summoned` is derived from. Its
                        // *length* is the number of dots in the field, so a
                        // seven-character word is a seven-dot picture.
                        lockAuth.buffer = "hunter2";
                    } else if (kind === "caps") {
                        // Normally inferred from a keystroke — LockPolicy
                        // .capsFromKey — which there is no keyboard to press.
                        lockSurface.capsLock = true;
                    } else if (kind === "failed") {
                        // A refusal, minus PAM: the message under the field is
                        // whatever the stack said, and this is the only seam
                        // that can photograph it. The shake is not here — an
                        // animation is not a still, and it stays with the
                        // real-session half of #96.
                        lockAuth.pose({
                            message: text || root.lockPosedText[kind],
                            messageIsError: true
                        });
                    } else if (kind === "lockout") {
                        // faillock. `lockedOut` is presentation-only and never
                        // retreats (#30), which is exactly why it had never been
                        // seen: nothing on this machine could reach it.
                        lockAuth.pose({
                            message: text || root.lockPosedText[kind],
                            messageIsError: true,
                            lockedOut: true
                        });
                    } else if (kind === "fingerprint") {
                        // The parallel conversation, on a machine with no
                        // reader. `fingerprintActive` is the whole gate, so
                        // posing it is the branch drawing for the first time.
                        lockAuth.pose({
                            fingerprintActive: true,
                            fingerprintMessage: text || root.lockPosedText[kind]
                        });
                    } else if (kind === "fingerprintdone") {
                        // The withdrawn offer (#169). Its own state rather than
                        // a `:text` on the one above, because the two differ in
                        // the gate as well as the words: this line is on screen
                        // with `fingerprintActive` false, which is the binding
                        // #169 changed and the reason it is worth a picture.
                        // The longest string that line ever holds, too — and it
                        // is not written down here: the offer is posed open and
                        // then really withdrawn, so the words in the picture are
                        // the ones LockPolicy would give a user rather than a
                        // copy of them that can drift.
                        lockAuth.pose({ fingerprintActive: true });
                        lockAuth.withdrawFingerprint(true);
                        if (text)
                            lockAuth.pose({ fingerprintMessage: text });
                    } else if (kind === "notify") {
                        // The bell is gated on the count *and* on the setting
                        // that allows it to be shown at all, so both are set:
                        // pinning one and photographing the other is how #73's
                        // strip came back empty the first time.
                        SessionLock.notificationCount = parseInt(text);
                        Config.set("system.lock.notificationCount", true);
                    } else if (kind !== "quiet") {
                        // A typo used to pose nothing and still report PASS,
                        // which is the failure this seam is least able to
                        // afford: a picture of a quiet lock filed as a picture
                        // of a lockout. The script fails the run on this line.
                        console.warn("capture: unknown --lock-state token "
                                     + JSON.stringify(token));
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

            // Applied just before the grab and not here: the page is a
            // Flickable whose `contentHeight` is the sum of a column that has
            // not been laid out yet at `onLoaded`, so a clamp computed now
            // would clamp against zero.
            root.describeScene = function () {
                if (root.settingsScroll > 0)
                    settingsLoader.item.scrollPageTo(root.settingsScroll);
                const at = settingsLoader.item.pageScroll;
                root.sceneDescription = "tab=" + settingsLoader.item.currentTab
                                      + (at > 0 ? "+scroll=" + Math.round(at) : "");
            };
            root.sceneDescription = "tab=" + settingsLoader.item.currentTab;
        }
    }

    /// The first descendant of `item` with this `objectName`, or null.
    ///
    /// The calendar poses are set on the *week grid*, which `CalendarView` owns
    /// under an id no other file can reach — and the harness is deliberately
    /// not allowed to reach into that file. So the grid names itself
    /// (`objectName: "calendarWeekGrid"`) and this walks the tree for it. A
    /// missing grid is a warning and a plain picture, never an exception: a
    /// TypeError here would read as a broken harness rather than as a pose that
    /// did not apply.
    function findByObjectName(item: var, name: string): var {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        const kids = item.children;
        for (let i = 0; i < kids.length; i++) {
            const found = root.findByObjectName(kids[i], name);
            if (found)
                return found;
        }
        return null;
    }

    /// The three drag poses, as a day and a minute at each end.
    ///
    /// Not a synthetic pointer: `DragPolicy` is pure, so `begin` and `update`
    /// can be called with grid coordinates and the picture is the same one a
    /// real drag would be showing at that instant — deterministic, and with no
    /// compositor anywhere near it. The events named are the fixture's own
    /// (`tools/fixtures/calendar-events.json`).
    readonly property var calendarPoses: ({
        "drag-create": {
            "mode": "create",
            "eventId": "",
            "fromIso": "2026-08-19", "fromMin": 900,
            "toIso": "2026-08-19", "toMin": 990
        },
        "drag-move": {
            "mode": "move",
            "eventId": "evt-3",
            "fromIso": "2026-08-18", "fromMin": 600,
            "toIso": "2026-08-19", "toMin": 660
        },
        "resize": {
            "mode": "resizeBottom",
            "eventId": "evt-6",
            // **Not a whole hour.** This landed on 1020 — 5 PM exactly — and
            // the picture that came back was a chip whose top and bottom both
            // sat on hour rules, which is what a chip that is not being resized
            // looks like. A resize is only legible as one when the edge under
            // the finger is somewhere no rule is: 16:45 puts the bottom three
            // quarters down the 4 PM band, and the duration beside the range
            // reads 1h 45m rather than a round number the grid could have
            // produced on its own.
            "fromIso": "2026-08-18", "fromMin": 945,
            "toIso": "2026-08-18", "toMin": 1005
        }
    })

    function poseCalendarDrag(page: var): void {
        const pose = root.calendarPoses[root.calState];
        if (!pose)
            return;
        const week = root.findByObjectName(page, "calendarWeekGrid");
        if (!week) {
            console.warn("capture: no calendarWeekGrid to pose — the picture is the plain view");
            return;
        }
        week.posedDrag = pose;
    }

    /// The quick-create panel, on an event this function makes — the picture at
    /// the *end* of a drag-create rather than during one, which is the moment
    /// the panel exists for.
    ///
    /// It is the `drag-create` pose's own coordinates, so the two states are
    /// two frames of one gesture: the same Wednesday afternoon slot, drawn
    /// mid-drag by `posedDrag` and named-and-panelled by this.
    ///
    /// A predicate rather than a one-shot, because the panel is anchored to a
    /// chip rectangle and there is no chip rectangle until the grid has a
    /// width: `openQuickCreate` refuses a column it cannot find, silently and
    /// correctly, and at `onLoaded` it cannot find one. Returning false makes
    /// the grab wait and try again instead of photographing the plain week.
    function poseCalendarPopover(page: var): bool {
        const week = root.findByObjectName(page, "calendarWeekGrid");
        if (!week) {
            console.warn("capture: no calendarWeekGrid to pose the popover on");
            return false;
        }
        // Already open, one whole retry ago: the panel scales and fades in from
        // `Component.onCompleted`, so a grab taken on the pass that opened it
        // photographs a shadow with nothing inside (measured). The wait is the
        // animation's, and `false` below is what buys it.
        if (week.quickCreateId.length > 0)
            return true;
        if (week.width <= 0)
            return false;

        const pose = root.calendarPoses["drag-create"];
        const id = CalendarStore.createEvent(pose.fromIso, pose.fromMin,
                                             pose.toMin - pose.fromMin, "");
        if (!id) {
            // Said out loud rather than posed around: a popover the store
            // refused to build is a failed capture, not a plain view.
            console.warn("capture: the store would not create the popover's event");
            return false;
        }
        const event = CalendarStore.policy.byId(CalendarStore.events, id);
        if (!event) {
            console.warn("capture: created " + id + " and could not read it back");
            return false;
        }
        week.openQuickCreate(id, pose.fromIso, event.start, event.end);
        if (week.quickCreateId.length === 0) {
            console.warn("capture: " + pose.fromIso + " is not a column on screen —"
                         + " the popover has nothing to anchor to");
            return false;
        }
        return false;
    }

    /// The calendar window (#calendar), on the same terms as the settings one
    /// above and for the same reason: `CalendarView` is a `FloatingWindow`, so
    /// it is built as itself and its content is then moved onto
    /// `calendarBacking`, where the scene can be grabbed like any other
    /// surface. Grabbing it where it was built gives a transparent page — the
    /// fill is the window's `color` — and runs into Quickshell's
    /// `ProxyWindowContentItem`, which `grabToImage` refuses outright.
    ///
    /// The pose is handed in as properties rather than driven, which is what
    /// keeps this mode compositor-free: `nowOverride` in particular is what
    /// makes two runs the same picture.
    ///
    /// Posed on `CalendarWindow` and not on the view: the window is the
    /// surface's only clock, so freezing it there is what keeps `ipc call
    /// calendar today` agreeing with this picture instead of a second clock
    /// on the view drifting from it.
    Binding {
        target: CalendarWindow
        property: "nowOverride"
        value: root.isCalendar ? root.calNow : ""
    }

    Loader {
        id: calendarLoader

        active: root.isCalendar
        sourceComponent: CalendarView {
            view: root.calView
            anchorDate: root.calDate

            // The clock a real window is handed by `CalendarWindow`, which is
            // the surface's only clock (see the `Binding` below): under
            // `--cal-now` it is the frozen stamp, otherwise the wall clock the
            // shell itself is reading — one clock either way.
            shellStamp: CalendarWindow.nowStamp

            // The two keyboard overlays are posed as properties rather than
            // driven with a key, for the same reason the drag is posed rather
            // than dragged: this mode has no compositor to deliver either.
            //
            // Two poses, and `command` is the **empty** one.
            //
            // It was the typed one, on the argument that a picture of an empty
            // field says nothing about whether filtering works. True, and it
            // bought that at the cost of the picture being a menu at all: the
            // one query left one row under the field, and a card that is 74%
            // chrome around a single command is a photograph of a search result,
            // not of a command menu. What has to be judgeable here is the thing
            // this surface is for — the whole keymap, grouped, with its rail of
            // shortcuts down the right — so the default pose opens with nothing
            // typed and every command showing.
            //
            // Filtering keeps its own picture rather than losing one:
            // `command-filtered` is the old pose under its own name.
            commandOpen: root.calState === "command"
                      || root.calState === "command-filtered"
            commandQuery: root.calState === "command-filtered" ? "to" : ""
            shortcutsOpen: root.calState === "shortcuts"

            // The guests pose, on the same terms and for the same reason: the
            // editor is opened on a *named* fixture event — the Tuesday 10:00
            // "Design review", which already has two guests on it so the panel
            // shows both halves of the control at once — and the picker is
            // posed **with a query typed and its list down**. An editor
            // photographed with an empty field would say nothing about whether
            // searching, ranking or the invite row work.
            //
            // `"a"` and not `"mi"`: one letter matches almost everybody, so
            // the picture carries a full dropdown with the prefix match on top
            // (Amina) and the word-prefix one under it (Alvarez), which is the
            // ranking rule made visible.
            editorId: root.calState === "guests" ? "evt-3" : ""
            editorQuery: root.calState === "guests" ? "a" : ""
            editorListOpen: root.calState === "guests"
        }

        onLoaded: {
            const content = calendarLoader.item.contentItem;
            if (content.children.length !== 1) {
                // The move below takes one child. If the window ever grows a
                // second, a silent half-capture is the worst outcome available.
                console.warn("capture: calendar content has "
                             + content.children.length + " children, expected 1");
            }
            if (content.children.length < 1) {
                // And with none there is nothing to move at all — reaching for
                // children[0] here would turn the warning above into a
                // TypeError, which reads like a broken harness rather than an
                // empty window. Leaving the backing bare fails the run at the
                // "not blank" check instead, which is the true diagnosis.
                console.warn("capture: nothing to reparent — the capture will be blank");
                return;
            }
            const page = content.children[0];
            page.parent = calendarBacking;
            page.anchors.fill = calendarBacking;

            root.poseCalendarDrag(page);
            if (root.calState === "popover")
                root.sceneReady = () => root.poseCalendarPopover(page);

            root.sceneDescription = "view=" + root.calView + "+date=" + root.calDate
                                  + "+now=" + root.calNow
                                  + (root.calState.length > 0 ? "+state=" + root.calState : "");
        }
    }

    /// A scene's own last word, called just before the grab rather than at
    /// completion. Set by a scene whose description depends on layout that is
    /// still settling — the launcher's card grows a row at a time as the
    /// desktop-entry scan streams in, so its height at `Component.onCompleted`
    /// is the height of an empty card.
    property var describeScene: null

    /// An optional predicate a scene sets when it has something asynchronous
    /// worth waiting for. The grab retries until it answers true or the budget
    /// below runs out — it never gives up silently, because a capture taken
    /// before the scene settled is a picture of the wrong thing and looks
    /// exactly like a picture of the right thing.
    property var sceneReady: null

    /// A sparkline's worth of samples, generated rather than typed out: sixty
    /// numbers written into the pose above would be sixty numbers to read past
    /// (#50). Deterministic — a sine and not a random walk — because the whole
    /// point of a posed capture is that the same picture is taken twice.
    ///
    /// `gap` leading samples come back as NaN, which is what a card that has
    /// only just opened actually holds.
    function wave(centre: real, swing: real, period: int, gap: int): var {
        const out = [];
        const missing = gap === undefined ? 0 : gap;
        for (let i = 0; i < 60; i++)
            out.push(i < missing
                     ? NaN
                     : Math.max(0, Math.min(1, centre + swing * Math.sin(i / period))));
        return out;
    }

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
        id: grabTimer

        /// How many more times the grab may wait on `sceneReady`. The budget is
        /// generous because the thing it waits for is a wallpaper decode: the
        /// largest wallpaper on this machine is a 27 MiB PNG that takes ~1 s to
        /// read the size of and ~0.6 s to quantize.
        property int retries: Math.ceil(6000 / Math.max(1, root.delayMs))

        interval: root.delayMs
        running: true
        repeat: false
        onTriggered: {
            if (root.outPath.length === 0) {
                console.log("capture: saved=false no CAPTURE_OUT set");
                Qt.quit();
                return;
            }
            if (root.sceneReady && !root.sceneReady()) {
                if (grabTimer.retries > 0) {
                    grabTimer.retries--;
                    grabTimer.restart();
                    return;
                }
                // Said out loud rather than captured anyway: the harness script
                // treats a missing `saved=true` as a failure, which is the
                // right outcome for a scene that never settled.
                console.log("capture: saved=false scene never became ready");
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
