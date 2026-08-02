pragma Singleton

// The Ask Claude provider (#41) — a question in, an answer arriving a token at
// a time.
//
//     Claude.ask(body, settings)   start a turn
//     Claude.cancel()              stop the one in flight
//     Claude.turns                 the transcript
//     Claude.answer                the turn still being written
//
// The decisions are ClaudePolicy.qml next door, where `tests/` can reach them:
// the argv, the fold from stream-json into text, the deadline ladder. What is
// here is the part that needs Quickshell — one `Process` reading line-delimited
// JSON, a watchdog, and the session id that makes a second question a
// follow-up rather than a new conversation.
//
// ## Why the answer is two properties and not one
//
// `turns` is a `ListModel` and the streaming answer is a plain string beside
// it. The transcript delegate is built once per turn and never rebuilt; the
// live answer is one `Text` bound to `answer`, so a token appends to a string
// instead of reassigning a model. #75 is the ticket about what the other shape
// costs — reassigning a model rebuilds every delegate in it, and here that
// would be every bubble in the conversation, per token.
//
// The finished turn moves into the model when the run settles, which is one
// re-layout at the end rather than one per token.
//
// ## Why it never spawns on a keystroke
//
// Every other provider answers the query as it is typed. This one costs about
// a second of Node startup and real money, so it answers Enter and nothing
// else — `prime()` deliberately does not reach this file.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core

Singleton {
    id: root

    readonly property ClaudePolicy policy: ClaudePolicy {}

    /// Whether the CLI is there and logged in on the subscription. Optimistic
    /// until the preflight answers, so the first frames of the shell's life do
    /// not accuse a machine that is signed in perfectly well.
    property bool available: true
    property bool probed: false

    /// The conversation this shell is in. Persisted (`state.claude.sessionId`)
    /// so a follow-up survives a shell restart, and minted on the first turn
    /// after a reset.
    property string sessionId: ""

    /// The transcript. `speaker` is `"you"` or `"claude"`; `note` carries the
    /// denial chip for the turn it belongs to, so a tool refused three answers
    /// ago does not sit under the current one.
    readonly property alias turns: transcript

    /// The answer being written right now — bound by the surface, appended to
    /// per token. Empty between turns.
    property string answer: ""

    /// The transient line under the caret: "using WebSearch…", "retrying
    /// 2/10…". Not an answer and not an error; it disappears when text starts.
    property string status: ""

    /// Why the last turn failed, in a sentence the panel can show. Cleared by
    /// the next question.
    property string failure: ""

    /// The model the turn in flight is using — the chip in the field.
    property string model: ""

    readonly property bool streaming: runner.running

    /// The fold of the stream so far. Replaced per run by `policy.begin()`.
    property var run: ({})

    property double startedAt: 0

    /// A `--resume` whose session no longer exists is retried once from a
    /// fresh id. Guarded so a genuinely broken session cannot loop.
    property bool retriedLostSession: false

    /// Something the *next* turn to settle has to say for itself, beyond its
    /// own text. Today that is only the lost-session retry: the answer is
    /// real, but it was given without the history the user assumes it has,
    /// and a shell that quietly starts a second conversation inside the first
    /// is answering a different question from the one that was asked.
    property string pendingNote: ""

    ListModel { id: transcript }

    // --- asking --------------------------------------------------------------

    /// Start a turn. Returns whether one started, so the surface can tell "sent"
    /// from "there was nothing to send".
    ///
    /// A question is refused while another is in flight rather than queued:
    /// assigning a command to a running `Process` kills it, and a launcher
    /// that silently discards the answer you are reading to start another is
    /// worse than one that waits.
    function ask(body: string, settings: var): bool {
        // Each refusal says which one it was. A question that vanished
        // because another was still streaming is exactly the silent
        // lifecycle #81 is about — the panel looks like it dropped what was
        // typed, and nothing anywhere says why.
        if (runner.running) {
            Logger.log("launcher", root.policy.refused("a turn is already in flight"));
            return false;
        }
        if (!root.available) {
            Logger.log("launcher", root.policy.refused("the CLI is not logged in"));
            return false;
        }

        const split = root.policy.split(body);
        if (split.question === "") {
            Logger.log("launcher", root.policy.refused("there is no question yet"));
            return false;
        }

        root.model = root.policy.modelFor(split.model, settings);
        root.retriedLostSession = false;
        transcript.append({ speaker: "you", text: split.question, note: "" });
        root.start(split.question, settings);
        return true;
    }

    /// Spawn one run for a question already in the transcript. Separate from
    /// `ask()` because the lost-session retry re-runs the same question
    /// without asking it again.
    function start(question: string, settings: var): void {
        const resume = root.sessionId !== "";
        if (!resume)
            root.sessionId = root.policy.newSessionId();

        root.answer = "";
        root.failure = "";
        root.status = "Thinking…";
        root.run = root.policy.begin();
        root.startedAt = Date.now();

        runner.asked = question;
        runner.settings = settings ?? {};
        runner.started = false;
        // Cleared per run: stderr is what a failure with nothing on stdout is
        // reported from, and a line left over from the previous run would
        // explain this one with the last one's reason.
        runner.tail = "";
        // The resolved model rather than the configured one, so an inline
        // `?sonnet` override reaches the argv instead of being resolved twice
        // to two different answers.
        runner.command = root.policy.argv(
            question,
            Object.assign({}, settings ?? {}, { model: root.model }),
            root.sessionId, resume);
        runner.running = true;
        watchdog.restart();

        Logger.log("launcher", root.policy.asked(root.model, question));
        Logger.log("launcher", root.policy.opened(root.sessionId, resume));
    }

    /// Stop the turn in flight. SIGTERM and not SIGKILL: the CLI flushes a
    /// terminal `result` line, tears down any child process tree, and exits
    /// 143 — so a cancel settles through the same path as an answer instead of
    /// leaving the panel mid-sentence.
    function cancel(): void {
        if (!runner.running)
            return;
        runner.cancelled = true;
        watchdog.stop();
        runner.signal(15);
        Logger.log("launcher", root.policy.cancelled());
    }

    /// Forget the conversation. The next question opens a new session.
    function reset(): void {
        root.cancel();
        Logger.log("launcher", root.policy.forgot(transcript.count));
        transcript.clear();
        root.answer = "";
        root.failure = "";
        root.status = "";
        root.sessionId = "";
        ShellState.set("claude.sessionId", "");
    }

    /// What the panel says instead of a conversation.
    function silence(body: string): var {
        return root.policy.silence(root.policy.split(body).question, {
            available: root.available,
            probed: root.probed,
            streaming: root.streaming,
            turns: transcript.count,
            failure: root.failure
        });
    }

    // --- settling ------------------------------------------------------------

    /// Fold the finished run into the transcript. One place, because a run can
    /// end four ways — a result line, a watchdog, a cancel, and a binary that
    /// was never there — and all four have to leave the panel in a state the
    /// user can type into.
    /// `reason` is what ended it: `""` for a terminal `result` line,
    /// `"cancelled"` for the user, or a watchdog id.
    function settle(reason: string): void {
        const state = root.run ?? {};
        const note = root.policy.denialNote(state.denials ?? []);

        if (note !== "")
            Logger.log("launcher", root.policy.denied(state.denials));

        // Whatever streamed is kept, however the run ended. A cancel and a
        // watchdog both arrive here with an answer half written, and throwing
        // away the part the user was reading is a worse outcome than the one
        // they asked for — and it is the only copy: nothing else holds it.
        const text = String(state.answer ?? "");
        if (text !== "" || note !== "")
            transcript.append({ speaker: "claude", text,
                                note: root.pendingNote === ""
                                      ? note
                                      : root.pendingNote + (note === "" ? "" : " · " + note) });
        root.pendingNote = "";

        if (reason === "cancelled") {
            // Not a failure. The user asked for it, the panel already shows
            // what arrived, and a red line under it would be the shell
            // reporting an error it was told to cause.
            root.failure = "";
        } else if (reason !== "") {
            root.failure = root.policy.watchdog(reason);
        } else if (state.failed === true) {
            root.failure = state.message;
            Logger.warn("launcher", root.policy.failed(state.message));
        } else {
            root.failure = "";
            Logger.log("launcher",
                       root.policy.answered(text.length, state.ttft ?? 0));
        }

        root.answer = "";
        root.status = "";
    }

    // --- running -------------------------------------------------------------

    Process {
        id: runner

        /// The question this run answers, kept for the lost-session retry.
        property string asked: ""
        property var settings: ({})

        /// Whether the process ever got as far as existing. The calculator's
        /// argument, unchanged: a binary that is not there emits no `exited`
        /// signal at all, so the absence of `started` is the only signal.
        property bool started: false

        /// The user stopped this one. Distinguishes a cancel from a failure —
        /// both arrive as a non-zero exit and only one of them is news.
        property bool cancelled: false

        /// Which watchdog killed it, or "".
        property string killedOn: ""

        workingDirectory: Paths.claudeDir

        /// An inherited `ANTHROPIC_API_KEY` bills this run to an API account
        /// instead of the subscription, and an inherited `CLAUDE_EFFORT`
        /// quietly overrides the effort the settings asked for. Both are
        /// failures that still answer correctly, which is the kind that goes
        /// unnoticed — so the child is given an environment with them removed.
        environment: {
            const scrubbed = {};
            for (const name of root.policy.scrubbed)
                scrubbed[name] = null;
            return scrubbed;
        }

        stdout: SplitParser {
            splitMarker: "\n"

            onRead: line => {
                const event = root.policy.parse(line);
                if (!event)
                    return;

                root.policy.apply(root.run, event);

                // The three the surface is bound to. Copied out rather than
                // read through `run` directly, because `run` is a plain object
                // and mutating it notifies nothing.
                root.answer = String(root.run.answer ?? "");
                root.status = String(root.run.status ?? "");
                if (root.run.sessionId)
                    root.sessionId = root.run.sessionId;

                // The billing check, acted on rather than noted. It is raised
                // on the *first* line of a run that would otherwise answer
                // perfectly well and be paid for by an API account instead of
                // the subscription, so the only useful response is to stop it
                // now — see `abort` in ClaudePolicy.begin().
                if (root.run.abort === true && runner.running) {
                    root.run.abort = false;
                    watchdog.stop();
                    runner.signal(15);
                    Logger.warn("launcher", root.policy.failed(root.run.message));
                }
            }
        }

        /// Kept for the error surface: a fatal argument error never reaches
        /// stdout, so without this a run that died on its own flags has
        /// nothing on screen to explain it.
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const text = String(line ?? "").trim();
                if (text === "")
                    return;
                // The last few lines, not the last one: a fatal argument
                // error is often a usage line under the reason for it, and
                // keeping only the final line keeps the least useful half.
                const kept = runner.tail === "" ? [] : runner.tail.split("\n");
                kept.push(text);
                runner.tail = kept.slice(-4).join("\n");
            }
        }

        property string tail: ""

        onStarted: runner.started = true

        onExited: (exitCode, exitStatus) => {
            watchdog.stop();

            const state = root.run ?? {};

            // A session that no longer resolves is the one failure a retry can
            // actually fix: the id outlives the transcript it names (state.json
            // persists, the CLI prunes at 30 days), so the first question after
            // that gap would otherwise fail for a reason the user cannot act on.
            if (state.lostSession === true && !root.retriedLostSession) {
                root.retriedLostSession = true;
                root.sessionId = "";
                // Said out loud on the answer it produces. The retry is
                // right — the id outlives the transcript it names — but the
                // answer comes back without the history the user believes is
                // behind it, and a shell that starts a second conversation
                // inside the first without saying so is answering a different
                // question from the one that was asked.
                root.pendingNote = "The earlier conversation had expired, "
                                 + "so this is a fresh one";
                root.start(runner.asked, runner.settings);
                return;
            }

            // No terminal `result` line and a non-zero exit: the run died on
            // something that never reached stdout. stderr is the only account
            // of it there is.
            if (state.done !== true && exitCode !== 0 && !runner.cancelled
                    && runner.killedOn === "") {
                state.failed = true;
                state.message = runner.tail !== "" ? runner.tail
                                                   : "claude exited " + exitCode;
            }

            // One way out, so that a cancel and a watchdog keep whatever
            // streamed and surface whatever was denied, exactly as a normal
            // answer does. Returning early from either was how a cancelled
            // half-answer disappeared and a denial went unreported.
            const reason = runner.cancelled ? "cancelled" : runner.killedOn;
            runner.cancelled = false;
            runner.killedOn = "";
            root.settle(reason);
        }

        onRunningChanged: {
            // False without ever having started: the binary is not there. The
            // one case with no exit code to read.
            if (runner.running || runner.started)
                return;
            root.available = false;
            root.probed = true;
            root.answer = "";
            root.status = "";
            root.failure = root.policy.absent();
            watchdog.stop();
            Logger.warn("launcher", root.policy.absent());
        }
    }

    /// The deadline ladder, ticked. The CLI will retry a dead network for over
    /// two minutes without terminating itself, so nothing below this line is
    /// optional — see ClaudePolicy's own header.
    Timer {
        id: watchdog

        interval: 250
        repeat: true
        running: false

        onTriggered: {
            if (!runner.running) {
                watchdog.stop();
                return;
            }

            const reason = root.policy.deadline(root.run, Date.now() - root.startedAt);
            if (reason === "")
                return;

            watchdog.stop();
            runner.killedOn = reason;
            runner.signal(15);
            Logger.warn("launcher", root.policy.killed(reason));
        }
    }

    // --- is it there, and are we logged in -----------------------------------

    /// The working directory has to exist before the first turn runs in it —
    /// a `Process` with a `workingDirectory` that is not there fails to spawn,
    /// which reads exactly like a missing binary.
    Process {
        id: makeDir

        command: ["mkdir", "-p", Paths.claudeDir]
        running: true

        onExited: preflight.running = true
        onRunningChanged: {
            if (!makeDir.running && !preflight.running)
                preflight.running = true;
        }
    }

    Process {
        id: preflight

        command: root.policy.preflightArgv()
        workingDirectory: Paths.stateDir

        property bool started: false

        stdout: StdioCollector { id: preflightOut }

        onStarted: preflight.started = true

        onExited: (exitCode, exitStatus) => {
            root.probed = true;
            root.available = root.policy.ready(exitCode, preflightOut.text);
            if (root.available)
                Logger.log("launcher", root.policy.found());
            else
                Logger.warn("launcher", root.policy.unauthorised());
        }

        onRunningChanged: {
            if (preflight.running || preflight.started)
                return;
            root.probed = true;
            root.available = false;
            Logger.warn("launcher", root.policy.absent());
        }
    }

    // --- the session that outlives the shell ---------------------------------

    onSessionIdChanged: {
        if (ShellState.ready && root.sessionId !== "")
            ShellState.set("claude.sessionId", root.sessionId);
    }

    Component.onCompleted: {
        root.sessionId = String(ShellState.values.claude.sessionId ?? "");
        Logger.stage("claude provider armed");
    }
}
