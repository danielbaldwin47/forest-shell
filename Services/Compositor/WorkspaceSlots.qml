// The workspace row, as data (#35).
//
// Hyprland destroys a workspace the moment its last window closes, so its
// workspace list is not a row you can draw: it is whatever happens to exist
// right now. A ridgeline needs a stable set of slots to fall away from, so the
// row is a fixed range 1..N unioned with every live workspace beyond it — the
// same rule the prototype settled on (`.wayfinder/prototypes/bar-ridgeline`).
//
// Pure functions, no Quickshell imports, so tests/ can reach them
// (Core/Tokens.qml explains why that split exists at all). The facade in
// Services/Compositor/Compositor.qml is what feeds this real IPC objects.
import QtQuick

QtObject {
    /// The row: `[{ id, occupied, active }]`, ascending by id.
    ///
    /// `live` is `[{ id, windows }]` — `windows` may be missing, which is read
    /// as occupied rather than empty: the workspace exists, and Hyprland only
    /// keeps workspaces that have a reason to. Guessing "empty" there would
    /// make a real workspace vanish from the row until the next full refresh.
    ///
    /// Negative ids are Hyprland's special workspaces (scratchpad); they are
    /// not part of the numbered range and never get a slot.
    function cells(slotCount, live, activeId) {
        const occupancy = {};
        const ids = [];

        const slots = Math.max(0, Math.round(Number(slotCount)) || 0);
        for (let id = 1; id <= slots; id++) {
            occupancy[id] = false;
            ids.push(id);
        }

        for (const workspace of (Array.isArray(live) ? live : [])) {
            const id = Math.round(Number(workspace ? workspace.id : NaN));
            if (!isFinite(id) || id < 1)
                continue;

            const windows = workspace.windows;
            const occupied = typeof windows === "number" ? windows > 0 : true;

            if (occupancy[id] === undefined)
                ids.push(id);
            occupancy[id] = occupancy[id] || occupied;
        }

        // The focused workspace is always in the row even if the event that
        // would have introduced it has not arrived yet — a bar that cannot show
        // where you are is worse than a bar with one extra slot.
        const active = Math.round(Number(activeId));
        if (isFinite(active) && active >= 1 && occupancy[active] === undefined) {
            occupancy[active] = true;
            ids.push(active);
        }

        ids.sort((a, b) => a - b);
        return ids.map(id => ({
            id: id,
            occupied: occupancy[id] === true,
            active: id === active
        }));
    }
}
