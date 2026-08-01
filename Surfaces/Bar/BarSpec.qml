// The bar as data (#35): the module registry's id list, the layout the config
// orders those ids into, and the surface knobs.
//
// Same split as Core/SettingsSchema.qml against Core/Config.qml — this file
// imports nothing but QtQuick, so tests/ can reach it, and the live QML next to
// it stays a thin reader. What is *not* here is anything the spec table already
// types: `bar.position`, `bar.height`, `bar.padding`, `bar.moduleGap` and
// `bar.floating` are ordinary leaves with defaults and coercers of their own,
// and re-stating their defaults here would give them two homes. This file owns
// exactly the parts the schema deliberately leaves opaque: the atomic themed
// groups, and the module layout.
import QtQuick

QtObject {
    id: spec

    readonly property QtObject k: Knobs {}

    // --- the registry --------------------------------------------------------

    /// Every module the bar can place. This list *is* the registry as far as
    /// config is concerned: an id not here is not a module, and
    /// Surfaces/Bar/ModuleRegistry.qml maps exactly these ids to components.
    /// Adding a module is one entry here and one line there.
    readonly property var moduleIds: ["workspaces", "clock"]

    /// The three clusters, in visual order. Named rather than positional so a
    /// vertical bar reads the same file: on a left/right bar these are top,
    /// middle and bottom (#35 — axis-agnostic, so a vertical bar lands post-v1
    /// without a rewrite).
    readonly property var slotNames: ["left", "center", "right"]

    /// `bar.modules` → `{ left, center, right }` of known ids.
    ///
    /// The config value is an atomic object, so a user who names any slot
    /// replaces the *whole* layout: a file saying only `{ "left": ["clock"] }`
    /// gets a bar with a clock on the left and nothing else. Merging per slot
    /// would make "remove the clock" impossible to express, since an absent
    /// slot would keep re-inheriting the shipped default.
    ///
    /// Unknown ids are dropped with a warning rather than silently ignored —
    /// this arrives hand-edited, and a typo'd module should say so. A repeated
    /// id is dropped for the same reason it would be wrong to honour it: one
    /// module, one place on the bar.
    function modules(value) {
        const raw = k.group(value);
        const out = {};
        const seen = {};

        for (const slot of spec.slotNames) {
            const ids = Array.isArray(raw[slot]) ? raw[slot] : [];
            const kept = [];
            for (const id of ids) {
                if (spec.moduleIds.indexOf(id) < 0) {
                    console.warn("Bar: unknown module in bar.modules." + slot + ":", id);
                    continue;
                }
                if (seen[id]) {
                    console.warn("Bar: module placed twice, keeping the first:", id);
                    continue;
                }
                seen[id] = true;
                kept.push(id);
            }
            out[slot] = kept;
        }

        return out;
    }

    // --- the surface ---------------------------------------------------------

    /// The floor under `bar.surface.fillOpacity` (#35, and #10's measurements).
    ///
    /// Not taste: the prototype measured `text-secondary` on a translucent bar
    /// over the brightest pin wallpaper and found it falls to 2.89:1 once the
    /// fill gets thin, against a 4.5:1 body-text floor. 86% fill measures
    /// 7.12:1 in the same spot. A user may thin the bar toward the wallpaper,
    /// but not past the point where the bar stops being readable on a bright
    /// sky — the number moves with the wallpaper, so it cannot be left to be
    /// noticed later.
    readonly property real minFillOpacity: 0.65

    /// `bar.surface` → the resolved knob set.
    ///
    /// Only *taste* lives here. The amounts these switches turn on — the
    /// top-edge lightening, the mist wash, the grain — are design-system
    /// tokens (Core/Tokens.qml), so the config answers "is the bar grainy",
    /// never "how grainy", and no number has two homes.
    function surface(value) {
        const raw = k.group(value);
        return {
            // 86% over compositor-blurred wallpaper: the ticket's shipped
            // surface, and the one the contrast measurement is quoted for.
            fillOpacity: k.number(raw.fillOpacity, 0.86, spec.minFillOpacity, 1.0),

            // Brief §3.2 — every pin is brighter at the top, compressed into
            // 32px so the bar carries the same vertical luminance the wallpaper
            // does.
            topLight: k.flag(raw.topLight, true),

            // Brief §6.1 — depth through haze, not through shadow.
            wash: k.flag(raw.wash, true),

            // The bar's bottom edge is a horizon; the hairline is what makes it
            // one rather than a cut. Flush bars only — a floating island has no
            // horizon to draw, so the surface never asks for it there.
            hairline: k.flag(raw.hairline, true),

            // Brief §3.5 — 3% noise, because a 32px gradient over a flat fill
            // bands on an 8-bit panel.
            grain: k.flag(raw.grain, true),

            // Off by default (#35). When on, the fill goes solid while there is
            // a window on the bar's own monitor and thins back out over an
            // empty workspace — the wallpaper shows through only when there is
            // wallpaper to show.
            adaptiveOpacity: k.flag(raw.adaptiveOpacity, false)
        };
    }
}
