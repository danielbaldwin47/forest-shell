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
// ## Motion
//
// The drawer's own — DrawerSlot.qml runs the 320 ms entrance, the 240 ms exit
// and #27's cross-drawer overlap, and the transform origin is set to this
// panel's corner so the entrance grows out of the bar button. Nothing here
// animates on open; the tiles and the sliders animate only in place.
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
import qs.Surfaces.Settings

FocusScope {
    id: root

    /// Raised when the centre wants the drawer gone. The session button raises
    /// it too — that press opens another drawer, and two drawers open at once
    /// is the state Surfaces/Drawers/DrawerPolicy.qml makes unrepresentable.
    signal closeRequested(string reason)

    readonly property ControlCenterPolicy policy: ControlCenterPolicy {}

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
    readonly property var sliderRows: root.policy.sliders(root.facts)
    readonly property string batteryLine: root.policy.batteryLine(root.facts.battery)

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
        height: Math.min(column.implicitHeight + panel.padding * 2, root.maxPanelHeight)

        color: Theme.surface
        radius: Theme.radiusLg
        border.width: Theme.hairline
        border.color: Theme.borderSubtle

        ColumnLayout {
            id: column

            x: panel.padding
            y: panel.padding
            width: panel.width - panel.padding * 2
            height: panel.height - panel.padding * 2
            spacing: Theme.space3

            // --- the sliders --------------------------------------------------

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space1
                visible: root.sliderRows.length > 0

                Repeater {
                    model: root.sliderRows

                    ControlSlider {
                        required property var modelData

                        Layout.fillWidth: true
                        model: modelData
                        policy: root.policy

                        onMoved: percent => ControlCenterActions.slide(modelData.id, percent)
                        onMuteToggled: ControlCenterActions.mute(modelData.id)
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

                IconButton {
                    glyph: "skip-back"
                    dimmed: !Mpris.canGoBack
                    onPressed: Mpris.previous()
                }

                IconButton {
                    glyph: Mpris.playing ? "pause" : "play"
                    dimmed: !Mpris.canToggle
                    onPressed: Mpris.togglePlaying()
                }

                IconButton {
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
                IconButton {
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
                IconButton {
                    glyph: "power"
                    onPressed: Drawers.open("session")
                }
            }
        }
    }

    // A small round icon button, three of them in the media card and two in the
    // power line. Local rather than in Widgets/: it is this panel's strip
    // furniture, and the shell's other icon-buttons (the bar's modules, the
    // notification centre's dismiss) are each shaped by their own surface.
    component IconButton: Item {
        id: button

        required property string glyph
        property bool dimmed: false

        signal pressed

        implicitWidth: 28
        implicitHeight: 28

        HoverHandler {
            id: buttonHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: button.pressed()
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: buttonHover.hovered ? Theme.surfaceOverlay : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: Theme.duration(Theme.motionFast)
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.fogEase
                }
            }
        }

        Icon {
            anchors.centerIn: parent
            name: button.glyph
            size: 16
            // Dimmed rather than hidden: a player that will not skip is worth
            // showing as a player that will not skip.
            color: button.dimmed ? Theme.textMuted
                 : buttonHover.hovered ? Theme.accentPrimary : Theme.textSecondary
        }
    }

    Component.onCompleted: Logger.log("control-centre",
        root.tiles.length + " tile(s), " + root.sliderRows.length + " slider(s)")
}
