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
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets

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

    Layout.fillWidth: true
    spacing: Theme.space5

    // `enabled` is Item's own, and setting it on a row whose feature has not
    // landed yet does both halves of the job: the control stops taking input,
    // and this greys the row. Greyed and inert beats hidden — the key exists in
    // the file, and the tab is the place that says so.
    opacity: root.enabled ? 1 : 0.45

    ColumnLayout {
        Layout.fillWidth: true
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

        Text {
            Layout.fillWidth: true
            visible: root.hint !== ""
            text: root.hint
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(11.5)
            lineHeight: Theme.lineHeightBody
            lineHeightMode: Text.ProportionalHeight
            wrapMode: Text.WordWrap
        }
    }

    // Reset. Present in the layout only when it has something to undo, so rows
    // do not shift sideways as values change — it is the icon's opacity that
    // moves, not the geometry.
    Item {
        implicitWidth: 20
        implicitHeight: 20
        opacity: (root.binding?.modified ?? false) ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.motionFast
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.fogEase
            }
        }

        Icon {
            anchors.centerIn: parent
            name: "rotate-ccw"
            size: 14
            color: resetHover.hovered ? Theme.accentPrimary : Theme.textMuted
        }

        HoverHandler { id: resetHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.binding?.resetValue() }
    }

    Item {
        id: slot

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }
}
