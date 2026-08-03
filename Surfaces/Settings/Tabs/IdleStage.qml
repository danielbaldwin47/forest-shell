// One rung of the idle ladder, on the System tab (#55, for #48, #30).
//
// Four stages with the same three keys — a switch and a pair of timeouts in
// minutes — and each with an extra or two of its own, which arrive through the
// default slot. This lives in `Tabs/` and not `Controls/` because it is one
// tab's editor for one key group rather than a form control anything else could
// hold; a second caller is what would move it up.
//
// ## Why the minutes are typed rather than dragged
//
// The range is 0–600 and the default dim is 2.5, so a slider over it would step
// in hundredths across ten hours: a control that can express every value and
// land on almost none of them. A field also makes the two meanings of *off*
// distinguishable, which is the whole shape of this ladder — `0` is "not on
// this power source" and the switch above is "not at all" (#30). Typing a zero
// is the deliberate act that deserves to be.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Surfaces.Settings.Controls

ColumnLayout {
    id: root

    /// `dim`, `lock`, `dpms` or `suspend`.
    required property string stage

    required property string title

    property string hint: ""

    /// The stage's own extra rows, drawn under its two timeouts.
    default property alias extras: extraSlot.data

    readonly property bool on: enabledBinding.value === true

    Layout.fillWidth: true
    spacing: Theme.space5

    ConfigBinding {
        id: enabledBinding
        path: "system.idle." + root.stage + ".enabled"
    }

    SettingRow {
        label: root.title
        hint: root.hint
        binding: enabledBinding

        SettingSwitch { binding: enabledBinding }
    }

    Repeater {
        model: [
            { key: "battery", label: "On battery" },
            { key: "ac", label: "On mains" }
        ]

        SettingRow {
            id: timeoutRow

            required property var modelData

            label: timeoutRow.modelData.label
            hint: "Minutes of idle before this stage fires. 0 is off on this power source."
            enabled: root.on
            binding: timeoutBinding

            ConfigBinding {
                id: timeoutBinding
                path: "system.idle." + root.stage + "." + timeoutRow.modelData.key
            }

            SettingText {
                binding: timeoutBinding
                placeholder: "0"
                // The coercer clamps to 0–600 and falls back to the default on
                // anything unreadable, so what this refuses is the value that
                // would silently become something else.
                validate: text => {
                    const value = Number(text);
                    return text.trim() !== "" && isFinite(value) && value >= 0 && value <= 600;
                }
                submit: text => timeoutBinding.commit(Number(text))
            }
        }
    }

    ColumnLayout {
        id: extraSlot

        // Hidden when empty rather than left at zero height: a layout skips an
        // invisible item entirely, and an empty one still collects the spacing
        // on both sides of it — which reads as a stage with a gap under it and
        // makes two of the four rungs look like they belong to the next.
        visible: extraSlot.children.length > 0

        Layout.fillWidth: true
        spacing: Theme.space5
    }
}
