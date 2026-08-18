// Which of the eight event hues an event wears.
//
// The colours themselves are in `CalendarTokens.qml`, which is where a Theme
// import is allowed; this file holds only the *choice*, so it stays a pure
// QtObject that `tests/tst_huepolicy.qml` can load offscreen.
//
// Two things have to be true of that choice and neither is obvious:
//
// 1. **An event with no colour still has to get one.** The fixture events all
//    carry `colour: ""` and so will most real ones — nobody picks a colour for
//    a meeting they accepted. A week of eight grey chips is a worse picture
//    than a week of eight arbitrary but *stable* ones, so an uncoloured event
//    is hashed onto the wheel by its id.
// 2. **The same event must get the same hue on every run.** The hash is over
//    the id, which is `evt-3` forever, and not over an array index, a load
//    order or an insertion time — any of which would repaint the whole week
//    when one event is deleted and would make two captures of the same fixture
//    two different pictures.
pragma ComponentBehavior: Bound
import QtQuick

QtObject {
    id: policy

    /// The wheel, in order. The index into this array is the hue's identity
    /// everywhere else: `CalendarTokens` indexes its three colour tables by it,
    /// and a stored `colour` is one of these names.
    readonly property var names: [
        "glacier", "moss", "lamplight", "ember", "lake", "lichen", "heather", "stone"
    ]

    readonly property int count: policy.names.length

    /// A stable non-negative hash of a string. djb2, kept here rather than
    /// pulled from anywhere clever because the only property that matters is
    /// that it never changes — an implementation someone might "improve" would
    /// repaint every calendar in the world.
    ///
    /// `>>> 0` after each step keeps the value in 32 unsigned bits: QML numbers
    /// are doubles, and a djb2 left to run past 2^53 stops being the same hash
    /// on the next character.
    function hash(text: string): int {
        let h = 5381;
        const s = String(text === undefined || text === null ? "" : text);
        for (let i = 0; i < s.length; i++)
            h = (((h * 33) >>> 0) ^ s.charCodeAt(i)) >>> 0;
        return h >>> 0;
    }

    /// The hue index for a stored `colour` and an id, always `0..count-1`.
    ///
    /// A named colour wins, case-insensitively. An out-of-range or unknown
    /// name does **not** fall back to hue 0 — that would quietly make every
    /// typo glacier and hide the typo — it falls through to the id hash, which
    /// at least keeps two mistyped events apart.
    ///
    /// A numeric string is accepted too (`"3"`), because a colour picker that
    /// stores an index is the obvious next thing someone writes and refusing it
    /// would be a silent all-glacier calendar.
    function indexFor(colour: string, id: string): int {
        const name = String(colour === undefined || colour === null ? "" : colour).trim().toLowerCase();
        if (name.length > 0) {
            const named = policy.names.indexOf(name);
            if (named >= 0)
                return named;
            if (/^[0-9]+$/.test(name)) {
                const n = parseInt(name, 10);
                if (n >= 0 && n < policy.count)
                    return n;
            }
        }
        return policy.hash(id) % policy.count;
    }

    /// The same question asked of a whole event, which is what a surface has in
    /// its hand. A missing event is hue 0 rather than an exception: the caller
    /// is a delegate mid-rebuild, and a thrown TypeError there costs the whole
    /// column.
    function forEvent(event: var): int {
        if (!event)
            return 0;
        return policy.indexFor(event.colour, event.id);
    }
}
