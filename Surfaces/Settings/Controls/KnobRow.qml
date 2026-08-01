// One knob of a theme-flagged group, rendered from what the schema says it is
// (#54).
//
//     KnobRow { path: "bar.surface"; knob: "opacity" }
//
// The label, the range and the closed list all come from the group's knob table
// (Core/SettingsSchema.qml `group()`), which is also what the coercer is built
// from — so a control cannot offer a value the file would then clamp, and a
// range cannot drift away from the slider that sets it.
//
// This is why the Bar tab is a `Repeater` over a knob table rather than thirty
// hand-written rows: the bar's surface and ridgeline resolved as *settings, not
// constants* (#10), which is a lot of knobs, and every one of them is one of
// three shapes.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

SettingRow {
    id: root

    required property string path
    required property string knob

    /// Overrides the schema's label for the odd knob that needs more words in
    /// the GUI than in the file.
    property string title: ""

    property string note: ""

    label: root.title !== "" ? root.title : (binding.spec?.label ?? root.knob)
    hint: root.note
    binding: knobBinding

    ConfigBinding {
        id: knobBinding
        path: root.path
        knob: root.knob
    }

    // One of three, decided by what the knob declares — the same three cases
    // `SettingsSchema.coercerFor` derives its coercer from.
    Loader {
        sourceComponent: {
            if ((knobBinding.spec?.values ?? null) !== null)
                return choiceControl;
            if (knobBinding.spec?.min !== undefined || knobBinding.spec?.max !== undefined)
                return sliderControl;
            return switchControl;
        }
    }

    Component {
        id: choiceControl
        SettingChoice { binding: knobBinding }
    }

    Component {
        id: sliderControl
        SettingSlider { binding: knobBinding }
    }

    Component {
        id: switchControl
        SettingSwitch { binding: knobBinding }
    }
}
