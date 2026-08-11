# forest-shell

A Quickshell (QML) desktop shell for Hyprland — bar, launcher, lock, and
settings surfaces launched from one `shell.qml` (`qs -p <repo>/shell.qml`).
Decisions live in pure-QML policy objects tested offscreen; everything
compositor-bound is verified in a nested session. Decisions worth defending:
`docs/adr/`.

## Test seams

Before writing code for a ticket, decide **which seam verifies it** — one of
the three below, or the real session at the end — and say so in the PR. A
ticket whose acceptance criteria cannot be checked at any seam is not ready to
build — that is the thing to resolve first.

**1. `tests/` — pure QML, offscreen, run by `tests/run.sh`.**
Everything that is a *decision* rather than a picture: policy, formatting,
parsing, merging, migration, thresholds. Prior art is `Surfaces/Lock/LockPolicy.qml`
and `tests/tst_lockpolicy.qml` — a `QtObject` of pure functions with the surface
kept on the other side of it.

The constraint that shapes this: Quickshell's own QML modules are compiled into
the binary and `qmltestrunner` cannot load them, so a file that imports
`Quickshell` is unreachable from here. That is the argument for keeping as
little as possible on the far side of the line — when a surface holds a decision
worth testing, pull the decision out into a policy object and leave the surface
thin.

**2. `tools/nested-session.sh` — the real shell inside a nested Hyprland.**
Everything that only exists once a compositor is involved: lifecycles that
depend on real Wayland protocol events, IPC, layer-shell behaviour, keyboard
focus, anything `Quickshell.*`. Drive it over IPC, with `nested_key`, or with
`nested_click`, and assert on the log. `tools/lock-harness.sh` and
`tools/settings-harness.sh` are the worked examples; a harness that edits config
sets `NESTED_ENV` to a scratch `XDG_CONFIG_HOME` so it does not touch the
session running it, and one that needs the *compositor* configured differently —
two keyboard layouts, say — sets `NESTED_CONFIG`.

**Pointer delivery is drivable here too, and it is not the same seam as IPC**
(#187). `nested_click x y` warps with `hyprctl` and presses through a virtual
pointer (`tools/nested-click.c`), so the button is hit-tested and focus-routed
exactly as a real one is. Reach for it whenever the claim is that a *click*
does something: #187 was a bar whose buttons were unreachable while a drawer
was open, and every IPC-driven check passed throughout, because the verb was
never the broken part. `hyprctl dispatch sendshortcut` is the trap — it carries
mouse buttons, answers `ok`, and delivers nothing to a layer surface, which the
whole shell is. `tools/bar-click-harness.sh` is the worked example, and it aims
its clicks by writing the bar's module layout into the scratch config and
reading the bar's own rect out of `hyprctl layers` rather than guessing at icon
widths.

**The cursor is drivable here too, and it is a protocol read rather than a
picture** (#185). A cursor shape is not something the client draws — it is a
`wp_cursor_shape_device_v1.set_shape` request it sends — so `WAYLAND_DEBUG=1` in
`NESTED_ENV` puts every one of them in the shell log, and hovering a control is
an assertion (`4` is the hand, `1` is the arrow). `tools/cursor-harness.sh` is
the worked example. Two things it had to learn: a headless seat advertises no
pointer capability at all, so `movecursor` alone reaches no client and a hover
is a warp plus a middle click to make `tools/nested-click.c`'s virtual pointer
exist; and the debug log is colourised even into a file, so a pattern like
`wl_pointer@` matches nothing and reads exactly like a shell that never asked.
Asserting the *absence* of something needs a control the way #78's blur run did:
a module decides its own `shown`, so a readout that hid itself leaves bare strip
under the pointer, which is an arrow too — each readout is configured in front
of a control that never hides, so an empty slot fails the check rather than
passing it.

This seam is also the only place the shell is ever on more than one screen.
`NESTED_MONITORS` declares the layout and `nested_output_add` /
`nested_output_remove` plug one in and out mid-run, so per-screen geometry and
hotplug are assertions rather than theory (#98,
`tools/multi-monitor-harness.sh`). The outputs are headless and the backend's
own window is dropped (`NESTED_HEADLESS_ONLY=1`): a second wayland-backend
output is a second window on the *host*, so the host's tiling decides its size
— measured, and fatal to any geometry assertion.

Surfaces get a log line for each state change worth asserting on. #81 was a
silent lifecycle: nothing logged, so a lock that could not be unlocked had two
candidate causes for a week and cost a session to narrow.

Known gap: this seam cannot take screenshots or count frames — the nested
compositor never presents after its first commit (upstream bug, diagnosed in
#85 and filed as hyprwm/aquamarine#348; see the header of
`tools/nested-session.sh`). Looking at pixels is seam 3's job.

**3. `tools/capture-harness.sh` — the shell's visuals, rendered client-side
and grabbed pixel-exact.**
Everything that is a *picture* but still a client-side one: layout (#80-class
overflows), colour, opacity compositing — one surface per run
(`--surface bar|bar-full|lock|settings`). By default the real surface
components render on `QT_QPA_PLATFORM=offscreen` — deterministic geometry,
scratch config, generated wallpaper — and the scene is grabbed with
`Item.grabToImage`, so no compositor is involved and no compositor bug can
starve it. `--contrast` is the #79 measurement (`tools/measure-contrast.py`),
and it is the *stricter* form of it: compositor blur only averages the
wallpaper locally, so a window that passes unblurred passes blurred.

A measurement that decides a *policy* rather than checking one needs more than
one picture, and that is a third kind of tool rather than a fourth seam:
`tools/measure-strip-floor.py` runs the bar's contrast arithmetic over a whole
folder of wallpapers, which is what settled #79 — one capture said the floor
failed, 171 said no single floor could pass. Tools of that shape may take
Pillow/NumPy; anything inside a gate stays stdlib-only, so it runs anywhere.

One caveat picks the mode: `MultiEffect` draws nothing on the offscreen
scenegraph (measured — `Widgets/Icon.qml`), so every Lucide glyph is missing
from an offscreen capture. `--session` renders the same components on the
caller's own Wayland session, where they draw; that is the mode for anything
with an icon in it, and how #73's lock status strip and settings chrome were
finally judged.

What no seam covers, and why: compositor composition — blur behind the bar,
layer stacking, frame pacing — needs presents the nested compositor cannot
currently make and pixels a client-side grab never sees. That still takes a
real session; a ticket whose acceptance lives there should say that in the PR,
not claim a seam.

Two of those live in scripts anyway, because a performance number wants the
same method twice rather than a fresh one each pass: `tools/idle-budget.sh`
(#22 §5 — CPU, context switches, repaints at rest) and `tools/frame-budget.sh`
(#22 §6 — `render`/`swap`/`total` over driven bar interaction). Both launch the
real shell on the caller's own session and both say so; neither is a seam. What
they add over doing it by hand is that they record the conditions: the 1-minute
load average over the window, and — for the idle one — whether anything drove
the compositor while it ran, which **exits 2, inconclusive**. #95 measured 155
idle frames where #73 measured 6, and the difference was another agent
switching workspaces on the same session, not the shell. A performance number
without its conditions next to it is a number that will be misread later.

The idle one records two more of those conditions (#176), because the shell's
own idle ladder is waiting for the same thing the harness is. **Power state**,
on every run: `system.idle.dim` fires at 2.5 min on battery and 5 min on mains,
so the 195 s default straddles a rung on one source and not on the other — and
#73's 6 frames and #137's 21 are only comparable if they were taken on the same
source, which until now nothing recorded. And **which rung fired inside the
window**, read off the shell's own ladder line so the harness cannot disagree
with the shell about what was armed: #152 measured 45 frames against a budget
of 10 and 39 of them were the screen dimming at 151.7 s, which is the harness
measuring the ladder rather than the shell, so it voids the frame count and
exits 2 the way input does. `--help` says which rungs a given `--seconds` can
reach; the arithmetic that decides it is at the first seam
(`tools/idle-rungs.py`, `tests/tst_idle_rungs.py`).

One piece of what no seam covers is now measurable rather than merely visible.
`tools/blur-measure.sh` (#97) photographs the caller's own session with `grim`
with `bar.surface.blur` on and off, and `tools/measure-blur.py` reads the
difference: a blur is a low-pass, so the detail behind the surface collapses
while its mean stays put. It borrows the session — empty workspace, `hyprctl
keyword`, `hyprctl reload` on the way out — and gives it back, which is why it
is a thing you do to a desktop deliberately rather than a seam to run alongside
the others.

Two habits from it are worth copying by anything else that needs a real
session. The run opens with a **control**: an ordinary translucent window, no
layer rule near it, and the run stops if that shows no blur. #78 spent a
session unable to tell "the rule did nothing" from "this machine draws no
blur", and the answer turned out to be `decoration:blur:enabled = 0` in the
machine's own Hyprland config. And the **arithmetic stays at seam 1** — a
stdlib script with its own unit tests (`tests/tst_measure_blur.py`), where a
box blur applied in the test is the picture the compositor is supposed to
produce. Only the photograph needs the desktop.

Layer stacking is still uncovered; frame pacing is `tools/frame-budget.sh`'s
job above, on the same borrowed-session terms.

### Why this is a rule

The build ran seven tickets green against `tests/` alone. The first pass under a
real compositor (#73) produced eight bugs at once (#74–#81), including a lock
that could not be unlocked on a live session. Every one of them lived at seam 2,
which did not exist yet.

## Context discipline

Implementation sessions were peaking at 200–340k tokens against a ~120k
budget. The budget is about sharpness, not cost: a model deep in a long
context reasons worse than the same model early in one. Everything printed
into the session is paid for again on every call that follows, so the rules
below are all one rule — nothing enters the main session unless the main
session is about to act on it. Measured on the transcripts (2026-08), the
dominant costs were accumulated Bash output (test, typecheck and harness
runs) and whole-file Reads of large files, often repeated; review subagents
were *not* a cost — a subagent's report returns a few KB and its own reading
never enters this context.

**Plan outside the session that will build.** The planning read-through is
the widest exploration a ticket does. Have a Plan agent (or equivalent)
produce the plan in its own context and hand back only the plan; the build
session starts executing, not exploring. One ticket per session — a phase
boundary is a session boundary, so churn from one phase never dulls the next.

**Delegate exploration; only Read what you will edit.** "How does X work /
where is Y decided" goes to a read-only subagent (`cavecrew-investigator`
where available, Explore otherwise), which returns an address or a
conclusion, not the files. Reserve main-session Read for files about to be
edited — and do not re-read a file after editing it: Edit and Write fail
loudly when a change misses, so the re-read buys nothing (measured: 11 of 24
sessions did it anyway, and prose alone barely moved it — ~46% to ~39% — so
`.claude/hooks/read-guard.py` now blocks a whole-file Read of a file the
session has edited; a ranged Read stays allowed).

**Code review means the two-axis skill, not a lone reviewer agent.** When a
session is told to `/code-review` its work, invoke the
`mattpocock-skills:code-review` skill and follow it as written: Standards and
Spec run as parallel sub-agents and are reported side by side. Do not
substitute a single `cavecrew-reviewer` pass — that collapses both axes into
one correctness sweep (this happened on #79). The skill's own sub-agents are
already context-cheap: each axis reports back under 400 words, which is why
the measurement above found review subagents were never the cost.

**On a big file, grep first and Read a range.** `Grep -n` for the key or
section name, then Read with offset/limit around the hit. Never write down or
reuse line numbers across edits — they drift; the grep is the address. Section
keys and knob names are unique in the schema files precisely so this works.

**Never let a noisy command print into the session.** Test suites, harnesses
and typechecks redirect to a scratch file; grep the decisive lines back:

    log=$(mktemp); tests/run.sh >"$log" 2>&1; grep -E 'FAIL|Totals' "$log"

(`mktemp`, not a fixed `/tmp` name — parallel sessions share `/tmp`.)
Quote the shortest line that proves pass or fail.

`2>&1 | tail -30` is not this rule — it is the violation the rule exists to
stop. A tail caps one run, but runs repeat: a suite rerun ten times at
`tail -30` is three hundred lines paid again on every call after. Measured on
the 2026-08 relay, zero of seven sessions used the scratch file, and every
one peaked past 200k. The test is what enters context: a grep returning one
decisive line complies; anything printing a screenful does not. On a failure,
grep the log for the failing case by name — never cat the log.

**Bash `cat` is a Read.** These rules govern content entering context, not
which tool fetched it. `cat`/`sed -n` of a source file in Bash is a
whole-file Read with a worse interface — one 237k-token session scored a
perfect zero on the Read rules by pulling 162KB through `cat` loops and never
calling Read once. Use Read (ranged, after a grep), or pipe to grep for the
decisive lines. A PreToolUse hook (`.claude/hooks/context-guard.py`) blocks
both this and the tail-pipe pattern above; a block from it is the rule
firing, not an obstacle to route around.

**Prefer Edit over Write on existing files.** A Write resends the whole file
through context; an Edit sends only the hunk. On a schema-sized file that is
an order of magnitude.
## Session workflow

Push the branch after the first commit — pushed work survives a lost
session — but do **not** open a PR yet: a pre-review PR has no valid
`Review:` line, so it is born gate-red and forces a second full review after
fixes land just to satisfy the check. The review happens on the branch,
before the PR exists. Review weight follows what the diff touches, not how
simple it looks:

- **Anything executable** — QML, `tools/`, `tests/`, `.claude/hooks/`,
  workflow YAML — gets `/code-review` (the two-axis skill, run as Context
  discipline specifies). Hooks and workflows count: they are config that
  executes, and a broken gate fails silently for weeks.
- **Pure prose** — docs, README, CLAUDE.md — gets one lightweight inline
  pass, and the line reads `Review: clean — prose only, single-pass`.

If the review finds issues, fix them and re-check the fix diff — a focused
pass over what changed, not a second full review. One full review per PR is
the default; a fresh full pass is only for fixes large enough to be a new
diff. Then open the PR with the review record already in the body: findings
and their resolutions (if any) first, ending with the `Review:` line. The
gate (`.github/workflows/review-gate.yml`, a required status check) reads
only the **last** `Review:` line in the body and passes only `Review: clean`
(optionally followed by a summary) — any other last line blocks merge — so a
PR opened this way is green from its first gate run. If a PR gains commits
after opening, re-review the new diff and append a fresh `Review:` line; the
earlier lines stay above it as the record.

When fully done: merge the PR.

If the work came from a ticket, close the ticket once the PR is open and the
work is complete — even when you cannot merge (background sessions can't).
Other sessions gate on ticket state, so an unclosed ticket stalls the chain.

## Agent skills

### Issue tracker

Issues and PRDs live as GitHub issues on `danielbaldwin47/forest-shell`, driven
with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name: `needs-triage`,
`needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See
`docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` and `docs/adr/` at the repo root, both created
lazily by `/domain-modeling` rather than upfront. See `docs/agents/domain.md`.
