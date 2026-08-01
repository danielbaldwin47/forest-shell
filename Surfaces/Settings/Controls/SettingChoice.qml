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
//
// A `Flow` and not a `RowLayout` (#80): how many options there are is set by the
// tab, and how much room there is is set by the window, so the two do not agree
// and one of them has to give. Wrapping onto a second line is the answer that
// keeps every option on screen — as a row, three theming chips were wider than
// the content pane and the ones that did not fit were simply outside the window.
// `width` is what makes it wrap, and it comes from the row's slot; left to
// itself a Flow lays out in one line however wide that is.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Flow {
    id: root

    required property ConfigBinding binding

    /// `[{ value, label, enabled }]`. `label` defaults to the value, `enabled`
    /// to true. Falls back to the knob table's closed list.
    property var options: (root.binding.spec?.values ?? []).map(value => ({ value: value }))

    /// The widest this control may be before it wraps, from the `SettingRow`
    /// slot it sits in. Zero — no row around it — means no constraint.
    property real availableWidth: root.parent?.availableWidth ?? 0

    /// What the chips would measure on one line.
    readonly property real naturalWidth: metrics.naturalWidth(root)

    /// Which option is selected, and which may be. Both are what the arrow keys
    /// walk (#77) — an inert option is stepped over, not landed on.
    readonly property int currentIndex:
        root.options.findIndex(option => option.value === root.binding.value)
    readonly property var allowed: root.options.map(option => option.enabled ?? true)

    width: metrics.slotWidth(root.naturalWidth, root.availableWidth)
    spacing: Theme.space1

    /// Selects an option and takes the keyboard with it, so the ring is on what
    /// was just chosen.
    function choose(index: int): void {
        root.binding.commit(root.options[index].value);
        chips.itemAt(index)?.forceActiveFocus(Qt.TabFocusReason);
    }

    // Arrow keys arrive here from the focused chip, which does not handle them:
    // moving through a closed list is the list's decision, not a chip's.
    Keys.onPressed: event => {
        const delta = keys.step(event.key);
        if (delta === 0)
            return;

        const next = root.currentIndex < 0 ? keys.firstAllowed(root.allowed)
                                           : keys.advance(root.currentIndex, delta, root.allowed);
        if (next >= 0 && next !== root.currentIndex)
            root.choose(next);
        event.accepted = true;
    }

    KeyPolicy { id: keys }
    RowMetrics { id: metrics }

    Repeater {
        id: chips

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
