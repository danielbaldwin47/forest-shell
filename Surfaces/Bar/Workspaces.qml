// The ridgeline: workspaces as a range of receding strata (#35, brief §6.3).
//
// Three things meet here and nowhere else — the compositor facade for the row,
// the spec for the falloff, the widget for the shape:
//
//   Services/Compositor → which workspaces exist, and where this screen is
//   RidgelineSpec       → how tall and how hazy each one is
//   Widgets/Strata      → draws `{ length, haze, color }`, knows nothing else
//
// **The active workspace is teal.** The brief's single-lamplight rule names
// both the active workspace and the item needing attention as candidates for
// amber, and they coexist constantly; #35 settled it the other way round from
// the prototype's default — amber is reserved for attention, so the bar at rest
// carries no warm element at all.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Widgets
import qs.Services.Compositor

Item {
    id: root

    /// Bar context, assigned by BarSlot.qml when the module is loaded. Plain
    /// properties rather than required ones because a module is created by a
    /// Loader, which cannot pass initial values for them; neither changes over
    /// a live bar window's lifetime.
    property var screen: null
    property bool vertical: false

    readonly property QtObject spec: RidgelineSpec {}
    readonly property var knobs: root.spec.knobs(Config.values.bar.ridgeline)

    /// The row, live. Re-evaluates on `Compositor.revision`, which moves only
    /// on real compositor events — nothing here polls.
    readonly property var cells: Compositor.workspaceRow(root.screen, root.knobs.slotCount)

    /// The same row with the falloff applied and a colour per stratum. Teal
    /// marks where you are; everything else is ordinary chrome. Distance is
    /// already carried by height and haze, so colour does not encode it too.
    readonly property var strata: root.spec.strata(root.cells, root.knobs).map(cell => ({
        length: cell.length,
        haze: cell.haze,
        color: cell.active ? Theme.accentPrimary : Theme.textSecondary
    }))

    implicitWidth: ridge.implicitWidth
    implicitHeight: ridge.implicitHeight

    Strata {
        id: ridge

        anchors.centerIn: parent
        model: root.strata
        vertical: root.vertical

        unitWidth: root.knobs.unitWidth
        gap: root.knobs.gap
        // Fixed to the tallest a stratum may get, so the row does not resize as
        // focus moves along it.
        extent: root.knobs.activeHeight

        animationMs: Theme.motionStandard
        animationCurve: Theme.fogEase

        onActivated: index => {
            const cell = root.cells[index];
            if (cell)
                Compositor.focusWorkspace(cell.id);
        }
    }
}
