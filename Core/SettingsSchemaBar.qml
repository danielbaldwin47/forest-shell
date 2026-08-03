// The `bar` section of the settings spec table, split out of
// Core/SettingsSchema.qml because it is the fattest section by far — the
// aggregate schema composes `section` back in, and every consumer keeps
// reading `Config.schema.spec.bar` and `Config.schema.barModules` as before.
// The rules the table is read under are documented in Core/SettingsSchema.qml;
// a section moves into a file like this one when its tab lands (#54 built the
// Bar tab, so this one exists).
//
// Pure data, no Quickshell imports, so tests/ can reach it.
import QtQuick

QtObject {
    id: barSchema

    readonly property SchemaKnobs knobs: SchemaKnobs {}
    readonly property QtObject c: knobs.c

    /// Every bar module the registry knows, in no particular order — the order
    /// that matters is the user's, and it is the cluster arrays below. Ids not
    /// listed in any cluster are simply off; there is no separate enable flag.
    /// `status` is one module and not four: #9 groups network, bluetooth, volume
    /// and mic into a single quiet icon cluster.
    readonly property var modules: [
        "launcher", "workspaces", "activeWindow",
        "clock", "media",
        "tray", "status", "battery", "keyboard", "notifications", "controlCenter",
        // Shipped in the registry, off by default (#9).
        "systemMonitor", "brightness", "nightLight", "recorder"
    ]

    // Geometry and inventory are plain keys; the two styling groups are
    // theme-flagged, because a preset (#56) swaps how the bar *looks*
    // without moving modules around or resizing it.
    readonly property var section: ({
        // Top horizontal is the v1 bar (#9). Left/right are absent rather
        // than accepted-and-ignored: the widgets are built axis-agnostic so
        // a vertical bar can land post-v1 without rewrites, but a position
        // the shell cannot actually lay out is a dead setting.
        position: { def: "top", coerce: c.oneOf(["top", "bottom"]) },
        // 32 logical px — 48 device px at the T480's 1.5 scale. 26 crowds
        // the icons, 36+ reads as a title bar (#10).
        height: { def: 32, coerce: c.integer(20, 64) },
        padding: { def: 12, coerce: c.integer(0, 48) },
        moduleGap: { def: 14, coerce: c.integer(0, 48) },

        // Flush full-width is the default; floating insets the bar into a
        // rounded slab. The margins and radius only apply while floating.
        floating: { def: false, coerce: c.boolean },
        floatMarginH: { def: 12, coerce: c.integer(0, 64) },
        floatMarginV: { def: 8, coerce: c.integer(0, 64) },
        floatRadius: { def: 10, coerce: c.integer(0, 32) },

        // The window is never destroyed to hide it (#12 §2, #22 §5) — it
        // drops its content and keeps a reveal strip.
        autoHide: { def: false, coerce: c.boolean },

        // Which modules the bar carries, in which cluster, in what order.
        // Presence *is* enablement: there is no separate `enabled` flag,
        // because a module that is off is a module that is not in a list.
        //
        // A list of names, not a closed enum: unknown names are dropped by
        // the registry with a warning rather than here
        // (Surfaces/Bar/BarRegistry.qml), so a file written by a newer
        // shell keeps its modules under an older one. Three leaves rather
        // than one leaf holding all three, so reordering one cluster
        // writes back only that cluster.
        //
        // The default inventory is #9's, in #9's order — #37 brought all
        // but the notification indicator, which lands here with the
        // notification centre (#43). Left is where you are — the workspaces and
        // the window in front of you, behind the door into the launcher.
        // Centre is the clock and what is playing. Right is the machine's
        // condition, tray first and the control-centre door outermost: the
        // right cluster is all readings except that last one, and a door at
        // the screen edge is the easiest target on the bar.
        //
        // Three of these hide themselves — media with nothing playing, the
        // keyboard layout on a single-layout machine, the window title on
        // an empty workspace — so the shipped bar is shorter than this list
        // most of the time.
        modules: {
            left: { def: ["launcher", "workspaces", "activeWindow"],
                    coerce: c.arrayOf(c.string, "bar.modules.left") },
            center: { def: ["clock", "media"],
                      coerce: c.arrayOf(c.string, "bar.modules.center") },
            right: { def: ["tray", "status", "battery", "keyboard", "notifications",
                           "controlCenter"],
                     coerce: c.arrayOf(c.string, "bar.modules.right") }
        },

        // The two ceilings #37 needed and #36 did not: a track title and a
        // window title are arbitrary text from another application, and an
        // uncapped one walks across the bar and pushes the clock off centre
        // (the #80 class of overflow). Both elide from the right.
        //
        // JSON-only for now, which #9 allows for the long tail: they are
        // two numbers in px that depend on a screen width the Bar tab has
        // no preview of.
        mediaMaxWidth: { def: 180, coerce: c.integer(60, 600) },
        windowMaxWidth: { def: 220, coerce: c.integer(60, 800) },

        // The two styling groups, declared knob by knob (SchemaKnobs
        // `group()`): the group's default object, its knob-by-knob coercer
        // and the controls the Bar tab renders are all derived from each
        // line, so a slider cannot offer a value the file would then clamp.
        //
        // Every number below is a measured decision from the bar prototype
        // (#10), not a taste call made at this keyboard. What is *not*
        // here is as deliberate: no ridgeline shape key (`peaks` and
        // `pills` were built and rejected — shipping them as settings
        // would ship the rejected designs), no horizon rule and no
        // workspace id under the active peak (both measured as not working
        // at a 32px bar).
        surface: knobs.group("bar.surface", {
            // 86% of `surface` over the wallpaper. Measured 7.12:1 for
            // text-secondary under the right-hand cluster — the worst
            // case, since that cluster sits over the brightest part of the
            // sky. The floor is 0.65: 0.60 measured 4.44:1 and fails the
            // body-text rule (#10).
            opacity: { def: 0.86, min: 0.65, max: 1.0, label: "Fill opacity" },
            // Blur is the compositor's job — a Hyprland layerrule on this
            // bar's namespace, which costs the shell nothing per frame.
            blur: { def: true, label: "Blur the wallpaper behind" },
            // The brief's pale mist wash, §6.1.
            mistWash: { def: 0.10, min: 0, max: 0.5, label: "Mist wash" },
            // "Barely-perceptible top-edge lightening" — the vertical
            // luminance gradient every board pin has, compressed into 32px.
            topLight: { def: true, label: "Top-edge lightening" },
            topLightAmount: { def: 0.05, min: 0, max: 0.4, label: "Top light amount" },
            // 1px border-subtle bottom hairline: the bar's bottom edge is
            // a horizon, and the horizon motif wants a line.
            hairline: { def: true, label: "Bottom hairline" },
            // 2-4% monochrome noise kills gradient banding (brief §3.5).
            grain: { def: 0.03, min: 0, max: 0.1, label: "Grain" },
            // Less translucency as the wallpaper brightens. Off by
            // default, and costs nothing while off.
            adaptiveOpacity: { def: false, label: "Adapt opacity to the wallpaper" }
        }),

        ridgeline: knobs.group("bar.ridgeline", {
            // Width is the whole ballgame (#10): at w14/gap4 the units
            // read as receding strata; narrower and it reads as a bar
            // chart, wider and it reads as a row of buttons. Locked taste
            // call.
            unitWidth: { def: 14, min: 4, max: 40, label: "Unit width" },
            gap: { def: 4, min: 0, max: 20, label: "Gap" },
            // Heights: active tallest, occupied falling away by distance,
            // empty at the vanishing height regardless.
            activeHeight: { def: 14, min: 2, max: 48, label: "Active height" },
            occupiedHeight: { def: 9, min: 1, max: 48, label: "Occupied height" },
            emptyHeight: { def: 3, min: 0, max: 48, label: "Empty height" },
            falloff: { def: 2, min: 0, max: 12, label: "Height falloff" },
            minHeight: { def: 4, min: 0, max: 48, label: "Minimum height" },
            // Haze: the same encoding again, in opacity, so distance reads
            // twice.
            occupiedHaze: { def: 0.62, min: 0, max: 1, label: "Occupied haze" },
            emptyHaze: { def: 0.22, min: 0, max: 1, label: "Empty haze" },
            hazeFalloff: { def: 0.10, min: 0, max: 1, label: "Haze falloff" },
            minHaze: { def: 0.15, min: 0, max: 1, label: "Minimum haze" },
            // Hyprland destroys empty workspaces, so a fixed slot range is
            // unioned with whatever live workspaces exist beyond it —
            // otherwise the row grows and shrinks as you work.
            slots: { def: 5, min: 1, max: 20, label: "Workspace slots" },
            // The single-lamplight rule, resolved (#10): amber is reserved
            // for attention, so the active workspace is teal and the bar
            // at rest carries no warm element at all. This is the escape
            // hatch for the other reading, not the default.
            amberActive: { def: false, label: "Amber active workspace" }
        })
    })
}
