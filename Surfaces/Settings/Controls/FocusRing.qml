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
// Shown for the parent's `activeFocus`, and tab traversal is what sets that —
// the controls activate off a `TapHandler`, which does not take focus. So a
// pointer user does not collect rings behind them, which is the behaviour the
// rest of the desktop has. The one place that overrides `visible` is the tab
// rail, where the keyboard is held by the pane and the ring belongs on the
// selected row.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Rectangle {
    id: ring

    /// Air between the control's edge and the ring. Larger for a control whose
    /// drawn shape is smaller than its item — a slider is a 4px groove in a
    /// 24px box.
    property real inset: 3

    anchors.fill: parent
    anchors.margins: -ring.inset

    visible: ring.parent?.activeFocus ?? false
    color: "transparent"
    border.width: Theme.rail
    border.color: Theme.accentPrimary
    // A parent with no radius of its own — an IconButton, a slider — gets the
    // kit's small radius, so no ring in the window is a hard corner.
    radius: (ring.parent?.radius ?? Theme.radiusSm) + ring.inset
}
