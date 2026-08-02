pragma Singleton

// The calculator provider (#40) — an expression in, `qalc`'s answer out.
//
//     Calculator.ask("12 * 60 * 24")     evaluate, eventually
//     Calculator.rows                     what the launcher should show
//     Calculator.silence(expression)      what it says when there is no row
//
// The decisions are CalculatorPolicy.qml next door, where `tests/` can reach
// them: what counts as a sum, what argv to build, how to read an exit code.
// What is here is the part that needs Quickshell — one `Process`, and the
// three-way distinction between an answer, a refusal, and a machine with no
// `qalc` on it.
//
// ## Why `started` is tracked
//
// Measured against Quickshell 0.3.0, a `Process` whose binary does not exist
// emits **no `exited` signal at all** — `running` simply goes false, and
// `started` never fires. So there is no exit code to key the "not installed"
// message off, and keying it off empty output instead is precisely the shape
// the ticket's maintenance pass called out: "a failed spawn that reads as an
// empty result is the #78 shape". The absence of `started` is the signal, and
// it is the only reliable one.
//
// The probe below asks the question once at startup rather than letting the
// first sum discover it. That is not an optimisation: it is the difference
// between a launcher that says "qalc is not installed" the moment you type `=`
// and one that shows "Working…" until you type the second character.
//
// ## Why it debounces
//
// `=1+` is a keystroke on the way to `=1+2`, and spawning a process for it
// costs a fork on a path whose acceptance criterion is 60 Hz while filtering.
// The timer is short enough that a finished expression answers immediately to
// the eye and long enough that a typed one spawns once.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core

Singleton {
    id: root

    readonly property CalculatorPolicy policy: CalculatorPolicy {}

    /// Whether `qalc` is on the machine. Optimistic until the probe answers,
    /// so the first frames say "Type a sum" rather than accusing a machine that
    /// has it perfectly well installed.
    property bool available: true
    property bool probed: false

    /// The expression the launcher last asked about, trimmed of its prefix by
    /// `LauncherPolicy.bodyOf`.
    property string expression: ""

    /// The answer to `expression`, or "". Cleared the moment the question
    /// changes — a stale result under a new sum is a launcher that lies for
    /// 120 ms, and Enter during that window would copy the wrong number.
    property string answer: ""

    /// The evaluation of the current expression failed. Distinct from
    /// `available`: `qalc` was there and said no.
    property bool failed: false

    /// A run is in flight or waiting for the debounce to elapse.
    readonly property bool pending: debounce.running || runner.running

    // --- asking --------------------------------------------------------------

    /// Ask about an expression. Idempotent for the same string, so the surface
    /// can bind this to the query without a run per re-evaluation of the
    /// binding.
    function ask(text: string): void {
        const next = String(text ?? "");
        if (next === root.expression)
            return;

        root.expression = next;
        root.answer = "";
        root.failed = false;

        if (!root.available || !root.policy.evaluable(next)) {
            debounce.stop();
            return;
        }
        debounce.restart();
    }

    /// The rows for the current expression — one, or none. A `var` property
    /// rather than a function so the surface's list is a binding that updates
    /// when the answer lands, which it does asynchronously.
    readonly property var rows: root.answer === ""
                                ? []
                                : [root.policy.row(root.expression, root.answer)]

    /// The rows for a *named* expression — the same list, but only if it is an
    /// answer to the question being asked.
    ///
    /// This is what the dispatcher calls, and the guard is not theoretical.
    /// `ask()` is pushed from the surface's `onQueryChanged` while the row list
    /// is a binding on the same property, and QML does not order a handler
    /// against a binding on the same change. Without this the launcher can
    /// paint one frame of the previous sum's answer under the new expression —
    /// and Enter in that frame would copy a number that answers nothing on
    /// screen.
    function rowsFor(expression: string): var {
        return String(expression ?? "") === root.expression ? root.rows : [];
    }

    /// What to say instead of a row. The provider's own state, handed to the
    /// policy — see `LauncherPolicy.empty()` for where this ends up.
    function silence(text: string): var {
        // An expression this provider has not been asked about yet counts as
        // pending, for `rowsFor()`'s reason one step further on: between the
        // keystroke and the `ask()` the honest answer is "working", not "that
        // is not a sum" — which is what the *previous* expression's `failed`
        // would otherwise say about this one.
        const asking = String(text ?? "") !== root.expression;
        return root.policy.silence(text, {
            available: root.available,
            probed: root.probed,
            pending: root.pending || asking,
            failed: root.failed && !asking
        });
    }

    // --- running -------------------------------------------------------------

    Timer {
        id: debounce

        interval: 120
        onTriggered: root.run()
    }

    /// Start a run, or queue one behind the run in flight. Assigning a command
    /// to a running `Process` kills it (Services/Compositor/Compositor.qml), so
    /// the in-flight one is allowed to finish and `onExited` picks up whatever
    /// the question has become by then — which is the right answer anyway,
    /// because it is the one the user is looking at.
    function run(): void {
        if (runner.running)
            return;
        if (!root.policy.evaluable(root.expression))
            return;

        runner.asked = root.expression;
        runner.started = false;
        runner.command = root.policy.argv(root.expression);
        runner.running = true;
    }

    Process {
        id: runner

        /// The expression this run is answering. Kept because the reply arrives
        /// after the fact and says nothing about which question it is for — the
        /// user has typed two more characters by then, and applying an old
        /// answer to a new sum is the bug this field exists to make impossible.
        property string asked: ""

        /// Whether the process ever got as far as existing. See the header.
        property bool started: false

        stdout: StdioCollector { id: out }

        onStarted: runner.started = true

        onExited: (exitCode, exitStatus) => {
            if (runner.asked === root.expression) {
                if (root.policy.answered(exitCode, out.text)) {
                    root.answer = root.policy.result(out.text);
                    root.failed = false;
                    Logger.log("launcher",
                               root.policy.evaluated(runner.asked, root.answer));
                } else {
                    root.answer = "";
                    root.failed = true;
                    Logger.log("launcher", root.policy.refused(runner.asked, exitCode));
                }
            }

            // The question moved while this run was out. Answer the new one
            // rather than leaving the launcher on a result for a sum nobody is
            // looking at any more.
            if (runner.asked !== root.expression)
                root.run();
        }

        onRunningChanged: {
            // False without ever having started: the binary is not there. The
            // one case with no exit code to read, and the reason this handler
            // exists at all.
            if (runner.running || runner.started)
                return;
            root.available = false;
            root.probed = true;
            root.answer = "";
            root.failed = false;
            Logger.warn("launcher", root.policy.absent());
        }
    }

    // --- is it even installed ------------------------------------------------

    Process {
        id: probe

        command: root.policy.probeArgv()
        // A `Process` does nothing until it is told to run — the point
        // Services/Hardware/Backlight.qml makes about a probe that only ever
        // declared its command.
        running: true

        property bool started: false

        stdout: StdioCollector { id: probeOut }

        onStarted: probe.started = true

        onExited: (exitCode, exitStatus) => {
            root.probed = true;
            root.available = root.policy.accepted(exitCode);
            if (root.available)
                Logger.log("launcher", root.policy.found(probeOut.text));
            else
                Logger.warn("launcher", root.policy.absent());
        }

        onRunningChanged: {
            if (probe.running || probe.started)
                return;
            root.probed = true;
            root.available = false;
            Logger.warn("launcher", root.policy.absent());
        }
    }

    Component.onCompleted: Logger.stage("calculator provider armed")
}
