// What the Google half of the calendar *says about itself* — the sidebar's
// source row and the toolbar's sync control, decided here so that neither
// surface holds a branch.
//
// `Services/Calendar/GoogleSync.qml` imports Quickshell and is therefore
// unreachable from `tests/`; the two surfaces that read it are pictures. So the
// few words in between — which mode the block is in, what its lines say, what
// colour the dot is — live here, where they are a table anyone can check.
//
// ## One argument, named
//
// Every function takes the same object: `{status, account, lastSync, ago,
// error, connecting}`, which is `GoogleSync`'s five status properties plus
// `CalendarFormat.relativeAgo`'s answer. Elapsed time is handed in rather than
// computed because it needs `Date` and this file parses nothing. Six positional
// arguments of which four are strings is a call site nobody can read, and worse,
// one nobody can *misread loudly* — swapping `account` and `error` would type-
// check and render.
//
// ## Colours are role *names*, not colours
//
// `dot` answers with the name of a `Theme` role (`textMuted`, `accentPrimary`,
// `accentEmber`, `accentWarm`) and the surface looks it up. That is what keeps
// this file loadable by `qmltestrunner` — `Core/Theme.qml` is a Quickshell
// singleton — and it is also the honest shape: the decision here is "this is
// the urgent one", and which teal that is belongs to the palette.
//
// ## The states, and which outranks which
//
// `status` is one word (`off`, `idle`, `syncing`, `auth`, `error`) and
// `connecting` is the browser window being open. They do not overlap by
// accident: `connecting` outranks everything under it, because a person who has
// just clicked Connect is owed the answer to *that*, not the state the account
// was in before they clicked.
//
// ## Off means gone, not greyed
//
// With `calendar.google.enabled` false the shell has no Google half at all, and
// a disabled row sitting in the rail would be a permanent advertisement for a
// setting the person already found and switched off. Both the row and the
// control answer `visible: false`, and the rail closes over them.
import QtQuick

QtObject {
    id: policy

    /// The service's own name. Here rather than typed into the view so the row
    /// and the toolbar control name the same thing.
    readonly property string serviceName: "Google Calendar"

    /// What the sidebar's Google row draws — **two lines and a tile**, which is
    /// the vocabulary the *This device* row directly beneath it already
    /// established for a calendar source. The Google half is the second member
    /// of that class, not a feature with a section of its own.
    ///
    /// - `visible` — false only when the setting is off.
    /// - `mode` — `connect`, `connecting` or `account`, which is what decides
    ///   whether the row ends in a button.
    /// - `title` — the row's top line, and deliberately **the volatile one**:
    ///   what the last round did once there is an account, the state's own
    ///   words while there is not. The address is the least actionable string
    ///   here and the sync time is the only one that ever changes, so the time
    ///   takes the rank *This device* spends on its name.
    /// - `subtitle` — the dim second line: whose account it is, what went
    ///   wrong, or the service's name when the row has nothing else to say.
    ///   This is where the address lives.
    /// - `tone` — `error` when the subtitle is the failure rather than the
    ///   address, so the surface picks an ink instead of re-deciding.
    /// - `action` — the row's one button, empty where there is none. Only
    ///   *Connect*: a manual round is the toolbar's control, because it is an
    ///   action on the calendar rather than a fact about the account.
    function block(sync: var): var {
        const state = sync || ({});
        const status = state.status || "off";
        if (status === "off") {
            return {
                "visible": false, "mode": "off", "title": "",
                "subtitle": "", "tone": "muted", "action": ""
            };
        }

        // The browser is open. Said plainly, because the gap between clicking
        // Connect and finishing consent is tens of seconds of a surface that
        // would otherwise look like it swallowed the click — and the button is
        // gone while it lasts, since a second click would only log
        // "auth already running".
        if (state.connecting === true) {
            return {
                "visible": true, "mode": "connecting",
                "title": "Waiting for browser…",
                "subtitle": policy.serviceName, "tone": "muted", "action": ""
            };
        }

        // `auth` is the helper's "nobody has run the consent flow". No address
        // and no round ever finishing is the same thing said by silence — a
        // shell switched on and never connected — and it gets the same block.
        const account = state.account || "";
        if (status === "auth" || !policy.hasAccount(state)) {
            return {
                "visible": true, "mode": "connect",
                "title": "Not connected",
                "subtitle": policy.serviceName, "tone": "muted",
                "action": "Connect"
            };
        }

        // A round that failed takes the second line off the address. Both are
        // true and only one is worth two lines of a 248px rail: the address
        // never changes and cannot be acted on, and *This device* proves the
        // row still reads without one. The time above it stays the last good
        // one, so "synced 20 min ago, and failing since" survives.
        const failing = status === "error";
        const code = (state.error || "").length > 0 ? state.error : "sync failed";
        return {
            "visible": true, "mode": "account",
            "title": policy.syncedLine(status, state.ago || ""),
            // An account with no address is a token that answered the round but
            // never the address — rare, and the service's own name is a truer
            // second line than an empty one.
            "subtitle": failing
                        ? "Sync failed · " + code
                        : (account.length > 0 ? account : policy.serviceName),
            "tone": failing ? "error" : "muted",
            "action": ""
        };
    }

    /// Whether anything has ever answered for this account — an address, or a
    /// round that landed. Shared by the row and the toolbar control so the two
    /// cannot disagree about whether there is an account at all.
    function hasAccount(sync: var): bool {
        const state = sync || ({});
        return (state.account || "").length > 0
            || (state.lastSync || "").length > 0;
    }

    /// The top line of the connected row: what the last round did, or that one
    /// is happening now. An error keeps the *old* time rather than blanking
    /// it — "synced 20 min ago, and failing since" is the useful reading, and a
    /// line that emptied itself on the first failure would hide it.
    function syncedLine(status: string, ago: string): string {
        if (status === "syncing")
            return "Syncing…";
        if (!ago)
            return "Not synced yet";
        return "Synced " + ago;
    }

    /// The toolbar's sync control: whether it is drawn, which role inks its
    /// glyph, whether it pulses, and whether pressing it means anything.
    ///
    /// **It is a control, not a badge.** This used to answer a 6px dot held at
    /// 40% of the muted role, which measured 1.84:1 against the chrome band —
    /// under every text colour on the surface, including the greys, and under
    /// the 3:1 a non-text mark needs to be a mark at all. A status light nobody
    /// can see is not quiet, it is absent, and it was encoding in a second
    /// place what the rail's row already says in words. So the toolbar keeps
    /// only the *verb*: a refresh glyph in the same ghost rank the chevrons and
    /// *Today* wear, at full ink, whose colour is the one thing it adds.
    ///
    /// - `actionable` — there is an account for a manual round to run against.
    ///   Consent in flight and a shell that never connected are both false:
    ///   pressing refresh would do nothing either can use, and the rail's row
    ///   is already carrying *Connect*.
    function dot(sync: var): var {
        const state = sync || ({});
        const status = state.status || "off";
        const known = policy.hasAccount(state);
        if (status === "off")
            return { "visible": false, "role": "textMuted", "pulse": false, "actionable": false };
        if (state.connecting === true)
            return { "visible": true, "role": "accentPrimary", "pulse": true, "actionable": false };
        if (status === "syncing")
            return { "visible": true, "role": "accentPrimary", "pulse": true, "actionable": known };
        if (status === "error")
            return { "visible": true, "role": "accentEmber", "pulse": false, "actionable": known };
        if (status === "auth")
            return { "visible": true, "role": "accentWarm", "pulse": false, "actionable": false };
        return { "visible": true, "role": "textMuted", "pulse": false, "actionable": known };
    }

    /// The control's hover label. One sentence, and it always names the
    /// service: a refresh glyph on a calendar toolbar could be refreshing the
    /// grid, so a label reading only "syncing…" would be answering a question
    /// nobody could have asked.
    function dotTitle(sync: var): string {
        return policy.serviceName + " · " + policy.dotDetail(sync);
    }

    function dotDetail(sync: var): string {
        const state = sync || ({});
        const status = state.status || "off";
        if (state.connecting === true)
            return "waiting for the browser";
        if (status === "syncing")
            return "syncing…";
        if (status === "auth")
            return "not connected";
        if (status === "error")
            return (state.error || "").length > 0 ? state.error : "sync failed";
        return state.ago ? "synced " + state.ago : "not synced yet";
    }
}
