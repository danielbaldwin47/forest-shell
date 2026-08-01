# Launcher

Sources: [#9](https://github.com/danielbaldwin47/forest-shell/issues/9), [#11](https://github.com/danielbaldwin47/forest-shell/issues/11), [#16](https://github.com/danielbaldwin47/forest-shell/issues/16), [#7](https://github.com/danielbaldwin47/forest-shell/issues/7), [#12](https://github.com/danielbaldwin47/forest-shell/issues/12), [#27](https://github.com/danielbaldwin47/forest-shell/issues/27), [.wayfinder/prototypes/launcher-clearing/findings.md](../../.wayfinder/prototypes/launcher-clearing/findings.md), [.wayfinder/research/claude-cli-contract.md](../../.wayfinder/research/claude-cli-contract.md)

The launcher is a clearing: a full-screen fog scrim with one centred card floating in it, holding the search field and the results in a single surface. It is a prefix dispatcher over six providers.

## Window and surface

The launcher is content inside the **shared per-screen drawer window** — it does not own a window. It opens on the focused screen, is globally exclusive with the other drawers, and shares the drawer's single `HyprlandFocusGrab`. Layer namespace `forest-shell:launcher`.

The scrim is the drawer window's full-screen background: the design brief's **pale mist**, `rgba(190,206,209,0.10)`, over the compositor's blur, with a 5%→0 top-lit god-ray wash across the whole scrim (on by default; it costs nothing). The scrim animates **opacity only** — blur never animates.

The bar renders **above** the scrim and stays clickable; clicking another bar icon while the launcher is open runs the cross-drawer transition rather than dismissing.

## Layout

| Property | Value |
|---|---|
| Horizon | **32%** of screen height — the field's hairline rule sits here |
| Column width | **720** logical px, centred |
| Card radius | 16 (large radius token) |
| Card fill | `surface` @ **90%**, top-lit |
| Row height | **46** px |
| Row icon | 22 px |
| Row title | 14.5 px |
| Row subtitle | 12 px |
| Category label | 10.5 px caps, +0.08em tracking |
| Prose measure (Ask Claude transcript) | capped at **600** px inside the 720 column |

At 32% on a 1280×720 logical screen the list shows **8 rows** with sky above and the legend clear. 22% floats the field high in empty sky and lets the list dominate; 42% crowds the legend and leaves no sky. The clearing is the emptiness *around* the card, not the horizon line itself — once the field lives in a card the rule is an internal divider, not a horizon spanning the screen.

**The list is capped at the fold and does not scroll.** When more results match than fit, the last line of the card reads `N more`. Selection cannot move past the last visible row; reaching the rest is a matter of refining the query.

## The card

One surface, radius 16, `surface` @90%, top-lit, holding the field, the hairline rule, the result rows and the footer legend. **The card is what lets the scrim stay pale**: a pale wash lightens exactly the surface light text sits on, so every piece of text in the launcher sits on the card and none sits on bare fog.

Structure, top to bottom:

1. **Field row** — provider chip on the left, input, model chip on the right (Ask Claude only). The provider chip names the room you are in ("Calculate", "Clipboard", "Ask Claude") the moment a prefix resolves.
2. **1 px `border-subtle` hairline** under the field.
3. **Result rows**, 46 px each, separated by nothing — the rows are bands, not cards.
4. **`N more`** line when the list is capped.
5. **Footer legend** — a thin strip inside the card, hairline above it.

### Text roles on the card

**`text-muted` carries no text anywhere in the launcher.** Row titles are `text-primary` when selected and `text-secondary` otherwise; subtitles, category labels, the `N more` count and the footer legend are all full-opacity `text-secondary`. Differentiation is by size, caps and tracking — never by opacity.

Constraint: `text-muted` on the card measures **4.26:1** over a bright wallpaper against a 4.5:1 floor, and on bare scrim it measures **1.96:1**. Full-opacity `text-secondary` in the same place measures **4.84:1** with no backing plate at all. The card stays at 90%; the roles move.

## Rows

Every row carries its **category label** (`APP`, `ACTION`, `EMOJI`, …) — on every row, not only the selected one.

**Selection**: `accent-deep` @18% fill + **2 px `accent-primary` left rail** + the icon at full saturation.

**Unselected rows sit in the haze**: icon desaturated 65%, brightness lifted 6%, opacity 72%; title dropped to `text-secondary`. Selection reads even with the fill and the rail removed, and the list looks like depth rather than a highlight bar.

Constraint: the design brief's §6.5 rule — "only the selected row's icon warms to `#d8ac81`" — **cannot apply to app icons**, which are full-colour PNGs. Amber survives only on the providers that use monochrome Lucide glyphs (Calculator, Clipboard, Emoji, Actions), where the selected row's icon does warm to `accent-warm` and is the one amber element on screen. Real app icons never take amber.

Selection **cuts** between rows — the fill and rail fade in at the new row over 140 ms and there is no travelling rail. Interruptible.

## Footer legend

A thin strip **inside the card**, hairline above, listing the six providers and their prefixes:

```
= calc    ; clipboard    : emoji    / actions    ? ask claude
```

Full-opacity `text-secondary` on the card surface. The prefix that is currently active brightens to `text-primary`. This strip is how the providers become discoverable at all; without it the prefix vocabulary is invisible.

Constraint: this legend used to sit on bare scrim in `text-muted` and measured 1.96–2.39:1. Moving it inside the card and to full-opacity `text-secondary` is the fix, by the same no-text-on-bare-fog mechanism as everything else on the card.

## Compositor blur

**Compositor blur is cosmetic, not load-bearing.** A Gaussian smears detail but leaves the mean luminance roughly where it was, so blur can never fix a contrast problem and its absence can never cause one. Measured off the captures:

| | busy wall, blur on | blur off | ridge wall, blur on | blur off |
|---|---|---|---|---|
| `text-muted` on the card | 4.43:1 | 4.43:1 | 4.26:1 | 4.26:1 |
| footer legend on bare scrim | 2.39:1 | 2.39:1 | 1.96:1 | 1.96:1 |

Identical to two decimal places in both directions. The card insulates its contents completely.

Consequences, all binding:

- Ship `layerrule = blur, forest-shell:*` **unconditionally**. It is a no-op when `decoration:blur:enabled` is off globally, so it costs nothing to always set.
- **Nothing is mandatory from Hyprland.** `decoration:blur:enabled` is documented as an optional step that makes the shell look better. Global blur changes every window and costs iGPU time on the T480.
- **No veil ladder.** Stepping the veil up when blur is unavailable is actively wrong for a *pale* mist — it raises the luminance under the light footer text: 0.10 → 2.39:1, 0.18 → 2.10:1, 0.26 → 1.85:1. Every rung makes it worse and none of it touches the card.

If anything ever does need to adapt, the shell can detect blur at startup. Verified against upstream 0.3.0, returns in a few ms:

```qml
Process {
    running: true
    command: ["hyprctl", "getoption", "decoration:blur:enabled", "-j"]
    stdout: StdioCollector {
        onStreamFinished: Theme.compositorBlur = JSON.parse(this.text).int === 1
    }
}
```

Nothing in v1 consumes that flag.

## Providers

Dispatch is by prefix on the raw query. The prefix is stripped before the provider sees the query.

| Provider | Prefix | Backing | Notes |
|---|---|---|---|
| Apps | *(none — default)* | `DesktopEntries` | Fuzzy match over name, generic name and exec; ranked by frecency |
| Calculator | `=` or a leading digit | `qalc` CLI | |
| Clipboard | `;` | `cliphist` | Image entries render thumbnails |
| Emoji | `:` | bundled list | |
| Actions | `/` | shell-internal | Dark mode, wallpaper, session, settings pages |
| Ask Claude | `?` | Claude Code CLI, headless print mode | Multi-turn chat |

**Apps** — frecency is a JSON use-count map kept in the **state file** under `Quickshell.stateDir`, debounced on write. Nothing the launcher writes may land inside the config directory; Quickshell hot-reloads on any write there.

**Calculator** — runs `["qalc", "-t", "<expression>"]` through `Process` on a 120 ms debounce, one process per settled query. The result row's action copies the result to the clipboard.

**Clipboard** — `["cliphist", "list"]` to enumerate, `["cliphist", "decode", "<id>"]` to fetch. The history is fed by `wl-paste --type text --watch cliphist store` and `wl-paste --type image --watch cliphist store` from Hyprland autostart — the shell does not own the watcher. There is no separate clipboard panel; this provider is the only surface.

**Emoji** — a bundled list shipped in `Assets/`, matched on name and keywords. Selecting copies the character.

**Actions** — shell-internal commands only: dark/light mode toggle, wallpaper picker, session commands (lock, log out, suspend, reboot, power off) and direct jumps to settings pages. This provider is also the **shell-switch launcher entry point**: `qs ipc call launcher actions` opens the launcher directly into it.

## Ask Claude

Backed by the **Claude Code CLI in headless print mode**, which bills against the user's **subscription via OAuth**, not an API key. The launcher panel becomes a lightweight chat: the transcript replaces the results list in the same column at the same horizon, the field placeholder becomes `Reply…`, and a model chip (`haiku`, mono, `accent-warm`) appears on the right of the field. Turn labels use the caps micro-label — `YOU` in `text-secondary`, `CLAUDE` in `accent-primary`. The streaming caret is a **7×15 px block**, not a text cursor. Prose wraps at the 600 px measure inside the 720 px column.

In transcript mode there is no results list, so the model chip is the one amber element on screen; it never coexists with a warmed row icon.

The provider hides itself when `claude` is not on `PATH`, or when the preflight fails.

### Working directory — hard requirement

Session lookup is **scoped to the working directory**. Resuming from a different cwd fails with `No conversation found with session ID: <uuid>`.

The provider pins one fixed, stable, **non-git** working directory and uses it for every invocation:

```
$XDG_STATE_HOME/forest-shell/claude      # fallback ~/.local/state/forest-shell/claude
```

Created at shell start. Never inherit the compositor's cwd (it varies) and never use a git repo (worktree scoping widens the lookup unpredictably).

### Preflight

Run once at shell start and again on any auth failure. It makes no API call:

```
claude auth status
```

Emits JSON on stdout, exit 0 when logged in. Gate the provider on `loggedIn === true && apiProvider === "firstParty"`.

```json
{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"max"}
```

Also pin a CLI version check here. Known-good: **2.1.220**.

### Invocation

Turn 1, exact argv — every element a separate array item, never a shell string:

```
["claude",
 "-p", "<user prompt>",
 "--output-format", "stream-json",
 "--verbose",
 "--include-partial-messages",
 "--model", "haiku",
 "--safe-mode",
 "--setting-sources", "",
 "--tools", "WebSearch,WebFetch,Read,Grep,Glob",
 "--allowedTools", "WebSearch,WebFetch,Read,Grep,Glob",
 "--permission-mode", "default",
 "--settings", "{\"alwaysThinkingEnabled\":false}",
 "--system-prompt", "<forest-shell launcher system prompt>",
 "--max-budget-usd", "0.50",
 "--session-id", "<uuid v4>"]
```

Turns 2..n are the **same flag set** with `--session-id <uuid>` replaced by `--resume <uuid>`.

Flag-by-flag, all of it load-bearing:

- **`--verbose` is required.** Without it, `--output-format stream-json` prints `Error: When using --print, --output-format=stream-json requires --verbose` to stderr and exits 1. Hard gate, not a warning.
- **`--safe-mode` and `--setting-sources ""` together** make the run hermetic. `--setting-sources ""` suppresses user/project/local settings files (hooks, permissions, model overrides); `--safe-mode` additionally kills plugins, skills, CLAUDE.md, MCP, LSP and output styles. They overlap and neither is a superset — pass both. A plain `claude -p` loads hooks, CLAUDE.md, 44 skills and 2 plugins, reads 20 137 tokens of context and costs **$0.0187** to answer "Say OK"; this invocation costs **$0.0002**.
- **`--system-prompt` replaces** Claude Code's coding-agent prompt entirely (3626 → 146 input tokens). Never `--append-system-prompt`.
- **`--settings '{"alwaysThinkingEnabled":false}'`** removes thinking blocks entirely — the answer becomes content block index 0 and time-to-first-visible-token drops ~0.5 s. `--effort` does not do this; there is no "effort off".
- **`--tools` and `--allowedTools` do different things and both are required.** `--tools` restricts the loaded set (`system/init.tools` becomes exactly that list); `--allowedTools` only grants permission. Passing `--allowedTools "WebSearch,WebFetch,Read,Grep,Glob"` alone left all 30 built-in tools loaded and `Bash(uname -a)` executed successfully. Passing `--tools` alone loads the tool but denies it at use time. Use the single comma-separated argv element, not the space-separated variadic form. With the tool list empty, pass `--tools ""`.
- **`--resume` does not restore `--settings`, `--mcp-config`, `--plugin-dir`, `--add-dir` or `--fallback-model`.** Re-pass the full flag set on every turn.

**`--no-session-persistence` is never passed.** It is accepted alongside `--session-id` and the run succeeds, but no transcript is written and the next `--resume` fails.

### `--bare` must be unreachable

`--bare` makes Anthropic auth strictly `ANTHROPIC_API_KEY`/`apiKeyHelper`, which kills OAuth: probed with no API key it returns `result.result = "Not logged in · Please run /login"`. The docs recommend it for scripted calls and state **it will become the `-p` default in a future release**.

Therefore:

- No settings key, action or code path may add flags to the argv. The flag list is closed.
- **Assert `apiKeySource === "none"` on every `system/init` event.** Anything else means an inherited `ANTHROPIC_API_KEY` is silently redirecting billing to an API account — abort the turn and surface `billing-misconfigured`.
- The version check in preflight is what catches the day `--bare` becomes the default.

**Environment**: build an explicit child environment. Scrub `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_SKIP_PROMPT_HISTORY` and `CLAUDE_EFFORT`. An inherited `CLAUDE_EFFORT` silently changes the model's effort level; an inherited `CLAUDE_CODE_SKIP_PROMPT_HISTORY` makes resume silently never work.

`result.total_cost_usd` and `result.modelUsage[*].costUSD` are populated on subscription runs, but they are **informational spend equivalents, not charges**. Never surface them as money in the UI; they exist for the local budget guard only.

### Inline model override

`?haiku …` / `?sonnet …` / `?opus …` — the first whitespace-delimited token after `?`, if it is exactly `haiku`, `sonnet` or `opus`, is consumed as the model and stripped from the prompt. Bare `?` uses `launcher.claude.model`.

Aliases resolve to `claude-haiku-4-5`, `claude-sonnet-5`, `claude-opus-5`. **Always pin `--model` explicitly** — omitting it inherits the machine's configured default. An override applies to the whole conversation from that turn on.

### Reading the stream

stdout is strictly **line-delimited JSON**; every warning and every fatal argument error goes to stderr, never stdout. Parse with `SplitParser { splitMarker: "\n" }`, wrap `JSON.parse` in try/catch and drop unparseable lines rather than tearing down the stream (lines reach ~2 kB). Read stderr separately and keep the last ~4 lines for the error surface.

| Line | Action |
|---|---|
| `system/init` | Latch `session_id`; assert `apiKeySource === "none"`; assert `model` and `tools` match the request; flip the UI to "thinking" |
| `system/status` | Optional spinner state |
| `system/thinking_tokens` | Ignore |
| `system/api_retry` | Show `retrying n/10`; **count it** — watchdog C |
| `rate_limit_event` | Read `rate_limit_info.status` / `resetsAt` (epoch **seconds**); anything other than `"allowed"` shows a "near your 5-hour limit" affordance |
| `stream_event/content_block_start` | Record which `index` is the `text` block; on `tool_use`, show `using <name>…` from `content_block.name` |
| `stream_event/content_block_delta` | Append `delta.text` for `text_delta` **at the recorded text index only** |
| `stream_event/message_delta` | Read `delta.stop_reason` |
| `assistant` | Whole-message snapshot; use as a reconciliation checkpoint or ignore |
| `user` | Tool results, and `[Request interrupted by user]` on SIGTERM |
| `result` | **Always the last line.** Terminal state |

**Branch on `result.is_error`, never on `result.subtype`** — some error paths report `subtype: "success"` with `is_error: true`, and key order is not stable. Do not treat process exit as end-of-stream; wait for the `result` line (the CLI waits up to 30 s for a slow consumer to drain).

`input_json_delta.partial_json` fragments must be concatenated before parsing, but the launcher only needs the tool **name** from `content_block_start` and discards the argument deltas.

### Deadlines — the provider owns them

An unreachable API produces a `system/api_retry` ladder — 10 attempts, `retry_delay_ms` 526 → 1070 → 2356 → 4075 → 9380 → 17853 → 37635 — with **no terminal event for well over 120 s**. The CLI will not self-terminate in a UI-acceptable window, so the launcher must:

| Watchdog | Trigger | Report |
|---|---|---|
| A | no `system/init` within **5 s** | "Claude CLI failed to start" |
| B | no first `text_delta` within **20 s** | "no response" |
| C | **2 or more** `system/api_retry` events | "network problem" — kill immediately, do not wait out the ladder |
| D | absolute cap **120 s** | timeout |

Kill with **SIGTERM, never SIGKILL**. SIGTERM produces a clean terminal `result` (`terminal_reason: "aborted_streaming"`, exit 143) and lets the CLI tear down its child process tree. `--max-budget-usd 0.50` is the runaway guard and produces a distinguishable `subtype: "error_max_budget_usd"`.

### Tool denials

A denial is **soft**: no error event, exit 0, `is_error: false`. Three distinguishable shapes:

| Case | Signal |
|---|---|
| Loaded but not permitted | `tool_result` `is_error: true`, `"Claude requested permissions to use WebSearch, but you haven't granted it yet."` + **`result.permission_denials[]` populated** |
| Not loaded at all | no `tool_use` emitted; Claude states it lacks the tool; `permission_denials` empty |
| `--permission-mode dontAsk` | `tool_result` `is_error: true`, `"…denied because Claude Code is running in don't ask mode."` + `permission_denials` populated |

**After every turn, if `result.permission_denials.length > 0`, show a chip: "Claude wanted to use *X* but isn't allowed."** That array is the only reliable machine-readable denial signal — the prose answer is not. The chip is `text-secondary` on `surface-overlay`, **not amber**; the one-amber rule holds.

Constraint: `--tools` is the real containment boundary. `--permission-mode manual` did **not** block a loaded `Bash` headlessly (there is no human to prompt), and the observed default mode with tools available is `auto`, which self-approves. Never rely on the permission mode alone.

### Failure states

| State | exit | Distinguishing signal |
|---|---|---|
| Success | 0 | `is_error: false`, `terminal_reason: "completed"` |
| Invalid model | 1 | `result.api_error_status: 404`, `terminal_reason: "api_error"` |
| Not logged in | 1 | `result` only; `result.result === "Not logged in · Please run /login"` |
| Unknown session id | 1 | `subtype: "error_during_execution"`, `errors: ["No conversation found with session ID: <uuid>"]`, `num_turns: 0` |
| Offline | hangs | repeating `system/api_retry` — watchdog C |
| Budget exceeded | 1 | `subtype: "error_max_budget_usd"`, `terminal_reason: "budget_exhausted"` |
| Cancelled (SIGTERM) | 143 | `terminal_reason: "aborted_streaming"` |

An unknown-session-id result is recoverable: mint a fresh uuid and re-send the prompt as turn 1.

### Sessions

A conversation is one uuid v4. Turn 1 mints it with `--session-id`; every later turn resumes it. The id is held in the runtime **state file**, not in `settings.json`. `result.num_turns` is always `1` — it counts turns in *this invocation* — so never use it as a conversation length.

Transcripts land at `~/.claude/projects/<cwd-slug>/<session-id>.jsonl`. Closing the drawer ends the conversation; the next `?` query mints a new id. **Transcripts in the provider's own working directory older than `transcriptRetentionDays` are deleted at shell start** — the provider owns its retention rather than inheriting the global `cleanupPeriodDays`.

History is resent every turn (turn-3 input measured 890 tokens vs 146 for a fresh turn); there is no server-side session.

### Cost and latency

Budget **~1.7 s to first visible token on haiku**. Show a placeholder the instant Enter is pressed; do not wait for `system/init` to render the row.

| Model | `ttft_ms` (median) | exec → init | exec → **first text delta** | exec → result | cost/turn |
|---|---|---|---|---|---|
| haiku | 896 ms | ~1.0 s | **1.63–1.68 s** | 1.8–2.1 s | $0.0002–0.0008 |
| sonnet | 1410 ms | ~1.0 s | **1.77–1.82 s** | 2.4–2.5 s | $0.0014 |
| opus | 1461 ms | ~1.0 s | **2.18–2.20 s** | 2.5–2.9 s | $0.0012–0.0018 |

~1.0 s of that is constant Node/CLI startup and is **not** reducible by model choice. Enabling the read-only+web tool set raises input from 146 → **3634 tokens** per turn.

## Keybinds and IPC

- `GlobalShortcut` name `launcher` in namespace `forest-shell` — Hyprland side `bind = SUPER, SPACE, global, forest-shell:launcher`, using the `TEST_ALIVE || fallback` idiom so the compositor stays usable when the shell is down.
- Co-located `IpcHandler` with target `launcher` and functions `toggle`, `open`, `close`, `actions`.
- shell-switch's `launcher_cmd` is **mandatory** and is unconditionally bound to Super+Space; it is interpolated into templates by `sed`, so the command **must not contain `|` or `&`**. Register `qs ipc call launcher toggle`.

Escape closes. Enter activates the selected row. Up/Down move selection within the fold.

## Motion

Drawer open **320 ms** in / **240 ms** out on the fog ease: scrim (opacity → 0.10) and card together, **no stagger**; content is opacity plus a 1% scale settle (99 → 100) with the transform origin at the launcher's own centre. Selection **cuts** with a 140 ms fill/rail fade at the new row. `reducedEffects` collapses everything to 140 ms opacity crossfades.

Result rows render **outside the animated layer** — results arriving during the 320 ms entrance would otherwise force a per-frame texture re-render. Measure this at build time; the fallback ladder is drop the scale-settle, then adopt `reducedEffects` behavior as this surface's default.

## Settings

Section `launcher` in `settings.json`.

| Key | Default | Notes |
|---|---|---|
| `providers` | `["apps","calculator","clipboard","emoji","actions","claude"]` | Removing an id disables that provider and drops it from the legend |
| `horizon` | `0.32` | fraction of screen height |
| `columnWidth` | `720` | logical px |
| `rowHeight` | `46` | |
| `cardOpacity` | `0.90` | |
| `cardRadius` | `16` | |
| `scrimOpacity` | `0.10` | alpha of the `rgb(190,206,209)` mist wash |
| `godRay` | `true` | 5%→0 top-lit wash over the scrim |
| `showCategoryLabels` | `true` | |
| `showFooterLegend` | `true` | |
| `proseMeasure` | `600` | text measure inside the column |

Nested `launcher.claude`:

| Key | Default | Notes |
|---|---|---|
| `model` | `"haiku"` | `haiku` \| `sonnet` \| `opus`; inline `?<model>` overrides per conversation |
| `effort` | `""` | empty omits `--effort`; accepted: `low`, `medium`, `high`, `xhigh`, `max` |
| `tools` | `["WebSearch","WebFetch","Read","Grep","Glob"]` | Passed to **both** `--tools` and `--allowedTools`; empty list passes `--tools ""` |
| `permissionMode` | `"default"` | `default` \| `acceptEdits` \| `bypassPermissions` \| `dontAsk` \| `auto` \| `plan` |
| `systemPrompt` | `""` | empty uses the built-in launcher system prompt |
| `maxBudgetUsd` | `0.50` | |
| `transcriptRetentionDays` | `30` | |

An invalid `--effort` value only warns to stderr and then silently runs at the default — coerce the key against the accepted set before passing it.

Interactive permission prompts (a shell dialog approving tool use) are **post-v1**. Until then, widening `permissionMode` to `acceptEdits` or `bypassPermissions` is a settings action the user takes deliberately.

## Out of v1

File search, shell-command runner, window switcher, web search. None of them ship, and none of them has a prefix reserved.

## Build notes

- **`DesktopEntries.applications` was empty in a detached/background prototype shell** and stayed empty with `XDG_DATA_DIRS`/`XDG_DATA_HOME` exported (194 entries on disk, both upstream 0.3.0 and the noctalia fork). Icon-theme lookup via `Quickshell.iconPath` works in the same process. Verify the model populates in the shipping shell before trusting it.
- **`font.pixelSize` is an `int`** and the type scale has half-pixel steps (14.5, 12.5, 10.5). Sizes go through `font.pointSize` with a `px × 72/96` helper in `Core/Theme.qml`.
- **`MultiEffect` renders nothing under `QT_QPA_PLATFORM=offscreen`** — anything that needs to be captured must run on a real session.
- Nothing the launcher writes (frecency counts, caches, Claude state) may land inside the config directory; Quickshell hot-reloads on any write there and silently resets singleton state.
