# CLAUDE.md

## Test seams

Before writing code for a ticket, decide **which of the two seams verifies it**,
and say so in the PR. A ticket whose acceptance criteria cannot be checked at
either seam is not ready to build — that is the thing to resolve first.

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

Surfaces get a log line for each state change worth asserting on. #81 was a
silent lifecycle: nothing logged, so a lock that could not be unlocked had two
candidate causes for a week and cost a session to narrow.

Known gap: this seam cannot take screenshots or count frames — the nested
compositor never presents after its first commit (upstream aquamarine bug,
diagnosed in #85; see the header of `tools/nested-session.sh`). Visual checks
go through `tools/capture-harness.sh` instead: the real surface components
rendered offscreen, client-side, and grabbed pixel-exact — layout and contrast
checks (#79, #80) run there (`--contrast` is the #79 measurement). What still
needs a real session: `MultiEffect` surfaces and compositor composition (blur,
layer stacking, frame pacing).

### Why this is a rule

The build ran seven tickets green against `tests/` alone. The first pass under a
real compositor (#73) produced eight bugs at once (#74–#81), including a lock
that could not be unlocked on a live session. Every one of them lived at seam 2,
which did not exist yet.

## Session workflow

If you implemented anything during a session, when fully done: push the branch,
open a PR, and merge it.
