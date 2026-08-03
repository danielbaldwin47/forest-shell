// Bar — geometry, surface, ridgeline, module registry (#54, for #35).
//
// This tab exists in the shape it does because of a decision, not a preference:
// #10 prototyped the bar with every parameter on a live slider and resolved
// that **all of it is settings, not constants** — flush vs floating, height,
// padding, the whole surface treatment and the whole ridgeline block, including
// whether the active workspace is teal or amber. The defaults here are the ones
// that prototype landed on, and they are defaults rather than the answer.
//
// The two styling blocks are rendered from the schema's knob tables rather than
// written out row by row (Controls/KnobRow.qml): every range in this tab is
// declared once, next to the coercer that enforces it.
//
// The bar itself does not exist yet (#35). Nothing here is inert for that
// reason — the keys are real, the file is real, and #35 reads them — but there
// is no live preview, which is what the note at the top says.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Surfaces.Settings.Controls

TabPage {
    id: page

    title: "Bar"
    section: "bar"
    blurb: "The strip along the top of the screen. Every value below was a live slider "
           + "in the prototype these defaults came from."

    FieldPolicy { id: fields }

    SectionHeader { text: "Geometry" }

    SettingRow {
        label: "Floating"
        hint: "Off is a flush full-width band. Flushness turned out to be a property of "
              + "the wallpaper rather than of the bar, and the opaque band is the failure "
              + "mode worth designing for."
        binding: floatingBinding

        ConfigBinding { id: floatingBinding; path: "bar.floating" }

        SettingSwitch { binding: floatingBinding }
    }

    SettingRow {
        label: "Height"
        hint: "32 logical px is where the content sits with air around it and the bar "
              + "still reads as a strip rather than a panel."
        binding: heightBinding

        ConfigBinding { id: heightBinding; path: "bar.height" }

        SettingSlider { binding: heightBinding; from: 24; to: 48 }
    }

    SettingRow {
        label: "Inner padding"
        binding: paddingBinding

        ConfigBinding { id: paddingBinding; path: "bar.padding" }

        SettingSlider { binding: paddingBinding; from: 0; to: 32 }
    }

    SettingRow {
        label: "Module gap"
        binding: gapBinding

        ConfigBinding { id: gapBinding; path: "bar.moduleGap" }

        SettingSlider { binding: gapBinding; from: 0; to: 32 }
    }

    SectionHeader { text: "Surface" }

    SectionNote {
        // #94: the sentence that used to be here quoted 7.12:1 at 0.86 and
        // 4.44:1 at 0.60 — figures for the fill against nothing, which told the
        // user their bar was readable at settings where it is not.
        //
        // Every number below is a line of `tools/measure-strip-floor.py
        // ~/Pictures/wallpaper` over the 171 wallpapers on this machine: 4.73
        // and 2.72 from "what a fixed setting leaves on the worst wallpaper
        // here", 0.84 from p100 of the opacity each one needs. #94 asks that the
        // copy be reproducible from a documented command, so the copy quotes
        // what that command prints rather than a capture of one wallpaper —
        // `capture-harness.sh --surface bar --contrast` puts italy.png at 4.85:1
        // and 2.82:1, which is the same claim about a kinder image.
        note: "Fill opacity is taste, not legibility. Over the least forgiving wallpaper "
              + "here, secondary text on the bar measures 4.73:1 at 0.86 and 2.72:1 at "
              + "0.65, so the slider on its own cannot keep the bar readable — the lowest "
              + "setting that would is 0.84. Instead the bar reads the strip of wallpaper "
              + "behind it and paints more solid than you asked only where it has to, to "
              + "hold the design system's 4.5:1 floor. Over a dark wallpaper you get "
              + "exactly what you set."
    }

    Repeater {
        model: page.surfaceKnobs

        KnobRow {
            required property string modelData

            path: "bar.surface"
            knob: modelData
        }
    }

    SectionHeader { text: "Ridgeline" }

    SectionNote {
        note: "Workspaces as receding strata: height and haze both fall away with distance "
              + "from the active one, and that double encoding is what reads as a range "
              + "instead of a progress bar. Unit width decides it — much wider and the "
              + "units read as buttons."
    }

    Repeater {
        model: page.ridgelineKnobs

        KnobRow {
            required property string modelData

            path: "bar.ridgeline"
            knob: modelData
        }
    }

    SectionHeader { text: "Modules" }

    SectionNote {
        note: "Three ordered clusters. A module is on when it is in one of them, so "
              + "removing it here parks it in the pool rather than losing it. `status` is "
              + "one module and not four — network, bluetooth, volume and mic are a single "
              + "quiet icon group."
    }

    OrderedList { path: "bar.modules.left"; label: "Left"; pool: page.pool }
    OrderedList { path: "bar.modules.center"; label: "Centre"; pool: page.pool }
    OrderedList { path: "bar.modules.right"; label: "Right"; pool: page.pool }

    // --- what the schema says ------------------------------------------------

    readonly property var surfaceKnobs: Object.keys(Config.schema.spec.bar.surface.knobs)
    readonly property var ridgelineKnobs: Object.keys(Config.schema.spec.bar.ridgeline.knobs)

    /// Every module the registry knows that is currently in no cluster. Depends
    /// on `Config.values`, so dropping a module into a cluster takes it out of
    /// every pool at once.
    readonly property var pool: {
        const modules = Config.values.bar.modules;
        return fields.pool(Config.schema.barModules,
                           [].concat(modules.left, modules.center, modules.right));
    }
}
