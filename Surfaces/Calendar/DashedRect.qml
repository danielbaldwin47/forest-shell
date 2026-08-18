// A whole dashed rectangle: four `DashedEdge`s around the item it fills.
//
// The dash itself, and why it is two pixels in two colours, is
// `DashedEdge.qml`'s header. What this adds is only the frame — and the reason
// it exists is that the frame was written twice. `WeekView` outlines the extent
// a resize is leaving; `EventChip` hollows itself into the slot a move is
// leaving. Both are the same four edges with the same two colours, and the
// second copy differed only in which hue it read them from, which is exactly
// the kind of duplicate that drifts one corner at a time.
//
// The edges are laid out rather than anchored because each one is `clip: true`
// with a run of rectangles inside it, and an anchor-driven resize would rebuild
// the run twice per frame during a drag — which is the one thing this mark is
// on screen for.
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: frame

    /// The hue the dashes are drawn in, and the pixel underneath each of them.
    /// Named rather than derived: the two callers read them off different
    /// `CalendarTokens` entries.
    property color ink: "transparent"
    property color halo: "transparent"

    /// The thickness of one edge. `DashedEdge` draws 1px of ink and 1px of
    /// halo, so anything other than 2 crops one of the two.
    readonly property int thickness: 2

    DashedEdge {
        x: 0
        y: 0
        width: frame.width
        height: frame.thickness
        ink: frame.ink
        halo: frame.halo
    }

    DashedEdge {
        x: 0
        y: frame.height - frame.thickness
        width: frame.width
        height: frame.thickness
        ink: frame.ink
        halo: frame.halo
    }

    DashedEdge {
        x: 0
        y: 0
        width: frame.thickness
        height: frame.height
        vertical: true
        ink: frame.ink
        halo: frame.halo
    }

    DashedEdge {
        x: frame.width - frame.thickness
        y: 0
        width: frame.thickness
        height: frame.height
        vertical: true
        ink: frame.ink
        halo: frame.halo
    }
}
