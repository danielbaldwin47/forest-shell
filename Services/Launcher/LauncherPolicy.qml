// The launcher's decisions (#39) — which provider a query is in, which rows
// come back, in what order, and where the list stops.
//
// The launcher is a *dispatcher* first and a list second. A leading punctuation
// character picks the provider; everything after it is that provider's query.
// The set is closed and the prefixes are fixed (#9), so the table below is the
// whole routing rule and a provider registers by appearing in it — a prefix, a
// name, an icon, and whether it has landed yet.
//
// Only the apps provider has landed (#39). The other five are declared here
// anyway, and deliberately: the footer legend is how six providers become
// discoverable at all (#11 §7), and a legend that grows a row per ticket would
// teach the prefixes twice. Typing an unlanded prefix says which ticket owns it
// rather than showing an empty list, which is the difference between "not yet"
// and "no matches".
//
// Everything here is a decision, which is why it is here and not in
// Surfaces/Drawers/Launcher.qml: this file imports nothing but QtQuick, so
// `tests/` can reach it (CLAUDE.md, and Core/Tokens.qml for the same split one
// layer down). The desktop-entry model, the process that launches, the state
// file that remembers — all of those need Quickshell and live on the other
// side of the line, in Apps.qml next door.
//
// It sits under Services/ rather than beside its surface the way
// Surfaces/Drawers/SessionPolicy.qml does, for one reason: Apps.qml needs it
// too. A policy under Surfaces/ would have the service importing the surface
// directory that imports the service, and Quickshell resolves `qs.` imports
// per directory — so the dependency is made to run one way instead.
import QtQuick

QtObject {
    id: policy

    // --- the providers -------------------------------------------------------

    /// Every provider, keyed by the prefix that reaches it. Apps is the empty
    /// prefix: it is what a bare query means, so it is not punctuation.
    ///
    /// `id` is both the provider's name in the log and its key under
    /// `launcher.providers` in the config — one field, because a second one
    /// holding the same six strings is a rename waiting to only half happen.
    /// `landed` is whether the shell can actually answer, and `owner` is the
    /// ticket that makes it true. `placeholder` is what the empty field says
    /// once the prefix has resolved — the prototype's finding that a resolved
    /// prefix is a room you are in rather than punctuation you typed (#11 §7).
    readonly property var providers: [
        { prefix: "", id: "apps", name: "Apps", icon: "layout-grid",
          category: "App", placeholder: "Search", landed: true, owner: "#39" },
        { prefix: "=", id: "calculator", name: "Calculate",
          icon: "calculator", category: "Calculator", placeholder: "12 * 60 * 24",
          landed: true, owner: "#40" },
        // Clipboard *history* is #53, not #40 — #40 is the three providers
        // below it. The owner was wrong here from the day the table was
        // written, and it is not a comment: `unavailable()` puts it on screen,
        // so a user typing `;` was being sent to the wrong ticket.
        { prefix: ";", id: "clipboard", name: "Clipboard",
          icon: "clipboard-list", category: "Clipboard", placeholder: "Search clipboard",
          landed: false, owner: "#53" },
        { prefix: ":", id: "emoji", name: "Emoji", icon: "smile",
          category: "Emoji", placeholder: "Search emoji", landed: true, owner: "#40" },
        { prefix: "/", id: "actions", name: "Actions", icon: "command",
          category: "Action", placeholder: "Run an action", landed: true, owner: "#40" },
        { prefix: "?", id: "claude", name: "Ask Claude", icon: "sparkles",
          category: "Claude", placeholder: "Ask anything", landed: false, owner: "#41" }
    ]

    /// Whether a provider is switched on, given `launcher.providers` from the
    /// config. Unknown keys read as on: the schema fills every leaf, so a
    /// missing one means the config was not resolved rather than that the user
    /// said no, and a launcher that silently answers nothing is worse than one
    /// that ignores a key it cannot read.
    function enabled(provider: var, settings: var): bool {
        if (!provider)
            return false;
        const value = (settings ?? {})[provider.id];
        return value === undefined ? true : value === true;
    }

    /// The providers the legend lists, in table order: the ones the user has
    /// left on, minus apps — the empty prefix has no key to teach.
    function legend(settings: var): var {
        return policy.providers.filter(
            entry => entry.prefix !== "" && policy.enabled(entry, settings));
    }

    // --- routing -------------------------------------------------------------

    /// The prefix a query is in, or `""` for apps. One character, and only when
    /// a provider claims it — a query that opens with any other punctuation is
    /// an app search that happens to start with punctuation.
    ///
    /// A disabled provider does not claim its prefix, so `=2+2` with the
    /// calculator off searches apps for "=2+2" and finds nothing, rather than
    /// opening a room that is switched off.
    function prefixOf(query: string, settings: var): string {
        const text = String(query ?? "");
        if (text.length === 0)
            return "";
        const match = policy.providers.find(
            entry => entry.prefix !== "" && entry.prefix === text[0]);
        return match && policy.enabled(match, settings) ? match.prefix : "";
    }

    /// The query with the prefix taken off, and one optional space after it —
    /// `= 2+2` and `=2+2` are the same question.
    function bodyOf(query: string, settings: var): string {
        const text = String(query ?? "");
        const prefix = policy.prefixOf(text, settings);
        return prefix === "" ? text : text.slice(1).replace(/^ /, "");
    }

    /// The provider a query reaches with no prefix in front of it, or `""` for
    /// apps. One rule today: a query that opens with a digit is a sum (#40).
    ///
    /// This is the only place in the launcher where a provider is reached
    /// without the user naming it, so it is deliberately a table of one. `=` is
    /// still there for `(3+4)*2` and for `2048` when 2048 is the game — an
    /// implicit route has to be right nearly always, and "a leading digit means
    /// arithmetic" is, where "a leading bracket does" would not be.
    ///
    /// Gated on `enabled` and on `landed` for the same reason `prefixOf` gates
    /// its own: a calculator switched off in the settings must not swallow a
    /// query the apps provider would have answered.
    function impliedId(query: string, settings: var): string {
        if (!/^[0-9]/.test(String(query ?? "")))
            return "";
        const calculator = policy.providers.find(entry => entry.id === "calculator");
        return calculator && calculator.landed && policy.enabled(calculator, settings)
            ? "calculator" : "";
    }

    /// The provider a query routes to. Never null: apps is the fallback, which
    /// is what makes the empty prefix the default rather than a special case.
    function route(query: string, settings: var): var {
        const prefix = policy.prefixOf(query, settings);
        if (prefix === "") {
            const implied = policy.impliedId(query, settings);
            if (implied !== "")
                return policy.providers.find(entry => entry.id === implied);
        }
        return policy.providers.find(entry => entry.prefix === prefix)
            ?? policy.providers[0];
    }

    /// Whether the provider a query routes to will answer it at all: switched
    /// on, and landed.
    ///
    /// Apps is gated here and not in `prefixOf`, and the difference matters.
    /// A *prefixed* provider that is off does not claim its punctuation, so the
    /// query falls through to apps. Apps has no punctuation to stop claiming —
    /// it is what everything falls through to — so the only place its own
    /// `launcher.providers.apps` key can be honoured is at the point of asking
    /// for rows. Without this the key is inert: the settings tab offers a
    /// switch that turns nothing off.
    function answers(query: string, settings: var): bool {
        const provider = policy.route(query, settings);
        return provider.landed && policy.enabled(provider, settings);
    }

    /// What a provider that has not landed says instead of a list. Names the
    /// ticket, because "nothing here yet" and "nothing matched" look identical
    /// on screen and only one of them is worth waiting for.
    function unavailable(provider: var): string {
        return !provider || provider.landed
            ? ""
            : provider.name + " lands with " + provider.owner;
    }

    // --- fuzzy matching ------------------------------------------------------

    /// Subsequence score for `needle` in `hay`: every character of the needle
    /// must appear in order, and the score rewards the two things that make a
    /// match feel intended rather than incidental — hits that are adjacent, and
    /// a hit at the very start. Longer haystacks are penalised slightly so that
    /// a short exact-ish name beats a long one that merely contains the letters.
    ///
    /// `-1` for no match at all, which is the only value callers test against;
    /// an empty needle matches everything at 0, because "no query" is not a
    /// filter.
    function score(needle: string, hay: string): real {
        const want = String(needle ?? "").toLowerCase();
        const text = String(hay ?? "").toLowerCase();
        if (want.length === 0)
            return 0;
        if (text.length === 0)
            return -1;

        let at = 0;
        let total = 0;
        let previous = -1;
        for (let i = 0; i < want.length; i++) {
            at = text.indexOf(want[i], at);
            if (at < 0)
                return -1;
            total += (previous >= 0 && at === previous + 1) ? 3 : 1;
            if (at === 0)
                total += 4;
            previous = at;
            at++;
        }
        return total - text.length * 0.02;
    }

    /// How well an entry matches, across the fields a desktop file offers.
    ///
    /// The name is what the user is aiming at, so it scores at full weight; a
    /// generic name ("Web Browser") and the keyword list are how you find an
    /// app whose name you do not know, and score at a fraction so they order
    /// *within* the misses rather than jumping ahead of a name hit. Matching on
    /// them at all is the difference between typing "browser" and getting
    /// nothing.
    function scoreEntry(needle: string, entry: var): real {
        if (!entry)
            return -1;
        const want = String(needle ?? "");
        if (want.length === 0)
            return 0;

        const name = policy.score(want, entry.name ?? "");
        if (name >= 0)
            return name;

        const generic = policy.score(want, entry.genericName ?? "");
        if (generic >= 0)
            return generic * 0.5;

        const keywords = (entry.keywords ?? []).join(" ");
        const keyword = policy.score(want, keywords);
        return keyword >= 0 ? keyword * 0.25 : -1;
    }

    // --- frecency ------------------------------------------------------------
    //
    // Use counts and last-use stamps, both plain integer maps in the state file
    // (Core/StateSchema.qml). Two maps rather than one map of objects because
    // the schema coerces per leaf: `mapOf(integer)` drops a corrupt entry and
    // keeps the rest, where a map of free-form objects can only be taken whole
    // or refused whole, and this file is hand-editable ephemera.

    /// How much an app's history is worth on top of its match score.
    ///
    /// Logarithmic in the count, so the tenth launch moves the list far less
    /// than the second one does — a launcher where one heavily-used app
    /// permanently outranks a typed exact match is one you fight. Capped for
    /// the same reason: the boost is a tie-breaker between plausible matches,
    /// never a way to win against a better one.
    function frecency(id: string, uses: var, lastUsed: var, now: real): real {
        const count = Number((uses ?? {})[id] ?? 0);
        if (!(count > 0))
            return 0;

        const frequency = Math.min(4, Math.log(1 + count) * 1.6);

        // Recency, as a half-life rather than a cliff: a week-old launch is
        // worth about half a fresh one, and nothing ever falls all the way to
        // zero, so a rarely-used app keeps its place in the recents list.
        const at = Number((lastUsed ?? {})[id] ?? 0);
        const days = at > 0 ? Math.max(0, (now - at) / 86400000) : 365;
        return frequency * (0.5 + 0.5 * Math.pow(0.5, days / 7));
    }

    /// The use map after `id` is launched. Returns a new object rather than
    /// editing the one it was given: Core/SpecFile.qml deep-copies on write,
    /// and a caller that mutated its own copy first would have already changed
    /// what it is about to compare against.
    function bump(uses: var, id: string): var {
        const out = Object.assign({}, uses ?? {});
        out[id] = Number(out[id] ?? 0) + 1;
        return out;
    }

    /// The last-use map after `id` is launched.
    function stamp(lastUsed: var, id: string, now: real): var {
        const out = Object.assign({}, lastUsed ?? {});
        out[id] = Math.round(now);
        return out;
    }

    // --- the list ------------------------------------------------------------

    /// How many rows a bare launcher shows. The prototype measured that a
    /// launcher opening onto a full screen of apps is a menu, not a clearing
    /// (#11 §6) — the empty state is a short list of what you actually use.
    readonly property int recentsLimit: 6

    /// The rows for a query, ranked.
    ///
    /// With a query: match score first, frecency as the tie-breaker. Without
    /// one: frecency alone, capped at `recentsLimit`, name as the tie-break so
    /// that a first run with no history is alphabetical rather than arbitrary.
    ///
    /// Returns *every* match. Where the list stops is `fold()`, which is a
    /// question about the screen and is asked separately — a caller that wants
    /// the count of what it hid needs both numbers.
    function rank(entries: var, query: string, uses: var, lastUsed: var, now: real): var {
        const list = entries ?? [];
        const want = String(query ?? "");
        const scored = [];

        for (let i = 0; i < list.length; i++) {
            const entry = list[i];
            const match = policy.scoreEntry(want, entry);
            if (match < 0)
                continue;
            scored.push({
                entry: entry,
                match: match,
                boost: policy.frecency(entry.id, uses, lastUsed, now),
                order: i
            });
        }

        if (want.length === 0) {
            scored.sort((a, b) => b.boost - a.boost
                                || String(a.entry.name ?? "").localeCompare(String(b.entry.name ?? ""))
                                || a.order - b.order);
            return scored.slice(0, policy.recentsLimit).map(row => row.entry);
        }

        scored.sort((a, b) => (b.match + b.boost) - (a.match + a.boost)
                            || b.boost - a.boost
                            || a.order - b.order);
        return scored.map(row => row.entry);
    }

    // --- the row -------------------------------------------------------------
    //
    // Every provider hands the surface the same object, and this is it:
    //
    //     provider    which provider made it — what activation switches on
    //     id          unique within the list, and the delegate's identity
    //     title       the line the eye lands on
    //     subtitle    the quieter line under it, or ""
    //     icon        a Lucide glyph name, or ""
    //     glyph       literal text drawn in the icon slot (an emoji), or ""
    //     iconSource  an image path (a real application icon), or ""
    //     category    the label at the right-hand end of the row
    //     copy        what Enter puts on the clipboard, or ""
    //     entryId     the desktop-entry id, for the apps provider
    //     run         an action descriptor, for the actions provider
    //
    // One shape and not four, because the delegate is built once at the fold
    // count and survives every keystroke (Surfaces/Drawers/Launcher.qml): a row
    // whose *shape* changed with the provider would need a Loader per row and a
    // component swap per keystroke, which is the #75 cost the launcher was
    // built to avoid. The three icon fields are the price — exactly one is
    // ever set — and they are cheap because they are strings the delegate
    // binds to rather than items it creates.

    /// A desktop entry as a row. Pure, so `tests/` can check the mapping; the
    /// icon *path* is not here, because resolving one is `Quickshell.iconPath`
    /// and that is the far side of the line — Apps.qml adds it.
    function appRow(entry: var): var {
        if (!entry)
            return null;
        return {
            provider: "apps",
            id: "app:" + entry.id,
            title: String(entry.name ?? ""),
            subtitle: String(entry.genericName || entry.comment || ""),
            // The affordance for an app the icon theme has nothing for. It does
            // *not* warm to amber when selected — see the delegate's own note.
            icon: "box",
            glyph: "",
            iconSource: "",
            category: "App",
            copy: "",
            entryId: String(entry.id ?? ""),
            run: null
        };
    }

    // --- geometry ------------------------------------------------------------
    //
    // The clearing, as measured in #11 §6: horizon at 32% of screen height, a
    // 720px column, 46px rows, and the list capped at what fits rather than
    // running off the bottom of the screen behind the legend.

    readonly property int columnWidth: 720
    readonly property int rowHeight: 46
    readonly property real horizonFraction: 0.32

    /// The column, narrowed if the screen cannot hold it. A fixed 720 on a
    /// small output is a card wider than the screen it is centred on.
    function column(screenWidth: real, margin: real): real {
        return Math.max(240, Math.min(policy.columnWidth, screenWidth - margin * 2));
    }

    /// How many rows fit between the horizon and the legend.
    ///
    /// `chrome` is everything below the last row that still has to be on
    /// screen — the overflow label and the footer legend — and is passed in
    /// rather than assumed, because the surface is what knows how tall its own
    /// footer is. Never fewer than three: a fold that hides almost everything
    /// is worse than a launcher that overhangs slightly on a very short screen.
    function fold(screenHeight: real, chrome: real): int {
        const below = screenHeight * (1 - policy.horizonFraction) - chrome;
        return Math.max(3, Math.floor(below / policy.rowHeight));
    }

    /// What the list says where it stops. Empty when nothing was hidden, so the
    /// label's own visibility is this string being non-empty rather than a
    /// second condition that has to agree with it.
    function hidden(total: int, shown: int): string {
        const count = Math.max(0, total - shown);
        return count === 0 ? "" : count + " more";
    }

    /// What the launcher shows when it has no rows — an icon and a line, as one
    /// answer rather than two cascades that can disagree.
    ///
    /// Five silences now, and they are not the same news: a provider that has
    /// been switched off, one that has not landed, one with something of its
    /// own to say, a scan that has not finished, and a query that genuinely
    /// matched nothing. #81 is the ticket about a failure with two candidate
    /// causes; showing "No matches" for all five is how that happens on a
    /// surface.
    ///
    /// `note` is the routed provider's own silence — `qalc` missing, an emoji
    /// query that matched nothing — or null when it has none. It is passed in
    /// rather than looked up because the providers that produce one need
    /// Quickshell to know it, and this file must not; Services/Launcher/
    /// Providers.qml is what asks them and hands the answer down.
    ///
    /// It sits *after* the two questions about the provider itself and before
    /// the two about the apps scan, which is the order of scope: a provider
    /// switched off has nothing to say, and a provider that does say something
    /// is talking about a narrower thing than "no matches".
    function empty(query: string, settings: var, indexed: bool, note: var): var {
        const provider = policy.route(query, settings);

        if (!policy.enabled(provider, settings))
            return { icon: "eye-off", text: provider.name + " is switched off" };
        if (!provider.landed)
            return { icon: "hourglass", text: policy.unavailable(provider) };
        if (note)
            return note;
        if (provider.id !== "apps")
            return { icon: "circle-slash", text: "No matches" };
        if (!indexed)
            return { icon: "loader", text: "Looking for applications…" };
        return String(query ?? "").length > 0
            ? { icon: "circle-slash", text: "No matches" }
            : { icon: "circle-slash", text: "No applications found" };
    }

    // --- what the log says ---------------------------------------------------
    //
    // The wording is the contract: tools/launcher-harness.sh greps for exactly
    // these (#81, and Surfaces/Drawers/DrawerPolicy.qml makes the same argument
    // one file over).

    /// The desktop-entry model settled. Logged because it arrives
    /// asynchronously — the model is empty for the first frames of the shell's
    /// life and fills in one entry at a time, so "the launcher found no apps"
    /// and "the launcher has not finished looking" are the same picture.
    function indexed(count: int): string {
        return count + " application" + (count === 1 ? "" : "s") + " indexed";
    }

    /// An app was launched, and what it ran.
    function launched(id: string, command: string): string {
        return id + " → " + command;
    }

    /// Enter pressed on nothing. Not a warning: an empty list is a normal
    /// answer to a query, and the only thing worth recording is that the key
    /// was seen at all.
    function launchedNothing(query: string): string {
        return "nothing to launch for \"" + query + "\"";
    }

    /// A row was activated for an entry the model no longer has. Rare and
    /// real: the model is live, so an app uninstalled between the keystroke and
    /// the Enter is an id that resolves to nothing.
    function stale(id: string): string {
        return id ? "no desktop entry for " + id
                  : "asked to launch nothing at all";
    }

    /// The frecency write, with the count it wrote — the harness reads the
    /// number back out of the state file and this is what it compares against.
    function remembered(id: string, count: int): string {
        return "remembered " + id + " (" + count + ")";
    }
}
