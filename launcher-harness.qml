// A shell root that is the launcher's providers, and a way to ask them things
// (#39, #40).
//
// The launcher's *decisions* — routing, matching, frecency weighting, where
// the list stops — are pure functions with their own unit tests
// (tests/tst_launcherpolicy.qml). What cannot be reached from there is
// everything the provider is made of: `DesktopEntries` populating
// asynchronously, `Quickshell.iconPath` resolving, a launch actually launching,
// and the frecency write reaching `state.json` through Core/SpecFile.qml's
// debounce. This is that half, against real desktop files.
//
// The awkward part this exists to work around: **the harness cannot press
// Enter.** Hyprland's `sendshortcut` takes a toplevel and this shell is layer
// surfaces all the way down, so there is no key-injection path this repo may
// assume (tools/drawer-harness.sh says the same of Escape). So the keyboard
// path is driven at the seam below it — `Apps.remember()` is called directly,
// which is the function `Launcher.activate()` reaches through `Apps.launch()`.
// That tests the write and not the keystroke, and the gap is honest: what is
// unchecked is one `Keys.onReturnPressed` handler, and the alternative is an
// untested write.
//
// `launch()` is deliberately *not* exposed. A harness that runs `execute()`
// spawns real applications on the machine running it, which is the same class
// of mistake as tools/lock-harness.sh sending real passwords at the real PAM
// stack and locking the account out (#81). `runAction()` below refuses the lock
// action for exactly the same reason, and that is the whole of the difference
// between the two.
//
// ## What #40 added, and why it needs this seam
//
// Three more providers, and each one has a half that no unit test can see:
//
//   - **the calculator spawns a process.** `CalculatorPolicy` decides what to
//     run and how to read the reply; whether a `Process` on this machine
//     actually produces that reply — and, more sharply, what Quickshell does
//     when the binary is *not there* — is a question with a compositor-shaped
//     hole in it. The measured answer is that a failed spawn emits no `exited`
//     signal at all, which is a thing you can only find out by trying.
//   - **the emoji and calculator providers write the clipboard.**
//     `Quickshell.clipboardText` is the Wayland data-device protocol, so the
//     write only means anything inside a compositor.
//   - **the actions provider reaches four other singletons.** Whether
//     `Theme.setDark()` from a launcher row actually lands in `settings.json`
//     is a question about Core/SpecFile.qml's debounce, not about the table.
//
// A second entry point at the repo root rather than a file under `tools/`, for
// lock-harness.qml's reason: Quickshell takes the entry point's directory as
// the config root, and only from here does `qs.Services.Launcher` resolve to
// the real provider.
//
//   qs -p launcher-harness.qml   # inside the nested display
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Services.Launcher

ShellRoot {
    id: harness

    Component.onCompleted: {
        // Naming the singletons is what constructs them — the reason
        // Core/ServiceInit.qml exists. `Apps` starts the desktop-entry scan;
        // `ShellState` reads the file the frecency write lands in.
        ServiceInit.initDeferred();
        Logger.log("harness", "launcher harness ready");
    }

    IpcHandler {
        target: "launcher"

        /// How many applications the scan found, and whether it has finished.
        /// Two questions and not one: zero-and-still-looking is a different
        /// answer from zero-and-done, and the whole reason the count is logged
        /// at all (Services/Launcher/Apps.qml).
        function count(): int { return Apps.count; }
        function indexed(): bool { return Apps.indexed; }

        /// The ranked ids for a query, comma-separated — what the launcher
        /// would show, in the order it would show it.
        ///
        /// One line, not one per row: `qs ipc call` prints its own chatter on
        /// the same stream, so a multi-line reply cannot be told from the
        /// client's own output by a script reading it.
        function rank(query: string): string {
            return Apps.rank(query).map(entry => entry.id).join(",");
        }

        /// The id of an entry whose name starts with `text`, or "". Gives the
        /// script something real to search for without baking a package list
        /// into it — the desktop files on a CI box are not the ones here.
        function sample(text: string): string {
            const match = Apps.entries.find(
                entry => String(entry.name ?? "").toLowerCase()
                              .startsWith(String(text ?? "").toLowerCase()));
            return match ? match.id : "";
        }

        /// Whether the icon theme resolves an entry's icon. The prototype found
        /// `Quickshell.iconPath` working in a process where the entry model did
        /// not, so the two are asked separately.
        function iconFor(id: string): string {
            const entry = Apps.byId(id);
            return entry ? Quickshell.iconPath(entry.icon, true) : "";
        }

        /// Bump an app's history — the write half of a launch, without the
        /// launch. See the header.
        function remember(id: string): bool {
            Apps.remember(id);
            return true;
        }

        /// The count the shell currently believes, straight out of the state
        /// object rather than off disk, so a mismatch between the two isolates
        /// to the file write.
        ///
        /// There is deliberately no `flush()` beside it. Core/SpecFile.qml
        /// debounces its write by 250 ms and the script polls the file for
        /// longer than that — adding a public flush to Core/ShellState.qml for
        /// a harness would put a method on the shell's state singleton that
        /// only a test ever calls.
        function uses(id: string): int {
            return Number(ShellState.values.launcher.uses[id] ?? 0);
        }

        // --- the dispatcher (#40) --------------------------------------------

        /// What the launcher would show for a query, as the row ids,
        /// comma-separated. One line for the reason `rank()` gives; the ids
        /// already carry their provider, so nothing is prefixed here.
        ///
        /// The whole query, prefix and all — this is the dispatcher's own
        /// entry point, so `=2+2`, `:rocket` and `/dark` all go in here and the
        /// routing is part of what is being checked.
        function rows(query: string): string {
            return harness.queryRows(query).map(row => String(row.id)).join(",");
        }

        /// The title of one row — the line the user reads. Indexed, because a
        /// script asserting on "the first row" should not have to parse the id
        /// out of the list above.
        function title(query: string, index: int): string {
            const list = harness.queryRows(query);
            return index >= 0 && index < list.length ? String(list[index].title) : "";
        }

        /// What the launcher says when there are no rows. The whole point of
        /// #39's four-silences rule and #40's fifth: a script that could only
        /// see "no rows" could not tell a missing `qalc` from a bad sum.
        function silence(query: string): string {
            harness.prime(query);
            return String(Providers.silence(query, harness.providerSettings,
                                            Apps.indexed).text);
        }

        // --- the calculator ---------------------------------------------------

        /// Ask, without waiting. The reply is asynchronous — a process has to
        /// start, run and exit — so the script calls this, then polls `rows()`
        /// or `answer()` until it settles. A single `rows("=2+2")` returning
        /// nothing is the *correct* first answer, not a failure: `qalc` has not
        /// run yet.
        function ask(expression: string): bool {
            harness.prime("=" + expression);
            return true;
        }

        function answer(): string { return Calculator.answer; }

        /// Whether the probe found `qalc`. The check that matters on a machine
        /// without it, and the one that cannot be written as a unit test: the
        /// answer comes from a spawn that never happened.
        function calculatorReady(): bool { return Calculator.available; }
        function calculatorProbed(): bool { return Calculator.probed; }

        // --- Enter, and what it wrote -----------------------------------------

        /// Activate a row — the Enter path, minus the keystroke, exactly as
        /// `remember()` is for the apps provider.
        ///
        /// Safe for the calculator, emoji and clipboard providers, which copy.
        /// For the actions provider see `runAction()` below; for apps this
        /// refuses, because activating an app row launches it.
        function activate(query: string, index: int): bool {
            const list = harness.queryRows(query);
            if (index < 0 || index >= list.length)
                return false;
            if (list[index].provider === "apps") {
                Logger.warn("harness", "refusing to activate an app row — it would launch");
                return false;
            }
            if (list[index].provider === "actions")
                return harness.runGuarded(list[index]);
            return Providers.activate(list[index]);
        }

        /// What is on the clipboard now. Read back through Quickshell rather
        /// than through a `wl-paste` subprocess, so the assertion is about the
        /// protocol the shell actually wrote to.
        ///
        /// Text only, and that is the protocol rather than a shortcut: an image
        /// copy never passes through here — it is `cliphist decode` piped into
        /// `wl-copy`, which then *holds* the offer — so the picture half of the
        /// round trip is checked from outside, with `wl-paste --list-types`
        /// against the nested display.
        function clipboard(): string { return Quickshell.clipboardText; }

        // --- clipboard history (#53) ------------------------------------------
        //
        // The provider whose failure mode is silence. An absent `cliphist`, a
        // watcher that was never started and a genuinely empty history all
        // produce zero rows and zero bytes on stdout, so every question below is
        // asked separately rather than inferred from an empty list (#78).

        /// Whether the listing at startup found `cliphist`. The calculator's
        /// `calculatorReady()`, and it cannot be a unit test for the same
        /// reason: the answer comes from a spawn that may never have happened.
        function clipboardReady(): bool { return Clipboard.available; }
        function clipboardProbed(): bool { return Clipboard.probed; }

        /// How many entries the last listing found. Distinct from the row count
        /// for a query: a filter that matched nothing over a history of forty is
        /// not an empty history, and only one of those two is worth a sentence
        /// about the watcher.
        function clipboardCount(): int { return Clipboard.count; }

        /// The decoded thumbnail for an entry, as a file URL, or "". Arrives
        /// after the row does — one `cliphist decode` per picture — so a script
        /// polls this the way it polls the calculator's answer.
        function clipboardThumbnail(id: string): string {
            return String(Clipboard.thumbnails[id] ?? "");
        }

        // --- the actions ------------------------------------------------------

        /// Run an action by id, guarded. See `runGuarded()`.
        function runAction(id: string): bool {
            const match = Actions.rows("").find(row => row.run.id === id);
            if (!match) {
                Logger.warn("harness", "no such action: " + id);
                return false;
            }
            return harness.runGuarded(match);
        }

        /// The current mode, straight out of the config object rather than off
        /// disk, so a mismatch between the two isolates to the file write —
        /// the same split `uses()` makes for frecency.
        function dark(): bool { return Theme.dark; }

        // --- Ask Claude (#41) -------------------------------------------------
        //
        // Everything below stops short of the API by default. One real
        // question costs real money on the user's subscription and needs a
        // network, so the script asks for it explicitly (`--live`) and the
        // rest of the checks are about the parts that fail without one: the
        // preflight, the argv, the silences, and the cancel path.

        /// Whether the preflight found a logged-in, first-party CLI. The
        /// calculator's `calculatorReady()` question, and it cannot be a unit
        /// test for the same reason: the answer comes from a spawn.
        function claudeReady(): bool { return Claude.available; }
        function claudeProbed(): bool { return Claude.probed; }

        /// The argv the provider would actually build for a question, under
        /// the *resolved* config rather than a fixture.
        ///
        /// tests/tst_claudepolicy.qml already asserts the shape of this from a
        /// hand-written settings object. What it cannot see is whether
        /// Core/SettingsSchema.qml resolves to something that still produces
        /// it — a coercer that quietly dropped `launcher.claude.tools` would
        /// pass every unit test and ship an unrestricted run.
        function claudeArgv(question: string): string {
            return Claude.policy.argv(question, Config.values.launcher.claude,
                                      "00000000-0000-4000-8000-000000000000",
                                      false).join(" ");
        }

        /// Send a question, for real. The script gates this behind `--live`.
        /// Through the dispatcher rather than through `Claude.ask()`, so the
        /// routing and the settings lookup are part of what is checked.
        function askClaude(question: string): bool {
            Providers.submit("?" + question, harness.providerSettings);
            return true;
        }

        function claudeStreaming(): bool { return Claude.streaming; }
        function claudeAnswer(): string { return Claude.answer; }
        function claudeStatus(): string { return Claude.status; }
        function claudeFailure(): string { return Claude.failure; }
        function claudeSession(): string { return Claude.sessionId; }
        function claudeModel(): string { return Claude.model; }
        function claudeTurns(): int { return Claude.turns.count; }

        /// One turn, as `speaker|text`. The pipe rather than a colon because
        /// an answer is prose and will contain colons.
        function claudeTurn(index: int): string {
            if (index < 0 || index >= Claude.turns.count)
                return "";
            const turn = Claude.turns.get(index);
            return String(turn.speaker) + "|" + String(turn.text);
        }

        /// Stop a turn in flight — the Escape path, minus the keystroke, for
        /// the reason the header gives about Enter.
        function claudeCancel(): bool {
            return Providers.cancel("?", harness.providerSettings);
        }

        function claudeReset(): bool {
            Claude.reset();
            return true;
        }
    }

    readonly property var providerSettings: Config.values.launcher.providers

    /// Ask a query the way the surface does: prime first, then read.
    ///
    /// Surfaces/Drawers/Launcher.qml pushes the query into the providers from
    /// `onQueryChanged` and reads the rows from a binding. A script has no
    /// `onQueryChanged`, so a harness function that only read would be asking
    /// the calculator about an expression nobody had told it about — and would
    /// report an empty list as if that were the launcher's answer. Priming here
    /// makes one IPC call the equivalent of one keystroke settling.
    function queryRows(query: string): var {
        harness.prime(query);
        return Providers.rows(query, harness.providerSettings);
    }

    function prime(query: string): void {
        Providers.prime(query, harness.providerSettings);
    }

    /// Every action but the lock.
    ///
    /// Locking from here would lock the session running the harness — the same
    /// class of mistake as exposing `launch()`, and a worse one, because the
    /// nested session has no unlock path a script can drive (#81). The action
    /// itself is one line in Services/Launcher/Actions.qml and is checked by
    /// `tests/tst_actionspolicy.qml` reaching the descriptor; what stays
    /// unchecked is the single `SessionLock.lock()` call behind it, which is
    /// the same call tools/lock-harness.sh already drives from its own side.
    function runGuarded(row: var): bool {
        if (row.run.kind === "lock") {
            Logger.warn("harness", "refusing to run the lock action — see the header");
            return false;
        }
        return Actions.run(row.run);
    }
}
