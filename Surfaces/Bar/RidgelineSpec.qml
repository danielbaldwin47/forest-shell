// The ridgeline as data (#35): the strata knobs and the falloff that turns a
// row of workspaces into a receding range.
//
// The shape is settled and not a knob — **strata**, w14/gap4, the taste call
// #35 locked after #10 put peaks, pills and strata on the same screen. Peaks
// lose the flat top edge that makes strata read as strata, and pills are the
// generic idiom forest-shell is choosing not to ship; neither is a preference
// the config should carry, and neither is the width.
//
// w14/gap4 is a decision *against* the prototype's own leaning, recorded here
// so nobody re-derives it: #10 found w14 reads as blocks — "a row of buttons,
// not a ridge" — and that at w9 gap3 "the horizontal rhythm outruns the
// vertical and the range appears". #35 locked w14 anyway. The prototype was
// judging the ridge alone at full attention; the bar is judged at a glance,
// beside a clock, where the narrower units read as a chart rather than as
// ground. A locked call is exactly the kind that has to survive somebody
// finding the sheet later and thinking it was a mistake.
//
// Height *and* opacity encode distance from the active workspace: active
// tallest and fully present, occupied neighbours progressively shorter and
// hazier, empty workspaces at the vanishing height regardless of where they
// sit. Colour does not encode distance — the active workspace is teal, and
// nothing on the bar at rest is warm (#35: amber is reserved for attention).
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    id: spec

    readonly property QtObject k: Knobs {}

    /// The active stratum is fully present by definition — it is the one thing
    /// on the ridge that is not receding. Not a knob: hazing it would leave the
    /// row with no near edge for everything else to fall away from.
    readonly property real activeHaze: 1.0

    /// The locked width and rhythm. Constants, not knobs, for the reason the
    /// header gives: this is the taste call, and a config key would quietly
    /// re-open it.
    readonly property int unitWidth: 14
    readonly property int gap: 4

    /// `bar.ridgeline` → the resolved knob set. Defaults are #10's measured
    /// sheet: 14/9/3 px with a 2px falloff, haze 1.0/0.62/0.22.
    ///
    /// The locked pair above is folded in here rather than read separately, so
    /// a caller has one object to bind against and cannot half-configure a
    /// ridge.
    function knobs(value) {
        const raw = k.group(value);
        return {
            unitWidth: spec.unitWidth,
            gap: spec.gap,

            // How many workspaces the ridge always shows, whether or not they
            // exist (Services/Compositor/WorkspaceSlots.qml unions the rest in).
            slotCount: k.integer(raw.slotCount, 5, 1, 20),

            activeHeight: k.integer(raw.activeHeight, 14, 2, 64),
            occupiedHeight: k.integer(raw.occupiedHeight, 9, 1, 64),
            emptyHeight: k.integer(raw.emptyHeight, 3, 0, 64),
            falloff: k.integer(raw.falloff, 2, 0, 16),
            minHeight: k.integer(raw.minHeight, 4, 0, 64),

            occupiedHaze: k.number(raw.occupiedHaze, 0.62, 0.0, 1.0),
            emptyHaze: k.number(raw.emptyHaze, 0.22, 0.0, 1.0),
            hazeFalloff: k.number(raw.hazeFalloff, 0.10, 0.0, 1.0),
            minHaze: k.number(raw.minHaze, 0.15, 0.0, 1.0)
        };
    }

    /// `[{ id, occupied, active }]` → the same cells carrying `length` and
    /// `haze`. `length` rather than `height` because the widget that draws this
    /// is axis-agnostic: on a vertical bar the strata grow sideways, and a
    /// property called height would be the wrong word in half the cases.
    ///
    /// Distance is counted in *row positions*, not in workspace ids. With a
    /// contiguous row the two agree, which is why the prototype could use ids;
    /// they part company as soon as Hyprland leaves a hole (1, 2, 3, 9), and
    /// then id-distance drops workspace 9 to the floor for being numbered high
    /// rather than for being far away. What the eye reads is the gap on screen.
    function strata(cells, knobs) {
        const row = Array.isArray(cells) ? cells : [];
        let activeIndex = -1;
        for (let i = 0; i < row.length; i++)
            if (row[i].active) {
                activeIndex = i;
                break;
            }

        return row.map(function (cell, index) {
            const distance = activeIndex < 0 ? 1 : Math.abs(index - activeIndex);
            return {
                id: cell.id,
                occupied: cell.occupied,
                active: cell.active === true,
                length: spec.lengthFor(cell, distance, knobs),
                haze: spec.hazeFor(cell, distance, knobs)
            };
        });
    }

    function lengthFor(cell, distance, knobs) {
        if (cell.active)
            return knobs.activeHeight;
        if (!cell.occupied)
            return knobs.emptyHeight;
        return Math.max(knobs.minHeight,
                        knobs.occupiedHeight - knobs.falloff * (distance - 1));
    }

    function hazeFor(cell, distance, knobs) {
        if (cell.active)
            return spec.activeHaze;
        if (!cell.occupied)
            return knobs.emptyHaze;
        return Math.max(knobs.minHaze,
                        knobs.occupiedHaze - knobs.hazeFalloff * (distance - 1));
    }
}
