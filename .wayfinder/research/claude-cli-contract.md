# Claude provider CLI contract — headless print-mode integration

Wayfinder research ticket [#16](https://github.com/danielbaldwin47/forest-shell/issues/16). Blocks #13.

**Method.** Primary source is the CLI installed on this machine, exercised with ~50 live `claude -p`
probes. Official docs (<https://code.claude.com/docs/en/headless>, `/sessions`, `/cli-reference>`)
were used only for things a probe cannot show. Every claim below marked *(probed)* was reproduced
locally; claims marked *(docs)* come from documentation only.

| Fact | Value |
| --- | --- |
| CLI version (`claude --version`) | **2.1.220 (Claude Code)** |
| Binary path | `/usr/bin/claude` |
| Auth (`claude auth status`) | `loggedIn: true`, `authMethod: "claude.ai"`, `apiProvider: "firstParty"`, `subscriptionType: "max"` |
| Probe date | 2026-07-31 |
| Probe host | CachyOS, kernel 7.1.5-1-cachyos |

---

## 1. Executive summary — the pinned contract

Everything the launcher spec assumes **works**, with five corrections that change the invocation:

1. **`--output-format stream-json` requires `--verbose`.** Without it the CLI prints
   `Error: When using --print, --output-format=stream-json requires --verbose` to stderr and exits 1.
   This is a hard gate, not a warning.
2. **Multi-turn via `--session-id` + `--resume` works across separate `-p` invocations** — confirmed
   over three turns. **But session lookup is scoped to the working directory**: resuming from a
   different `cwd` fails with `No conversation found with session ID: <uuid>`. QML must spawn every
   turn of a conversation with the same, fixed `workingDirectory`.
3. **`--allowedTools` does NOT restrict the tool set** — it only pre-approves permissions. Passing
   `--allowedTools "WebSearch,WebFetch,Read,Grep,Glob"` alone left all 30 built-in tools loaded and
   Claude happily ran `Bash(uname -a)`. Restriction is `--tools`; permission is `--allowedTools`.
   **Both are required.**
4. **Do not use `--bare`.** Docs recommend it for scripted calls and it will become the `-p` default,
   but it hard-disables OAuth ("Anthropic auth is strictly `ANTHROPIC_API_KEY` or `apiKeyHelper`").
   Probed: `--bare` with no API key returns `result.result = "Not logged in · Please run /login"`.
   That would break the subscription-billing requirement. Use `--safe-mode --setting-sources ""`
   instead, which gets the same hermeticity while keeping OAuth.
5. **Claude Code's own context leaks into `-p` by default.** A plain `claude -p` from `/tmp` loaded
   Daniel's `SessionStart` hook (injected "CAVEMAN MODE ACTIVE" into the answer), 44 skills, 2
   plugins, and 20k tokens of context, costing **$0.0187 to answer "Say OK"**. The recommended
   invocation below costs **$0.0002** for the same prompt — a 95x reduction.

---

## 2. Recommended invocation

### 2.1 Conversational answer, no tools (default launcher mode)

```
claude
  -p "<user prompt>"
  --output-format stream-json
  --verbose
  --include-partial-messages
  --model haiku
  --safe-mode
  --setting-sources ""
  --tools ""
  --settings '{"alwaysThinkingEnabled":false}'
  --system-prompt "<forest-shell launcher system prompt>"
  --session-id <uuid v4>
```

Argument-vector notes for QML (`Quickshell.Io.Process`):

- Pass every element as a separate array item; never build a shell string. The prompt goes in
  `argv` unquoted, or pipe it on stdin (`echo "..." | claude -p ...` — probed, works, and is safer
  for prompts containing quotes/newlines; stdin is capped at 10 MB *(docs)*).
- `--settings` takes a JSON **string** as one argv element — no file needed.
- `--system-prompt` **replaces** the entire Claude Code system prompt. This is what collapses the
  input from 3626 tokens (`--safe-mode` alone) → 402 → 146 tokens. Use `--append-system-prompt` only
  if you actually want Claude Code's coding-agent persona, which the launcher does not.
- `--setting-sources ""` suppresses user/project/local settings files (hooks, permissions, model
  overrides). `--safe-mode` additionally kills plugins, skills, CLAUDE.md, MCP, LSP, output styles.
  Use both — they overlap but neither is a superset of the other.

### 2.2 Research answer, read-only + web tools

Add (and drop `--tools ""`):

```
  --tools       "WebSearch,WebFetch,Read,Grep,Glob"
  --allowedTools "WebSearch,WebFetch,Read,Grep,Glob"
```

Cost of the tool definitions: input jumps from 146 → **3634 tokens** per turn. Only enable this mode
when the user explicitly asks for a web-backed answer.

### 2.3 Preflight

Run once at shell start (and on auth failure) — it is cheap and makes no API call:

```
claude auth status
```

Emits JSON on stdout, exit 0 when logged in / 1 when not *(docs)*:

```json
{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty",
 "email":"...","orgId":"...","orgName":"...","subscriptionType":"max"}
```

Gate the "Ask Claude" provider on `loggedIn === true && apiProvider === "firstParty"`.

---

## 3. Billing / auth

- *(probed)* Every `-p` run reports `"apiKeySource":"none"` in the `system/init` event when no
  `ANTHROPIC_API_KEY` is set. That is the OAuth/subscription path. The launcher should assert
  `apiKeySource === "none"` on the init event and abort if it is anything else — that would mean an
  inherited `ANTHROPIC_API_KEY` is silently redirecting billing to an API account.
- *(probed)* `result.total_cost_usd` and `result.modelUsage[*].costUSD` are still populated on a
  subscription run. They are **informational spend equivalents**, not charges. Do not surface them
  as money in the UI; they are useful only for a local budget guard.
- *(probed)* `rate_limit_event` lines report subscription quota:
  `{"status":"allowed","resetsAt":1785522000,"rateLimitType":"five_hour","overageStatus":"rejected","isUsingOverage":false}`.
  `resetsAt` is epoch **seconds**. `status` other than `allowed` is the signal for a
  "you're near/over your 5-hour limit" UI affordance.
- **`--bare` must never be reachable from the launcher config.** See §1.4 and the failure table.
- The launcher process must not inherit `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`,
  `ANTHROPIC_BASE_URL`, or `CLAUDE_CODE_*` from its parent. Quickshell should build an explicit
  child environment. (All probes here scrubbed `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`,
  `CLAUDE_CODE_SESSION_ID`, `CLAUDE_EFFORT`, etc., because an inherited `CLAUDE_EFFORT` silently
  changes the model's effort level.)

---

## 4. stream-json wire format

### 4.1 Stream discipline

- **stdout is strictly line-delimited JSON.** *(probed)* Every warning and every fatal argument error
  goes to **stderr**, never stdout. Verified for: unknown `--effort` value, missing `--verbose`,
  unknown session ID, invalid model. A QML `SplitParser { splitMarker: "\n" }` on stdout can assume
  every non-empty line parses as JSON.
- Still wrap `JSON.parse` in try/catch and drop unparseable lines rather than tearing down the
  stream — lines can be long (a `signature_delta` line is ~1.5 kB; an `assistant` line carrying a
  300-number count was ~2 kB) and a truncated read must not kill the reader.
- Read stderr separately and keep the last ~4 lines for the error surface.
- *(docs)* If the consumer reads slowly, Claude Code waits for the queue to drain before exiting,
  capped at 30 s. Do not assume process-exit means end-of-stream — wait for the `result` line.

### 4.2 Complete line-type catalog

Every distinct line type observed across all probes. `type` is always present; `subtype` narrows
`system` and `result`.

| Line | When | Launcher action |
| --- | --- | --- |
| `system/init` | First line (unless hooks precede). Carries `session_id`, `cwd`, `model`, `tools[]`, `permissionMode`, `apiKeySource`, `claude_code_version`, `mcp_servers`, `plugins`, `capabilities[]`, `output_style` | Latch `session_id`; assert `apiKeySource`, `model`, `tools` match what you asked for; flip UI to "thinking" |
| `system/status` | `status: "requesting"` / `null` with `permissionMode` | Optional spinner state |
| `system/hook_started`, `system/hook_response` | Only when a `SessionStart`/`Setup` hook exists. **Suppressed by `--safe-mode`** | Ignore (should never appear) |
| `system/thinking_tokens` | `estimated_tokens`, `estimated_tokens_delta`. Very chatty (151 lines across probes) | Ignore, or drive a "thinking…" token counter |
| `system/api_retry` | Retryable API failure. `attempt`, `max_retries` (10), `retry_delay_ms`, `error_status`, `error` | **Surface as "retrying (n/10)"**; see §7 |
| `rate_limit_event` | Emitted once per turn | Read `rate_limit_info.status` / `resetsAt` |
| `stream_event/message_start` | Assistant turn begins. `event.message.model`, `.usage` | Start a new answer bubble |
| `stream_event/content_block_start` | `event.content_block.type` ∈ `text` \| `thinking` \| `tool_use`; `event.index` | **Record which index is the text block** |
| `stream_event/content_block_delta` | `event.delta.type` ∈ `text_delta` \| `thinking_delta` \| `signature_delta` \| `input_json_delta` | Append `delta.text` for `text_delta` only |
| `stream_event/content_block_stop` | `event.index` | Close that block |
| `stream_event/message_delta` | `event.delta.stop_reason`, plus final `event.usage` | Read `stop_reason` |
| `stream_event/message_stop` | End of assistant message | — |
| `assistant` | **Whole-message snapshot**, re-emitted after each completed content block. `message.content[]` is the full assembled array | Use as a reconciliation checkpoint, or ignore if you assemble from deltas |
| `user` | Tool results (`content[].type === "tool_result"`), and `[Request interrupted by user]` on SIGTERM | Render tool activity; detect cancel |
| `result` | **Always last.** `is_error`, `subtype`, `result` (final text), `session_id`, `usage`, `modelUsage`, `permission_denials[]`, `terminal_reason`, `ttft_ms`, `duration_ms`, `total_cost_usd`, `api_error_status` | Terminal state — see §7 |

Note the `result` line does **not** always have `"type"` first in key order and in some error paths
`subtype` is `"success"` while `is_error` is `true`. **Branch on `is_error`, never on `subtype`.**

### 4.3 Trimmed raw sample — recommended invocation

`claude -p "What is the capital of France?" --output-format stream-json --verbose
--include-partial-messages --model haiku --safe-mode --setting-sources "" --tools ""
--settings '{"alwaysThinkingEnabled":false}' --no-session-persistence --system-prompt "..."`

```jsonl
{"type":"system","subtype":"init","cwd":"/tmp/fsprobe","session_id":"2f373806-6319-4319-bc84-c0b0f85c4628","tools":[],"mcp_servers":[],"model":"claude-haiku-4-5-20251001","permissionMode":"default","apiKeySource":"none","claude_code_version":"2.1.220","output_style":"default","capabilities":["interrupt_receipt_v1","interrupt_cancel_queued_v1","msg_lifecycle_v1"],"uuid":"…"}
{"type":"system","subtype":"status","status":"requesting","uuid":"…","session_id":"2f373806-…"}
{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1785522000,"rateLimitType":"five_hour","overageStatus":"rejected","overageDisabledReason":"org_level_disabled","isUsingOverage":false},"uuid":"…","session_id":"2f373806-…"}
{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"msg_011CdaMuGfusv4tKAW3Kmvmo","type":"message","role":"assistant","content":[],"stop_reason":null,"usage":{"input_tokens":3634,…}}},"session_id":"…","parent_tool_use_id":null,"uuid":"…"}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"session_id":"…","parent_tool_use_id":null,"uuid":"…"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"The"}},"session_id":"…","parent_tool_use_id":null,"uuid":"…"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" capital of France is **Paris**. It's located in the north-central part of the"}},…}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"."}},…}
{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","id":"msg_011CdaMuGfusv4tKAW3Kmvmo","type":"message","role":"assistant","content":[{"type":"text","text":"The capital of France is **Paris**. …"}],…},"session_id":"…","uuid":"…"}
{"type":"stream_event","event":{"type":"content_block_stop","index":0},…}
{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":3634,"output_tokens":74,…}},…}
{"type":"stream_event","event":{"type":"message_stop"},…}
{"is_error":false,"duration_api_ms":9568,"num_turns":1,"stop_reason":"end_turn","session_id":"2f373806-…","total_cost_usd":0.004592,"usage":{…},"modelUsage":{…},"permission_denials":[],"terminal_reason":"completed","subtype":"success","api_error_status":null,"result":"The capital of France is **Paris**. …","ttft_ms":896,"ttft_stream_ms":887,"time_to_request_ms":64,"type":"result","duration_ms":946,"uuid":"…"}
```

### 4.4 Thinking blocks

By default the model emits an **interleaved thinking block at index 0 and the answer text at index
1**, so a naive "append every `text_delta`" parser is fine but a naive "index 0 is the answer" parser
is not. Thinking deltas also arrive with `estimated_tokens: null` and are followed by a large
`signature_delta` (base64, ~1.4 kB).

*(probed)* **`--settings '{"alwaysThinkingEnabled":false}'` removes thinking entirely** — the answer
becomes content block index 0, no `thinking_delta`/`signature_delta` lines at all, and time-to-first-
visible-token drops by ~0.5 s. Recommended for the launcher.

The inline form `/config thinking=false` as the first line of the prompt also works *(probed)* but
pollutes the prompt; prefer `--settings`.

### 4.5 Tool-use streaming

When a tool fires, the block sequence is:

```jsonl
{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01PUTB2iYwc3aauY91SwAenM","name":"WebSearch","input":{}}},…}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}},…}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"query\": \"Quickshell homepage URL"}},…}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"}"}},…}
```

`input_json_delta.partial_json` fragments must be concatenated across deltas before parsing. For a
launcher UI you almost certainly only want the tool **name** from `content_block_start` (to show
"Searching the web…") and can discard the argument deltas.

The tool's result arrives as a `user` line:

```jsonl
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_…","is_error":false,"content":"Web search results for query: …"}]},…}
```

### 4.6 QML parsing skeleton

```qml
Process {
    id: ask
    // command: [...]  // see §2
    stdout: SplitParser {
        splitMarker: "\n"
        onRead: line => {
            if (!line) return
            let ev
            try { ev = JSON.parse(line) } catch (e) { return }   // never throw out of the handler

            if (ev.type === "system" && ev.subtype === "init") {
                root.sessionId = ev.session_id
                if (ev.apiKeySource !== "none") root.fail("billing-misconfigured")
                return
            }
            if (ev.type === "system" && ev.subtype === "api_retry") {
                root.status = `retrying ${ev.attempt}/${ev.max_retries}…`
                return
            }
            if (ev.type === "rate_limit_event") {
                root.quota = ev.rate_limit_info
                return
            }
            if (ev.type === "stream_event") {
                const e = ev.event
                if (e.type === "content_block_start" && e.content_block.type === "text")
                    root.textIndex = e.index
                else if (e.type === "content_block_start" && e.content_block.type === "tool_use")
                    root.status = `using ${e.content_block.name}…`
                else if (e.type === "content_block_delta"
                         && e.delta.type === "text_delta"
                         && e.index === root.textIndex)
                    root.answer += e.delta.text
                return
            }
            if (ev.type === "result") {          // ALWAYS the last line
                root.finish(ev)                  // branch on ev.is_error, not ev.subtype
            }
        }
    }
    stderr: SplitParser { splitMarker: "\n"; onRead: line => root.stderrTail.push(line) }
}
```

---

## 5. Multi-turn / session management

### 5.1 It works — verified

```bash
SID=$(uuidgen)

# turn 1 — mint the session
claude -p "My favourite colour is chartreuse. Reply with just OK." \
  --output-format json --model haiku --safe-mode --tools "" \
  --session-id "$SID" --system-prompt "$SP"
#   → {"session_id":"c91fb957-…","result":"OK","num_turns":1,"is_error":false}

# turn 2 — continue it, separate process
claude -p "What is my favourite colour? One word." \
  --output-format json --model haiku --safe-mode --tools "" \
  --resume "$SID" --system-prompt "$SP"
#   → {"session_id":"c91fb957-…","result":"Chartreuse","num_turns":1,"is_error":false}

# turn 3 — still works, history accumulates
claude -p "And what did I say before that? One sentence." … --resume "$SID"
#   → "You asked me to reply with just OK."
```

Key mechanics *(all probed)*:

| Behaviour | Result |
| --- | --- |
| `--session-id <uuid>` on turn 1 | Session is created with exactly that UUID. Must be a valid UUID (v4 is fine). |
| `--resume <uuid>` on turns 2..n | Same `session_id` echoed back — **the session is not forked**. |
| `num_turns` in each result | Always `1` — it counts turns *in this invocation*, not the conversation. Do not use it as a conversation length. |
| Transcript location | `~/.claude/projects/<cwd-with-non-alphanumerics-replaced-by-dashes>/<session-id>.jsonl` — e.g. `/tmp/fsprobe` → `~/.claude/projects/-tmp-fsprobe/c91fb957-….jsonl`. Grew to 22 lines over 3 turns. |
| `--continue` (no id) | Resumes the most recent session **in that cwd** and reuses its id. Works in `-p`. Racy if the launcher ever runs two conversations — prefer explicit ids. |
| `--fork-session` with `--resume` | New session id, full history inherited. Useful for a "branch this answer" affordance. |
| Token growth | Turn-3 input was 890 tokens vs 146 for a fresh turn. History is resent every turn; there is no server-side session. Budget for it. |

### 5.2 The cwd trap — **hard requirement**

```
$ cd /tmp/fsprobe  && claude -p "…" --session-id $SID              # ok
$ cd /tmp/fsprobe2 && claude -p "…" --resume    $SID
No conversation found with session ID: 933a66ba-684d-40d1-b4fa-cf0ce2e647ae     (exit 1)
$ cd /tmp/fsprobe  && claude -p "…" --resume    $SID
"Your code word is pineapple."                                                  (exit 0)
```

*(docs)* "session ID lookup is scoped to the current project directory and its git worktrees."

**Contract for the launcher:** pin a single `workingDirectory` for the Ask Claude provider — a
dedicated, stable, non-git directory such as `$XDG_STATE_HOME/forest-shell/claude` — and use it for
every invocation. Never inherit the compositor's cwd (it varies) and never use a git repo (worktree
scoping widens the lookup unpredictably).

### 5.3 `--no-session-persistence`

*(probed)* Mutually exclusive with resumability, as expected:

- No transcript file is written (`~/.claude/projects/<cwd>/` has no `<sid>.jsonl`).
- It does **not** conflict with `--session-id` — the flag is accepted, the run succeeds, and the
  result still echoes the requested `session_id`, but a subsequent `--resume` fails with
  `No conversation found with session ID: <uuid>`.

Use it for one-shot answers (privacy-friendly, no disk trail). Omit it the moment the user can send
a follow-up. `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1` in the env does the same thing globally *(docs)* —
make sure the launcher does not inherit it, or resume will silently never work.

### 5.4 What resume does and does not restore

*(docs)* Restored: conversation history (including tool calls/results), model, permission mode
(except `plan`/`bypassPermissions`). **Not restored:** `--settings`, `--mcp-config`, `--plugin-dir`,
`--add-dir`, `--fallback-model`.

⇒ **Re-pass the full flag set on every resume**, including `--system-prompt`, `--tools`,
`--allowedTools`, `--settings '{"alwaysThinkingEnabled":false}'`, `--safe-mode`,
`--setting-sources ""`. All probes above did this and behave consistently.

---

## 6. Tool policy

### 6.1 The two flags do different things

| Flag | Effect *(probed)* |
| --- | --- |
| `--tools "A,B,C"` | **Restricts the loaded set.** `system/init.tools` becomes exactly `["A","B","C"]` (sorted). `--tools ""` ⇒ `tools: []`. The model is told it has nothing else. |
| `--allowedTools "A,B,C"` | **Grants permission only.** Does *not* restrict — init still listed all 30 tools and `Bash(uname -a)` executed successfully. |
| `--disallowedTools "Bash"` | Removes the named tool from context entirely (init listed 29 tools, no `Bash`). Scoped rules like `Bash(rm *)` leave the tool but deny matching calls *(docs)*. |

Both accept **comma-separated in one argv element** *and* **space-separated as multiple argv
elements** — verified equivalent:

```
--allowedTools "WebSearch,WebFetch,Read,Grep,Glob"
--allowedTools WebSearch WebFetch Read Grep Glob
```

Prefer the single comma-separated element in QML — a space-separated list is a variadic option and
will swallow a following positional argument if you get the ordering wrong.

Scoped rules use permission-rule syntax, e.g. `Bash(git diff *)`; the space before `*` matters
*(docs)*.

### 6.2 The read-only + web set — exact syntax

```
--tools        "WebSearch,WebFetch,Read,Grep,Glob"
--allowedTools "WebSearch,WebFetch,Read,Grep,Glob"
```

Verified end to end: init reported `tools: ["Glob","Grep","Read","WebFetch","WebSearch"]`, WebSearch
ran without a permission error, and the answer cited real URLs.

**Both flags are required.** With `--tools` alone the tool is loaded but *not permitted*:

```jsonl
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"WebSearch","input":{"query":"today's date Tokyo July 2026"}}]},…}
{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"Claude requested permissions to use WebSearch, but you haven't granted it yet."}]},…}
```

### 6.3 What a denial actually looks like

There is **no error event and no non-zero exit**. Denial is soft and the run still completes with
`is_error: false`, `subtype: "success"`. Three distinguishable shapes:

| Scenario | Stream evidence | Final answer |
| --- | --- | --- |
| Tool loaded but not permitted (`--tools` without `--allowedTools`) | `tool_use` block, then `user`/`tool_result` with `is_error: true` and text `"Claude requested permissions to use WebSearch, but you haven't granted it yet."`. **`result.permission_denials[]` is populated** with `{tool_name, tool_use_id, tool_input}` | Degraded — Claude answers from context and does not mention the denial reliably |
| Tool not loaded at all (`--tools ""` or not in the list) | **No `tool_use` at all**, `permission_denials` is `[]` | Claude states it lacks the tool ("I don't have access to a shell command execution tool. The tools available to me are: Glob, Grep, Read, WebFetch, WebSearch") |
| `--permission-mode dontAsk` with the tool loaded | `tool_use` block, then `tool_result` `is_error: true`: `"Permission to use Bash has been denied because Claude Code is running in don't ask mode. …"`. `permission_denials` populated | Claude explains it cannot run the command |

**Launcher rule:** after every turn, if `result.permission_denials.length > 0`, surface a small
"Claude wanted to use *X* but isn't allowed" chip. That array is the only reliable machine-readable
denial signal — the prose answer is not.

With `--tools ""` Claude sometimes *hallucinates the shape of tool use* before catching itself
("I'll read the /etc/hostname file for you. ```bash cat /etc/hostname``` Please give me a moment…
Unfortunately, I don't have direct access…"). If the launcher offers a no-tools mode, the system
prompt should say so explicitly.

### 6.4 `--permission-mode` headlessly

Accepted values *(help text)*: `acceptEdits`, `auto`, `bypassPermissions`, `manual`, `dontAsk`,
`plan`. Docs add `default` (`manual` is its alias since v2.1.200).

*(probed)* Observed defaults are surprising and matter:

- With **no** `--permission-mode`, `system/init.permissionMode` came back as **`"auto"`** in every
  headless run that had tools available — Claude Code auto-classifies and self-approves. `Bash` ran
  unprompted. Do not rely on "default = safe".
- **`--permission-mode manual` did NOT block `Bash`** in print mode — the tool executed. There is no
  human to prompt, so `manual` degrades to permissive. `init.permissionMode` reported `"default"`.
- **`--permission-mode dontAsk` is the real headless deny gate** — it denies anything outside
  `permissions.allow` and the read-only command set *(docs)*, confirmed by the `rm -rf` probe above.

**Contract:** treat `--tools` as the primary containment boundary (it is the only one that changed
what the model was *offered*), and add `--permission-mode dontAsk` as defence in depth. Never rely on
`manual` or the absence of a flag.

---

## 7. Failure states

Reproduced locally except where noted. `exit` is the process exit status.

| State | exit | stdout | Distinguishing signal |
| --- | --- | --- | --- |
| Success | 0 | full stream + `result` | `is_error:false`, `terminal_reason:"completed"`, `subtype:"success"` |
| **Invalid model** | 1 | `init`, then a synthetic `assistant` line, then `result` | `assistant.error === "model_not_found"`, `is_api_error_message:true`, `message.model === "<synthetic>"`; `result.is_error:true`, `result.api_error_status: 404`, `terminal_reason:"api_error"`, `result.result` = `"There's an issue with the selected model (bogus-model-xyz). It may not exist or you may not have access to it. Run --model to pick a different model."` — note `subtype` is still `"success"` |
| **Not logged in** (reproduced via `--bare` with no API key; same shape expected after logout) | 1 | `result` only | `is_error:true`, `terminal_reason:"api_error"`, `api_error_status:null`, `result.result === "Not logged in · Please run /login"` |
| **Unknown session id** (`--resume`) | 1 | one `result` line | `type:"result"`, `subtype:"error_during_execution"`, `is_error:true`, `errors:["No conversation found with session ID: <uuid>"]`, `num_turns:0`. Same text also on stderr. |
| **Offline / unreachable API** | **hangs** | `init`, then repeating `system/api_retry` | `subtype:"api_retry"` with `attempt` 1→10, `retry_delay_ms` 526 → 1070 → 2356 → 4075 → 9380 → 17853 → 37635 (exponential). `error:"unknown"`, `error_status:null` for connection errors. **Total backoff exceeds 120 s** — the process will not self-terminate in a UI-acceptable window. |
| **Budget exceeded** (`--max-budget-usd`) | 1 | `result` | `subtype:"error_max_budget_usd"`, `terminal_reason:"budget_exhausted"`, `errors:["Reached maximum budget ($1e-7)"]` |
| **Cancelled (SIGTERM)** | **143** | partial stream, then a `user` line `[Request interrupted by user]`, then `result` | `subtype:"error_during_execution"`, `terminal_reason:"aborted_streaming"`, `is_error:true`. Clean — the CLI flushes a terminal `result` before exiting. *(docs: SIGTERM aborts the turn, kills the Bash process tree, runs `SessionEnd` hooks, exits 143.)* |
| **Missing `--verbose`** | 1 | *(empty)* | stderr only: `Error: When using --print, --output-format=stream-json requires --verbose` |
| **Unknown `--effort` value** | 0 | normal stream | stderr only: `Warning: Unknown --effort value 'bogus' — ignoring it and using the default effort. Valid values: low, medium, high, xhigh, max.` — **the run proceeds at default effort**, so a typo silently changes behaviour |
| **Rate limited** *(not reproduced — quota was `allowed`)* | — | — | Watch `rate_limit_event.rate_limit_info.status !== "allowed"` and `system/api_retry` with `error: "rate_limit"`. *(docs)* `api_retry.error` categories: `authentication_failed`, `oauth_org_not_allowed`, `billing_error`, `rate_limit`, `overloaded`, `invalid_request`, `model_not_found`, `server_error`, `max_output_tokens`, `unknown` |

### 7.1 Timeout policy — mandatory

The offline probe proves the CLI will retry for **well over two minutes** with no terminal event.
The launcher must own the deadline:

- **Watchdog A — no `system/init` within 5 s** ⇒ kill, report "Claude CLI failed to start".
  (Observed init at 922–1049 ms; 5 s is ~5x headroom.)
- **Watchdog B — no first `text_delta` within 20 s** ⇒ kill, report "no response".
- **Watchdog C — 2 or more `system/api_retry` events** ⇒ kill immediately and report "network
  problem"; do not wait out the 10-retry ladder.
- **Watchdog D — absolute cap 120 s** ⇒ kill.
- Kill with **SIGTERM**, not SIGKILL: SIGTERM produces a clean terminal `result` and exit 143, and
  it lets the CLI tear down any child process tree.
- Also arm **`--max-budget-usd`** (e.g. `0.50`) as a runaway guard — it produces a clean,
  distinguishable `error_max_budget_usd` result.

---

## 8. Model & effort matrices

### 8.1 `--model` aliases *(probed)*

| Passed | Resolved `canonicalModel` | Context | Max output |
| --- | --- | --- | --- |
| `haiku` | `claude-haiku-4-5` (`claude-haiku-4-5-20251001`) | 200 000 | 32 000 |
| `sonnet` | `claude-sonnet-5` | 1 000 000 | 64 000 |
| `opus` | `claude-opus-5` | 1 000 000 | 64 000 |
| `fable` | `claude-fable-5` | 1 000 000 | 64 000 |
| `opusplan` | resolved to `claude-sonnet-5` for a `-p` run (plan-mode-only alias; **do not use headlessly**) | 1 000 000 | 64 000 |
| `default` | `claude-opus-5[1m]` (this machine's configured default) | 1 000 000 | 64 000 |
| full id, e.g. `claude-sonnet-4-6` | `claude-sonnet-4-6` | 200 000 | 32 000 |
| unknown, e.g. `bogus-model-xyz` | **error**, exit 1, 404 — see §7 | — | — |

**Pin an explicit alias.** Omitting `--model` inherits Daniel's `default` (Opus) — expensive and
slower for launcher-sized questions.

Recommendation: `haiku` for the default Ask Claude path, `sonnet` for an explicit "think harder"
affordance. Opus showed no latency or quality advantage at this prompt size.

`--fallback-model sonnet,haiku` is available and `--print`-only; worth wiring for overload
resilience.

### 8.2 `--effort` *(probed)*

Valid values, per the CLI's own warning text: **`low`, `medium`, `high`, `xhigh`, `max`**
(docs add `ultracode`, v2.1.203+). Anything else — including `none`/`off` — prints a stderr warning
and **silently falls back to default**; there is no "effort off".

Effort had no measurable effect on a trivial prompt (sonnet, "What is 2+2?", 3 output tokens,
ttft 1350–5221 ms with no monotonic trend — noise dominated). Availability is model-dependent.

**To reduce latency, disable thinking (`--settings '{"alwaysThinkingEnabled":false}'`), not effort.**
That is the knob that actually removed thinking blocks and cut ~0.5 s off first-token time.

Beware: an inherited `CLAUDE_EFFORT` environment variable silently sets effort. Scrub it.

---

## 9. Latency

Recommended invocation (`--safe-mode --setting-sources "" --tools ""`, thinking off, custom system
prompt), prompt "What is the capital of France?", 3 runs each, wall clock from `exec()`:

| Model | `ttft_ms` (CLI-internal, median of 3) | wall `exec` → `init` | wall `exec` → **first `text_delta`** | wall `exec` → `result` | cost/turn |
| --- | --- | --- | --- | --- | --- |
| `haiku` | **896 ms** (896 / 1821 / 896) | 974–1006 ms | **1629 / 1684 ms** | 1783–2053 ms | $0.0002–0.0008 |
| `sonnet` | **1410 ms** (1423 / 1129 / 1410) | 922–1007 ms | **1774 / 1815 ms** | 2391–2515 ms | $0.0014 |
| `opus` | **1461 ms** (1461 / 1353 / 1722) | 1033–1049 ms | **2179 / 2201 ms** | 2541–2886 ms | $0.0012–0.0018 |

Breakdown of where the time goes:

- **~1.0 s constant CLI startup** before `system/init` — Node boot + config resolution. This is the
  dominant cost for short answers and it is *not* reducible by model choice.
  `result.time_to_request_ms` (init → request sent) was only **52–80 ms** with
  `--setting-sources ""`, vs 116–146 ms with `--safe-mode` alone — so the flags help a little, but
  the ~1 s floor is process startup.
- **`result.ttft_ms`** is measured from request dispatch, not from `exec`. Real perceived latency is
  `≈ 1.0 s + ttft_ms`.
- Thinking on adds ~0.5 s: the same haiku prompt with thinking enabled had `exec` → first *text*
  delta at ~2159 ms vs ~1650 ms with it off.

**UX implication:** budget **~1.7 s to first visible token on haiku**. The launcher should show a
placeholder/spinner immediately on Enter, and should not wait for `system/init` to render the row.
A persistent warm process would eliminate the 1 s startup, but `-p` is one-shot by design; the
alternative is `--input-format stream-json` with a long-lived process (out of scope for this ticket,
worth a follow-up if 1.7 s proves unacceptable).

Cost note: the same prompt with default Claude Code context loaded (no `--safe-mode`, no
`--system-prompt`) cost **$0.0187** and read 20 137 tokens of context. The recommended invocation
costs **$0.0002**. Enabling the read-only+web tool set raises input from 146 → 3634 tokens.

---

## 10. Open items / follow-ups

1. **Warm-process mode.** `--input-format stream-json` supports realtime streaming input into a
   long-lived process, which would remove the ~1 s per-question startup and make multi-turn free of
   the cwd-scoping trap. Not probed. Worth a separate ticket if 1.7 s TTFT is judged too slow.
2. **Rate-limit shape unverified.** Quota was `allowed` throughout. The `rate_limit_event` +
   `api_retry(error:"rate_limit")` handling is designed from docs, not observation.
3. **`--json-schema`** exists and puts validated structured output in `result.structured_output`.
   Potentially useful for a "give me a command to run" launcher action.
4. **`--bare` will become the `-p` default in a future release** *(docs)*. When that lands, the
   launcher must pass an explicit opt-out or it will lose OAuth billing overnight. Pin the CLI
   version check on startup and re-verify `apiKeySource === "none"` on every `system/init`.
5. **Session GC.** Transcripts accrue in `~/.claude/projects/<cwd>/` with a 30-day default retention
   (`cleanupPeriodDays`). If the launcher uses a dedicated cwd, decide a retention policy rather than
   inheriting the global one.

---

## Sources

- Installed CLI 2.1.220: `claude --help`, `claude auth status`, ~50 live `claude -p` probes
  (2026-07-31).
- <https://code.claude.com/docs/en/headless> — Run Claude Code programmatically.
- <https://code.claude.com/docs/en/sessions> — Manage sessions (resume scope, transcript paths).
- <https://code.claude.com/docs/en/cli-reference> — flag semantics, permission modes, exit codes.
