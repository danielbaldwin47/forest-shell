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
// written out row by row (Controls/KnobRow.qml): a knob's range is declared
// once, next to the coercer that enforces it.
//
// The plain leaves cannot do that — a leaf's bounds live inside the closure
// `Coerce.integer` returns and nothing can read them back — so their slider
// tracks are declared in BarTabPolicy.qml, which is where a test can hold them
// against the coercer. That file also says which leaves this tab covers, which
// is #72's other half: the section had five keys with no control at all after
// the #35/#54 merge, and nothing failed.
//
// There is still no live preview of the bar in this window. The keys are real
// and Surfaces/Bar reads them; what the tab has of the bar is BarRegistry,
// borrowed to say which module ids this build can actually draw.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Surfaces.Bar
import qs.Surfaces.Settings.Controls

TabPage {
    id: page

    title: "Bar"
    section: "bar"
    blurb: "The strip along the edge of the screen. Every value below was a live slider "
           + "in the prototype these defaults came from."

    FieldPolicy { id: fields }

    // Every slider track below comes from here, and the same file lists what
    // this tab claims to edit — both held against the schema by
    // tests/tst_bartabpolicy.qml, which is the only seam that can see a plain
    // leaf's bounds (#72).
    BarTabPolicy { id: policy }

    // The bar's own module table, used for nothing but greying: the vocabulary
    // the pool offers is the schema's and runs ahead of what this build can
    // draw, and the difference between the two is a fact only the registry has.
    // Held the way the Dashboard tab holds its own registry — a typed readonly
    // property, so it is a stated dependency rather than a child of the page.
    readonly property BarRegistry registry: BarRegistry {}

    SectionHeader { text: "Geometry" }

    SettingRow {
        label: "Position"
        hint: "Top is the v1 bar. Left and right are not offered rather than accepted and "
              + "ignored — the widgets are built axis-agnostic, but a vertical bar is not "
              + "something the shell can lay out yet."
        binding: positionBinding

        ConfigBinding { id: positionBinding; path: "bar.position" }

        SettingChoice {
            binding: positionBinding
            options: fields.options(Config.schema.barPositions,
                                    { top: "Top", bottom: "Bottom" })
        }
    }

    SettingRow {
        label: "Height"
        hint: "32 logical px is where the content sits with air around it and the bar "
              + "still reads as a strip rather than a panel."
        binding: heightBinding

        ConfigBinding { id: heightBinding; path: "bar.height" }

        SettingSlider {
            binding: heightBinding
            from: policy.from("bar.height")
            to: policy.to("bar.height")
        }
    }

    SettingRow {
        label: "Inner padding"
        binding: paddingBinding

        ConfigBinding { id: paddingBinding; path: "bar.padding" }

        SettingSlider {
            binding: paddingBinding
            from: policy.from("bar.padding")
            to: policy.to("bar.padding")
        }
    }

    SettingRow {
        label: "Module gap"
        binding: gapBinding

        ConfigBinding { id: gapBinding; path: "bar.moduleGap" }

        SettingSlider {
            binding: gapBinding
            from: policy.from("bar.moduleGap")
            to: policy.to("bar.moduleGap")
        }
    }

    SettingRow {
        label: "Floating"
        hint: "Off is a flush full-width band. Flushness turned out to be a property of "
              + "the wallpaper rather than of the bar, and the opaque band is the failure "
              + "mode worth designing for."
        binding: floatingBinding

        ConfigBinding { id: floatingBinding; path: "bar.floating" }

        SettingSwitch { binding: floatingBinding }
    }

    // The three keys that only mean anything while floating. Hidden rather
    // than greyed, which is the opposite of this window's usual call — the
    // sibling-dependent rows on the System and Control Centre tabs all use
    // `enabled` — and it is #72's wording that decides it: "floating
    // margin/radius controls appear only while Floating is on". A greyed row
    // says "this exists and something else has to happen first", and three of
    // them in a column say it about the switch immediately above. Turn Floating
    // on and the slab's shape appears where it was.
    SettingRow {
        label: "Horizontal margin"
        hint: "How far the floating slab is inset from the screen edges."
        visible: floatingBinding.value === true
        binding: marginHBinding

        ConfigBinding { id: marginHBinding; path: "bar.floatMarginH" }

        SettingSlider {
            binding: marginHBinding
            from: policy.from("bar.floatMarginH")
            to: policy.to("bar.floatMarginH")
        }
    }

    SettingRow {
        label: "Vertical margin"
        visible: floatingBinding.value === true
        binding: marginVBinding

        ConfigBinding { id: marginVBinding; path: "bar.floatMarginV" }

        SettingSlider {
            binding: marginVBinding
            from: policy.from("bar.floatMarginV")
            to: policy.to("bar.floatMarginV")
        }
    }

    SettingRow {
        label: "Corner radius"
        visible: floatingBinding.value === true
        binding: radiusBinding

        ConfigBinding { id: radiusBinding; path: "bar.floatRadius" }

        SettingSlider {
            binding: radiusBinding
            from: policy.from("bar.floatRadius")
            to: policy.to("bar.floatRadius")
        }
    }

    SettingRow {
        label: "Auto-hide"
        hint: "Slide the bar away and leave a reveal strip at the edge. The window is "
              + "never destroyed to hide it, so nothing has to be rebuilt on the way back."
        binding: autoHideBinding

        ConfigBinding { id: autoHideBinding; path: "bar.autoHide" }

        SettingSwitch { binding: autoHideBinding }
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

    OrderedList {
        path: "bar.modules.left"
        label: "Left"
        pool: page.pool
        unsupported: page.unsupported
    }

    OrderedList {
        path: "bar.modules.center"
        label: "Centre"
        pool: page.pool
        unsupported: page.unsupported
    }

    OrderedList {
        path: "bar.modules.right"
        label: "Right"
        pool: page.pool
        unsupported: page.unsupported
    }

    SettingRow {
        label: "Media width"
        hint: "A ceiling in px on the track title. It is arbitrary text from another "
              + "application, and an uncapped one walks across the bar and pushes the "
              + "clock off centre. Both of these elide from the right."
        binding: mediaWidthBinding

        ConfigBinding { id: mediaWidthBinding; path: "bar.mediaMaxWidth" }

        SettingSlider {
            binding: mediaWidthBinding
            from: policy.from("bar.mediaMaxWidth")
            to: policy.to("bar.mediaMaxWidth")
        }
    }

    SettingRow {
        label: "Window title width"
        binding: windowWidthBinding

        ConfigBinding { id: windowWidthBinding; path: "bar.windowMaxWidth" }

        SettingSlider {
            binding: windowWidthBinding
            from: policy.from("bar.windowMaxWidth")
            to: policy.to("bar.windowMaxWidth")
        }
    }

    // --- what the schema says ------------------------------------------------

    readonly property var surfaceKnobs: Object.keys(Config.schema.spec.bar.surface.knobs)
    readonly property var ridgelineKnobs: Object.keys(Config.schema.spec.bar.ridgeline.knobs)

    /// Every module the vocabulary knows that is currently in no cluster.
    /// Depends on `Config.values`, so dropping a module into a cluster takes it
    /// out of every pool at once.
    readonly property var pool: {
        const modules = Config.values.bar.modules;
        return fields.pool(Config.schema.barModules,
                           [].concat(modules.left, modules.center, modules.right));
    }

    /// Of those, the ones this build cannot draw — greyed in the pool and
    /// inert. The distinction is the registry's own table and not a second
    /// list, so a module landing in `BarRegistry` un-greys its chip with no
    /// edit here (#72).
    readonly property var unsupported: fields.unsupported(Config.schema.barModules,
                                                          registry.modules)
}
