// A shell root that is the apps provider, and a way to ask it things (#39).
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
// stack and locking the account out (#81).
//
// A second entry point at the repo root rather than a file under `tools/`, for
// lock-harness.qml's reason: Quickshell takes the entry point's directory as
// the config root, and only from here does `qs.Services.Launcher` resolve to
// the real provider.
//
//   qs-upstream -p launcher-harness.qml   # inside the nested display
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
    }
}
