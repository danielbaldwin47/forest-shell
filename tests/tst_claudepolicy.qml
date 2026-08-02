// The Ask Claude provider's decisions (#41).
//
// Four groups, and they are the four things the ticket said the risk lives in:
// the argv (what the run is *allowed* to be), the reduction of a stream-json
// line into an answer, the deadline ladder, and `permission_denials[]`.
//
// The values here are not invented. They are the measured shapes from
// `.wayfinder/research/claude-cli-contract.md` — including the two that a
// reasonable implementation gets wrong on the first try: a `result` line can
// carry `subtype: "success"` while `is_error` is true, and a denial produces
// no error event and no non-zero exit at all.
import QtQuick
import QtTest
import "../Services/Launcher"

TestCase {
    id: testCase
    name: "ClaudePolicy"

    ClaudePolicy { id: policy }

    // The shipped defaults, as Core/SettingsSchema.qml resolves them. Spelled
    // out rather than imported so that a change to the schema shows up here as
    // a failing test rather than as a silently different argv.
    readonly property var settings: ({
        model: "haiku",
        effort: "medium",
        tools: ["WebSearch", "WebFetch", "Read", "Grep", "Glob"],
        permissionMode: "default"
    })

    readonly property var noTools: ({
        model: "haiku", effort: "medium", tools: [], permissionMode: "default"
    })

    function argvOf(question, settings, sessionId, resume) {
        return policy.argv(question, settings, sessionId, resume);
    }

    /// The value of a flag in an argv, or "" — the argv is long and asserting
    /// on indices would make every test a test of the flag order.
    function flag(argv, name) {
        const at = argv.indexOf(name);
        return at < 0 || at + 1 >= argv.length ? "" : argv[at + 1];
    }

    // --- the model override --------------------------------------------------

    function test_a_leading_alias_picks_the_model() {
        const split = policy.split("haiku what is a quine");
        compare(split.model, "haiku");
        compare(split.question, "what is a quine");
    }

    function test_every_shipped_alias_is_an_override() {
        for (const alias of ["haiku", "sonnet", "opus"]) {
            const split = policy.split(alias + " hello");
            compare(split.model, alias);
            compare(split.question, "hello");
        }
    }

    function test_a_bare_alias_is_an_override_with_nothing_asked_yet() {
        // `?opus` on the way to `?opus explain this`. Reading it as the
        // question "opus" would put the model chip on the wrong model for
        // every character of the word.
        const split = policy.split("opus");
        compare(split.model, "opus");
        compare(split.question, "");
    }

    function test_anything_else_is_the_question() {
        const split = policy.split("what is the capital of France");
        compare(split.model, "");
        compare(split.question, "what is the capital of France");
        // The cost of the rule, named so it is a decision and not a surprise:
        // a question that opens with an alias cannot be asked with that word
        // first. `?tell me about opus` is the way round it.
        compare(policy.split("opus is a band").question, "is a band");
    }

    function test_the_default_model_comes_from_the_settings() {
        compare(policy.modelFor("", testCase.settings), "haiku");
        compare(policy.modelFor("sonnet", testCase.settings), "sonnet");
        // An alias the schema does not know cannot reach the CLI: omitting
        // `--model` inherits the user's own default, which the contract
        // measured as Opus.
        compare(policy.modelFor("bogus", testCase.settings), "haiku");
    }

    // --- the argv ------------------------------------------------------------

    function test_the_question_is_one_argument_after_dash_p() {
        const argv = argvOf("2+2; rm -rf ~", testCase.settings, "sid", false);
        compare(argv[0], "claude");
        compare(argv[1], "-p");
        // The calculator's argument, and sharper here: this string is typed by
        // the user and a shell line would run the second half of it.
        compare(argv[2], "2+2; rm -rf ~");
    }

    function test_stream_json_always_carries_verbose() {
        // Measured: `--output-format stream-json` without `--verbose` exits 1
        // with an empty stdout and the error on stderr — a provider that is
        // silent for a reason nothing on screen can name.
        const argv = argvOf("hi", testCase.settings, "sid", false);
        compare(flag(argv, "--output-format"), "stream-json");
        verify(argv.indexOf("--verbose") >= 0);
        verify(argv.indexOf("--include-partial-messages") >= 0);
    }

    function test_bare_is_unreachable() {
        // The ticket names this one: `--bare` hard-disables OAuth, so a run
        // carrying it is a run billed to an API account instead of the
        // subscription. There is no setting that can produce it.
        for (const permissionMode of ["default", "acceptEdits", "bypassPermissions"]) {
            const argv = argvOf("hi", { model: "opus", effort: "max",
                                        tools: ["Read"], permissionMode },
                                "sid", true);
            verify(argv.indexOf("--bare") < 0);
        }
    }

    function test_the_run_is_hermetic() {
        const argv = argvOf("hi", testCase.settings, "sid", false);
        // Both, because neither is a superset: `--setting-sources ""` drops
        // the settings files, `--safe-mode` drops plugins, skills, CLAUDE.md
        // and MCP. Without them the user's own Claude Code context is in the
        // prompt — measured at 20k tokens and 95x the cost.
        verify(argv.indexOf("--safe-mode") >= 0);
        compare(flag(argv, "--setting-sources"), "");
        // Replaces the coding-agent persona rather than appending to it.
        verify(argv.indexOf("--system-prompt") >= 0);
        verify(argv.indexOf("--append-system-prompt") < 0);
        verify(flag(argv, "--system-prompt").length > 0);
        // Thinking off: it occupies content block 0 by default and costs about
        // half a second of first-token latency the launcher cannot spend.
        compare(flag(argv, "--settings"), "{\"alwaysThinkingEnabled\":false}");
    }

    function test_a_tool_set_is_restricted_and_granted() {
        // Both flags, because they do different things: `--tools` restricts
        // what is loaded, `--allowedTools` only permits. With the first alone
        // the model asks for WebSearch and is refused mid-answer.
        const argv = argvOf("hi", testCase.settings, "sid", false);
        const expected = "WebSearch,WebFetch,Read,Grep,Glob";
        compare(flag(argv, "--tools"), expected);
        compare(flag(argv, "--allowedTools"), expected);
    }

    function test_an_empty_tool_set_restricts_without_granting() {
        // `--allowedTools ""` is not a grant of nothing, it is an empty grant
        // — the restriction is what carries the meaning, and a stray
        // `--allowedTools` with no value would swallow the next argument.
        const argv = argvOf("hi", testCase.noTools, "sid", false);
        compare(flag(argv, "--tools"), "");
        verify(argv.indexOf("--allowedTools") < 0);
    }

    function test_the_shipped_permission_mode_is_the_real_deny_gate() {
        // The schema's `default` is the *safe* mode, and measured headlessly
        // the CLI's own default is `auto`, which self-approves. `manual` does
        // not block either. `dontAsk` is the only one that denies.
        compare(flag(argvOf("hi", testCase.settings, "sid", false),
                     "--permission-mode"), "dontAsk");
        compare(flag(argvOf("hi", { model: "haiku", effort: "medium", tools: [],
                                    permissionMode: "acceptEdits" }, "sid", false),
                     "--permission-mode"), "acceptEdits");
        compare(flag(argvOf("hi", { model: "haiku", effort: "medium", tools: [],
                                    permissionMode: "bypassPermissions" }, "sid", false),
                     "--permission-mode"), "bypassPermissions");
    }

    function test_a_runaway_is_capped_in_money_as_well_as_time() {
        verify(parseFloat(flag(argvOf("hi", testCase.settings, "sid", false),
                               "--max-budget-usd")) > 0);
    }

    function test_the_first_turn_mints_and_the_rest_resume() {
        const first = argvOf("hi", testCase.settings, "abc", false);
        compare(flag(first, "--session-id"), "abc");
        verify(first.indexOf("--resume") < 0);

        const next = argvOf("and then?", testCase.settings, "abc", true);
        compare(flag(next, "--resume"), "abc");
        verify(next.indexOf("--session-id") < 0);
    }

    function test_a_resume_repasses_the_whole_flag_set() {
        // Resume restores the history and the model and *not* `--settings`,
        // `--tools` or the system prompt. A second turn that dropped them
        // would silently be a different, more expensive, less contained run.
        const argv = argvOf("and then?", testCase.settings, "abc", true);
        verify(argv.indexOf("--safe-mode") >= 0);
        compare(flag(argv, "--setting-sources"), "");
        compare(flag(argv, "--tools"), "WebSearch,WebFetch,Read,Grep,Glob");
        compare(flag(argv, "--settings"), "{\"alwaysThinkingEnabled\":false}");
        verify(flag(argv, "--system-prompt").length > 0);
    }

    function test_a_session_id_is_a_uuid() {
        // Not cosmetic: the CLI rejects a `--session-id` that is not one.
        const id = policy.newSessionId();
        verify(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
               .test(id));
        verify(policy.newSessionId() !== id);
    }

    // --- the preflight -------------------------------------------------------

    function test_the_preflight_makes_no_api_call() {
        compare(policy.preflightArgv(), ["claude", "auth", "status"]);
    }

    function test_only_a_first_party_subscription_is_ready() {
        verify(policy.ready(0, JSON.stringify({ loggedIn: true,
                                                apiProvider: "firstParty" })));
        verify(!policy.ready(1, JSON.stringify({ loggedIn: true,
                                                 apiProvider: "firstParty" })));
        verify(!policy.ready(0, JSON.stringify({ loggedIn: false,
                                                 apiProvider: "firstParty" })));
        // An API-key account answers perfectly well and bills somewhere else.
        verify(!policy.ready(0, JSON.stringify({ loggedIn: true,
                                                 apiProvider: "bedrock" })));
        verify(!policy.ready(0, "not json at all"));
    }

    // --- reading the stream --------------------------------------------------

    function line(object) {
        return JSON.stringify(object);
    }

    function test_an_unparseable_line_is_dropped_not_thrown() {
        // Lines reach ~2 kB and a truncated read must not tear down a stream
        // that is still producing an answer.
        compare(policy.parse("{ not json"), null);
        compare(policy.parse(""), null);
        compare(policy.parse("   "), null);
    }

    function test_init_latches_the_session_and_checks_the_billing() {
        const state = policy.begin();
        policy.apply(state, policy.parse(line({
            type: "system", subtype: "init", session_id: "abc",
            model: "claude-haiku-4-5-20251001", apiKeySource: "none"
        })));
        verify(state.init);
        compare(state.sessionId, "abc");
        verify(!state.failed);
    }

    function test_an_inherited_api_key_aborts_the_run() {
        // `apiKeySource` anything but "none" means an ANTHROPIC_API_KEY in the
        // environment is redirecting the billing away from the subscription.
        const state = policy.begin();
        policy.apply(state, policy.parse(line({
            type: "system", subtype: "init", session_id: "abc",
            apiKeySource: "environment"
        })));
        verify(state.failed);
        verify(state.message.length > 0);
        // And it must *stop* the run rather than note it. The answer would
        // arrive perfectly well and be billed to the wrong account, so
        // reporting without aborting is the whole failure.
        verify(state.abort);
        // Not `done`: that is what stands the watchdog down, and a run being
        // paid for by the wrong account is the last one to leave running.
        verify(!state.done);
    }

    function test_only_text_deltas_at_the_text_index_are_the_answer() {
        const state = policy.begin();
        policy.apply(state, policy.parse(line({
            type: "system", subtype: "init", session_id: "abc", apiKeySource: "none" })));

        // Thinking at 0, answer at 1 — the default layout when thinking is on,
        // and the reason "index 0 is the answer" is not the rule.
        policy.apply(state, policy.parse(line({ type: "stream_event", event: {
            type: "content_block_start", index: 0,
            content_block: { type: "thinking" } } })));
        policy.apply(state, policy.parse(line({ type: "stream_event", event: {
            type: "content_block_delta", index: 0,
            delta: { type: "thinking_delta", thinking: "hmm" } } })));
        compare(state.answer, "");

        policy.apply(state, policy.parse(line({ type: "stream_event", event: {
            type: "content_block_start", index: 1,
            content_block: { type: "text" } } })));
        policy.apply(state, policy.parse(line({ type: "stream_event", event: {
            type: "content_block_delta", index: 1,
            delta: { type: "text_delta", text: "Paris" } } })));
        policy.apply(state, policy.parse(line({ type: "stream_event", event: {
            type: "content_block_delta", index: 1,
            delta: { type: "text_delta", text: " it is." } } })));

        compare(state.answer, "Paris it is.");
        verify(state.streamed);
    }

    function test_a_tool_is_named_while_it_runs() {
        const state = policy.begin();
        policy.apply(state, policy.parse(line({ type: "stream_event", event: {
            type: "content_block_start", index: 1,
            content_block: { type: "tool_use", name: "WebSearch" } } })));
        verify(state.status.indexOf("WebSearch") >= 0);
    }

    function test_retries_are_counted_because_two_is_the_ceiling() {
        const state = policy.begin();
        compare(state.retries, 0);
        policy.apply(state, policy.parse(line({
            type: "system", subtype: "api_retry", attempt: 1, max_retries: 10 })));
        compare(state.retries, 1);
        verify(state.status.indexOf("1") >= 0);
    }

    function test_a_result_ends_the_stream() {
        const state = policy.begin();
        policy.apply(state, policy.parse(line({
            type: "result", is_error: false, subtype: "success",
            result: "The capital of France is Paris.",
            permission_denials: [], ttft_ms: 896 })));
        verify(state.done);
        verify(!state.failed);
    }

    function test_the_final_text_backfills_an_answer_the_deltas_missed() {
        // `--include-partial-messages` is the only reason deltas arrive at
        // all; if a future CLI stops emitting them the `result` line still
        // carries the whole answer, and an empty bubble under a successful run
        // is the #78 shape.
        const state = policy.begin();
        policy.apply(state, policy.parse(line({
            type: "result", is_error: false, subtype: "success",
            result: "Paris.", permission_denials: [] })));
        compare(state.answer, "Paris.");
    }

    function test_a_streamed_answer_is_not_overwritten_by_the_result() {
        const state = policy.begin();
        policy.apply(state, policy.parse(line({ type: "stream_event", event: {
            type: "content_block_start", index: 0,
            content_block: { type: "text" } } })));
        policy.apply(state, policy.parse(line({ type: "stream_event", event: {
            type: "content_block_delta", index: 0,
            delta: { type: "text_delta", text: "Paris." } } })));
        policy.apply(state, policy.parse(line({
            type: "result", is_error: false, subtype: "success",
            result: "Paris.", permission_denials: [] })));
        compare(state.answer, "Paris.");
    }

    function test_is_error_is_the_branch_and_subtype_is_not() {
        // Measured: the invalid-model path reports `subtype: "success"` and
        // `is_error: true` in the same line. Branching on subtype shows an
        // error message as if it were an answer.
        const state = policy.begin();
        policy.apply(state, policy.parse(line({
            type: "result", is_error: true, subtype: "success",
            api_error_status: 404,
            result: "There's an issue with the selected model (bogus-model-xyz).",
            permission_denials: [] })));
        verify(state.done);
        verify(state.failed);
        verify(state.message.indexOf("bogus-model-xyz") >= 0);
        // And the error text is not left sitting in the answer bubble.
        compare(state.answer, "");
    }

    function test_an_unknown_session_reports_its_own_error_list() {
        const state = policy.begin();
        policy.apply(state, policy.parse(line({
            type: "result", is_error: true, subtype: "error_during_execution",
            errors: ["No conversation found with session ID: abc"] })));
        verify(state.failed);
        verify(state.message.indexOf("No conversation found") >= 0);
        // The one failure a retry can actually fix, and the provider has to be
        // able to tell it apart to mint a fresh session instead.
        verify(state.lostSession);
    }

    function test_a_success_that_said_nothing_is_a_failure() {
        // The #78 shape in its success branch: exit 0, `is_error: false`, and
        // an empty string. Left alone it is a question sitting in the
        // transcript under a reply that never came, with nothing on screen
        // wrong enough to explain it.
        const state = policy.begin();
        policy.apply(state, policy.parse(line({
            type: "result", is_error: false, subtype: "success",
            result: "", permission_denials: [] })));
        verify(state.failed);
        verify(state.message.length > 0);
    }

    function test_a_denial_alone_is_answer_enough() {
        // ...but a run that said nothing *because* a tool was refused has
        // already explained itself, and calling that a failure would hide the
        // chip behind an error line.
        const state = policy.begin();
        policy.apply(state, policy.parse(line({
            type: "result", is_error: false, subtype: "success", result: "",
            permission_denials: [{ tool_name: "WebSearch" }] })));
        verify(!state.failed);
    }

    function test_a_cancel_keeps_the_half_written_answer() {
        // SIGTERM produces `is_error: true` (terminal_reason
        // "aborted_streaming"), so a cancel arrives down the failure branch —
        // and throwing away the text the user was reading is a worse outcome
        // than the one they asked for.
        const state = policy.begin();
        policy.apply(state, policy.parse(line({ type: "stream_event", event: {
            type: "content_block_start", index: 0,
            content_block: { type: "text" } } })));
        policy.apply(state, policy.parse(line({ type: "stream_event", event: {
            type: "content_block_delta", index: 0,
            delta: { type: "text_delta", text: "Rayleigh scattering is" } } })));
        policy.apply(state, policy.parse(line({
            type: "result", is_error: true, subtype: "error_during_execution",
            terminal_reason: "aborted_streaming", permission_denials: [] })));
        compare(state.answer, "Rayleigh scattering is");
    }

    // --- denials -------------------------------------------------------------

    function test_a_denial_is_soft_and_only_the_array_reports_it() {
        // No error event, exit 0, `is_error: false`. The prose answer does not
        // reliably mention it either — this array is the whole signal.
        const state = policy.begin();
        policy.apply(state, policy.parse(line({
            type: "result", is_error: false, subtype: "success",
            result: "I could not look that up.",
            permission_denials: [{ tool_name: "WebSearch", tool_use_id: "t1" },
                                 { tool_name: "Bash", tool_use_id: "t2" }] })));
        verify(!state.failed);
        compare(state.denials, ["WebSearch", "Bash"]);
        // Surfaced, not swallowed: the ticket's third acceptance criterion.
        verify(policy.denialNote(state.denials).indexOf("WebSearch") >= 0);
        verify(policy.denialNote(state.denials).indexOf("Bash") >= 0);
        compare(policy.denialNote([]), "");
    }

    // --- the deadline ladder -------------------------------------------------

    function test_no_init_is_a_five_second_deadline() {
        const state = policy.begin();
        compare(policy.deadline(state, 4000), "");
        compare(policy.deadline(state, 6000), "start");
    }

    function test_no_first_token_is_a_twenty_second_deadline() {
        const state = policy.begin();
        state.init = true;
        compare(policy.deadline(state, 6000), "");
        compare(policy.deadline(state, 21000), "response");
    }

    function test_two_retries_do_not_wait_out_the_ladder() {
        // The offline probe retries ten times with exponential backoff past
        // two minutes and never terminates itself. Two is enough to know.
        const state = policy.begin();
        state.init = true;
        state.retries = 1;
        compare(policy.deadline(state, 1000), "");
        state.retries = 2;
        compare(policy.deadline(state, 1000), "network");
    }

    function test_a_streaming_answer_still_has_an_absolute_cap() {
        const state = policy.begin();
        state.init = true;
        state.streamed = true;
        compare(policy.deadline(state, 60000), "");
        compare(policy.deadline(state, 121000), "cap");
    }

    function test_a_finished_run_has_no_deadline_left() {
        const state = policy.begin();
        state.done = true;
        compare(policy.deadline(state, 600000), "");
    }

    function test_every_watchdog_says_something_different() {
        const said = ["start", "response", "network", "cap"]
            .map(reason => policy.watchdog(reason));
        for (const text of said)
            verify(text.length > 0);
        // #81: four ways to be killed that read identically on screen is four
        // bugs with one symptom.
        compare(new Set(said).size, 4);
    }

    // --- the silences --------------------------------------------------------

    function test_a_logged_out_shell_says_so_before_anything_else() {
        const said = policy.silence("what is a quine", {
            available: false, probed: true, streaming: false,
            turns: 0, failure: "" });
        verify(said.text.indexOf("login") >= 0);
    }

    function test_an_empty_question_invites_one() {
        const said = policy.silence("", { available: true, probed: true,
                                          streaming: false, turns: 0, failure: "" });
        compare(said.text, "Ask anything");
    }

    function test_a_conversation_in_progress_has_no_silence() {
        compare(policy.silence("", { available: true, probed: true,
                                     streaming: false, turns: 2, failure: "" }), null);
    }

    // --- the log -------------------------------------------------------------

    function test_the_log_can_tell_two_runs_apart() {
        // #81 again: a line that says only "asked" cannot be told from the
        // previous one, so the model and the question are both in it.
        compare(policy.asked("haiku", "what is a quine"),
                "asked haiku \"what is a quine\"");
        verify(policy.opened("abc", false).indexOf("abc") >= 0);
        verify(policy.opened("abc", true).indexOf("resumed") >= 0);
        verify(policy.opened("abc", false).indexOf("resumed") < 0);
        compare(policy.answered(42, 896), "answered in 896ms (42 chars)");
        verify(policy.killed("response").indexOf("response") >= 0
               || policy.killed("response").length > 0);
        verify(policy.cancelled().length > 0);
        verify(policy.absent().indexOf("claude") >= 0);
        verify(policy.unauthorised().indexOf("login") >= 0);
        compare(policy.denied(["WebSearch"]),
                "denied WebSearch — not in the allowed tools");
    }
}
