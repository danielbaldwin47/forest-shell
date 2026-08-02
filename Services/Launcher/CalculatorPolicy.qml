// The calculator provider's decisions (#40) — what counts as a sum, what to
// run, and how to read what comes back.
//
// `qalc` does the arithmetic. This file never does any: it decides whether a
// query is arithmetic at all, builds the argv, and turns an exit code plus a
// stream of text into one of three answers — a result, a refusal, or "the tool
// is not installed". Services/Launcher/Calculator.qml owns the `Process`, and
// nothing else here needs Quickshell, so `tests/` can reach the whole decision.
//
// ## Why the exit code is the only thing trusted
//
// The ticket's maintenance pass named the shape to avoid: "a failed spawn that
// reads as an empty result is the #78 shape" — a layerrule Hyprland refused,
// reported as applied. Measured against Quickshell 0.3.0, the three outcomes
// are told apart like this:
//
//   qalc present, sum fine      started → exited(0),  answer on stdout
//   qalc present, sum bad       started → exited(1),  *also* text on stdout
//   qalc not installed          neither signal — only `running` going false
//
// The middle row is why output is never the test: `qalc -t "frobnicate(2)"`
// exits 1 and still prints `0 B·t·m⁴`, confidently. The bottom row is why
// `started` is tracked at all — a spawn that never happened produces no exit
// code to key off, so the absence of the signal *is* the signal.
//
// ## Two ways in
//
// `=2+2` is the prefix, and a leading digit is the same question asked without
// one — `12 * 60 * 24` is not an application name, and requiring punctuation in
// front of it is the launcher making the user say what it can already see (#9).
// The routing for that lives in LauncherPolicy.qml, because it is a decision
// about which provider a query is in and that table is the whole routing rule;
// what is here is the test it consults.
import QtQuick

QtObject {
    id: policy

    /// The binary. Named once, because it appears in the argv, in the probe and
    /// in the sentence the user reads when it is missing, and a shell that
    /// spells its dependency two ways in three places installs the wrong one.
    readonly property string tool: "qalc"

    // --- what is a sum -------------------------------------------------------

    /// Whether a *bare* query — no prefix in front of it — should be read as
    /// arithmetic. A leading digit, and nothing else: an expression starting
    /// with `(` or `-` is far rarer than an app whose name does, and `=` is
    /// there for exactly that case.
    ///
    /// The cost is that an application whose name opens with a digit ("2048")
    /// is reached by typing a letter of it instead. That is the trade #9 made
    /// when it fixed the prefixes, and it is cheap in the direction that
    /// matters: a sum is what the leading digit almost always means.
    function looksNumeric(query: string): bool {
        return /^[0-9]/.test(String(query ?? ""));
    }

    /// Whether there is anything to evaluate. Guards the argv below: `qalc -t`
    /// with an empty expression drops into its own REPL and waits on a stdin
    /// that never comes, which is a process the shell would keep alive per
    /// keystroke for the length of the session.
    function evaluable(expression: string): bool {
        return String(expression ?? "").trim().length > 0;
    }

    /// What to run. `-t` is terse: the answer alone, without the echoed
    /// expression and the units commentary that the interactive form prints.
    ///
    /// The expression is one argv element, never interpolated into a shell
    /// line — the argument Surfaces/Drawers/SessionPolicy.qml makes for session
    /// commands, and it is sharper here because this string is *typed by the
    /// user*: `2+2; rm -rf ~` is a sum with a semicolon in it to `qalc`, and a
    /// second command to `sh -c`.
    function argv(expression: string): var {
        return [policy.tool, "-t", String(expression ?? "").trim()];
    }

    /// The probe, run once at startup so that "not installed" is known before
    /// the first sum rather than discovered by it. `-v` prints a version and
    /// exits; it touches no config and evaluates nothing.
    function probeArgv(): var {
        return [policy.tool, "-v"];
    }

    // --- reading the reply ---------------------------------------------------

    function accepted(exitCode: int): bool {
        return exitCode === 0;
    }

    /// The answer, out of a terse reply. First non-empty line: `-t` prints one,
    /// but a warning ahead of it is possible and the answer is what follows.
    function result(stdout: string): string {
        const lines = String(stdout ?? "").split("\n");
        for (const line of lines) {
            const trimmed = line.trim();
            if (trimmed.length > 0)
                return trimmed;
        }
        return "";
    }

    /// Whether a reply is worth showing. An exit of 0 with nothing on stdout is
    /// not an answer — it is the one case where empty output is meaningful,
    /// and it means the same as a refusal.
    function answered(exitCode: int, stdout: string): bool {
        return policy.accepted(exitCode) && policy.result(stdout) !== "";
    }

    // --- the row -------------------------------------------------------------

    /// The single row a successful evaluation becomes.
    ///
    /// The result is the *title* and the expression is the subtitle, which is
    /// the opposite of the apps provider and deliberate: what you want from a
    /// calculator is the number, at the size the eye lands on first. Enter
    /// copies it, so `copy` and the title are the same string by construction
    /// rather than by two assignments that can drift.
    function row(expression: string, answer: string): var {
        return {
            provider: "calculator",
            id: "calculator:" + expression,
            title: answer,
            subtitle: String(expression ?? "").trim(),
            icon: "equal",
            glyph: "",
            iconSource: "",
            category: "Calculator",
            copy: answer,
            entryId: "",
            run: null
        };
    }

    // --- the silences --------------------------------------------------------
    //
    // Four, and they are not the same news — the argument LauncherPolicy.empty()
    // makes for the apps provider, and the reason this returns an icon and a
    // line together rather than letting the surface pick an icon per case.

    /// What the calculator says instead of a row, or `null` when it has one.
    ///
    /// `state` is the provider's own: `{ available, probed, pending, failed }`.
    /// Order matters and is the order of certainty — a missing tool is a fact
    /// about the machine and outranks anything about this particular sum.
    function silence(expression: string, state: var): var {
        const it = state ?? {};

        if (it.probed === true && it.available === false)
            return { icon: "circle-slash", text: policy.missing() };
        if (!policy.evaluable(expression))
            return { icon: "equal", text: "Type a sum" };
        if (it.pending === true)
            return { icon: "loader", text: "Working…" };
        if (it.failed === true)
            return { icon: "circle-slash", text: "That is not a sum " + policy.tool
                                                 + " can do" };
        return null;
    }

    /// The sentence for a machine with no `qalc` on it. Names the package
    /// rather than the binary: `qalc` is not installable by that name, and a
    /// message that sends the reader to a package manager which has never heard
    /// of it is a message that costs a search.
    function missing(): string {
        return policy.tool + " is not installed (package: libqalculate)";
    }

    // --- what the log says ---------------------------------------------------
    //
    // The wording is the contract: tools/launcher-harness.sh greps for exactly
    // these.

    function evaluated(expression: string, answer: string): string {
        return String(expression ?? "").trim() + " = " + answer;
    }

    function refused(expression: string, exitCode: int): string {
        return policy.tool + " refused \"" + String(expression ?? "").trim()
            + "\" — exit " + exitCode;
    }

    /// The spawn that never happened. A warning and not a log line: every sum
    /// typed from here on is a silence, and this is the only place the reason
    /// is written down.
    function absent(): string {
        return "no " + policy.tool + " on PATH — the calculator is inert";
    }

    function found(version: string): string {
        const trimmed = String(version ?? "").trim();
        return trimmed === "" ? policy.tool + " ready" : policy.tool + " ready (" + trimmed + ")";
    }
}
