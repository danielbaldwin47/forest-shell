// One of a closed list (#54) — the shell's only enum control.
//
// A segmented row rather than a dropdown, because every closed list in the
// schema is short (three theming modes, three permission modes, five effort
// levels) and a menu hides the alternatives behind a click. When a list arrives
// that is too long for a row, that is the ticket that adds a second control,
// not a reason to make this one generic.
//
// Options may be given outright, or left to fall out of the binding's own knob
// table — `values: ["teal", "amber"]` in the schema is enough for a control.
//
// An option can be present and unavailable: `enabled: false` renders it greyed
// and inert, which is how a theming mode whose service has not landed (#58, #59)
// stays visible in the window it belongs to instead of appearing later from
// nowhere.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core

RowLayout {
    id: root

    required property ConfigBinding binding

    /// `[{ value, label, enabled }]`. `label` defaults to the value, `enabled`
    /// to true. Falls back to the knob table's closed list.
    property var options: (root.binding.spec?.values ?? []).map(value => ({ value: value }))

    spacing: Theme.space1

    Repeater {
        model: root.options

        Chip {
            required property var modelData

            label: modelData.label ?? modelData.value
            selected: root.binding.value === modelData.value
            available: modelData.enabled ?? true
            onTapped: root.binding.commit(modelData.value)
        }
    }
}
