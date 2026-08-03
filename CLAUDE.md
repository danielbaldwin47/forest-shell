# CLAUDE.md

## Test seams

Before writing code for a ticket, decide **which of the three seams verifies
it**, and say so in the PR. A ticket whose acceptance criteria cannot be
checked at any seam is not ready to build — that is the thing to resolve first.

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
focus, anything `Quickshell.*`. Drive it over IPC or with `nested_key`, and
assert on the log. `tools/lock-harness.sh` and `tools/settings-harness.sh` are
the worked examples; a harness that edits config sets `NESTED_ENV` to a scratch
`XDG_CONFIG_HOME` so it does not touch the session running it.

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
edited — and do not re-read a file after editing it.

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

**Prefer Edit over Write on existing files.** A Write resends the whole file
through context; an Edit sends only the hunk. On a schema-sized file that is
an order of magnitude.
## Session workflow

If you implemented anything during a session, when fully done: push the branch,
open a PR, and merge it.

If the work came from a ticket, close the ticket once the PR is open and the
work is complete — even when you cannot merge (background sessions can't).
Other sessions gate on ticket state, so an unclosed ticket stalls the chain.
