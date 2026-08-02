// The fog a drawer sits in (#38) — the brief's pale mist over whatever the
// desktop was doing.
//
// Two things and no more: `Theme.fogWash` at `Theme.fogWashOpacity`, which is
// the value the launcher prototype settled (rgba(190,206,209,0.10) over the
// compositor's blur, .wayfinder/prototypes/launcher-clearing/findings.md), and
// the same 64px grain tile the bar uses, because a wash this pale bands on an
// 8-bit panel for exactly the reason the bar's top-light does.
//
// **Opacity is the only thing that animates here**, which is #27's rule for the
// scrim and also the cheap reading: one screen-sized quad changing alpha is the
// whole cost, and #22 §6 budgets 8 ms of GPU frame on a UHD 620. The blur is
// the compositor's, pushed as a layerrule against the window's namespace, and
// it snaps with the window mapping rather than animating — #27 rejected the
// variant that pops blur off and back on mid-swap, and an animated blur radius
// is that same cost every frame.
//
// The grain rides the same opacity as everything else rather than being gated
// on `Theme.drawDecoration`: it is not decoration in the ladder's sense
// (Core/EffectsPolicy.qml) but a fix for a rendering artefact — dropping it
// under reduced effects would make the reduced shell the one with visible
// banding in it.
import QtQuick
import qs.Core

Item {
    id: root

    /// Whether the fog is there. Everything else follows from this.
    property bool shown: false

    /// The step the fog enters on. `Theme.motionSlow` is #27's drawer open —
    /// "the whole screen changes meaning" is the definition of that step, and
    /// this is the surface it was written for.
    property int enterMs: Theme.motionSlow

    opacity: root.shown ? 1 : 0
    // Nothing to composite once it has faded out, and the window above reads
    // this to decide when it may unmap.
    visible: root.opacity > 0

    // No gate. A fade always runs and only its duration changes, which is the
    // rule Core/EffectsPolicy.qml states and the absence of a gate here is it.
    Behavior on opacity {
        NumberAnimation {
            duration: root.shown ? Theme.duration(root.enterMs)
                                 : Theme.exitDuration(root.enterMs)
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.fogEase
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.fogWash
        opacity: Theme.fogWashOpacity
    }

    Image {
        anchors.fill: parent
        opacity: 0.03
        source: Qt.resolvedUrl("../../assets/noise.png")
        fillMode: Image.Tile
    }
}
