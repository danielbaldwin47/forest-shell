// What a layer rule is spelled as, and what counts as the compositor having
// taken it (#78).
//
// The shell pushed `blur, forest-shell:bar` for four PRs. Hyprland reworked
// rule syntax in the 0.5x line and answers that with `invalid field blur:
// missing a value` — and the facade logged a success line next to the call
// regardless, so the failure read as evidence of working. Both halves are
// decisions rather than pictures, so both live here; the Process wiring that
// carries them is seam 2 (tools/blur-harness.sh).
//
// The measurements the expectations below encode, taken against Hyprland 0.56.1
// in a nested session:
//
//   layerrule "blur, forest-shell:bar"                     → invalid field blur: missing a value
//   layerrule "blur 1, match:namespace ^(forest-shell:bar)$" → ok
//   layerrule "unset, match:namespace ^(forest-shell:bar)$"  → invalid field unset: missing a value
//   layerrule "notarule 1, match:namespace ^(...)$"          → invalid field type notarule
//
// and every one of those, including the refusals, exits 0.
import QtQuick
import QtTest
import "../Services/Compositor"

TestCase {
    name: "LayerRulePolicy"

    LayerRulePolicy { id: policy }

    /// The rule argument as hyprctl receives it — the whole point of the file,
    /// so most tests go through here rather than through `command`.
    function rule(name, namespace) {
        return policy.command(name, namespace)[3];
    }

    /// The `match:namespace` pattern, read back out as a real regular
    /// expression, so what is asserted is what Hyprland will match on rather
    /// than a string that looks about right.
    function pattern(name, namespace) {
        const built = rule(name, namespace);
        return new RegExp(built.slice(built.indexOf("match:namespace ")
                                      + "match:namespace ".length));
    }

    function test_a_rule_is_a_field_value_pair_and_its_own_match_clause() {
        // The current syntax, exactly. The old one — `"<rule>, <namespace>"` —
        // is not a degraded version of this; it is refused outright.
        compare(rule("blur 1", "forest-shell:bar"),
                "blur 1, match:namespace ^(forest-shell:bar)$");
    }

    function test_the_command_is_argv_for_hyprctl_keyword() {
        // No shell in the middle: a namespace is a regular expression and a
        // rule carries spaces, and neither wants quoting rules applied twice.
        const argv = policy.command("blur 1", "forest-shell:bar");
        compare(argv.length, 4);
        compare(argv[0], "hyprctl");
        compare(argv[1], "keyword");
        compare(argv[2], "layerrule");
    }

    function test_the_namespace_is_anchored_so_a_longer_one_does_not_match() {
        // Unanchored, `forest-shell:bar` also matches a future
        // `forest-shell:barsomething` — which is not hypothetical, since every
        // surface this shell adds is named under the same prefix.
        const re = pattern("blur 1", "forest-shell:bar");
        verify(re.test("forest-shell:bar"));
        verify(!re.test("forest-shell:barsomething"));
        verify(!re.test("other:forest-shell:bar"));
    }

    function test_a_namespace_is_matched_literally_not_as_a_pattern() {
        // Callers pass a namespace, not a regex — so the metacharacters a
        // namespace may contain are escaped rather than interpreted.
        const re = pattern("blur 1", "forest-shell:bar.v2");
        verify(re.test("forest-shell:bar.v2"));
        verify(!re.test("forest-shell:barxv2"));
    }

    function test_ok_is_the_only_thing_that_counts_as_applied() {
        verify(policy.accepted(0, "ok"));
        verify(policy.accepted(0, "ok\n"));
    }

    function test_a_refusal_is_a_failure_even_though_hyprctl_exits_zero() {
        // This is #78 in one line. Reading the exit code alone would have
        // called every one of the four PRs' runs a success, because hyprctl
        // exits 0 when it refuses a rule.
        verify(!policy.accepted(0, "invalid field blur: missing a value"));
        verify(!policy.accepted(0, "invalid field type notarule"));
    }

    function test_hyprctl_failing_to_run_at_all_is_a_failure_too() {
        // The other direction: no compositor to ask, or no hyprctl to ask it
        // with, which is the case an exit code does answer.
        verify(!policy.accepted(1, ""));
        verify(!policy.accepted(0, ""));
        verify(!policy.accepted(127, "ok"));
    }

    function test_the_two_log_lines_cannot_be_mistaken_for_each_other() {
        // The whole of #78's second half. A harness reads these, and so does
        // whoever is looking at a startup log wondering whether the bar's blur
        // is on — so the refusal must not contain the success line as a
        // substring, and neither must be writable without an answer to check.
        const good = policy.applied("blur 1", "forest-shell:bar");
        const bad = policy.complaint("blur 1", "forest-shell:bar", 0,
                                     "invalid field blur: missing a value", "");
        verify(good.indexOf("blur 1") >= 0);
        verify(good.indexOf("forest-shell:bar") >= 0);
        verify(bad.indexOf(good) < 0, "a refusal reads as a success line: " + bad);
    }

    function test_the_complaint_carries_the_rule_and_hyprlands_own_words() {
        // A warning that says only "layerrule failed" costs the next session
        // the same hour this one cost: the compositor's reply is the whole
        // diagnosis, and it is free to pass on.
        const said = policy.complaint("blur 1", "forest-shell:bar", 0,
                                      "invalid field blur: missing a value", "");
        verify(said.indexOf("blur 1") >= 0);
        verify(said.indexOf("forest-shell:bar") >= 0);
        verify(said.indexOf("invalid field blur: missing a value") >= 0);
    }

    function test_the_complaint_falls_back_to_stderr_then_to_saying_so() {
        const fromStderr = policy.complaint("blur 1", "forest-shell:bar", 127,
                                            "", "hyprctl: command not found");
        verify(fromStderr.indexOf("hyprctl: command not found") >= 0);
        verify(fromStderr.indexOf("127") >= 0, "the exit code is worth having when there is one");

        const silent = policy.complaint("blur 1", "forest-shell:bar", 0, "", "");
        verify(silent.length > 0);
        verify(silent.indexOf("blur 1") >= 0);
    }
}
