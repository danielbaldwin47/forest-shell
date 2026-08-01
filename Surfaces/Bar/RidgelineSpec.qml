// The ridgeline as data (#35): the strata knobs and the falloff that turns a
// row of workspaces into a receding range.
//
// The shape is settled and not a knob — **strata**, w14/gap4, the taste call
// #10 locked after putting peaks and pills on the same screen. Peaks lose the
// flat top edge that makes strata read as strata, and pills are the generic
// idiom forest-shell is choosing not to ship; neither is a preference the
// config should carry.
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

    /// `bar.ridgeline` → the resolved knob set. Defaults are #10's measured
    /// sheet: 14/9/3 px with a 2px falloff, haze 1.0/0.62/0.22.
    function knobs(value) {
        const raw = k.group(value);
        return {
            // How many workspaces the ridge always shows, whether or not they
            // exist (Services/Compositor/WorkspaceSlots.qml unions the rest in).
            slots: k.integer(raw.slots, 5, 1, 20),

            // w14/gap4 — at w9 the horizontal rhythm outruns the vertical and
            // the range reads as a chart; at w6 it reads as spikes.
            unitWidth: k.integer(raw.unitWidth, 14, 2, 48),
            gap: k.integer(raw.gap, 4, 0, 24),

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
