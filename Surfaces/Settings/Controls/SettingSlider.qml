// A numeric setting on a track (#54).
//
// Range and step come from the binding's knob table when there is one — the
// schema declares `{ def: 0.86, min: 0.65, max: 1 }` once and both the coercer
// and this control read it, so the slider cannot offer a value the file would
// then clamp. A plain leaf has no such table and states its range here.
//
// Every drag step writes. That is deliberate and cheap: `Config.set` dispatches
// live so the shell recolours under the cursor, and the *file* write is
// debounced by the config engine, so a drag is one atomic write however many
// steps it took.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Item {
    id: root

    required property ConfigBinding binding

    /// Range and step. Defaulted from the knob table when the binding has one.
    property real from: root.binding.spec?.min ?? 0
    property real to: root.binding.spec?.max ?? 1
    property real stepSize: root.integers ? 1 : 0.01

    /// Whole numbers, taken from the shipped default: a knob whose default is
    /// `14` is not one anybody wants at `14.3`.
    readonly property bool integers: Number.isInteger(root.binding.defaultValue)

    readonly property real current: {
        const value = root.binding.value;
        return typeof value === "number" ? value : root.from;
    }

    readonly property real fraction: root.to > root.from
        ? Math.max(0, Math.min(1, (root.current - root.from) / (root.to - root.from)))
        : 0

    implicitWidth: 200
    implicitHeight: 24

    function commitAt(x: real): void {
        const span = groove.width - handle.width;
        if (span <= 0)
            return;

        const raw = root.from + Math.max(0, Math.min(1, (x - handle.width / 2) / span))
            * (root.to - root.from);
        const stepped = Math.round(raw / root.stepSize) * root.stepSize;
        // Rounded off the step before writing: floating-point drag arithmetic
        // otherwise puts `0.8600000000000001` in a file meant to be read.
        root.binding.commit(root.integers ? Math.round(stepped)
                                          : Math.round(stepped * 1000) / 1000);
    }

    Rectangle {
        id: groove

        anchors.left: parent.left
        anchors.right: valueLabel.left
        anchors.rightMargin: Theme.space3
        anchors.verticalCenter: parent.verticalCenter
        height: 4
        radius: Theme.radiusFull
        color: Theme.bgSunken

        Rectangle {
            width: handle.x + handle.width / 2
            height: parent.height
            radius: parent.radius
            color: Theme.accentDeep
        }

        Rectangle {
            id: handle

            width: 14
            height: 14
            radius: Theme.radiusFull
            anchors.verticalCenter: parent.verticalCenter
            x: (groove.width - width) * root.fraction
            color: drag.active || hover.hovered ? Theme.accentPrimary : Theme.textSecondary

            Behavior on color {
                ColorAnimation {
                    duration: Theme.motionFast
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.fogEase
                }
            }
        }

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

        // Tap anywhere on the groove jumps there; drag tracks. Both go through
        // the same commit, so there is one place the value is computed.
        TapHandler { onTapped: point => root.commitAt(point.position.x) }

        DragHandler {
            id: drag
            target: null
            onCentroidChanged: if (active) root.commitAt(centroid.position.x)
        }
    }

    Text {
        id: valueLabel

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        width: 44
        text: root.integers ? String(Math.round(root.current)) : root.current.toFixed(2)
        color: Theme.textSecondary
        font.family: Theme.fontMono
        font.pointSize: Theme.pt(11.5)
    }
}
