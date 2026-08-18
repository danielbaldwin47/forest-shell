// Who the guest picker offers, in what order, and what a guest looks like once
// invited.
//
// The decisions here are the ones a person notices and cannot articulate: that
// typing `mir` puts **Mira** first and not *Casimir*, that typing `jose` finds
// **José**, that an address nobody has ever met is still invitable, and that a
// given face keeps the same colour every time it is drawn. None of that needs a
// surface to be true, so none of it lives in one.
//
// Three decisions worth defending:
//
//   - **Prefix beats substring, and a whole-name prefix beats a word prefix.**
//     A picker that ranks by "contains" makes the person you typed the first
//     three letters of arrive third. The tiers are 3 (the name starts with the
//     query), 2 (some word of the name, or the address, starts with it) and 1
//     (it appears anywhere); ties keep the contact list's own order, so the
//     same query always produces the same list.
//   - **Comparison is folded, display is not.** `fold` lowercases, decomposes
//     to NFD and drops the combining marks, then fixes up the letters NFD
//     leaves alone because they are letters rather than a letter plus a mark
//     (ø, đ, ł, ß, æ, œ, ð, þ). So `rune` matches *Rune Halvørsen* and `jose`
//     matches *José*, while the list still shows the accents. The NFD step is
//     guarded — if `String.prototype.normalize` is ever missing, the accent
//     table alone still folds every letter this shell's fixtures contain.
//   - **An unknown address is a guest.** Notion lets you invite anyone, so
//     `parseFreeText` mints a synthetic contact from a typed address rather
//     than making the picker a closed set. `displayList` makes the same
//     concession from the other end: an id with no contact behind it renders
//     as itself instead of vanishing, because a guest silently dropped from an
//     event is worse than a guest shown as a raw handle.
//
// Colour is a *hue name*, not a colour: `palette` is eight names the surface
// maps to `Theme` (`colourFor` only picks which one), while a contact record
// that carries its own `colour` — the fixtures carry hex — keeps it. So the
// surface's rule is "starts with `#` means use it, anything else means look it
// up", and this file never imports Theme.
import QtQuick

QtObject {
    id: policy

    /// Eight hue names, in the order the fixture contacts use them. The surface
    /// maps a name to a Theme colour; nothing here knows what they look like.
    readonly property var palette: ["blue", "green", "yellow", "purple", "cyan", "red", "teal", "orange"]

    /// How many results a picker shows. More than this is a list to read rather
    /// than a list to pick from.
    readonly property int limit: 8

    /// Letters that survive NFD because they are not a letter plus a mark, and
    /// the accents themselves as a fallback for an engine without `normalize`.
    /// Applied after lowercasing, so only the lowercase forms are listed.
    readonly property var foldTable: [
        ["àáâãäåāăą", "a"],
        ["çćĉċč", "c"],
        ["ďđ", "d"],
        ["èéêëēĕėęě", "e"],
        ["ĝğġģ", "g"],
        ["ĥħ", "h"],
        ["ìíîïĩīĭįı", "i"],
        ["ĵ", "j"],
        ["ķ", "k"],
        ["ĺļľŀł", "l"],
        ["ñńņňŋ", "n"],
        ["òóôõöøōŏő", "o"],
        ["ŕŗř", "r"],
        ["śŝşš", "s"],
        ["ţťŧ", "t"],
        ["ùúûüũūŭůűų", "u"],
        ["ŵ", "w"],
        ["ýÿŷ", "y"],
        ["źżž", "z"],
        ["ß", "ss"],
        ["æ", "ae"],
        ["œ", "oe"],
        ["ð", "d"],
        ["þ", "th"]
    ]

    /// Lowercase, accent-free, comparison-only form of `text`. Never displayed.
    function fold(text: var): string {
        if (typeof text !== "string" || text === "")
            return "";
        let s = text.toLowerCase();
        if (typeof s.normalize === "function")
            s = s.normalize("NFD").replace(/[̀-ͯ]/g, "");
        for (let i = 0; i < foldTable.length; i++) {
            const from = foldTable[i][0];
            const to = foldTable[i][1];
            for (let c = 0; c < from.length; c++) {
                if (s.indexOf(from[c]) >= 0)
                    s = s.split(from[c]).join(to);
            }
        }
        return s;
    }

    /// The folded words of a name. Split on whitespace *and* the punctuation
    /// that joins names — a hyphen or an apostrophe is inside a name, so
    /// `o'brien` has to be reachable by typing `brien`.
    function nameWords(name: var): var {
        const folded = fold(name);
        if (folded === "")
            return [];
        return folded.split(/[\s\-.,'’‐-―]+/).filter(w => w.length > 0);
    }

    /// 3 whole-name prefix, 2 word or address prefix, 1 anywhere, 0 no match.
    /// An empty query matches everything at the bottom tier, which is what makes
    /// "just opened the picker" and "typed and deleted it again" the same list.
    /// The query is trimmed first: a pasted address arrives with a space in
    /// front of it, and a picker that goes empty on one reads as a broken
    /// search rather than as a strict one. A query of nothing but spaces is
    /// therefore the empty query.
    function rank(contact: var, query: string): int {
        if (!contact || typeof contact !== "object")
            return 0;
        const q = fold(query).trim();
        if (q === "")
            return 1;
        const name = fold(contact.name);
        const email = fold(contact.email);
        if (name.indexOf(q) === 0)
            return 3;
        const words = nameWords(contact.name);
        for (let i = 0; i < words.length; i++) {
            if (words[i].indexOf(q) === 0)
                return 2;
        }
        if (email !== "" && email.indexOf(q) === 0)
            return 2;
        if ((name !== "" && name.indexOf(q) >= 0) || (email !== "" && email.indexOf(q) >= 0))
            return 1;
        return 0;
    }

    /// The picker's list: everything matching `query`, best first, already
    /// invited ids (`exclude`) removed, capped at `limit`. Ties hold the
    /// contact list's own order, so the ranking is total and repeatable.
    function search(contacts: var, query: string, exclude: var): var {
        if (!Array.isArray(contacts))
            return [];
        const skip = Array.isArray(exclude) ? exclude : [];
        const scored = [];
        for (let i = 0; i < contacts.length; i++) {
            const c = contacts[i];
            if (!c || typeof c !== "object" || typeof c.id !== "string" || c.id === "")
                continue;
            if (skip.indexOf(c.id) >= 0)
                continue;
            const r = rank(c, typeof query === "string" ? query : "");
            if (r > 0)
                scored.push({ contact: c, rank: r, index: i });
        }
        scored.sort((a, b) => b.rank - a.rank || a.index - b.index);
        return scored.slice(0, limit).map(s => s.contact);
    }

    /// The first code point of `text`, so a surrogate pair or a CJK glyph comes
    /// back whole rather than as half a character.
    function firstGlyph(text: var): string {
        if (typeof text !== "string")
            return "";
        const trimmed = text.replace(/^[\s"'“”‘’(\[\-–—.,]+/, "");
        if (trimmed === "")
            return "";
        if (typeof trimmed.codePointAt === "function" && typeof String.fromCodePoint === "function")
            return String.fromCodePoint(trimmed.codePointAt(0)).toUpperCase();
        return trimmed.charAt(0).toUpperCase();
    }

    /// One or two glyphs for an avatar. Two words give first and last — "Mira
    /// Okonkwo" is "MO" — and one word gives one glyph, which is the same rule
    /// that makes "Prince" "P" and "李雷" "李" without the file having to know
    /// which script it is looking at.
    function initials(name: var): string {
        if (typeof name !== "string")
            return "";
        const words = name.split(/\s+/).filter(w => w.replace(/^[\s"'“”‘’(\[\-–—.,]+/, "").length > 0);
        if (words.length === 0)
            return "";
        if (words.length === 1)
            return firstGlyph(words[0]);
        return firstGlyph(words[0]) + firstGlyph(words[words.length - 1]);
    }

    /// The name a chip calls somebody by when it has a row of them to fit: the
    /// first whitespace-delimited word. Not a "given name" — plenty of names do
    /// not have one where English expects it — just the leading word, which is
    /// what a list of people in a small box can carry.
    function shortName(name: var): string {
        if (typeof name !== "string")
            return "";
        const words = name.trim().split(/\s+/).filter(w => w.length > 0);
        return words.length === 0 ? "" : words[0];
    }

    /// The guest line: the shown guests by name, then a `+N` for anybody there
    /// was no avatar for. One guest is named in full; nobody is a blank.
    function nameLine(all: var, shown: var): string {
        const party = Array.isArray(all) ? all : [];
        const faces = Array.isArray(shown) ? shown : [];
        if (party.length === 0)
            return "";
        if (party.length === 1)
            return party[0].name;
        const names = faces.map(function (g) {
            return policy.shortName(g.name);
        }).filter(function (n) {
            return n !== "";
        });
        const rest = party.length - faces.length;
        if (names.length === 0)
            return String(party.length) + " guests";
        return rest > 0 ? names.join(", ") + " +" + String(rest) : names.join(", ");
    }

    /// A hue name for `key`, stable across runs and across machines. FNV-1a over
    /// the code units — any hash would do, but it has to be *this* one forever,
    /// because a changed hash repaints every avatar in the shell.
    function colourFor(key: var, paletteIn: var): string {
        const pal = (Array.isArray(paletteIn) && paletteIn.length > 0) ? paletteIn : palette;
        if (typeof key !== "string" || key === "")
            return pal[0];
        const k = fold(key);
        let h = 2166136261;
        for (let i = 0; i < k.length; i++) {
            h = h ^ k.charCodeAt(i);
            h = (h * 16777619) >>> 0;
        }
        return pal[h % pal.length];
    }

    /// Guest ids with the duplicates and the junk gone, first mention winning.
    function dedupe(guestIds: var): var {
        if (!Array.isArray(guestIds))
            return [];
        const out = [];
        for (let i = 0; i < guestIds.length; i++) {
            const id = guestIds[i];
            if (typeof id !== "string" || id === "")
                continue;
            if (out.indexOf(id) < 0)
                out.push(id);
        }
        return out;
    }

    /// The contact record for `id`, or null.
    function contactFor(id: var, contacts: var): var {
        if (!Array.isArray(contacts) || typeof id !== "string")
            return null;
        for (let i = 0; i < contacts.length; i++) {
            const c = contacts[i];
            if (c && typeof c === "object" && c.id === id)
                return c;
        }
        return null;
    }

    /// Everything the surface needs to draw one guest, for every guest on an
    /// event. An id with no contact behind it is still drawn, named after
    /// itself — a deleted contact must not silently uninvite anybody.
    function displayList(guestIds: var, contacts: var, paletteIn: var): var {
        const ids = dedupe(guestIds);
        const out = [];
        for (let i = 0; i < ids.length; i++) {
            const id = ids[i];
            const c = contactFor(id, contacts);
            const name = (c && typeof c.name === "string" && c.name !== "") ? c.name : id;
            const email = (c && typeof c.email === "string") ? c.email : "";
            const colour = (c && typeof c.colour === "string" && c.colour !== "")
                ? c.colour : colourFor(id, paletteIn);
            out.push({
                id: id,
                name: name,
                email: email,
                initials: initials(name),
                colour: colour,
                known: c !== null
            });
        }
        return out;
    }

    /// The guest line on a wide chip: a few avatars and a count of the rest.
    ///
    /// **The count is of the whole party, not of the overflow.** `+2` after two
    /// avatars is ambiguous — four people or two? — where `4` beside two faces
    /// is the number anybody actually wants off a calendar chip, and it is the
    /// number that stays right when the chip narrows and shows fewer avatars.
    /// So the overflow is expressed as the total and the avatars are however
    /// many fit.
    ///
    /// A single guest is the one case with no count: one avatar beside a `1`
    /// says nothing twice, so a lone guest is drawn as their name instead —
    /// which is the whole fact, in less room than the pair of tokens.
    ///
    /// `maxShown` is the surface's — it is a width, and width is measured, not
    /// decided here.
    function summary(guestIds: var, contacts: var, maxShown: var): var {
        const all = displayList(guestIds, contacts, null);
        const cap = (typeof maxShown === "number" && maxShown >= 0)
            ? Math.floor(maxShown) : 3;
        const shown = all.slice(0, Math.min(cap, all.length));
        return {
            count: all.length,
            shown: shown,
            // The whole party, printed only where the avatars do not already
            // account for everybody.
            countLabel: (all.length > 1 && shown.length < all.length)
                ? String(all.length) : "",
            soloName: all.length === 1 ? all[0].name : "",
            // The one string the chip prints beside the avatars, so the surface
            // holds no `if` about guests at all.
            //
            // **It names people; it does not count the faces beside it.** The
            // previous rule printed the party size — two avatars followed by
            // "2 guests", three followed by "3 guests" — and the capture read
            // as a row that said the same thing twice, once in monograms too
            // small to be sure of and once in words. The count was never the
            // scarce fact: the reader can see how many discs there are. *Who*
            // is the fact, and the initials only hint at it.
            //
            // So the shown guests are named by their first names, and the
            // number returns only for the ones there was no disc for — a `+2`
            // that follows three faces is unambiguous precisely because the
            // three in front of it are named. A lone guest keeps their whole
            // name: there is room, and a surname is worth having when there is.
            line: policy.nameLine(all, shown)
        };
    }

    /// Is `text` an address? Deliberately loose — one `@`, something either
    /// side, a dot in the domain, no whitespace. Strict enough to keep a
    /// half-typed name from becoming a guest, loose enough not to argue with
    /// anybody's mail server about what a local part may contain.
    function isEmail(text: var): bool {
        if (typeof text !== "string")
            return false;
        return /^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/.test(text.trim());
    }

    /// A contact for an address nobody has met, or null when the query is not
    /// an address or is one the list already has. The id is the folded address,
    /// so inviting the same person twice from two spellings is one guest.
    function parseFreeText(query: var, contacts: var): var {
        if (!isEmail(query))
            return null;
        const email = query.trim();
        const id = fold(email);
        if (contactFor(id, contacts))
            return null;
        if (Array.isArray(contacts)) {
            for (let i = 0; i < contacts.length; i++) {
                const c = contacts[i];
                if (c && typeof c === "object" && fold(c.email) === id)
                    return null;
            }
        }
        return {
            id: id,
            name: email,
            email: email,
            colour: colourFor(id, null),
            synthetic: true
        };
    }
}
