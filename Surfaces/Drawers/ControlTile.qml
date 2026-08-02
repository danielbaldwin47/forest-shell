// One tile of the control centre's grid (#44).
//
// A card that is lit when the thing it speaks for is engaged: the `accentDeep`
// fill under `textPrimary` that Surfaces/Settings/Controls/Chip.qml already
// established for a selected thing (#54). The fill is the whole of the state —
// no pilot light, no switch graphic — because nine of these are on screen at
// once and nine small moving parts is a grid nobody can read at a glance.
//
// What it says is decided in ControlCenterPolicy.qml; what it *does* is a
// callback from the panel, because the services live on the far side of the
// Quickshell line and this file is a picture.
//
// ## Why the icon is above the label and not beside it
//
// It was beside it first, and seam 3 photographed the result: at three tiles to
// a 380px panel a tile is 113px wide, and an icon plus its gap takes 32 of them
// before the text starts. "Do Not Disturb" came back as "Do Not Di…", "Power
// Profile" as "Power Pr…" and the wallpaper tile as "Wal…" — four of the nine
// labels unreadable (tools/capture-harness.sh --surface controlcenter).
//
// That is the #80 class: a row whose text column starves because something
// beside it grew. Stacking gives the text the tile's whole width, and the label
// may take a second line rather than eliding — a tile whose name is cut in half
// is a tile you have to press to identify.
//
// The *detail* line still elides, and must: it is a network's own name, a VPN
// profile or a vendor power profile — arbitrary text from somewhere that is not
// this shell, with no length anybody can promise.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets

Rectangle {
    id: tile

    /// The row ControlCenterPolicy handed over: `{ id, on, icon, label, detail,
    /// drillIn }`.
    required property var model

    /// Pressed. The panel routes it to a service — the tile knows nothing about
    /// what it switches.
    signal activated

    readonly property bool lit: tile.model.on === true

    // Tall enough for the glyph, a two-line label and the detail — a fixed
    // height rather than an implicit one, because nine tiles that each sized
    // themselves would make a grid with three different row heights in it.
    implicitHeight: 84

    radius: Theme.radiusMd
    color: tile.lit ? Theme.accentDeep
                    : (hover.hovered ? Theme.surfaceOverlay : Theme.surfaceRaised)
    border.width: Theme.hairline
    border.color: tile.lit ? Theme.accentDeep : Theme.borderSubtle

    // A fill, so it fades, at the in-place step — nothing but this rectangle
    // moves (Core/EffectsPolicy.qml).
    Behavior on color {
        ColorAnimation {
            duration: Theme.duration(Theme.motionFast)
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.fogEase
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: tile.activated()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.space2
        spacing: 2

        Icon {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 2
            name: tile.model.icon
            size: 20
            // `textPrimary` on the `accentDeep` fill, which is the pairing
            // Surfaces/Settings/Controls/Chip.qml already established for a
            // selected thing (#54) — and the pairing both palette rows are
            // tuned for: the fill inverts with the mode the text does, so this
            // reads in either (Core/Tokens.qml).
            color: tile.lit ? Theme.textPrimary : Theme.textSecondary
        }

        Item { Layout.fillHeight: true }

        // Wraps rather than elides — see the header. Two lines is the ceiling
        // the tile is sized for; a third would push the detail out of the card.
        Text {
            Layout.fillWidth: true
            text: tile.model.label
            color: Theme.textPrimary
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(11)
            font.weight: Theme.weightMedium
        }

        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: tile.model.detail
            // On a lit tile the hierarchy is size and weight rather than
            // colour, and that is forced: `accentDeep` is a *fill*, and both
            // dimmer text roles fall under AA on it — dark `textSecondary`
            // measures 2.6:1 (tests/tst_tokens.qml gates exactly this). So the
            // detail keeps `textPrimary` and separates itself by being a point
            // smaller and a weight lighter.
            color: tile.lit ? Theme.textPrimary : Theme.textMuted
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(10)
        }
    }

    // The door tiles say so, in the corner rather than in the row: the text
    // column is the thing this layout exists to protect, and a chevron beside
    // it would be the #80 shape again in miniature. One glyph, and only on the
    // tile that opens something rather than switching it.
    Icon {
        anchors {
            top: parent.top
            right: parent.right
            margins: Theme.space2
        }
        visible: tile.model.drillIn === true
        name: "chevron-right"
        size: 12
        color: Theme.textMuted
    }
}
