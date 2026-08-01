// A row of receding strata — the shape the ridgeline is made of (#35).
//
//     Strata {
//         model: [{ length: 14, haze: 1.0 }, { length: 9, haze: 0.62 }]
//         color: Theme.accentPrimary
//     }
//
// Height and opacity carry the meaning; this widget carries neither. It is
// handed a list of `{ length, haze }` and draws it, which is what keeps the
// falloff rule (Surfaces/Bar/RidgelineSpec.qml) somewhere it can be tested
// without a screen, and what lets the same shape serve anything else that
// wants a small quantity read as a range.
//
// **Axis-agnostic**, which is the whole reason the geometry is arithmetic
// rather than a Row: with `vertical: true` the strata grow sideways off the
// left edge instead of upward off the bottom, so a vertical bar can land
// post-v1 without this file changing (#35). One delegate, one set of formulas,
// both axes.
//
// Dumb by contract, like everything in Widgets/: no Services, no Config, no
// Theme. Colour and durations arrive from the call site.
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root

    /// One entry per stratum, in visual order: `{ length, haze, color }`.
    /// `length` is along the growing axis, `haze` is opacity, and `color` is
    /// optional — a stratum that does not name one takes the row's.
    property var model: []

    /// Grow sideways instead of upward — the vertical-bar case.
    property bool vertical: false

    /// Thickness of one stratum across the growing axis, and the space between
    /// two of them.
    property int unitWidth: 14
    property int gap: 4

    /// The rounded cap on the growing end. Small on purpose: a full radius
    /// turns strata into pills, which is the idiom this shape exists to avoid.
    property int capRadius: 2

    /// The row's colour, for every stratum that does not name its own.
    /// Defaults to visible rather than correct, so an unbound Strata looks
    /// unfinished instead of invisible.
    property color color: "white"

    /// Cross-axis extent — how tall the tallest stratum is *allowed* to be.
    /// Fixed by the caller so the row does not resize when the active stratum
    /// moves; 0 fits the model as it stands.
    property int extent: 0

    /// Transition for a stratum changing length or haze. 0 disables it: the
    /// budget forbids ambient motion (#22 §5), so this only ever animates a
    /// real event, and a caller that wants none says so.
    property int animationMs: 0
    property var animationCurve: []

    /// A stratum was clicked. By index, not by id — the widget does not know
    /// what a workspace is.
    signal activated(int index)

    readonly property int count: root.model ? root.model.length : 0
    readonly property int run: count > 0 ? count * unitWidth + (count - 1) * gap : 0
    readonly property int cross: {
        if (root.extent > 0)
            return root.extent;
        let longest = 0;
        for (let i = 0; i < root.count; i++)
            longest = Math.max(longest, root.model[i].length || 0);
        return longest;
    }

    implicitWidth: vertical ? cross : run
    implicitHeight: vertical ? run : cross

    Repeater {
        model: root.model

        delegate: Item {
            id: cell

            required property int index
            required property var modelData

            readonly property int offset: cell.index * (root.unitWidth + root.gap)

            x: root.vertical ? 0 : cell.offset
            y: root.vertical ? cell.offset : 0
            width: root.vertical ? root.width : root.unitWidth
            height: root.vertical ? root.unitWidth : root.height

            Rectangle {
                id: stratum

                // Anchored to the far edge, so a stratum grows out of the bar's
                // inner edge rather than out of thin air.
                width: root.vertical ? (cell.modelData.length || 0) : cell.width
                height: root.vertical ? cell.height : (cell.modelData.length || 0)
                y: root.vertical ? 0 : cell.height - height

                color: cell.modelData.color !== undefined ? cell.modelData.color : root.color
                opacity: cell.modelData.haze !== undefined ? cell.modelData.haze : 1.0

                // Rounded only on the growing end: the flat base is what makes
                // the row read as strata seen edge-on rather than as bars.
                topLeftRadius: root.vertical ? 0 : root.capRadius
                topRightRadius: root.capRadius
                bottomRightRadius: root.vertical ? root.capRadius : 0

                Behavior on height {
                    enabled: root.animationMs > 0
                    NumberAnimation {
                        duration: root.animationMs
                        easing.type: root.animationCurve.length > 0 ? Easing.BezierSpline : Easing.InOutQuad
                        easing.bezierCurve: root.animationCurve
                    }
                }
                Behavior on width {
                    enabled: root.animationMs > 0
                    NumberAnimation {
                        duration: root.animationMs
                        easing.type: root.animationCurve.length > 0 ? Easing.BezierSpline : Easing.InOutQuad
                        easing.bezierCurve: root.animationCurve
                    }
                }
                Behavior on opacity {
                    enabled: root.animationMs > 0
                    NumberAnimation {
                        duration: root.animationMs
                        easing.type: root.animationCurve.length > 0 ? Easing.BezierSpline : Easing.InOutQuad
                        easing.bezierCurve: root.animationCurve
                    }
                }
                Behavior on color {
                    enabled: root.animationMs > 0
                    ColorAnimation { duration: root.animationMs }
                }
            }

            // The whole cell is the target, not just the visible stratum: an
            // empty workspace is 3px tall and would otherwise be unclickable.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activated(cell.index)
            }
        }
    }
}
