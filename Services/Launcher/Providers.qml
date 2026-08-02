pragma Singleton

// The launcher's dispatcher (#40) — one query in, one list of rows out, and one
// place that knows what Enter means on each of them.
//
//     Providers.rows(query, settings)      what the launcher should show
//     Providers.silence(query, settings)   what it says when that is empty
//     Providers.activate(row)              Enter
//
// #39 built the launcher as "a dispatcher first and a list second" but had only
// one provider to dispatch to, so the surface called `Apps` by name. This file
// is the seam that was implied by that sentence: the surface now asks *here*,
// and adding the clipboard (#53) or Ask Claude (#41) is a case in three
// switches rather than an edit to the delegate.
//
// Which provider a query is in is still LauncherPolicy.qml — that table is the
// routing rule and this file consults it, exactly as the surface used to. What
// is added here is the other half of routing: having decided which provider
// answers, ask *it*.
//
// ## Enter is not one verb
//
// The apps provider launches, the calculator and emoji providers copy, the
// actions provider runs. That is the whole reason `activate()` exists rather
// than the surface calling `Apps.launch()` on whatever it has: three verbs
// behind one key, chosen by the row and not by the surface.
//
// The clipboard write is `Quickshell.clipboardText`, which is the compositor's
// own selection through the Wayland data-device protocol — not `wl-copy`. A
// subprocess would be a dependency the shell does not otherwise have, and one
// that has to *stay alive* to serve the selection, which is a spawned process
// per copy outliving the launcher that made it.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import qs.Core

Singleton {
    id: root

    readonly property LauncherPolicy policy: LauncherPolicy {}

    /// The emoji provider, whole. It is pure — a compiled-in table and a
    /// search over it — so unlike the other three it needs no singleton of its
    /// own and no `Quickshell` anything.
    readonly property EmojiPolicy emoji: EmojiPolicy {}

    // --- what to show --------------------------------------------------------

    /// Every row for a query, unfolded. Where the list stops is the surface's
    /// question (`LauncherPolicy.fold`), asked separately for the reason #39
    /// gives: the label at the fold is a count of the difference.
    ///
    /// A provider that is switched off or has not landed returns nothing, and
    /// the reason it did shows up through `silence()` below — the two are
    /// answered by the same `LauncherPolicy` calls the surface used to make, so
    /// a query that used to say "Clipboard lands with #53" still does.
    function rows(query: string, settings: var): var {
        if (!root.policy.answers(query, settings))
            return [];

        const body = root.policy.bodyOf(query, settings);

        switch (root.policy.route(query, settings).id) {
        case "apps":       return Apps.rows(body);
        // `rowsFor` and not `rows`: the calculator answers asynchronously, and
        // a row that answers a different expression is worse than no row.
        case "calculator": return Calculator.rowsFor(body);
        case "emoji":      return root.emoji.rows(body);
        case "actions":    return Actions.rows(body);
        }
        return [];
    }

    /// Tell the providers what is being asked. Called by the surface when the
    /// query changes, and separate from `rows()` on purpose.
    ///
    /// The calculator is the one provider that cannot answer from the query
    /// alone — it has to spawn something and wait. Starting that from inside
    /// the `rows()` binding is the obvious shortcut and the wrong one: a
    /// binding that mutates the state it reads is a loop the engine has to be
    /// trusted to break, and the launcher is the surface with a 60 Hz
    /// criterion on the keystroke path. So the *question* is pushed, once per
    /// change, and the *answer* is a binding.
    ///
    /// A query that has routed away from the calculator clears it, so that
    /// coming back to `=` does not show the previous sum's answer under a new
    /// expression for a frame.
    function prime(query: string, settings: var): void {
        const routed = root.policy.route(query, settings).id;
        Calculator.ask(routed === "calculator"
                       ? root.policy.bodyOf(query, settings)
                       : "");
    }

    /// What the launcher says when `rows()` is empty. The routed provider's own
    /// silence, if it has one, handed to `LauncherPolicy.empty()` which decides
    /// whether anything wider outranks it.
    function silence(query: string, settings: var, indexed: bool): var {
        const body = root.policy.bodyOf(query, settings);
        let note = null;

        switch (root.policy.route(query, settings).id) {
        case "calculator": note = Calculator.silence(body); break;
        case "emoji":      note = root.emoji.silence(body); break;
        case "actions":    note = Actions.silence(body); break;
        }

        return root.policy.empty(query, settings, indexed, note);
    }

    // --- Enter ---------------------------------------------------------------

    /// Do whatever this row means. Returns whether the launcher should close:
    /// true for everything today, and a `bool` rather than nothing because the
    /// first provider that wants to stay open — a calculator you keep typing
    /// into, a clipboard you page through — should be able to say so without
    /// the surface learning a fourth rule.
    function activate(row: var): bool {
        if (!row) {
            Logger.log("launcher", root.policy.stale(""));
            return false;
        }

        switch (String(row.provider ?? "")) {
        case "apps": {
            const entry = Apps.byId(String(row.entryId ?? ""));
            if (!entry) {
                Logger.warn("launcher", root.policy.stale(String(row.entryId ?? "")));
                return false;
            }
            Apps.launch(entry);
            return true;
        }
        case "calculator":
        case "emoji":
            return root.copy(String(row.copy ?? ""), String(row.title ?? ""));
        case "actions":
            return Actions.run(row.run);
        }

        Logger.warn("launcher", root.policy.stale(String(row.id ?? "")));
        return false;
    }

    /// Put text on the clipboard. `what` is only for the log — a line saying
    /// `copied` and nothing else is one a harness cannot tell from the previous
    /// copy (#81).
    function copy(text: string, what: string): bool {
        if (String(text ?? "") === "") {
            Logger.warn("launcher", "nothing to copy");
            return false;
        }
        Quickshell.clipboardText = text;
        Logger.log("launcher", "copied " + text + " (" + what + ")");
        return true;
    }

    Component.onCompleted: Logger.stage("launcher providers armed")
}
