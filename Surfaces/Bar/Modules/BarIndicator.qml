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

    /// Whether the reading can be *changed* from here — the wheel and a click.
    /// Off by default: most of what the bar shows is a readout, and a pointer
    /// that silently does something over one glyph and nothing over the next is
    /// worse than one that never does anything.
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
            text: indicator.label
            visible: indicator.label !== ""
            color: indicator.labelTint
            font.family: Theme.fontUi
            font.weight: Theme.weightRegular
            // pointSize, not pixelSize: the scale has half-pixel steps and
            // `font.pixelSize` is an int (#10, measured the hard way).
            font.pointSize: Theme.pt(12.5)
            anchors.verticalCenter: parent.verticalCenter
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

        onClicked: indicator.clicked()
        // `angleDelta.y` is in eighths of a degree and a notch is 120; only the
        // sign is used, and the module decides what a notch means.
        onWheel: wheel => {
            if (wheel.angleDelta.y !== 0)
                indicator.stepped(wheel.angleDelta.y > 0 ? 1 : -1);
        }
    }
}
