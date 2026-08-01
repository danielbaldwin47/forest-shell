// A subset of a closed list (#54) — the array counterpart of SettingChoice.
//
// Built for the Ask Claude tool allowlist (#41), which is the only many-of-many
// setting in v1: the list is closed because it is passed to `--tools`, and a
// name the CLI does not know is a silently weaker restriction rather than an
// error, so free text would be the wrong control.
//
// Order is the schema's, not the click order: what is written is the closed list
// filtered by what is selected. Otherwise the file would record the sequence the
// user happened to tap in, and two identical toolsets would diff.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core

Flow {
    id: root

    required property ConfigBinding binding

    /// Every value that may be selected, in the order they are written.
    required property var choices

    readonly property var selected: Array.isArray(root.binding.value) ? root.binding.value : []

    spacing: Theme.space1

    function toggle(value: string): void {
        const has = root.selected.indexOf(value) >= 0;
        root.binding.commit(root.choices.filter(
            choice => choice === value ? !has : root.selected.indexOf(choice) >= 0));
    }

    Repeater {
        model: root.choices

        Rectangle {
            id: chip

            required property string modelData

            readonly property bool on: root.selected.indexOf(chip.modelData) >= 0

            implicitWidth: chipLabel.implicitWidth + Theme.space3 * 2
            implicitHeight: 26
            radius: Theme.radiusSm

            color: chip.on ? Theme.accentDeep
                           : (chipHover.hovered ? Theme.surfaceOverlay : Theme.surfaceRaised)
            border.width: Theme.hairline
            border.color: chip.on ? Theme.accentDeep : Theme.borderSubtle

            Behavior on color {
                ColorAnimation {
                    duration: Theme.motionFast
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.fogEase
                }
            }

            Text {
                id: chipLabel

                anchors.centerIn: parent
                text: chip.modelData
                color: chip.on ? Theme.textPrimary : Theme.textMuted
                font.family: Theme.fontMono
                font.pointSize: Theme.pt(11)
            }

            HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.toggle(chip.modelData) }
        }
    }
}
