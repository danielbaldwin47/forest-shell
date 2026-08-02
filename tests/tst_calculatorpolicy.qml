// The calculator provider's decisions (#40).
//
// The one that matters most is the last group: three outcomes — an answer, a
// refusal, and a machine with no `qalc` — told apart by exit status and by
// whether the process ever started, never by whether the output was empty.
// That is the ticket's own instruction ("must key off exit status; a failed
// spawn that reads as an empty result is the #78 shape") and the values below
// are measured, not invented: `qalc -t "frobnicate(2)"` really does exit 1
// while printing `0 B·t·m⁴`, which is why output alone cannot be the test.
import QtQuick
import QtTest
import "../Services/Launcher"

TestCase {
    id: testCase
    name: "CalculatorPolicy"

    CalculatorPolicy { id: policy }

    // --- what is a sum -------------------------------------------------------

    function test_a_leading_digit_is_arithmetic() {
        verify(policy.looksNumeric("2+2"));
        verify(policy.looksNumeric("12 * 60 * 24"));
        verify(policy.looksNumeric("0x10"));
    }

    function test_nothing_else_is() {
        verify(!policy.looksNumeric("firefox"));
        verify(!policy.looksNumeric(""));
        // The two an implicit route would have to be right about and is not:
        // `(` opens an expression far less often than it opens nothing at all,
        // and a leading minus is a dash in a package name at least as often as
        // it is a negative number. `=` is there for both.
        verify(!policy.looksNumeric("(3+4)*2"));
        verify(!policy.looksNumeric("-5 + 2"));
    }

    function test_only_a_non_empty_expression_is_evaluable() {
        verify(policy.evaluable("2+2"));
        verify(!policy.evaluable(""));
        // The guard that matters: `qalc -t ""` drops into its own REPL and
        // waits on a stdin that never arrives, which would be one process per
        // keystroke living for the length of the session.
        verify(!policy.evaluable("   "));
        // No `null` case: the `string` signature coerces one before the body
        // sees it, so whitespace is the only shape an "empty" query can
        // actually arrive in.
    }

    // --- the argv ------------------------------------------------------------

    function test_the_expression_is_one_argument() {
        const argv = policy.argv("2 + 2");
        compare(argv.length, 3);
        compare(argv[0], "qalc");
        compare(argv[1], "-t");
        compare(argv[2], "2 + 2");
    }

    function test_a_semicolon_stays_inside_the_expression() {
        // The whole reason this is argv and not a shell line: typed by the
        // user, `2+2; rm -rf ~` is a sum with a semicolon in it to qalc, and
        // two commands to `sh -c`.
        const argv = policy.argv("2+2; rm -rf ~");
        compare(argv.length, 3);
        compare(argv[2], "2+2; rm -rf ~");
    }

    function test_the_probe_evaluates_nothing() {
        const argv = policy.probeArgv();
        compare(argv[0], "qalc");
        compare(argv[1], "-v");
        compare(argv.length, 2);
    }

    // --- reading the reply ---------------------------------------------------

    function test_the_answer_is_the_first_non_empty_line() {
        compare(policy.result("17280\n"), "17280");
        compare(policy.result("\n\n  42  \n"), "42");
        compare(policy.result(""), "");
    }

    function test_an_exit_code_of_one_is_not_an_answer_however_confident() {
        // Measured: qalc prints this, on stdout, and exits 1.
        verify(!policy.answered(1, "0 B·t·m⁴\n"));
        verify(policy.answered(0, "17280\n"));
    }

    function test_success_with_no_output_is_not_an_answer_either() {
        // The one case where empty output means something, and it means the
        // same as a refusal.
        verify(!policy.answered(0, ""));
        verify(!policy.answered(0, "   \n"));
    }

    // --- the row -------------------------------------------------------------

    function test_the_result_is_the_title_and_the_thing_copied() {
        const row = policy.row("12 * 60 * 24", "17280");
        compare(row.provider, "calculator");
        compare(row.title, "17280");
        compare(row.subtitle, "12 * 60 * 24");
        compare(row.category, "Calculator");
        // Enter copies the answer, and it is the same string as the title by
        // construction rather than by two assignments that can drift.
        compare(row.copy, row.title);
        compare(row.glyph, "");
        compare(row.run, null);
    }

    // --- the silences --------------------------------------------------------

    function test_a_missing_tool_outranks_everything_about_the_sum() {
        const state = { available: false, probed: true, pending: true, failed: true };
        const said = policy.silence("2+2", state);
        compare(said.text, policy.missing());
        // Names the package, not the binary: `qalc` is not installable by that
        // name and a message that sends the reader to a package manager which
        // has never heard of it costs them a search.
        verify(said.text.indexOf("libqalculate") >= 0);
    }

    function test_an_unprobed_shell_does_not_accuse_the_machine() {
        // Optimistic until the probe answers — the first frames say "type a
        // sum", not "qalc is not installed".
        const said = policy.silence("", { available: true, probed: false,
                                          pending: false, failed: false });
        compare(said.text, "Type a sum");
    }

    function test_pending_and_failed_are_different_news() {
        const base = { available: true, probed: true };
        compare(policy.silence("2+", Object.assign({}, base,
                { pending: true, failed: false })).text, "Working…");
        verify(policy.silence("2+", Object.assign({}, base,
                { pending: false, failed: true })).text.indexOf("not a sum") >= 0);
    }

    function test_an_answered_sum_has_no_silence() {
        compare(policy.silence("2+2", { available: true, probed: true,
                                        pending: false, failed: false }), null);
    }

    // --- the log -------------------------------------------------------------

    function test_the_log_names_the_expression_and_the_exit_code() {
        compare(policy.evaluated(" 2+2 ", "4"), "2+2 = 4");
        compare(policy.refused("2+", 1), "qalc refused \"2+\" — exit 1");
        verify(policy.absent().indexOf("qalc") >= 0);
        compare(policy.found("qalc 5.12.0"), "qalc ready (qalc 5.12.0)");
        compare(policy.found(""), "qalc ready");
    }
}
