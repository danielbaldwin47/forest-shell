// forest-shell — the Widgets/ kit gallery. Dev-only, never loaded by the shell.
//
//   qs -p ~/repos/forest-shell/gallery.qml
//
// A second entry point rather than a file under `tools/`, because Quickshell
// takes the entry point's directory as the config root: only from here do
// `qs.Core` and `qs.Widgets` resolve to the real Theme and the real widgets.
// Everything the gallery shows is the shipping component, not a copy.
//
// It exists because two of #34's acceptance criteria cannot be checked
// headlessly:
//
//   - `MultiEffect` draws *nothing* under `QT_QPA_PLATFORM=offscreen`, with no
//     warning — an offscreen screenshot test would pass with the icons missing.
//   - Fractional scale is a compositor property. Run this on a Hyprland session
//     at scale 1.5 (`monitor = ..., 1.5`) to see what the ticket asks about;
//     the oversample comparison below is the whole reason to do so.
//
// The mode switch writes `appearance.darkMode` through Config — the real path
// the Dark/Light tile will use, not a local bool — so what you see is what the
// shell does. It puts the setting back when the window closes; kill the process
// mid-session and the flip stands, in the user's real settings.json.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Core
import qs.Widgets

ShellRoot {
    id: gallery

    // Restored on exit, so a dev poke at the switch does not silently
    // redecorate the user's shell.
    property bool enteredDark: true
    Component.onCompleted: gallery.enteredDark = Theme.dark
    Component.onDestruction: if (Theme.dark !== gallery.enteredDark) Theme.setDark(gallery.enteredDark)

    // Inline components live on the file's root object.
    component CapsLabel: Text {
        color: Theme.textMuted
        font.family: Theme.fontUi
        font.pointSize: Theme.pt(Theme.capsSize)
        font.weight: Theme.weightMedium
        font.letterSpacing: Theme.tracking(Theme.capsSize, Theme.capsTrackingEm)
    }

    component Note: Text {
        color: Theme.textSecondary
        font.family: Theme.fontMono
        font.pointSize: Theme.pt(11)
        wrapMode: Text.WordWrap
    }

    FloatingWindow {
        id: win

        title: "forest-shell — widget kit"
        implicitWidth: 920
        implicitHeight: 780
        color: Theme.bgBase

        // Icons are name-addressed and the filenames are the names, so there is
        // no manifest to read — a gallery just names what it wants to show.
        readonly property var barIcons: [
            "wifi", "bluetooth", "volume-2", "battery-medium", "cpu", "bell",
            "calendar", "cloud-fog", "mountain-snow", "settings", "search", "power"
        ]

        readonly property var setSample: [
            "a-arrow-up", "activity", "airplay", "alarm-clock", "album", "anchor",
            "aperture", "archive", "armchair", "arrow-down", "at-sign", "atom",
            "award", "axe", "backpack", "badge-check", "banknote", "beaker",
            "bike", "binary", "bird", "blocks", "bone", "book-open", "bookmark",
            "box", "brain", "briefcase", "brush", "bug", "cake", "camera", "car",
            "carrot", "cast", "chart-scatter", "chef-hat", "cherry", "circle-dot",
            "clapperboard", "clock", "cloud-rain", "coffee", "compass", "cookie",
            "crown", "diamond", "dices", "disc", "dna", "dog", "drum", "feather",
            "flame", "flower", "folder", "gamepad-2", "gem", "ghost", "gift",
            "globe", "graduation-cap", "guitar", "hammer", "hand", "heart",
            "hexagon", "house", "images", "key-round", "lamp", "leaf", "library",
            "lightbulb", "map", "medal", "microscope", "moon", "mountain", "music",
            "orbit", "origami", "palette", "paperclip", "pen-tool", "pickaxe",
            "pizza", "plane", "puzzle", "rabbit", "radio", "rocket", "ruler",
            "sailboat", "scissors", "shield", "shovel", "snowflake", "sparkles",
            "sprout", "sun", "sword", "tag", "telescope", "tent", "thermometer",
            "ticket", "trees", "trophy", "umbrella", "vault", "wind", "zap"
        ]

        // Bar-realistic sizes, plus the two larger ones the launcher rows and
        // dashboard cards will want.
        readonly property var sizeRamp: [12, 14, 16, 18, 20, 22, 24, 32, 48]

        readonly property var roleSwatches: [
            { label: "primary", role: Theme.textPrimary },
            { label: "secondary", role: Theme.textSecondary },
            { label: "muted", role: Theme.textMuted },
            { label: "accent", role: Theme.accentPrimary },
            { label: "warm", role: Theme.accentWarm },
            { label: "ember", role: Theme.accentEmber },
            { label: "lichen", role: Theme.accentLichen },
            { label: "stone", role: Theme.accentStone }
        ]

        // The prototype's pinned state — 1, 2, 3 and 5 occupied — so the
        // falloff is visible without opening windows across a live session.
        // Clicking a form moves the peak, which is the only way to see that
        // height and haze animate rather than snap.
        property int ridgeActive: 3
        readonly property var ridgeOccupied: [1, 2, 3, 5]
        readonly property var ridgeCells: {
            const out = [];
            for (let id = 1; id <= 5; id++)
                out.push({
                    id: id,
                    occupied: win.ridgeOccupied.indexOf(id) >= 0,
                    active: id === win.ridgeActive
                });
            return out;
        }

        // A full row and a row that has only just started, which are the two
        // states a sparkline is ever in (#50). Generated rather than typed out,
        // and deterministic, so the gallery draws the same two rows every time.
        readonly property var sparkFull: {
            const out = [];
            for (let i = 0; i < 60; i++)
                out.push(0.45 + 0.35 * Math.sin(i / 6));
            return out;
        }

        readonly property var sparkPartial: {
            const out = [];
            // The first three are the gap: a sample that could not be taken —
            // which is what the CPU row of a freshly opened card holds.
            for (let i = 0; i < 17; i++)
                out.push(i < 3 ? NaN : 0.2 + 0.5 * Math.abs(Math.sin(i / 4)));
            return out;
        }

        readonly property var oversampleCases: [
            { label: "oversample 1.0", value: 1.0 },
            { label: "oversample 3.0 — the default", value: 3.0 }
        ]

        Flickable {
            anchors.fill: parent
            contentHeight: page.implicitHeight + Theme.space6 * 2
            clip: true

            ColumnLayout {
                id: page

                x: Theme.space6
                y: Theme.space6
                width: parent.width - Theme.space6 * 2
                spacing: Theme.space6

                // --- header: the mode switch ---------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space4

                    Text {
                        text: "Widget kit"
                        color: Theme.textPrimary
                        font.family: Theme.fontDisplay
                        font.weight: Theme.weightDisplay
                        font.pointSize: Theme.pt(28)
                    }

                    Item { Layout.fillWidth: true }

                    Note { text: Theme.dark ? "dark" : "light" }

                    // Writes through Config, exactly as the Dark/Light tile
                    // will. Every colour on this page is a Theme binding, so
                    // the whole gallery recolours with nothing reloaded.
                    Rectangle {
                        implicitWidth: modeRow.implicitWidth + Theme.space4 * 2
                        implicitHeight: modeRow.implicitHeight + Theme.space3 * 2
                        radius: Theme.radiusFull
                        color: hover.hovered ? Theme.surfaceOverlay : Theme.surfaceRaised
                        border.width: Theme.hairline
                        border.color: Theme.borderSubtle

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.motionFast
                                easing.type: Easing.Bezier
                                easing.bezierCurve: Theme.fogEase
                            }
                        }

                        RowLayout {
                            id: modeRow

                            anchors.centerIn: parent
                            spacing: Theme.space2

                            Icon {
                                name: Theme.dark ? "sun" : "moon"
                                size: 16
                                color: Theme.accentWarm
                            }

                            Text {
                                text: Theme.dark ? "Switch to light" : "Switch to dark"
                                color: Theme.textPrimary
                                font.family: Theme.fontUi
                                font.weight: Theme.weightText
                                font.pointSize: Theme.pt(13)
                            }
                        }

                        HoverHandler { id: hover }
                        TapHandler { onTapped: Theme.setDark(!Theme.dark) }
                    }
                }

                // --- oversample: the criterion that needs a real display ------
                CapsLabel { text: "OVERSAMPLE — 16PX ICON, MAGNIFIED 6× NEAREST-NEIGHBOUR" }

                Note {
                    Layout.fillWidth: true
                    text: "Left is rasterized at the logical size, right at 3× and downsampled by "
                          + "the GPU. On a 1.5× fractional-scale display the left one is visibly "
                          + "mushy — and Screen.devicePixelRatio reports 2 there, which is why "
                          + "the multiplier is fixed rather than derived from it."
                }

                RowLayout {
                    spacing: Theme.space8

                    Repeater {
                        model: win.oversampleCases

                        ColumnLayout {
                            id: overCell

                            required property var modelData

                            spacing: Theme.space2

                            Item {
                                implicitWidth: 16 * 6
                                implicitHeight: 16 * 6

                                Icon {
                                    name: "wifi"
                                    size: 16
                                    color: Theme.accentPrimary
                                    oversample: overCell.modelData.value

                                    // The layer has to sit on the *scaled*
                                    // item, not on a wrapper drawn 1:1, or
                                    // `smooth` has nothing to apply to. Like
                                    // this the icon is rendered once at 16×16
                                    // and that texture is then drawn 6× with
                                    // nearest-neighbour filtering, so what you
                                    // are judging is the rasterization rather
                                    // than the upscaler. The texture size is
                                    // pinned for the same reason — left to
                                    // itself it would scale with the display.
                                    layer.enabled: true
                                    layer.smooth: false
                                    layer.textureSize: Qt.size(16, 16)

                                    transformOrigin: Item.TopLeft
                                    scale: 6
                                }
                            }

                            CapsLabel { text: overCell.modelData.label.toUpperCase() }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // --- size ramp -------------------------------------------------
                CapsLabel { text: "SIZE RAMP" }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space5

                    Repeater {
                        model: win.sizeRamp

                        ColumnLayout {
                            id: sizeCell

                            required property int modelData

                            spacing: Theme.space2

                            Icon {
                                Layout.alignment: Qt.AlignHCenter | Qt.AlignBottom
                                name: "mountain-snow"
                                size: sizeCell.modelData
                                color: Theme.textPrimary
                            }

                            CapsLabel {
                                Layout.alignment: Qt.AlignHCenter
                                text: sizeCell.modelData + "PX"
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // --- roles ------------------------------------------------------
                CapsLabel { text: "TOKEN ROLES — CONSUMERS ARE MODE-BLIND" }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space5

                    Repeater {
                        model: win.roleSwatches

                        ColumnLayout {
                            id: roleCell

                            required property var modelData

                            spacing: Theme.space2

                            Icon {
                                Layout.alignment: Qt.AlignHCenter
                                name: "leaf"
                                size: 24
                                color: roleCell.modelData.role
                            }

                            CapsLabel {
                                Layout.alignment: Qt.AlignHCenter
                                text: roleCell.modelData.label.toUpperCase()
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // --- a mock bar strip -------------------------------------------
                CapsLabel { text: "AT BAR SIZE — ON SURFACE, ONE LAMPLIT ELEMENT" }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    color: Theme.surface
                    radius: Theme.radiusMd

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space3
                        anchors.rightMargin: Theme.space3
                        spacing: Theme.space4

                        Repeater {
                            model: win.barIcons

                            Icon {
                                required property string modelData
                                required property int index

                                name: modelData
                                size: 16
                                // Brief §6.2: exactly one element carries
                                // lamplight at a time.
                                color: index === 0 ? Theme.accentWarm : Theme.textSecondary
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }

                // --- the ridgeline ------------------------------------------------
                CapsLabel { text: "RIDGELINE — HEIGHT AND HAZE BOTH FALL AWAY FROM THE PEAK" }

                Note {
                    Layout.fillWidth: true
                    text: "Click a form to move the peak. The active workspace is teal on "
                          + "purpose: amber is reserved for attention, so the bar at rest "
                          + "carries no warm element and amber anywhere on it means "
                          + "something wants you."
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    color: Theme.surface
                    radius: Theme.radiusMd

                    Ridgeline {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.space3
                        anchors.verticalCenter: parent.verticalCenter

                        cells: win.ridgeCells
                        color: Theme.textSecondary
                        activeColor: Theme.accentPrimary
                        easingCurve: Theme.fogEase

                        onCellActivated: id => win.ridgeActive = id
                    }
                }

                // --- the sparkline ------------------------------------------------
                CapsLabel { text: "SPARKLINE — A MINUTE OF A FRACTION, NEWEST AT THE RIGHT" }

                Note {
                    Layout.fillWidth: true
                    text: "Fixed slots and a fixed 0–1 scale, so a row that has been "
                          + "filling for ten seconds is ten bars against the right edge "
                          + "rather than ten bars stretched across the whole width. The "
                          + "gap at the left of the second row is a sample that could not "
                          + "be taken — drawn as nothing, never as a zero."
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 76
                    color: Theme.surface
                    radius: Theme.radiusMd

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.space3
                        spacing: Theme.space3

                        Sparkline {
                            Layout.fillWidth: true
                            implicitHeight: 20
                            values: win.sparkFull
                            color: Theme.accentDeep
                        }

                        Sparkline {
                            Layout.fillWidth: true
                            implicitHeight: 20
                            values: win.sparkPartial
                            color: Theme.accentPrimary
                        }
                    }
                }

                // --- a slab of the set -------------------------------------------
                CapsLabel { text: "THE SET — 1756 ICONS, ADDRESSED BY NAME" }

                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.space4

                    Repeater {
                        model: win.setSample

                        Icon {
                            required property string modelData

                            name: modelData
                            size: 20
                            color: Theme.textSecondary
                        }
                    }
                }

                // A name that does not resolve draws a hollow box and warns on
                // stderr, rather than rendering nothing — which reads as a
                // layout bug and gets debugged as one.
                CapsLabel { text: "AN UNRESOLVED NAME" }

                Icon {
                    name: "no-such-icon"
                    size: 24
                    color: Theme.accentEmber
                }

                Item { Layout.preferredHeight: Theme.space6 }
            }
        }
    }
}
