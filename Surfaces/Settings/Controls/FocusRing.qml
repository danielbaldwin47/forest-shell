// Where the keyboard is (#77).
//
//     SettingSwitch { ...; FocusRing {} }
//
// One ring for the whole window, drawn outside its control rather than inside
// it, so nothing reflows when focus arrives and a chip's own selected fill is
// never what says "focused". It follows its parent's radius, so it is a pill
// around a switch and a rounded rectangle around a chip without either of them
// stating anything.
//
// Only shown for `activeFocus`, and only tab traversal sets that — the controls
// activate off a `TapHandler`, which does not take focus. So the ring is the
// keyboard's marker and a pointer user never sees one, which is the behaviour
// the rest of the desktop has.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Rectangle {
    id: ring

    /// What the ring is around. The parent, unless a composite control wants
    /// the ring on a different piece of itself than the item that holds focus.
    property Item target: ring.parent

    /// Air between the control's edge and the ring.
    property real inset: metrics.focusInset

    anchors.fill: parent
    anchors.margins: -ring.inset

    visible: ring.target?.activeFocus ?? false
    color: "transparent"
    border.width: Theme.rail
    border.color: Theme.accentPrimary
    // A parent with no radius of its own — an IconButton, the tab rail's row —
    // gets the kit's small radius, so no ring in the window is a hard corner.
    radius: (ring.parent?.radius ?? Theme.radiusSm) + ring.inset

    RowMetrics { id: metrics }
}
