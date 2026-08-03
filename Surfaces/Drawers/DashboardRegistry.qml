// What the dashboard can carry, and how a config line turns into a card (#49).
//
// The same shape as the bar's registry (Surfaces/Bar/BarRegistry.qml), and
// deliberately so: `dashboard.cards` in settings.json is one list of names, and
// this file is the only thing that knows which names exist. Adding a card is two
// lines — an entry here, and the file it names under `Cards/`.
//
// **Presence is enablement.** There is no `enabled` flag, because a card that is
// off is a card that is not in the list, and two ways to express the same state
// is one way too many for a file people hand-edit.
//
// One list and not three: the dashboard is a single column of cards, so the
// only thing a config decides about a card is whether it is there and what it
// sits under. The bar's three clusters are a fact about a horizontal strip with
// two edges and a middle, not a pattern to copy.
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    id: root

    /// name → `{ file, label }`. `file` is resolved against `Cards/` by the
    /// dashboard; `label` is what a settings GUI (#55) will call it.
    ///
    /// Two entries, which is what #49 ships. The two data cards — weather and
    /// the system monitor — are #50's, and they are deliberately *not* here
    /// while they cannot be drawn: a registry entry naming a file nobody wrote
    /// is a card that loads as a warning. They are in the settings vocabulary
    /// instead (Core/SettingsSchema.qml), which is what keeps them in a config
    /// file written against a newer shell.
    readonly property var cards: ({
        calendar: { file: "CalendarCard.qml", label: "Calendar" },
        media: { file: "MediaCard.qml", label: "Media" }
    })

    function known(name: string): bool {
        return root.cards[name] !== undefined;
    }

    /// The list, cleaned: unknown names dropped, repeats dropped, order
    /// preserved.
    ///
    /// A name the shell does not have is a typo or a card from a version that is
    /// not installed. Both are reported and skipped rather than defaulted,
    /// because there is no sensible substitute for "the thing you asked for" —
    /// and a config that names one bad card still gets the rest of its
    /// dashboard.
    ///
    /// Repeats go because a card is a thing on the dashboard rather than a
    /// template: two calendars would be two things claiming to be the month, and
    /// two media cards would be two transports fighting over one player.
    function resolve(cards: var): var {
        if (!Array.isArray(cards))
            return [];

        const out = [];
        const seen = {};
        for (const name of cards) {
            if (!root.known(name)) {
                console.warn("dashboard: no such card:", name);
                continue;
            }
            if (seen[name]) {
                console.warn("dashboard: card listed twice:", name);
                continue;
            }
            seen[name] = true;
            out.push(name);
        }
        return out;
    }
}
