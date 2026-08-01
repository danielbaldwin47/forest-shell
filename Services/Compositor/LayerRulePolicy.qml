// How a layer rule is spelled, and how to tell whether the compositor took it
// (#78).
//
// Both are decisions, so both are here rather than in the facade next door:
// Compositor.qml imports Quickshell and is unreachable from `tests/`, and this
// file imports nothing but QtQuick. What is left on the far side of the line is
// the Process that carries the words — see tools/blur-harness.sh.
//
// Two things this exists to remember, both measured against Hyprland 0.56.1:
//
//   - **A rule is a `<field> <value>` pair, and the match is its own clause.**
//     Hyprland reworked rule syntax in the 0.5x line. The old
//     `"blur, forest-shell:bar"` is not a degraded form of the new one, it is
//     refused: `invalid field blur: missing a value`. Boolean rules need the
//     value spelled out, so blur on is `blur 1` and blur off is `blur 0` —
//     there is no `unset` any more (it answers `invalid field unset`), which
//     means a rule is turned off by pushing the opposite rule over it, not by
//     clearing it.
//
//   - **`hyprctl` exits 0 when it refuses a rule.** Every refusal above exits
//     0 with its complaint on stdout. So the exit code cannot be the test —
//     the reply text is the only evidence there is that anything happened. The
//     exit code is still read, because a hyprctl that could not be run at all
//     is the other way this fails and the only way that shows up there.
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    /// The argv for pushing `rule` at `namespace`, live.
    ///
    /// argv rather than a command line: a namespace becomes a regular
    /// expression and a rule carries a space, and neither wants a shell's
    /// quoting rules applied on top of Hyprland's.
    function command(rule: string, namespace: string): var {
        return ["hyprctl", "keyword", "layerrule",
                rule + ", match:namespace ^(" + literal(namespace) + ")$"];
    }

    /// A namespace is a name, not a pattern — anchored, so `forest-shell:bar`
    /// does not also claim a future `forest-shell:barsomething`, and escaped,
    /// so a `.` in a namespace matches a dot rather than anything at all.
    function literal(text: string): string {
        return String(text).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }

    /// Did the compositor apply it? `ok` is the whole of Hyprland's yes.
    function accepted(exitCode: int, output: string): bool {
        return exitCode === 0 && String(output ?? "").trim() === "ok";
    }

    /// What to say when it did. Both log lines live here rather than at the
    /// call site because a harness asserts on them (tools/blur-harness.sh) —
    /// and because the pair is the decision: for four PRs the shell wrote this
    /// line unconditionally, which is what made a refusal read as evidence of
    /// working.
    function applied(rule: string, namespace: string): string {
        return "layerrule " + rule + " → " + namespace;
    }

    /// What to say when it did not. The compositor's own words are the
    /// diagnosis and cost nothing to pass on; #78 survived four PRs because a
    /// line that said only "layerrule blur → forest-shell:bar" read exactly
    /// like one that had worked.
    function complaint(rule: string, namespace: string, exitCode: int,
                       output: string, error: string): string {
        const said = String(output ?? "").trim() || String(error ?? "").trim()
                   || "no reply";
        const code = exitCode === 0 ? "" : " (hyprctl exited " + exitCode + ")";
        return "hyprland refused layerrule \"" + rule + "\" for "
             + namespace + ": " + said + code;
    }
}
