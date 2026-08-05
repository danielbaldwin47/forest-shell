// The control centre (#44) — the shared drawer window's fourth tenant.
//
// Three sliders, a 3×3 toggle grid and a bottom strip, hanging from the
// top-right corner under the bar button that opens it (#27's "each drawer is
// anchored to what opened it").
//
// ## What this file is, and what it is not
//
// It is the one place in the shell that *assembles* the system services into a
// single picture: audio, backlight, network, bluetooth, VPN, night light, keep
// awake, power profile, battery, media, DND and the theme mode all meet here
// and nowhere else. That makes it the file most at risk of becoming where the
// decisions live, so they are all on the other side of two lines instead:
//
//   - **what to draw** is ControlCenterPolicy.qml — which tiles this machine
//     has, what each says, which sliders exist, the battery line. It imports
//     nothing but QtQuick, so `tests/` reaches all of it (35 cases) without a
//     compositor;
//   - **what a press does** is each service's own facade, which is where the
//     exit-status checks (#78) and the log lines (#81) live.
//
// What is left here is `facts` — one object per frame, assembled from the
// services and handed to the policy — and a `switch` that routes a tile id back
// to the service that owns it. Both are deliberately dull.
//
// ## Absent hardware
//
// A tower has no battery, no backlight and often no bluetooth radio; a machine
// with no VPN profile has no tunnel to toggle. Every one of those cases removes
// a control rather than greying one out, and the grid closes the gap behind it
// (ControlCenterPolicy.qml states the rule). So this panel is a different size
// on a laptop and on a tower, and both are correct.
//
// ## The detail views (#45)
//
// Four of the nine tiles and two of the three sliders have a *door* in them —
// Wi-Fi, Bluetooth and VPN are a switch and a list at once, the wallpaper tile
// is only a door, and the sound panel hangs off the volume slider. Behind each
// is one of Surfaces/Drawers/DrillIn/*.qml, and they slide in over the root view
// inside this same card rather than opening a window.
//
// Which is open is not held here: it is
// Surfaces/Drawers/ControlCenterActions.qml's `panel`, for the same reason the
// routing table is there. A drawer's contents cannot be clicked by anything this
// repo may assume, so the IPC door is both a feature and the only seam-2
// evidence that the navigation works at all.
//
// What *is* here is the transition, and one thing that has to happen with it:
// the two radio panels hold a scanner while they are open, so a drawer closing
// under an open panel has to close the panel too. `Component.onDestruction`
// below is that — without it, dismissing the drawer with the Wi-Fi list up
// leaves the radio scanning with nothing looking at it, which is a wakeup every
// few seconds that nothing on screen would show.
//
// ## Motion
//
// Two scales of it. The drawer's own is DrawerSlot.qml — the 320 ms entrance,
// the 240 ms exit and #27's cross-drawer overlap, with the transform origin at
// this panel's corner so it grows out of the bar button. Nothing here animates
// on open.
//
// The drill-in is the *in-place* step (`motionFast`, 140 ms): the card is
// already on screen and only its contents change, which is the same rung
// ControlTile.qml fades its fill on. Forward slides leftward and back reverses
// it, so the way out is always the way you came in (DrillInPolicy.qml).
//
// The animations are explicit and not `Behavior`s, for the reason DrawerSlot.qml
// documents at length: a `Behavior` does not run during component creation, and
// the incoming view is a freshly loaded delegate every time.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Core
import qs.Widgets
import qs.Services.Media
import qs.Services.Hardware
import qs.Services.Networking
import qs.Services.Notifications
import qs.Services.Recorder
import qs.Surfaces.Settings
import qs.Surfaces.Drawers.DrillIn

FocusScope {
    id: root

    /// Raised when the centre wants the drawer gone. The session button raises
    /// it too — that press opens another drawer, and two drawers open at once
    /// is the state Surfaces/Drawers/DrawerPolicy.qml makes unrepresentable.
    signal closeRequested(string reason)

    readonly property ControlCenterPolicy policy: ControlCenterPolicy {
        // The grid is a setting (#55). Bound and not read once: an edit on the
        // Control Center tab has to move the panel behind it, and
        // Core/Config.qml replaces `values` wholesale on every write.
        tileOrder: Config.values.controlCenter.tiles
        sliderOrder: Config.values.controlCenter.sliders
        columns: Config.values.controlCenter.columns
        step: Config.values.controlCenter.step
    }
    readonly property DrillInPolicy drillPolicy: DrillInPolicy {}

    /// Which detail view is open, or `""`. Read from the singleton rather than
    /// held, so the panel and `qs ipc call controlcenter drill wifi` cannot
    /// disagree about what is on screen.
    readonly property string drillPanel: ControlCenterActions.panel

    /// A component dimension, not a token (#8): wide enough for three tiles
    /// with a network name on each, narrow enough to leave the desktop visible
    /// beside it.
    readonly property int panelWidth: 400

    /// Never taller than the screen it hangs on, less its margins.
    readonly property int maxPanelHeight: Math.max(200, root.height - Theme.space4 * 2)

    focus: true

    /// Three measurement regions for tools/capture-harness.sh, and nothing in
    /// the shell reads any of them.
    ///
    /// Three and not one, because the panel carries *two* text-on-fill pairings
    /// and a whole-panel average measures neither: the tiles that are lit draw
    /// dark ink on a teal fill, and everything else draws light text on the
    /// panel's own surface. Averaged together the teal drags the mean toward a
    /// light text colour that is never drawn on it, and the result is a number
    /// about a pairing that does not exist.
    readonly property alias panelItem: panel
    /// The bottom strip: `textSecondary` on `surface`, which is the dimmest
    /// pairing in the panel and so the one the floor has to hold for.
    readonly property alias stripItem: powerLine
    /// The first lit tile, if any: `bgBase` ink on an `accentDeep` fill. The
    /// one pairing in the shell that exists nowhere but this grid.
    ///
    /// One tile and not the grid: the grid is mostly unlit surface, so its mean
    /// is the panel's fill again and measuring dark ink against it reads 1.9:1
    /// — a number about the tiles the ink is *not* on. Claimed by the first lit
    /// delegate to complete, which is the first in `tileOrder` because the
    /// repeater builds in order.
    property Item litTileItem: null

    // --- the machine, as one object ------------------------------------------
    //
    // Re-evaluated whenever any service property below changes, which is what
    // makes the grid live: a radio coming up, a cable going in or a tunnel
    // dropping redraws the tile under the pointer without anything here
    // subscribing to it.
    //
    // Not `readonly`, and that is the one concession this file makes to a
    // harness: a capture of the real panel would otherwise be a picture of
    // whatever hardware the machine running it happens to have, which is not a
    // thing a seam-3 check can assert on. Assigning `facts` replaces the
    // binding — the shell never does, and tools/capture-harness.sh always does.
    property var facts: ({
        wifi: { available: Networking.available,
                on: Networking.wifiEnabled,
                label: Networking.connected ? Networking.label : "" },
        bluetooth: { present: Bluetooth.present,
                     on: Bluetooth.enabled,
                     label: Bluetooth.label },
        dnd: { on: Notifications.dnd },
        nightlight: { available: NightLight.available,
                      on: NightLight.on,
                      temperature: NightLight.temperature },
        keepawake: { on: KeepAwake.on },
        dark: Theme.dark,
        powerprofile: { available: PowerProfiles.available,
                        profile: PowerProfiles.profile },
        vpn: { available: Vpn.available, on: Vpn.on, name: Vpn.name },
        recording: { available: Recorder.canRecord,
                     on: Recorder.active,
                     detail: Recorder.policy.tileDetail(Recorder.active,
                                                        Recorder.elapsedMs,
                                                        Recorder.engine,
                                                        Recorder.canRecord) },
        volume: { available: Audio.hasSink,
                  percent: root.policy.percent(Audio.volume),
                  muted: Audio.muted },
        mic: { available: Audio.hasSource,
               percent: root.policy.percent(Audio.sourceVolume),
               muted: Audio.sourceMuted },
        brightness: { available: Backlight.available, percent: Backlight.percent },
        battery: { hasBattery: Power.hasBattery,
                   label: Power.label,
                   state: Power.state,
                   timeRemaining: Power.timeRemaining }
    })

    readonly property var tiles: root.policy.tiles(root.facts)
    readonly property var tileRows: root.policy.rows(root.tiles)
    readonly property string batteryLine: root.policy.batteryLine(root.facts.battery)

    // --- the slider model, latched (#192) ------------------------------------
    //
    // Everything else here is bound straight off `facts`, and for the grid that
    // is fine. For the sliders it was the bug: `facts` is a new object on every
    // service tick, so `policy.sliders(facts)` was a new array of new rows on
    // every tick, and a JS array with a new identity is a model *reset* — every
    // delegate destroyed and re-created. A re-created ControlSlider starts with
    // a zero-width fill, and its `Behavior` does not run during creation, so
    // the first layout pass afterwards animates the fill from empty to the
    // level. The level therefore "refilled" on every volume key, every
    // brightness step, and — while recording — once a second off the elapsed
    // clock, plus any drag in progress lost its `dragging` flag mid-drag.
    //
    // So the model carries identities only, and is reassigned only when the set
    // of sliders this machine offers actually changes — hardware arriving or
    // going away, or the user reordering them. A level change is then a
    // property update on a live delegate, and the fill tweens from where it
    // was, which is what the `Behavior` was written for.
    /// `null` until the first latch, and a list — possibly an empty one —
    /// after it. The distinction is not decoration: a machine with no sound
    /// card, no microphone and no backlight latches `[]`, and starting this at
    /// `[]` would make that indistinguishable from "not latched yet" and log
    /// nothing at all on the one machine whose empty slider column most wants
    /// explaining.
    property var sliderIds: null

    function refreshSliderIds(): void {
        const next = root.policy.sliderIds(root.facts);
        if (root.sliderIds !== null && root.policy.sameIds(root.sliderIds, next))
            return;
        root.sliderIds = next;
        // The line seam 2 asserts on: drive the volume and this must not
        // repeat. One line per set change is the whole claim of the latch.
        Logger.log("control-centre", "slider set: "
                   + (next.length > 0 ? next.join(", ") : "(none)"));
    }

    onFactsChanged: root.refreshSliderIds()

    // The latch's *other* input, and it is not optional. `sliders()` reads
    // `policy.sliderOrder`, which is #55's setting — bound to
    // `Config.values.controlCenter.sliders`, so the Control Center tab can
    // reorder the sliders or take one out. Before the latch, that arrived on
    // its own because the model was bound straight to `sliders()`; now nothing
    // recomputes unless something asks, and a reorder that waited for the next
    // service tick to appear would be a settings edit that looks ignored.
    Connections {
        target: root.policy
        function onSliderOrderChanged(): void { root.refreshSliderIds(); }
    }

    // --- what a press does ---------------------------------------------------
    //
    // All of it is next door in ControlCenterActions.qml, and none of it is
    // here: a routing table reachable only by clicking a `TapHandler` is one
    // nothing can assert on, and "the eight toggles are functional" is a
    // seam-2 claim about real hardware. Split out, the same functions the tiles
    // call are reachable from `qs ipc call controlcenter press wifi` and so
    // from tools/drawer-harness.sh — one table, two callers.

    // --- the panel -----------------------------------------------------------

    Rectangle {
        id: panel

        anchors {
            top: parent.top
            right: parent.right
            margins: Theme.space4
        }

        readonly property int padding: Theme.space3

        width: root.panelWidth
        // Sized *from* the layout rather than anchored to it, for the reason
        // Surfaces/Drawers/NotificationCenter.qml documents at length: an
        // `anchors.fill` here is a height cycle Qt breaks by zeroing the
        // layout, and the panel then draws as its header alone with everything
        // stacked at x=0.
        //
        // Which layout it is sized from moves with the drill-in: a detail view
        // is a different height from the grid, and a card that stayed the grid's
        // height would draw a network list into the space nine tiles took.
        height: Math.min(root.contentHeight + panel.padding * 2, root.maxPanelHeight)

        // The card resizing is itself an in-place change of a visible surface,
        // so it moves on the same rung the slide does. A `Behavior` and not an
        // explicit animation, unlike everything inside the stack: this property
        // is never assigned during creation — it is a binding that already holds
        // the grid's height by the time any drill-in exists.
        Behavior on height {
            NumberAnimation {
                duration: Theme.duration(Theme.motionFast)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.fogEase
            }
        }

        color: Theme.surface
        radius: Theme.radiusLg
        border.width: Theme.hairline
        border.color: Theme.borderSubtle

        // First child: the card's own controls are hit-tested before it. See
        // Surfaces/Drawers/PressCatcher.qml (#193).
        PressCatcher {}

        // Both views live in here, and only during a transition are both drawn.
        // Clipped, so the one on its way out disappears at the card's padding
        // rather than over the edge of it.
        Item {
            id: stack

            x: panel.padding
            y: panel.padding
            width: panel.width - panel.padding * 2
            height: panel.height - panel.padding * 2
            clip: true

        ColumnLayout {
            id: column

            width: stack.width
            height: stack.height
            spacing: Theme.space3

            // --- the sliders --------------------------------------------------

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space1
                visible: (root.sliderIds ?? []).length > 0

                Repeater {
                    model: root.sliderIds

                    ControlSlider {
                        // The id, not the row: see `sliderIds` above. The row
                        // is a binding of this delegate's own, so a level
                        // change reaches it without the model moving.
                        //
                        // `root.facts` is read here, in the binding, and not
                        // inside a function this calls — #50 measured that a
                        // binding does not reliably pick up a dependency read
                        // one call deep, and a slider that captured nothing
                        // would sit frozen at the level it was built with,
                        // which is this bug wearing the opposite face.
                        required property string modelData
                        readonly property var row:
                            root.policy.sliderRow(modelData, root.facts)

                        Layout.fillWidth: true
                        // A slider whose hardware went away is a delegate on
                        // its way out — the latch drops it in the same turn.
                        // Hidden for that turn rather than drawn as a
                        // placeholder, because a placeholder reads 0%.
                        visible: row.present
                        model: row
                        policy: root.policy

                        onMoved: percent => ControlCenterActions.slide(modelData, percent)
                        onMuteToggled: ControlCenterActions.mute(modelData)
                        onDrillRequested: ControlCenterActions.drill(
                            root.drillPolicy.panelForSlider(modelData))
                    }
                }
            }

            // --- the grid -----------------------------------------------------

            ColumnLayout {
                id: grid

                Layout.fillWidth: true
                spacing: Theme.space2

                Repeater {
                    model: root.tileRows

                    RowLayout {
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: Theme.space2

                        Repeater {
                            model: parent.modelData

                            ControlTile {
                                id: tile

                                required property var modelData

                                Layout.fillWidth: true
                                model: modelData

                                onActivated: ControlCenterActions.press(modelData.id)
                                // The chevron, on the three tiles that are a
                                // switch and a door at once. The wallpaper tile
                                // raises this from its whole body instead, and
                                // `press` routes that one — one path, so a tile
                                // that is only a door still logs the press its
                                // eight neighbours do.
                                onDrillRequested: modelData.doorOnly
                                    ? ControlCenterActions.press(modelData.id)
                                    : ControlCenterActions.drill(modelData.drillIn)

                                // For tools/capture-harness.sh only; see
                                // `litTileItem` above.
                                Component.onCompleted:
                                    if (tile.lit && root.litTileItem === null)
                                        root.litTileItem = tile;
                            }
                        }

                        // A short last row is left-aligned rather than
                        // stretched: three tiles of one width and two of
                        // another is a grid that reads as two grids
                        // (ControlCenterPolicy.qml chunks without padding).
                        // Asked of the *model*, not of `children`: a
                        // `Repeater` is itself a child, so `children.length - 1`
                        // counts three for a two-tile row and the spacer never
                        // appeared — the two tiles stretched to fill, which is
                        // the thing this comment says they must not do.
                        Item {
                            Layout.fillWidth: true
                            visible: modelData.length < root.policy.columns
                        }
                    }
                }
            }

            // --- the bottom strip ---------------------------------------------

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space1
                implicitHeight: 1
                color: Theme.borderSubtle
            }

            // The media card. Absent rather than empty when nothing is playing:
            // a transport with no track is three buttons that do nothing.
            RowLayout {
                Layout.fillWidth: true
                visible: Mpris.showing
                spacing: Theme.space2

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: Mpris.trackTitle || Mpris.label
                        color: Theme.textPrimary
                        elide: Text.ElideRight
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(11.5)
                        font.weight: Theme.weightMedium
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: Mpris.trackArtist
                        color: Theme.textMuted
                        elide: Text.ElideRight
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(10.5)
                    }
                }

                RoundIconButton {
                    glyph: "skip-back"
                    dimmed: !Mpris.canGoBack
                    onPressed: Mpris.previous()
                }

                RoundIconButton {
                    glyph: Mpris.playing ? "pause" : "play"
                    dimmed: !Mpris.canToggle
                    onPressed: Mpris.togglePlaying()
                }

                RoundIconButton {
                    glyph: "skip-forward"
                    dimmed: !Mpris.canSkip
                    onPressed: Mpris.next()
                }
            }

            // The power line and the two doors. One row, because all three are
            // the same kind of thing: what this machine is doing and where to
            // go to change it properly.
            RowLayout {
                id: powerLine

                Layout.fillWidth: true
                spacing: Theme.space2

                Icon {
                    Layout.alignment: Qt.AlignVCenter
                    // Off `facts` rather than off `Power` directly, so a posed
                    // capture gets a posed strip — the glyph is the one part of
                    // this row whose presence changes the layout.
                    visible: root.facts.battery.hasBattery === true
                    name: Power.icon
                    size: 16
                    color: Power.emphasis === "urgent" ? Theme.accentEmber
                         : Power.emphasis === "attention" ? Theme.accentWarm
                         : Theme.textSecondary
                }

                Text {
                    Layout.fillWidth: true
                    text: root.batteryLine
                    color: Theme.textSecondary
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(11)
                }

                // `show` and not `toggle`, which is the whole of what the
                // ticket's "the settings gear dispatches open / showTab (#77) —
                // never show" is protecting: `SurfaceBus.toggle` would *close*
                // a settings window that was already open, so pressing a gear
                // to reach settings would sometimes take them away. `show("")`
                // is what the window's own `open()` IPC calls, so the gear and
                // the keybind land in the same place — on the tab it was left
                // on. Direct rather than over IPC: the window is a singleton in
                // this process.
                RoundIconButton {
                    glyph: "settings"
                    onPressed: {
                        root.closeRequested("settings");
                        SettingsWindow.show("");
                    }
                }

                // The session drawer, which is a *different drawer* — so this
                // closes nothing itself and lets the open replace it, which is
                // #27's cross-drawer transition rather than a close and an open
                // (DrawerSlot.qml runs the overlap).
                RoundIconButton {
                    glyph: "power"
                    onPressed: Drawers.open("session")
                }
            }
        }

            // The detail view, when there is one. A `Loader` and not five
            // always-present panels: a Wi-Fi list nobody has opened is a
            // `Repeater` over a live model and a scanner's worth of bindings,
            // and four of those behind a grid would be the idle cost of a panel
            // that is closed.
            Loader {
                id: drill

                width: stack.width
                height: stack.height
                // Kept alive until the slide out has finished — dropped in the
                // transition's own `ScriptAction`, not on `root.drillPanel`, or
                // the view being animated away would vanish on the first frame
                // of its exit.
                active: false
                opacity: 0

                sourceComponent: root.drillPanel === "wifi" ? wifiPanel
                               : root.drillPanel === "bluetooth" ? bluetoothPanel
                               : root.drillPanel === "audio" ? audioPanel
                               : root.drillPanel === "vpn" ? vpnPanel
                               : root.drillPanel === "wallpaper" ? wallpaperPanel
                               : null
            }
        }
    }

    Component { id: wifiPanel; WifiPanel {} }
    Component { id: bluetoothPanel; BluetoothPanel {} }
    Component { id: audioPanel; AudioPanel {} }
    Component { id: vpnPanel; VpnPanel {} }
    Component { id: wallpaperPanel; WallpaperPanel {} }

    // --- the slide -----------------------------------------------------------
    //
    // One animation for both directions, because they are the same movement:
    // whichever view is arriving comes from the side DrillInPolicy names and
    // whichever is leaving goes to the other, and back is forward with the sign
    // flipped.

    /// Where the card's height comes from — the open detail view, or the grid.
    readonly property int contentHeight: root.drillPanel !== "" && drill.item
                                       ? drill.item.implicitHeight
                                       : column.implicitHeight

    function runTransition(): void {
        const drilled = root.drillPanel !== "";
        const forward = ControlCenterActions.forward;

        const incoming = drilled ? drill : column;
        const outgoing = drilled ? column : drill;

        // The incoming view is placed before it is animated rather than being
        // left where it was: a panel loaded this frame has x 0, and starting its
        // slide from there is a fade with no slide in it.
        incoming.x = root.drillPolicy.offset(forward, true) * stack.width;
        incoming.opacity = 0;
        incoming.visible = true;
        outgoing.visible = true;

        slideIn.target = incoming;
        fadeIn.target = incoming;
        slideOut.target = outgoing;
        fadeOut.target = outgoing;
        slideOut.to = root.drillPolicy.offset(forward, false) * stack.width;

        transition.restart();
    }

    SequentialAnimation {
        id: transition

        ParallelAnimation {
            NumberAnimation {
                id: slideIn
                property: "x"
                to: 0
                duration: Theme.duration(Theme.motionFast)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.fogEase
            }

            NumberAnimation {
                id: fadeIn
                property: "opacity"
                to: 1
                duration: Theme.duration(Theme.motionFast)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.fogEase
            }

            NumberAnimation {
                id: slideOut
                property: "x"
                duration: Theme.duration(Theme.motionFast)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.fogEase
            }

            NumberAnimation {
                id: fadeOut
                property: "opacity"
                to: 0
                duration: Theme.duration(Theme.motionFast)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.fogEase
            }
        }

        ScriptAction {
            script: {
                // The view that left stops existing as far as input is
                // concerned. An `opacity: 0` item still takes presses, which
                // for a grid of nine toggles sitting behind a network list is
                // the worst kind of invisible bug.
                const drilled = root.drillPanel !== "";
                column.visible = !drilled;
                drill.visible = drilled;
                if (!drilled)
                    drill.active = false;
            }
        }
    }

    onDrillPanelChanged: {
        if (root.drillPanel !== "")
            drill.active = true;
        root.runTransition();
    }

    // A drawer dismissed with a detail view open has to close the view too:
    // two of the five hold a radio scanning while they are open, and a scanner
    // nobody released is a wakeup every few seconds that nothing on screen
    // would show (#22 §5).
    Component.onDestruction: ControlCenterActions.back("drawer")

    Component.onCompleted: {
        // A backstop, not the usual path: `facts` evaluating its binding
        // during creation normally fires `onFactsChanged` and fills the model
        // before this runs. `refreshSliderIds` reassigns nothing when the set
        // has not moved, so calling it twice costs a comparison and guarantees
        // the panel never completes with an empty slider column.
        root.refreshSliderIds();
        Logger.log("control-centre",
            root.tiles.length + " tile(s), "
            + (root.sliderIds ?? []).length + " slider(s)");
    }
}
