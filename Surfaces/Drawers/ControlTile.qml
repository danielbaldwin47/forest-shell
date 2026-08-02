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

    /// The chevron was pressed, or the whole tile was on a tile that is only a
    /// door (#45). The panel routes it to the drill-in — the tile knows nothing
    /// about what is behind it either.
    signal drillRequested

    /// Whether this tile has a detail view behind it, and whether the door is
    /// the whole card. Both off the model, which got them from DrillInPolicy —
    /// a tile that decided for itself which panel it opens would be a second
    /// copy of the map the navigation already holds.
    readonly property bool hasDoor: (tile.model.drillIn ?? "") !== ""
    readonly property bool doorOnly: tile.model.doorOnly === true

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
        // A tile that is only a door has no switch for a body press to mean, so
        // the whole card opens the panel. The other three doors keep the switch
        // on the body and put the door in the corner — pressing Wi-Fi to turn
        // Wi-Fi off is the press people already know, and moving it behind a
        // chevron to make room for a list would be the list costing the toggle.
        onTapped: tile.doorOnly ? tile.drillRequested() : tile.activated()
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
    // it would be the #80 shape again in miniature.
    //
    // On a tile that is *also* a switch it is a second hit target inside the
    // first, which is why it is an `Item` with its own handlers rather than a
    // bare glyph: the body's `TapHandler` would otherwise take the press and the
    // chevron would be decoration. 24px of target around a 12px glyph, because
    // the corner of a 113px tile is a place people miss.
    Item {
        id: door

        anchors {
            top: parent.top
            right: parent.right
            margins: Theme.space1
        }
        implicitWidth: 24
        implicitHeight: 24
        visible: tile.hasDoor && !tile.doorOnly

        HoverHandler {
            id: doorHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: tile.drillRequested()
        }

        Icon {
            anchors.centerIn: parent
            name: "chevron-right"
            size: 12
            color: doorHover.hovered ? Theme.accentPrimary
                 : tile.lit ? Theme.textPrimary
                            : Theme.textMuted
        }
    }

    // The door-only tile keeps the plain glyph: there is nothing to aim at,
    // because the whole card is the target.
    Icon {
        anchors {
            top: parent.top
            right: parent.right
            margins: Theme.space2
        }
        visible: tile.doorOnly
        name: "chevron-right"
        size: 12
        color: Theme.textMuted
    }
}
