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
    /// The four cards #9 named. #49 built the month and the player, and #50
    /// the two data cards — which were in the settings vocabulary before they
    /// were here, deliberately: a name a config may carry is not the same thing
    /// as a file this shell can draw, and a registry entry naming a file nobody
    /// has written yet is a card that loads as a warning.
    readonly property var cards: ({
        calendar: { file: "CalendarCard.qml", label: "Calendar" },
        weather: { file: "WeatherCard.qml", label: "Weather" },
        systemMonitor: { file: "SystemMonitorCard.qml", label: "System monitor" },
        media: { file: "MediaCard.qml", label: "Media" }
    })

    function known(name: string): bool {
        return root.cards[name] !== undefined;
    }

    /// Whether two resolved lists are the same dashboard.
    ///
    /// This exists because of what a config reload *is* (#75): Core/SpecFile.qml
    /// replaces `Config.values` wholesale on every reload and every `set()`, so
    /// a binding that resolves the card list hands back a new array identity
    /// when any key in the file changes — the bar's blur, a notification
    /// timeout, anything. A `Repeater` does not diff a JS array, so that
    /// identity change destroys and rebuilds every card: the calendar loses the
    /// month you paged to and the media card remounts under your hand.
    ///
    /// So the dashboard compares before it assigns, and this is the comparison.
    /// Order is part of it — reordering the cards *is* a change — which is why
    /// this is not a set difference.
    function same(before: var, after: var): bool {
        const a = Array.isArray(before) ? before : [];
        const b = Array.isArray(after) ? after : [];
        if (a.length !== b.length)
            return false;
        for (let i = 0; i < a.length; i++)
            if (a[i] !== b[i])
                return false;
        return true;
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
