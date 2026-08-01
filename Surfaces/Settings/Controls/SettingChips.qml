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
import qs.Core

Flow {
    id: root

    required property ConfigBinding binding

    /// Every value that may be selected, in the order they are written.
    required property var choices

    readonly property var selected: Array.isArray(root.binding.value) ? root.binding.value : []

    /// Where it wraps, from the `SettingRow` slot around it (#80). A Flow left
    /// to itself lays out on one line however wide that is, which for a long
    /// allowlist is a line that leaves the window.
    property real availableWidth: root.parent?.availableWidth ?? 0

    readonly property real naturalWidth: {
        let total = 0;
        for (let i = 0; i < root.children.length; i++) {
            const child = root.children[i];
            if (!child.visible || child.implicitWidth <= 0)
                continue;
            total += child.implicitWidth + (total > 0 ? root.spacing : 0);
        }
        return total;
    }

    width: metrics.slotWidth(root.naturalWidth, root.availableWidth)
    spacing: Theme.space1

    RowMetrics { id: metrics }

    function toggle(value: string): void {
        const has = root.selected.indexOf(value) >= 0;
        root.binding.commit(root.choices.filter(
            choice => choice === value ? !has : root.selected.indexOf(choice) >= 0));
    }

    Repeater {
        model: root.choices

        Chip {
            required property string modelData

            label: modelData
            mono: true   // a tool name is a literal passed to the CLI
            selected: root.selected.indexOf(modelData) >= 0
            onTapped: root.toggle(modelData)
        }
    }
}
