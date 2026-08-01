// A stable row of workspaces, out of a compositor that does not have one.
//
// Hyprland creates a workspace when something lands on it and destroys it when
// the last window leaves, so the live list is not a row — it is whatever you
// happen to be using. Rendered directly, the indicator would grow and shrink as
// you worked, and the workspace you are about to switch to would not be on
// screen until you were already there.
//
// So the row is a fixed range of slots, 1..n, unioned with any live workspace
// past it. Slots you have never used are drawn as empty rather than left out —
// #10 accepted the cost of that (empty forms at 3px and 22% opacity vanish so
// completely that you cannot count them at a glance) in exchange for a row that
// holds still.
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    /// `[{ id, occupied, active }]` for the whole row, ascending.
    ///
    /// `live` is what the compositor facade reports. Anything in it that is not
    /// in the slot range is appended in id order, so a workspace 9 you opened
    /// by hand shows up on the right of the row rather than vanishing or
    /// stretching it to nine slots.
    function row(live: var, slots: int): var {
        const known = {};
        for (const workspace of (live || []))
            if (workspace.id >= 1)
                known[workspace.id] = workspace;

        const ids = [];
        for (let id = 1; id <= slots; id++)
            ids.push(id);
        for (const key in known) {
            const id = parseInt(key, 10);
            if (id > slots)
                ids.push(id);
        }
        ids.sort((a, b) => a - b);

        return ids.map(id => ({
            id: id,
            occupied: known[id] ? known[id].occupied === true : false,
            active: known[id] ? known[id].active === true : false
        }));
    }
}
