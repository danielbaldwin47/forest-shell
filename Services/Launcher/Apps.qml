pragma Singleton

// The apps provider (#39) — desktop entries in, a launched process and a
// remembered use count out.
//
//     Apps.entries                  every application, live
//     Apps.rank("fire")             what the launcher should show
//     Apps.launch(entry)            run it, and remember that you did
//
// The ranking itself is not here: matching, frecency weighting and where the
// list stops are decisions, and they live in LauncherPolicy.qml next door,
// where `tests/` can reach them. What is here is the part that needs Quickshell
// — the desktop-entry model, the launch, and the state file.
//
// ## The model arrives late, and empty means "still looking"
//
// `DesktopEntries.applications` is populated asynchronously, one entry at a
// time, *after* the singleton is first observed. Reading `.values.length` at
// `Component.onCompleted` — or from a timer a second and a half later — returns
// 0 with 190 desktop files on disk, which is what the launcher prototype hit and
// recorded as unexplained (#11, "bake a fixture rather than trusting the
// model"). It is not unexplained: a *declarative* binding on the model fires
// once per entry as the scan streams in, and settles at the real count. So the
// model is bound, never polled, and the count is logged once it stops moving —
// because "found no apps" and "has not finished looking" are otherwise the same
// picture (#81).
//
// ## What remembering costs
//
// The use counts live in `state.json`, not `settings.json`: they are ephemera
// the shell writes on its own, and the portability test in Core/StateSchema.qml
// puts them there. Two integer maps rather than one map of objects, because the
// state file is hand-editable and `mapOf(integer)` drops a corrupt entry while
// keeping the rest.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import qs.Core

Singleton {
    id: root

    readonly property LauncherPolicy policy: LauncherPolicy {}

    /// Every application, live. Bound rather than copied: the model is the
    /// authority and it changes when a package is installed, so a snapshot
    /// taken once is a launcher that goes stale until the shell restarts.
    readonly property var entries: DesktopEntries.applications.values

    readonly property int count: root.entries.length

    /// True once the scan has stopped streaming. The launcher shows its empty
    /// state on this rather than on `count === 0`, which is also true for the
    /// first frames of every start.
    property bool indexed: false

    // --- what the launcher shows ---------------------------------------------

    /// The rows for a query, ranked — match first, then how much you use it.
    ///
    /// `Date.now()` is read here rather than passed in, because the recency
    /// half of frecency is a fact about now and every caller would otherwise
    /// have to supply the same one. The policy takes it as an argument so that
    /// `tests/` can hold the clock still.
    function rank(query: string): var {
        return root.policy.rank(root.entries, query,
                                ShellState.values.launcher.uses,
                                ShellState.values.launcher.lastUsed,
                                Date.now());
    }

    /// The same ranking, as launcher rows — the shape every provider hands the
    /// surface (`LauncherPolicy`'s row section).
    ///
    /// The mapping is in the policy so `tests/` can check it; the icon *path*
    /// is added here, because resolving one is `Quickshell.iconPath` and that
    /// is the whole of what keeps this function on this side of the line. The
    /// second argument asks for "" rather than a fallback glyph when the theme
    /// has nothing: the delegate draws its own affordance in that case, and a
    /// theme's generic placeholder would look like an icon the app chose.
    ///
    /// `rank()` stays beside it rather than being folded in. It is what
    /// launcher-harness.qml asks over IPC — ids in order, with nothing between
    /// the ranking and the assertion — and a harness that had to unwrap a row
    /// to check an order would be testing the wrapper.
    function rows(query: string): var {
        return root.rank(query).map(entry => {
            const row = root.policy.appRow(entry);
            row.iconSource = entry.icon ? Quickshell.iconPath(entry.icon, true) : "";
            return row;
        });
    }

    // --- launching -----------------------------------------------------------

    /// Run an entry and remember it.
    ///
    /// `DesktopEntry.execute()` rather than a `Process` on `execString`: the
    /// exec line is not a command, it is a template with field codes (`%u`,
    /// `%F`) in it, and it may want a terminal (`Terminal=true`) or D-Bus
    /// activation. Splitting the string ourselves — which is what
    /// Surfaces/Drawers/SessionPolicy.qml correctly does for a *config* value —
    /// would launch `firefox %u` with a literal `%u` argument.
    function launch(entry: var): void {
        if (!entry) {
            Logger.warn("launcher", root.policy.stale(""));
            return;
        }

        Logger.log("launcher", root.policy.launched(entry.id, entry.execString ?? ""));
        entry.execute();
        root.remember(entry.id);
    }

    /// Bump an app's history. Split out of `launch` so the write can be driven
    /// on its own from tools/launcher-harness.sh — the harness cannot press
    /// Enter (there is no key-injection tool this repo may assume), and a
    /// frecency write nothing can reach is a frecency write nobody checks.
    function remember(id: string): void {
        const uses = root.policy.bump(ShellState.values.launcher.uses, id);
        ShellState.set("launcher.uses", uses);
        ShellState.set("launcher.lastUsed",
                       root.policy.stamp(ShellState.values.launcher.lastUsed,
                                         id, Date.now()));
        Logger.log("launcher", root.policy.remembered(id, uses[id]));
    }

    /// The entry for an id, or null. The model is live, so an app uninstalled
    /// between the keystroke and the Enter is an id that resolves to nothing —
    /// rare, real, and quieter to answer than to crash on.
    function byId(id: string): var {
        return root.entries.find(entry => entry.id === id) ?? null;
    }

    // --- the count settles ---------------------------------------------------
    //
    // One line, not sixty-six. The scan notifies per entry, so this waits for
    // it to stop moving rather than logging each arrival.

    onCountChanged: settle.restart()

    Timer {
        id: settle
        interval: 250
        onTriggered: {
            root.indexed = true;
            Logger.log("launcher", root.policy.indexed(root.count));
        }
    }

    Component.onCompleted: Logger.stage("apps provider armed")
}
