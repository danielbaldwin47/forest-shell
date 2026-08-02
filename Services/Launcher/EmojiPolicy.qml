// The emoji provider's decisions (#40) — what a query matches, in what order,
// and what Enter puts on the clipboard.
//
// The glyphs themselves are EmojiTable.qml next door; this file never names
// one. That split is the same one LauncherPolicy makes between the ranking and
// the desktop-entry model: adding an emoji should not be an edit to the search.
//
// Matching reuses `LauncherPolicy.score()` rather than growing a second fuzzy
// matcher. There is one idea of what "a good match" means in this launcher and
// it belongs in one place — a provider whose ranking felt subtly different from
// the apps list would be a bug nobody could name.
//
// Imports nothing but QtQuick, so `tests/` can reach the whole of it.
import QtQuick

QtObject {
    id: policy

    readonly property EmojiTable table: EmojiTable {}

    /// The scorer, borrowed. LauncherPolicy is a bag of pure functions with no
    /// state, so instantiating a second one costs nothing and buys the
    /// guarantee that "fire" ranks emoji the way it ranks apps.
    readonly property LauncherPolicy base: LauncherPolicy {}

    /// How many rows a bare `:` shows. The same argument as the apps provider's
    /// recents (#11 §6): an emoji picker that opens onto everything it has is a
    /// character map, and the launcher is not one. Higher than the apps limit
    /// because these rows are being *browsed* rather than recognised — you know
    /// which app you want before you open the launcher, and you do not know
    /// which emoji you want until you see it.
    readonly property int browseLimit: 12

    // --- matching ------------------------------------------------------------

    /// The two scores an exact hit is worth. Far above anything the fuzzy
    /// scorer can reach, because they are not degrees of a match — they are the
    /// user having typed the thing itself.
    readonly property real exactName: 10000
    readonly property real exactKeyword: 1000

    /// How well one entry matches, as a ladder: the name exactly, a keyword
    /// exactly, the name fuzzily, a keyword fuzzily.
    ///
    /// The two exact rungs are what this provider needs and the apps provider
    /// does not, and the reason is the shape of the names. A desktop entry is
    /// called "Firefox"; an emoji is called "face with tears of joy". Fuzzy
    /// subsequence matching over prose that long finds a hit in almost
    /// anything — measured, `lol` scores 8.6 against "loudly crying face"
    /// (l·o·l, two of them adjacent and one at the start) and beat 😂's own
    /// `lol` keyword at the fractional weight. Ranking an accident above an
    /// intentional alias is exactly backwards, and no weighting of the two
    /// fuzzy scores against each other fixes it — the alias has to win by
    /// being *exact*, not by being a keyword.
    ///
    /// Keywords are scored one at a time and the best is taken, rather than
    /// joined into one string the way a desktop entry's are. A desktop file's
    /// keyword list is prose-like and long; these are single words, and joining
    /// them lets a needle match across the seam between two of them — "sadcry"
    /// would hit `["sad", "cry"]`, which is a match no one meant.
    function scoreEntry(needle: string, entry: var): real {
        if (!entry)
            return -1;
        const want = String(needle ?? "").toLowerCase().trim();
        if (want.length === 0)
            return 0;

        const name = String(entry.name ?? "").toLowerCase();
        if (name === want)
            return policy.exactName;

        const keywords = entry.keywords ?? [];
        for (const keyword of keywords) {
            if (String(keyword).toLowerCase() === want)
                return policy.exactKeyword;
        }

        const fuzzyName = policy.base.score(want, name);
        if (fuzzyName >= 0)
            return fuzzyName;

        let best = -1;
        for (const keyword of keywords) {
            const hit = policy.base.score(want, keyword);
            if (hit > best)
                best = hit;
        }
        return best >= 0 ? best * 0.4 : -1;
    }

    /// The matches for a query, ranked. An empty query is the browse list — the
    /// front of the table, which is ordered by how often the glyph is reached
    /// for rather than by codepoint.
    ///
    /// Ties break on table order rather than on the name, so the list is stable
    /// under a keystroke that does not change the score: a picker whose rows
    /// reshuffle while you look at them is one you cannot aim at.
    function search(query: string): var {
        const want = String(query ?? "");
        const list = policy.table.emoji;

        if (want.length === 0)
            return list.slice(0, policy.browseLimit);

        const scored = [];
        for (let i = 0; i < list.length; i++) {
            const hit = policy.scoreEntry(want, list[i]);
            if (hit < 0)
                continue;
            scored.push({ entry: list[i], hit: hit, order: i });
        }

        scored.sort((a, b) => b.hit - a.hit || a.order - b.order);
        return scored.map(row => row.entry);
    }

    // --- the rows ------------------------------------------------------------

    /// One row per match. The glyph goes in the icon slot rather than in the
    /// title: it is what you are choosing between, so it wants the position the
    /// eye scans down, and a 22px emoji beside a name reads as a picker where
    /// "😂 face with tears of joy" reads as a sentence.
    ///
    /// `copy` is the glyph and nothing else — no name, no codepoint. Enter here
    /// means "put this in the message I am writing".
    function rows(query: string): var {
        return policy.search(query).map(entry => ({
            provider: "emoji",
            id: "emoji:" + entry.char,
            title: entry.name,
            subtitle: (entry.keywords ?? []).join(" · "),
            icon: "",
            glyph: entry.char,
            iconSource: "",
            category: "Emoji",
            copy: entry.char,
            entryId: "",
            run: null
        }));
    }

    /// What the provider says when it has no rows. Only one silence here, which
    /// is the difference between this provider and the apps one: the table is
    /// compiled in, so there is no scan to be waiting on and no state in which
    /// "nothing yet" is a different answer from "nothing matched".
    function silence(query: string): var {
        return String(query ?? "").length === 0
            ? null
            : { icon: "circle-slash", text: "No emoji for \"" + query + "\"" };
    }

    // --- what the log says ---------------------------------------------------

    function copied(entry: var): string {
        return entry ? entry.char + " (" + entry.name + ") copied" : "nothing to copy";
    }
}
