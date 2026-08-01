// The workspace indicator: the ridgeline, wired to Hyprland.
//
// Three files meet here and each keeps its own business. The widget
// (Widgets/Ridgeline.qml) knows how a range of hills is drawn and nothing about
// workspaces. The facade (Services/Compositor/) knows what Hyprland is doing
// and nothing about how it looks. Surfaces/Bar/WorkspaceSlots.qml turns a
// compositor that destroys empty workspaces into a row that holds still. This
// module is the twenty lines that join them, and is where the settings and the
// theme roles are read.
//
// The colour is the one decision worth restating: **the active workspace is
// teal.** The brief allows exactly one lamplight-amber element at a time and
// names both the active workspace and the thing needing attention as
// candidates — but there is always an active workspace, so spending the warm
// accent on it means the bar is never at rest and amber never means anything.
// Resolved in #10: amber is reserved for attention, and `amberActive` is the
// escape hatch for anyone who wants the other reading.
import QtQuick
import qs.Core
import qs.Services.Compositor
import qs.Widgets

Ridgeline {
    id: root

    readonly property var settings: Config.values.bar.ridgeline
    readonly property bool reduced: Config.values.appearance.reducedEffects

    cells: slots.row(Compositor.workspaces, root.settings.slots)

    unitWidth: settings.unitWidth
    gap: settings.gap
    activeHeight: settings.activeHeight
    occupiedHeight: settings.occupiedHeight
    emptyHeight: settings.emptyHeight
    falloff: settings.falloff
    minHeight: settings.minHeight
    occupiedHaze: settings.occupiedHaze
    emptyHaze: settings.emptyHaze
    hazeFalloff: settings.hazeFalloff
    minHaze: settings.minHaze

    color: Theme.textSecondary
    activeColor: settings.amberActive ? Theme.accentWarm : Theme.accentPrimary

    // One surface changing in place, so the standard step (#27). Reduced
    // effects collapses it to an opacity-only fade at the fastest step, which
    // is the bottom of the degrade ladder (#22 §7).
    motionMs: reduced ? Theme.motionFast : Theme.motionStandard
    easingCurve: Theme.fogEase
    animateExtent: !reduced

    onCellActivated: id => Compositor.focusWorkspace(id)

    WorkspaceSlots { id: slots }
}
