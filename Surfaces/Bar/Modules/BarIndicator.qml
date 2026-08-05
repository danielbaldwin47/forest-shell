// One reading on the bar: a glyph, and optionally a number beside it.
//
// Shared by the three modules this ticket adds (#36) — the status cluster, the
// battery and the brightness readout — so they agree about icon size, gap and
// type without three near-identical rows drifting apart. It is not a registry
// entry and never loads as a module; it lives here rather than in `Widgets/`
// because it reads Theme, which everything in `Widgets/` is forbidden to
// (Widgets/README.md: dumb by contract).
//
// An `Item` wrapping a `Row`, rather than a `Row` outright, for one practical
// reason: the interactive modules put a `MouseArea` over the whole indicator,
// and a `MouseArea` that is a direct child of a `Row` is *positioned* by it —
// it takes a slot in the row and its `anchors.fill` fights the positioner.
// Wrapping means a caller can fill this from the outside.
import QtQuick
import qs.Core
import qs.Widgets

Item {
    id: indicator

    /// The Lucide name. An empty name draws nothing rather than a placeholder
    /// box — a module with no glyph to show yet should be invisible, not
    /// broken-looking.
    property string icon: ""

    /// The text beside it, or "" for a glyph on its own — which is what the
    /// status cluster is (#9: "one quiet icon group", no labels).
    property string label: ""

    /// The glyph's colour. This is where an alarm goes: a shape at 3:1 is
    /// legible (WCAG's non-text floor), and the two accents measure 4.92:1
    /// (warm) and 3.45:1 (ember) over the bar's worst-case composite —
    /// measured with tools/capture-harness.sh --contrast, over the brightest
    /// pin wallpaper, unblurred, which is the strict case (#79).
    property color tint: Theme.textSecondary

    /// The number's colour, and deliberately *not* `tint`. Ember is a text
    /// colour that fails the bar's own 4.5:1 rule on that same wallpaper, so
    /// the reading stays in text-secondary (4.93:1) at every level and the
    /// glyph beside it carries the alarm. It is also the more useful split:
    /// the number is the thing you read, and a red number is not more urgent
    /// than a red battery — it is only harder to read.
    property color labelTint: Theme.textSecondary

    /// Whether this belongs on the bar at all — the module contract
    /// Surfaces/Bar/BarContent.qml reads, and the reason a module says `shown`
    /// rather than `visible`. The bar owns the item's visibility: a hidden
    /// module has to take its module gap with it, which only the Loader above
    /// it can do, and a module that hid *itself* would leave a 14px hole where
    /// it is not. (An indicator used inside another module — the four in the
    /// status cluster — is not a module and uses `visible` as usual.)
    property bool shown: true

    visible: indicator.shown

    /// A ceiling on the text, in px, or 0 for "as wide as it needs" — which is
    /// what every reading in #36 wanted, since a percentage has a known width.
    ///
    /// #37 brought the two that do not: a track title and a window title are
    /// both arbitrary text arriving from another application, and an uncapped
    /// one pushes the clock off the centre of the bar (the #80 class of
    /// overflow). Capped, they elide from the right — the front of a title is
    /// the part worth keeping.
    property int labelMaxWidth: 0

    /// Whether the reading can be *changed* from here — the wheel and a click.
    /// Off by default: most of what the bar shows is a readout, and a pointer
    /// that silently does something over one glyph and nothing over the next is
    /// worse than one that never does anything.
    ///
    /// This one flag decides the input *and* the cursor (#185). #184 split them
    /// — the cursor followed a second `opensPanel` flag, on the argument that a
    /// hand means a door and the brightness readout has none — and nine shipped
    /// controls then hovered as a plain arrow, which is the bug #185 was filed
    /// as. The bar draws no hover highlight by decision, so the cursor is the
    /// only affordance there is: it has to mean "this does something", which is
    /// what this flag already gates.
    property bool interactive: false

    /// One notch of the wheel, up (1) or down (-1). The direction and not the
    /// delta: a high-resolution wheel sends many small deltas, and a value that
    /// moved by the raw number would jump.
    signal stepped(int direction)
    signal clicked()

    implicitWidth: row.width
    implicitHeight: row.height

    Row {
        id: row

        spacing: Theme.space1

        Icon {
            name: indicator.icon
            // 16px at a 32px bar: the icon occupies half the bar's height,
            // which is the proportion #10 settled on for the workspace strata.
            size: 16
            color: indicator.tint
            visible: indicator.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: reading

            text: indicator.label
            visible: indicator.label !== ""
            color: indicator.labelTint
            font.family: Theme.fontUi
            font.weight: Theme.weightRegular
            // pointSize, not pixelSize: the scale has half-pixel steps and
            // `font.pixelSize` is an int (#10, measured the hard way).
            font.pointSize: Theme.pt(12.5)
            anchors.verticalCenter: parent.verticalCenter

            // Only bound when there is a ceiling. An unconditional `width`
            // would take the text out of its implicit sizing, and every #36
            // reading would then be laid out in a box rather than sized by
            // its own glyphs.
            width: indicator.labelMaxWidth > 0
                ? Math.min(implicitWidth, indicator.labelMaxWidth) : implicitWidth
            elide: indicator.labelMaxWidth > 0 ? Text.ElideRight : Text.ElideNone
        }
    }

    // One handler for both gestures, here rather than in each module: the two
    // that take a wheel wrote the same four lines and the same comment about
    // `angleDelta`, which is one place too many for a rule about pointers.
    MouseArea {
        anchors.fill: parent
        enabled: indicator.interactive
        visible: indicator.interactive
        acceptedButtons: Qt.LeftButton

        // The pointer the rest of the shell's buttons show (Clock.qml,
        // ControlTile.qml, RoundIconButton.qml — all `PointingHandCursor`), on
        // the handler that is already here rather than a `HoverHandler` beside
        // it: those three have no MouseArea to hang it off and this does.
        //
        // The same flag that enables the handler, so the two cannot drift: a
        // module that becomes interactive later gains the pointer without being
        // edited, and a readout that accepts nothing never grows one. That is
        // the whole of #185 — the nine modules it lists are edited nowhere.
        cursorShape: indicator.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

        onClicked: indicator.clicked()
        // `angleDelta.y` is in eighths of a degree and a notch is 120; only the
        // sign is used, and the module decides what a notch means.
        onWheel: wheel => {
            if (wheel.angleDelta.y !== 0)
                indicator.stepped(wheel.angleDelta.y > 0 ? 1 : -1);
        }
    }
}
