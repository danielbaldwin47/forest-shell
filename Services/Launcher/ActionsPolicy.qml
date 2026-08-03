// The actions provider's decisions (#40) — what the shell can be asked to do
// from `/`, what each row says, and which door it goes through.
//
// This is the ticket's "scriptable spine": the set of shell-internal verbs that
// are not a window and not an application, gathered in one table so that the
// launcher, a keybind and a script are all reaching the same list. Everything
// here is data and filtering; Services/Launcher/Actions.qml runs them.
//
// ## Three rules the maintenance pass on #40 fixed in advance
//
//   - **Settings actions dispatch `open` and `showTab`, never `show`.** `qs ipc
//     call settings show` is parsed by the client as its own `show` subcommand,
//     prints the target listing and exits 0 — #77, and Core/SurfaceBusPolicy.qml
//     holds the reserved list. A row here that named `show` would be a row
//     nobody could bind a key to, so `tests/tst_actionspolicy.qml` checks every
//     verb in this table against that list.
//   - **The tab list is passed in, not copied here.** Surfaces/Settings/
//     SettingsTabs.qml is the registry and it lives on the far side of the
//     Quickshell line; a second copy of ten ids in this file is a tab that
//     silently loses its action the day someone renames one. `catalogue()`
//     takes them as an argument, which also lets `tests/` hand it three.
//   - **The dark/light row is a caller, not an owner.** Core/Theme.qml already
//     owns the mode — `Theme.setDark()`, with its own comment saying the key
//     name lives there and the Dark/Light tile stays a tile. #44's tile and
//     #58's mode switch are callers of the same function. So this table holds a
//     row that asks Theme to flip, and no state of its own; the overlap the
//     ticket asked to resolve resolves to "there is one owner and it landed
//     with #34".
//
// ## What is deliberately not here
//
// Log out, suspend, restart and shut down. #40's acceptance criterion asks for
// "session menu", and that is also the safer reading of the prose's "session
// verbs": the session menu orders its rows least-destructive-first precisely
// because a mis-aimed press should not end the session
// (Surfaces/Drawers/SessionPolicy.qml), and a fuzzy-matched launcher row that
// shuts the machine down on one Enter throws that away. `/session` opens the
// menu, which is one more keystroke and the whole of the protection. Locking is
// the exception and is here directly: it is the one session action that cannot
// lose work, and it is what the menu opens on for the same reason.
//
// Imports nothing but QtQuick, so `tests/` can reach it.
import QtQuick

QtObject {
    id: policy

    readonly property LauncherPolicy base: LauncherPolicy {}

    /// The verbs this table is allowed to name, mirrored from
    /// Core/SurfaceBusPolicy.qml. Stated rather than imported: that file is in
    /// Core/ and this one is in Services/, and a cross-directory import for
    /// three strings would be a dependency in the wrong direction. The test
    /// imports both and checks they still agree, which is where a divergence
    /// should be caught.
    readonly property var reservedVerbs: ["show", "list", "call"]

    // --- the table -----------------------------------------------------------

    /// Every action, given what the shell currently is.
    ///
    /// `context` is `{ dark, settingsTabs }` — the mode the theme is in, and
    /// Surfaces/Settings/SettingsTabs.qml's own list. Both are passed rather
    /// than read, for the reason `LauncherPolicy.rank()` takes `now`: a pure
    /// function that reaches for the current state is one `tests/` cannot pose.
    ///
    /// Each entry carries `kind` and `arg` — what Actions.qml switches on — and,
    /// where the shell has an IPC door for the same thing, the `target`/`verb`
    /// that reaches it. Those two are not plumbing: they are what makes this a
    /// spine rather than a menu, and they are what the reserved-verb test reads.
    function catalogue(context: var): var {
        const it = context ?? {};
        const dark = it.dark === true;
        const tabs = it.settingsTabs ?? [];

        const list = [
            {
                id: "theme.toggle",
                // The title says what will happen, not what is true now. A row
                // reading "Dark mode" in a list you are about to press Enter on
                // is ambiguous in exactly the way a toggle must not be.
                title: dark ? "Switch to light mode" : "Switch to dark mode",
                subtitle: "Appearance",
                icon: dark ? "sun" : "moon",
                // Deliberately *not* "appearance": that is the name of a
                // settings tab, and both rows claiming it exactly put the
                // mode toggle above the page the word actually names.
                keywords: ["theme", "dark", "light", "mode", "toggle"],
                kind: "theme",
                arg: "",
                target: "",
                verb: ""
            },
            {
                id: "session.lock",
                title: "Lock the screen",
                subtitle: "Session",
                icon: "lock",
                keywords: ["lock", "screen", "away", "secure"],
                kind: "lock",
                arg: "",
                target: "",
                verb: ""
            },
            {
                id: "screenshot.region",
                title: "Take a screenshot",
                subtitle: "Select a region or click a window",
                icon: "crop",
                keywords: ["screenshot", "screen", "shot", "capture", "grab",
                           "region", "snip", "crop", "print"],
                // Not `surface`, and for the reason `session.lock` is not
                // either: the bus is the door for *panels* a bar button opens,
                // and every verb it dispatches is `toggle()`. Asking a picker
                // to toggle mid-drag would throw the drag away, so this goes
                // straight to the service the same way the lock row does.
                kind: "screenshot",
                arg: "",
                target: "screenshot",
                verb: "open"
            },
            {
                id: "session.menu",
                title: "Session menu",
                // Names what is behind it, because the four verbs that are not
                // here are the reason to open it — see the header.
                subtitle: "Log out, suspend, restart, shut down",
                icon: "power",
                keywords: ["session", "logout", "log out", "suspend", "sleep",
                           "restart", "reboot", "shutdown", "shut down", "power", "quit"],
                kind: "surface",
                arg: "session",
                target: "session",
                verb: "toggle"
            },
            {
                id: "settings.open",
                title: "Open settings",
                subtitle: "Settings",
                icon: "settings",
                keywords: ["settings", "preferences", "config", "options"],
                kind: "settings",
                arg: "",
                // Not `show`, and this is the row the rule was written for.
                target: "settings",
                verb: "open"
            }
        ];

        for (const tab of tabs) {
            list.push({
                id: "settings." + tab.id,
                title: "Settings — " + tab.title,
                subtitle: policy.tabHint(tab),
                icon: tab.icon,
                keywords: ["settings", tab.id, tab.title.toLowerCase()]
                    .concat(policy.tabKeywords(tab.id)),
                kind: "settings",
                arg: tab.id,
                target: "settings",
                verb: "showTab"
            });
        }

        return list;
    }

    /// The subtitle for a settings row. An unbuilt tab says so rather than
    /// opening a page that explains itself only once you are on it — the same
    /// honesty Surfaces/Settings/SettingsTabs.qml's `built` flag buys the rail,
    /// applied one surface earlier.
    function tabHint(tab: var): string {
        return (tab && tab.built === true) ? "Settings" : "Settings — not built yet";
    }

    /// The words that reach a tab but are not in its name. Only where the gap
    /// is real: nobody types "appearance" looking for the wallpaper, and
    /// "wallpaper" is one of the four things #40 names outright.
    function tabKeywords(id: string): var {
        switch (id) {
        case "appearance":     return ["theme", "colour", "color", "accent", "font"];
        case "wallpaper":      return ["background", "image", "desktop", "picture"];
        case "bar":            return ["panel", "top", "status"];
        case "launcher":       return ["providers", "search", "prefix"];
        case "notifications":  return ["toast", "popup", "do not disturb", "dnd"];
        case "controlCenter":  return ["control", "centre", "center", "toggles"];
        case "weatherTime":    return ["clock", "weather", "temperature", "time"];
        case "system":         return ["session", "commands", "idle", "lock"];
        case "about":          return ["version", "credits", "changelog"];
        default:               return [];
        }
    }

    // --- matching ------------------------------------------------------------

    readonly property real exactTitle: 10000
    readonly property real exactKeyword: 1000

    /// How well an action matches, as the ladder EmojiPolicy uses: the title
    /// exactly, a keyword exactly, the title fuzzily, a keyword fuzzily.
    ///
    /// The exact rungs earn their place here for a different reason than they
    /// do over there. Emoji names are prose; action titles are short. What
    /// makes this table need them is that eleven of its rows *begin with the
    /// same word*: measured, `/settings` put "Settings — Bar" above "Open
    /// settings", because the fuzzy scorer pays a bonus for a hit at position
    /// zero and the tab rows have one. Typing the name of a window and being
    /// offered its third tab is the ranking losing to its own tie-breaker.
    ///
    /// Ties are broken by table order, which is why `settings.open` — earlier
    /// in the catalogue than any tab — wins the exact-keyword rung outright.
    function scoreAction(needle: string, action: var): real {
        if (!action)
            return -1;
        const want = String(needle ?? "").toLowerCase().trim();
        if (want.length === 0)
            return 0;

        if (String(action.title ?? "").toLowerCase() === want)
            return policy.exactTitle;

        const keywords = action.keywords ?? [];
        for (const keyword of keywords) {
            if (String(keyword).toLowerCase() === want)
                return policy.exactKeyword;
        }

        const title = policy.base.score(want, action.title ?? "");
        if (title >= 0)
            return title;

        let best = -1;
        for (const keyword of keywords) {
            const hit = policy.base.score(want, keyword);
            if (hit > best)
                best = hit;
        }
        return best >= 0 ? best * 0.4 : -1;
    }

    /// The actions a query matches, ranked. Table order breaks ties, which is
    /// why the four hand-written rows are first: an empty `/` should open on
    /// the things you meant, not on the eleventh settings tab.
    function search(query: string, context: var): var {
        const want = String(query ?? "");
        const list = policy.catalogue(context);
        if (want.length === 0)
            return list;

        const scored = [];
        for (let i = 0; i < list.length; i++) {
            const hit = policy.scoreAction(want, list[i]);
            if (hit < 0)
                continue;
            scored.push({ action: list[i], hit: hit, order: i });
        }

        scored.sort((a, b) => b.hit - a.hit || a.order - b.order);
        return scored.map(row => row.action);
    }

    /// One row per matching action. `run` is the descriptor Actions.qml
    /// switches on, carried whole so that the row is self-contained — the
    /// surface hands back what it was given rather than looking the action up
    /// again by an id that may by then match a different row.
    function rows(query: string, context: var): var {
        return policy.search(query, context).map(action => ({
            provider: "actions",
            id: "action:" + action.id,
            title: action.title,
            subtitle: action.subtitle,
            icon: action.icon,
            glyph: "",
            iconSource: "",
            category: "Action",
            copy: "",
            entryId: "",
            run: { id: action.id, kind: action.kind, arg: action.arg,
                   target: action.target, verb: action.verb }
        }));
    }

    function silence(query: string): var {
        return String(query ?? "").length === 0
            ? null
            : { icon: "circle-slash", text: "No action for \"" + query + "\"" };
    }

    /// Whether a verb can actually be typed at `qs ipc call`. The same question
    /// Core/SurfaceBusPolicy.qml asks of a surface, asked of an action — and an
    /// empty verb passes, because "this action has no IPC door" is a different
    /// statement from "this action has one nobody can open".
    function callable(verb: string): bool {
        return policy.reservedVerbs.indexOf(String(verb ?? "")) < 0;
    }

    // --- what the log says ---------------------------------------------------

    function ran(id: string, detail: string): string {
        return id + (detail !== "" ? " → " + detail : "");
    }

    function unknown(id: string): string {
        return "no such action: " + (id !== "" ? id : "(none)");
    }
}
