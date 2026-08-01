// A row of forms whose height and opacity encode state, read as a range of
// hills receding into haze (board brief §6.3, decided in #10).
//
//     Ridgeline {
//         cells: [{ id: 1, occupied: true, active: false }, ...]
//         color: Theme.textSecondary
//         activeColor: Theme.accentPrimary
//     }
//
// The workspace indicator is its first caller and not its definition: it takes
// a list of cells and paints them, and has no idea what a workspace is. What
// makes it read as a ridge rather than as a bar chart is that **both** height
// and opacity fall away with distance from the peak — one encoding twice, so
// the row still reads at a glance in the 14 logical px a 32px bar can spare.
//
// Dumb by contract, like everything in Widgets/: no Services, no Config, no
// Theme. Colours, geometry and motion arrive as properties.
//
// Axis-agnostic (#9: a vertical bar lands post-v1 without rewrites) — the whole
// encoding is in `strata`, which has no axis at all, and `vertical` only picks
// which way the positioner runs and which edge the forms grow from.
import QtQuick

Item {
    id: root

    /// `[{ id, occupied, active }]` — ascending, one entry per form. Ids are
    /// carried through untouched and handed back with `cellActivated`; nothing
    /// here reads them, so they may be any handle the caller likes.
    property var cells: []

    /// Distance is counted in **positions along the row**, not in ids: what
    /// recedes is what is further from the peak on screen. With a contiguous
    /// row — the usual case, and the one #10 measured — the two are the same.
    readonly property var strata: {
        const out = [];
        let peak = -1;
        for (let i = 0; i < root.cells.length; i++)
            if (root.cells[i].active)
                peak = i;

        for (let i = 0; i < root.cells.length; i++) {
            const cell = root.cells[i];
            const active = i === peak;
            // No peak at all (nothing focused yet) leaves every occupied form
            // at its full height rather than picking a winner.
            const steps = peak < 0 ? 1 : Math.max(1, Math.abs(i - peak));

            out.push({
                id: cell.id,
                active: active,
                occupied: cell.occupied === true,
                extent: active
                    ? root.activeHeight
                    : cell.occupied
                        ? Math.max(root.minHeight,
                                   root.occupiedHeight - root.falloff * (steps - 1))
                        : root.emptyHeight,
                haze: active
                    ? 1.0
                    : cell.occupied
                        ? Math.max(root.minHaze,
                                   root.occupiedHaze - root.hazeFalloff * (steps - 1))
                        : root.emptyHaze
            });
        }
        return out;
    }

    // --- geometry ------------------------------------------------------------
    // Defaults are the widget's own, not the shell's: the bar passes the
    // decided values from `bar.ridgeline`. They are chosen to be *visible* so a
    // Ridgeline with nothing bound looks unfinished rather than invisible.
    property int unitWidth: 14
    property int gap: 4
    property int activeHeight: 14
    property int occupiedHeight: 9
    property int emptyHeight: 3
    property int falloff: 2
    property int minHeight: 4
    property real occupiedHaze: 0.62
    property real emptyHaze: 0.22
    property real hazeFalloff: 0.10
    property real minHaze: 0.15

    /// The flat-topped corner rounding that keeps strata reading as strata —
    /// #10 rejected literal triangular peaks partly for losing it.
    property int cornerRadius: 2

    /// Runs top-to-bottom instead of left-to-right, for a vertical bar. Forms
    /// then grow from the right edge inward, the way they grow up from the
    /// bottom edge in a horizontal bar.
    property bool vertical: false

    // --- paint ---------------------------------------------------------------
    property color color: "gray"
    property color activeColor: "white"

    /// Motion for a workspace switch. Nothing here animates unattended — the
    /// idle budget forbids ambient motion outright (#22 §5).
    property int motionMs: 240
    property var easingCurve: []

    /// A `bezierCurve` is only read when the type says Bezier, and an empty one
    /// with the type set is a runtime error — so an unbound Ridgeline animates
    /// on a stock curve rather than not at all.
    readonly property int easingType: easingCurve.length === 6 ? Easing.Bezier : Easing.InOutQuad

    /// Off collapses the ridge to an opacity-only crossfade, which is what
    /// `reducedEffects` asks for at the bottom of its ladder (#22 §7).
    property bool animateExtent: true

    /// A form was clicked. The caller decides what that means.
    signal cellActivated(var id)

    // The across-axis size is the tallest form the settings allow, not the
    // tallest one currently drawn — otherwise the row would resize the bar's
    // layout every time you switched workspace.
    readonly property int extent: Math.max(activeHeight, occupiedHeight, emptyHeight, minHeight)

    implicitWidth: vertical ? extent : grid.implicitWidth
    implicitHeight: vertical ? grid.implicitHeight : extent

    Grid {
        id: grid

        anchors.centerIn: parent
        spacing: root.gap
        rows: root.vertical ? root.strata.length : 1
        columns: root.vertical ? 1 : root.strata.length

        Repeater {
            model: root.strata

            delegate: Item {
                id: cell

                required property var modelData

                width: root.vertical ? root.extent : root.unitWidth
                height: root.vertical ? root.unitWidth : root.extent

                Rectangle {
                    // Grows from the edge the bar itself sits on, so the flat
                    // tops line up into a skyline.
                    anchors.bottom: root.vertical ? undefined : parent.bottom
                    anchors.right: root.vertical ? parent.right : undefined
                    anchors.horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                    anchors.verticalCenter: root.vertical ? parent.verticalCenter : undefined

                    width: root.vertical ? cell.modelData.extent : root.unitWidth
                    height: root.vertical ? root.unitWidth : cell.modelData.extent

                    color: cell.modelData.active ? root.activeColor : root.color
                    opacity: cell.modelData.haze

                    topLeftRadius: root.cornerRadius
                    topRightRadius: root.vertical ? 0 : root.cornerRadius
                    bottomLeftRadius: root.vertical ? root.cornerRadius : 0

                    Behavior on width {
                        enabled: root.vertical && root.animateExtent
                        NumberAnimation {
                            duration: root.motionMs
                            easing.type: root.easingType
                            easing.bezierCurve: root.easingCurve
                        }
                    }
                    Behavior on height {
                        enabled: !root.vertical && root.animateExtent
                        NumberAnimation {
                            duration: root.motionMs
                            easing.type: root.easingType
                            easing.bezierCurve: root.easingCurve
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.motionMs
                            easing.type: root.easingType
                            easing.bezierCurve: root.easingCurve
                        }
                    }
                    Behavior on color {
                        ColorAnimation { duration: root.motionMs }
                    }
                }

                // The whole cell is the target, not the drawn form: an empty
                // workspace is 3px tall and would be unclickable otherwise.
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.cellActivated(cell.modelData.id) }
            }
        }
    }
}
