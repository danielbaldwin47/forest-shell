// The Ask Claude provider's decisions (#41) — what the run is allowed to be,
// what a stream-json line means, and when to stop waiting.
//
// `claude -p` does the answering. This file never talks to it: it builds an
// argv, folds a line of JSON into an answer, and decides which of four
// watchdogs has run out. Services/Launcher/Claude.qml owns the `Process`, and
// nothing here needs Quickshell, so `tests/` can reach the whole decision —
// which matters more here than anywhere else in the launcher, because the risky
// parts of this ticket are all parsing and all invisible.
//
// Everything below is measured, not guessed: `.wayfinder/research/
// claude-cli-contract.md` probed CLI 2.1.220 against a subscription account and
// the numbers, flag behaviours and failure shapes come from there.
//
// ## Four things that are counter-intuitive, and are the reason this is tested
//
// 1. **`--tools` restricts; `--allowedTools` only permits.** Neither alone is a
//    containment boundary. With `--tools` by itself the model is offered
//    WebSearch and then refused it mid-answer; with `--allowedTools` by itself
//    all thirty tools stay loaded and `Bash` runs. Both, always.
// 2. **`--permission-mode` has no safe default.** Headless, the CLI reports
//    mode `auto` and self-approves; `manual` degrades to permissive because
//    there is no human to prompt. `dontAsk` is the only value that denies, so
//    the schema's `default` maps to it.
// 3. **A `result` line can say `subtype: "success"` and `is_error: true` in the
//    same breath** — the invalid-model path does exactly that. `is_error` is
//    the branch.
// 4. **A tool denial is soft**: no error event, no non-zero exit,
//    `is_error: false`. `result.permission_denials[]` is the only machine-
//    readable signal, which is why the ticket asks for it by name.
//
// ## And one that is a billing question
//
// `--bare` hard-disables OAuth. A run carrying it is not a broken run — it is a
// working run billed to an API account instead of the subscription the user is
// paying for. It is unreachable from here by construction, and there is a test
// that says so.
import QtQuick

QtObject {
    id: policy

    /// The binary. Named once — argv, preflight, and the sentence the user
    /// reads when it is missing.
    readonly property string tool: "claude"

    /// The model aliases the launcher will pass to `--model`, matching
    /// Core/SettingsSchema.qml's `claudeModels`. Repeated rather than imported
    /// because that file needs Quickshell and this one must not; the test
    /// asserts the two agree.
    readonly property var models: ["haiku", "sonnet", "opus"]

    /// What replaces Claude Code's own system prompt. Short on purpose: it is
    /// resent on every turn, and the whole reason for `--system-prompt` over
    /// `--append-system-prompt` is that the coding-agent persona costs 3626
    /// input tokens the launcher has no use for.
    readonly property string systemPrompt:
        "You are answering from a desktop launcher. The answer appears in a "
        + "narrow panel, so be brief — a sentence or two unless asked for more. "
        + "Plain prose, no markdown headings, no code fences unless the answer "
        + "is code. If you lack a tool to answer properly, say so in one line "
        + "rather than describing what you would have done."

    /// The spend ceiling on a single turn. A guard against a runaway loop
    /// rather than a budget: it produces a clean, distinguishable
    /// `error_max_budget_usd` result instead of a run that grinds on.
    readonly property string budget: "0.50"

    // --- the deadline ladder -------------------------------------------------
    //
    // Measured: `system/init` arrives at 922–1049 ms, first visible token at
    // ~1.7 s on haiku. Offline, the CLI emits `system/api_retry` with
    // exponential backoff totalling over two minutes and never terminates
    // itself — so the launcher owns every deadline here.

    readonly property int initDeadlineMs: 5000
    readonly property int firstTokenDeadlineMs: 20000
    readonly property int capMs: 120000
    readonly property int retryCeiling: 2

    // --- the model override --------------------------------------------------

    /// A query body split into an inline model override and the question
    /// under it — `?sonnet why is the sky blue` is the think-harder affordance
    /// the settings tab already promises.
    ///
    /// A leading word that is exactly an alias is the override, and a bare
    /// alias is an override with nothing asked yet: `?opus` is a keystroke on
    /// the way to `?opus explain this`, and reading it as the question "opus"
    /// would put the chip on the wrong model for the whole word.
    ///
    /// The cost is that a question cannot *open* with an alias — `?opus is a
    /// band` asks about a band with the first word eaten. That is the trade a
    /// one-character prefix language makes, it is cheap in the direction that
    /// matters, and `?tell me about opus` is the way round it.
    function split(body: string): var {
        const text = String(body ?? "").trim();
        const space = text.indexOf(" ");
        const head = space < 0 ? text : text.slice(0, space);

        if (policy.models.indexOf(head) < 0)
            return { model: "", question: text };
        return { model: head, question: space < 0 ? "" : text.slice(space + 1).trim() };
    }

    /// The model a run should use: the override if there is a usable one, the
    /// configured default otherwise.
    ///
    /// An alias the schema does not know falls back rather than reaching the
    /// CLI, because omitting `--model` does not mean "the safe one" — it
    /// inherits the user's own default, measured as Opus, which is the
    /// expensive answer to a launcher-sized question.
    function modelFor(override: string, settings: var): string {
        const wanted = String(override ?? "");
        if (policy.models.indexOf(wanted) >= 0)
            return wanted;
        const configured = String((settings ?? {}).model ?? "");
        return policy.models.indexOf(configured) >= 0 ? configured : policy.models[0];
    }

    // --- the argv ------------------------------------------------------------

    /// What to run for one turn.
    ///
    /// `resume` picks between minting the session and continuing it. Every
    /// other flag is passed identically on both, and that is not tidiness:
    /// resume restores the history and the model but *not* `--settings`,
    /// `--tools`, `--allowedTools` or the system prompt, so a second turn that
    /// dropped them would quietly be a wider, costlier, less contained run
    /// than the first.
    ///
    /// The question is one argv element. The calculator makes this argument
    /// and it is sharper here: this string is typed by the user, and a shell
    /// line would run the half of it after the semicolon.
    function argv(question: string, settings: var, sessionId: string,
                  resume: bool): var {
        const it = settings ?? {};
        const tools = (it.tools ?? []).join(",");

        const argv = [
            policy.tool,
            "-p", String(question ?? ""),

            // stream-json is a hard error without --verbose: exit 1, empty
            // stdout, the reason on stderr. --include-partial-messages is what
            // makes the answer arrive token by token rather than all at once.
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",

            "--model", policy.modelFor(String(it.model ?? ""), it),
            "--effort", String(it.effort ?? "medium"),

            // Hermetic. Neither flag is a superset of the other: the first
            // drops the settings files (hooks, permissions, model overrides),
            // the second drops plugins, skills, CLAUDE.md, MCP and LSP.
            "--safe-mode",
            "--setting-sources", "",
            "--settings", "{\"alwaysThinkingEnabled\":false}",
            "--system-prompt", policy.systemPrompt,

            "--permission-mode", policy.permissionMode(String(it.permissionMode ?? "")),
            "--max-budget-usd", policy.budget
        ];

        // One comma-separated element rather than a space-separated list: the
        // flag is variadic and a space-separated form swallows the next
        // positional argument if the order is ever wrong.
        argv.push("--tools", tools);
        // `--allowedTools ""` is not "grant nothing", it is an empty grant with
        // a dangling value. With no tools loaded there is nothing to permit.
        if (tools !== "")
            argv.push("--allowedTools", tools);

        argv.push(resume ? "--resume" : "--session-id", String(sessionId ?? ""));
        return argv;
    }

    /// The CLI value for a configured permission mode.
    ///
    /// `default` is the schema's *safe* mode and maps to `dontAsk`, which is
    /// the only value measured to actually deny. Sending the literal string
    /// `default` would land on the CLI's own default — reported as `auto`,
    /// which self-approves — so the two names agreeing would be the bug.
    /// `--tools` is still the primary boundary; this is defence in depth.
    function permissionMode(configured: string): string {
        const wanted = String(configured ?? "");
        return wanted === "acceptEdits" || wanted === "bypassPermissions"
            ? wanted : "dontAsk";
    }

    /// A UUID v4. The CLI rejects a `--session-id` that is not one, and the
    /// rejection arrives as a failed run rather than as an argument error.
    function newSessionId(): string {
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, ch => {
            const value = Math.floor(Math.random() * 16);
            const digit = ch === "x" ? value : (value & 0x3) | 0x8;
            return digit.toString(16);
        });
    }

    /// Environment the child must not inherit. An `ANTHROPIC_API_KEY` in the
    /// parent silently redirects billing off the subscription, and an
    /// inherited `CLAUDE_EFFORT` silently changes the effort the settings
    /// asked for — both are failures that answer correctly, which is the kind
    /// that goes unnoticed.
    readonly property var scrubbed: [
        "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL",
        "ANTHROPIC_MODEL", "CLAUDE_CODE_SKIP_PROMPT_HISTORY", "CLAUDECODE",
        "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID", "CLAUDE_EFFORT"
    ]

    // --- the preflight -------------------------------------------------------

    /// Asked once at startup. Cheap, makes no API call, and turns "Ask Claude
    /// answers nothing and will not say why" into a sentence.
    function preflightArgv(): var {
        return [policy.tool, "auth", "status"];
    }

    /// Whether that reply means the provider can work: logged in, and on the
    /// subscription rather than an API account.
    function ready(exitCode: int, stdout: string): bool {
        if (exitCode !== 0)
            return false;
        try {
            const status = JSON.parse(String(stdout ?? ""));
            return status.loggedIn === true && status.apiProvider === "firstParty";
        } catch (error) {
            return false;
        }
    }

    // --- reading the stream --------------------------------------------------

    /// One line of stdout as an object, or null.
    ///
    /// stdout is strictly line-delimited JSON — every warning and every fatal
    /// argument error goes to stderr — but a line can reach 2 kB and a
    /// truncated read must drop a line rather than tear down a stream that is
    /// still producing an answer.
    function parse(line: string): var {
        const text = String(line ?? "").trim();
        if (text === "")
            return null;
        try {
            return JSON.parse(text);
        } catch (error) {
            return null;
        }
    }

    /// A fresh run's state. Mutated in place by `apply` — one object per run,
    /// rather than a new one per line, because a stream is hundreds of lines
    /// and the surface holds a reference to this.
    function begin(): var {
        return {
            init: false,        // `system/init` seen: the CLI is really running
            sessionId: "",
            textIndex: -1,      // which content block carries the answer
            answer: "",
            status: "",         // the transient line under the caret
            retries: 0,
            streamed: false,    // any text at all has arrived
            done: false,        // a `result` line closed the run
            failed: false,
            // Stop the run *now*, rather than reporting on it afterwards.
            // Only the billing check raises this: every other failure is
            // already terminal by the time it is known, where this one is
            // discovered on the first line of a run that would otherwise
            // stream happily to completion and be paid for by the wrong
            // account. Services/Launcher/Claude.qml watches it and signals.
            abort: false,
            lostSession: false, // the session id no longer resolves
            message: "",        // why it failed, in a sentence
            denials: [],
            ttft: 0
        };
    }

    /// Fold one parsed line into the run.
    function apply(state: var, event: var): var {
        if (!state || !event)
            return state;

        const type = String(event.type ?? "");

        if (type === "system") {
            const subtype = String(event.subtype ?? "");
            if (subtype === "init") {
                state.init = true;
                state.sessionId = String(event.session_id ?? "");
                // Anything but "none" means an inherited key is paying for
                // this. The run works, which is exactly why it is checked.
                if (String(event.apiKeySource ?? "none") !== "none") {
                    state.failed = true;
                    // Not `done`. Reporting it and letting the run finish is
                    // the whole failure: the answer would arrive, correctly,
                    // billed to the wrong account. `abort` is what stops it,
                    // and `done` would stand the watchdog down instead.
                    state.abort = true;
                    state.message = "An API key in the environment is billing this "
                                  + "run — Ask Claude needs the subscription";
                }
            } else if (subtype === "api_retry") {
                state.retries += 1;
                state.status = "retrying " + event.attempt + "/"
                             + event.max_retries + "…";
            }
            return state;
        }

        if (type === "stream_event") {
            const inner = event.event ?? {};
            const kind = String(inner.type ?? "");

            if (kind === "content_block_start") {
                const block = inner.content_block ?? {};
                // Which index is the answer is a fact about this run, not a
                // constant: with thinking on it is 1, with thinking off it is
                // 0, and "index 0 is the answer" is the parser that shows the
                // model's reasoning to the user.
                if (String(block.type ?? "") === "text")
                    state.textIndex = inner.index;
                else if (String(block.type ?? "") === "tool_use")
                    state.status = "using " + String(block.name ?? "a tool") + "…";
            } else if (kind === "content_block_delta") {
                const delta = inner.delta ?? {};
                if (String(delta.type ?? "") === "text_delta"
                        && inner.index === state.textIndex) {
                    state.answer += String(delta.text ?? "");
                    state.streamed = true;
                    state.status = "";
                }
            }
            return state;
        }

        if (type === "result") {
            state.done = true;
            state.status = "";
            state.ttft = Number(event.ttft_ms ?? 0);
            state.denials = (event.permission_denials ?? [])
                .map(denial => String(denial.tool_name ?? ""))
                .filter(name => name !== "");

            // `is_error`, never `subtype`: the invalid-model path reports
            // `subtype: "success"` alongside `is_error: true`, and branching
            // on the subtype renders that error as though it were an answer.
            if (event.is_error === true) {
                state.failed = true;
                const errors = event.errors ?? [];
                state.message = errors.length > 0
                    ? String(errors[0])
                    : String(event.result ?? "Claude could not answer");
                state.lostSession = state.message.indexOf("No conversation found") >= 0;
                // The failure text is not an answer and must not be left in
                // the bubble as if it were one — but only when there is no
                // answer of the user's own there already. A cancel arrives
                // down this branch (SIGTERM produces `is_error: true`), and
                // discarding the half-written answer they were reading is a
                // worse outcome than the one they asked for.
                if (!state.streamed)
                    state.answer = "";
            } else {
                if (!state.streamed) {
                    // The deltas are only there because of
                    // `--include-partial-messages`; the terminal line carries
                    // the whole answer regardless.
                    state.answer = String(event.result ?? "");
                }
                // A success that said nothing at all is the #78 shape in its
                // success branch: the question sits in the transcript under a
                // reply that never came, and nothing on screen is wrong.
                if (state.answer === "" && state.denials.length === 0) {
                    state.failed = true;
                    state.message = "Claude answered with nothing at all";
                }
            }
            return state;
        }

        return state;
    }

    /// Which watchdog has run out, or `""`.
    ///
    /// Ordered by certainty rather than by duration: two retries is a fact
    /// about the network and is worth acting on at once, where the elapsed
    /// clock is only ever a guess that something is wrong.
    function deadline(state: var, elapsedMs: real): string {
        const it = state ?? {};
        if (it.done === true)
            return "";
        if ((it.retries ?? 0) >= policy.retryCeiling)
            return "network";
        if (it.init !== true && elapsedMs > policy.initDeadlineMs)
            return "start";
        if (it.init === true && it.streamed !== true
                && elapsedMs > policy.firstTokenDeadlineMs)
            return "response";
        if (elapsedMs > policy.capMs)
            return "cap";
        return "";
    }

    /// What the panel says when a watchdog fires. Four sentences and not one,
    /// because four ways to be killed that read identically on screen are four
    /// bugs with one symptom (#81).
    function watchdog(reason: string): string {
        switch (String(reason ?? "")) {
        case "start":    return "Claude CLI failed to start";
        case "response":  return "No response — gave up waiting";
        case "network":   return "Network problem — could not reach the API";
        case "cap":       return "That took too long, so it was stopped";
        }
        return "Stopped";
    }

    /// The denial chip. Named tools, because "a tool" is not something the
    /// user can act on and "WebSearch" is — the settings tab has the switch.
    function denialNote(denials: var): string {
        const names = (denials ?? []).filter(name => String(name ?? "") !== "");
        if (names.length === 0)
            return "";
        return "Claude wanted " + names.join(", ")
             + " but is not allowed to use " + (names.length === 1 ? "it" : "them");
    }

    // --- the silences --------------------------------------------------------

    /// What the panel says instead of a conversation, or `null` when it has
    /// one to show.
    ///
    /// `state` is the provider's own: `{ available, probed, streaming, turns,
    /// failure }`. Order is the order of certainty, as the calculator's is: a
    /// logged-out CLI is a fact about the machine and outranks anything about
    /// this particular question.
    ///
    /// `failure` is a *sentence*, not a flag — deliberately not named `failed`,
    /// which is the boolean one file over in the run state. Two fields a
    /// function apart, one a bool and one a string, is how a caller passes the
    /// wrong object and takes a branch that reads as "fine".
    function silence(question: string, state: var): var {
        const it = state ?? {};

        if (it.probed === true && it.available === false)
            return { icon: "circle-slash", text: policy.unauthorised() };
        if ((it.turns ?? 0) > 0 || it.streaming === true)
            return null;
        if (String(it.failure ?? "") !== "")
            return { icon: "circle-slash", text: String(it.failure) };
        if (String(question ?? "").trim() === "")
            return { icon: "sparkles", text: "Ask anything" };
        return { icon: "corner-down-left", text: "Press Enter to ask" };
    }

    // --- what the log says ---------------------------------------------------
    //
    // The wording is the contract: tools/launcher-harness.sh greps for exactly
    // these. A streaming provider has more states worth asserting on than any
    // other in the launcher — spawned, resumed, first token, retried, killed,
    // denied — and #81 is the ticket about what it costs when a lifecycle is
    // silent.

    function asked(model: string, question: string): string {
        return "asked " + model + " \"" + String(question ?? "").trim() + "\"";
    }

    function opened(sessionId: string, resumed: bool): string {
        return "session " + sessionId + (resumed ? " resumed" : " opened");
    }

    function answered(chars: int, ttftMs: int): string {
        return "answered in " + ttftMs + "ms (" + chars + " chars)";
    }

    function failed(message: string): string {
        return "claude failed — " + String(message ?? "");
    }

    function killed(reason: string): string {
        return "killed on " + String(reason ?? "") + " — " + policy.watchdog(reason);
    }

    function cancelled(): string {
        return "cancelled by the user";
    }

    /// A question that was not sent, and which of the three reasons it was.
    /// Logged rather than shown: the panel already looks unchanged, and #81 is
    /// the ticket about a state change with nothing to grep for.
    function refused(why: string): string {
        return "not asking — " + String(why ?? "");
    }

    function forgot(turns: int): string {
        return "conversation forgotten (" + turns + " turn"
             + (turns === 1 ? "" : "s") + ")";
    }

    function denied(denials: var): string {
        const names = (denials ?? []).filter(name => String(name ?? "") !== "");
        return "denied " + names.join(", ") + " — not in the allowed tools";
    }

    /// The spawn that never happened. A warning: every question from here on
    /// is a silence, and this is the only place the reason is written down.
    function absent(): string {
        return "no " + policy.tool + " on PATH — Ask Claude is inert";
    }

    function unauthorised(): string {
        return "Not logged in — run `claude /login` in a terminal";
    }

    function found(): string {
        return policy.tool + " ready";
    }
}
