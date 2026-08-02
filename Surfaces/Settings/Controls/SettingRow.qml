// One labelled row in a settings tab (#54).
//
// Label and explanation on the left, the control on the right, and a
// reset-to-default affordance that only appears once the value has moved off
// its default — so a tab at rest is a list of settings rather than a field of
// undo buttons.
//
//     SettingRow {
//         label: "Dark mode"
//         hint: "Light is a seed; v1 ships dark-first."
//         binding: darkBinding
//         SettingSwitch { binding: darkBinding }
//     }
//
// The row takes the same `binding` its control does, purely so it can show
// whether the value is default and offer the reset. It never writes.
//
// Widths are a floor under the text and a ceiling over the control (#80), both
// from `RowMetrics`. Before that the text column was on `Layout.fillWidth` —
// "take what is left over" — and the slot's `implicitWidth` had no maximum, so
// the control was served first however wide it was: the Appearance tab's hint
// wrapped one word per line and its chips were pushed off the right edge of the
// window. A control that will not fit is now the thing that gives, and a control
// that can wrap reads `slot.availableWidth` to know when to.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core

RowLayout {
    id: root

    required property string label

    /// One line of why, not what. Empty for a control that explains itself.
    property string hint: ""

    /// The control's binding, for the reset affordance. Omitted for a row whose
    /// control is not a single value (the module registry, the app rules list),
    /// which resets at the section level instead.
    property ConfigBinding binding: null

    /// Where the control sits. Anything declared inside the row lands here.
    default property alias content: slot.data

    /// What the row spends before either column gets any: the gaps, and the
    /// reset affordance when it is present. Stated here so the ceiling below is
    /// arithmetic on real geometry rather than on a guess — and it follows the
    /// reset in and out, because a row at its default value has one gap and no
    /// icon, and reserving for one that is not there is the same over-claiming
    /// this ticket is about.
    readonly property real chrome: reset.visible
        ? root.spacing * 2 + reset.implicitWidth
        : root.spacing

    Layout.fillWidth: true
    spacing: Theme.space5

    // `enabled` is Item's own, and setting it on a row whose feature has not
    // landed yet does both halves of the job: the control stops taking input,
    // and this greys the row. Greyed and inert beats hidden — the key exists in
    // the file, and the tab is the place that says so.
    opacity: root.enabled ? 1 : Theme.opacityInert

    RowMetrics { id: metrics }

    ColumnLayout {
        Layout.fillWidth: true
        // The floor. Without it a wide control squeezes the hint to the width of
        // its longest word, which is the shape #80 reported.
        Layout.minimumWidth: metrics.textFloor
        spacing: Theme.space1

        Text {
            Layout.fillWidth: true
            text: root.label
            color: Theme.textPrimary
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(13)
            font.weight: Theme.weightText
            elide: Text.ElideRight
        }

        SectionNote {
            visible: root.hint !== ""
            note: root.hint
        }
    }

    // Reset. Present in the layout only when it has something to undo, so rows
    // do not shift sideways as values change — it is the icon's opacity that
    // moves, not the geometry.
    IconButton {
        id: reset

        name: "rotate-ccw"
        size: 14
        opacity: (root.binding?.modified ?? false) ? 1 : 0
        visible: opacity > 0
        onTapped: root.binding?.resetValue()

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.duration(Theme.motionFast)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.fogEase
            }
        }
    }

    Item {
        id: slot

        /// How wide the control in this slot may be. Read by the controls that
        /// can wrap — `SettingChoice`, `SettingChips` — which set their own
        /// width from it; a control that ignores it is one that cannot be
        /// wider than the ceiling anyway.
        ///
        /// Computed from the row's width and nothing inside the slot, which is
        /// what keeps it out of a loop with `implicitWidth` below.
        readonly property real availableWidth: metrics.slotCeiling(root.width, root.chrome)

        Layout.alignment: Qt.AlignVCenter
        // The ceiling. `implicitWidth` alone means "this is my size and I am not
        // a candidate for shrinking", which is the other half of #80.
        Layout.maximumWidth: slot.availableWidth
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }
}
