# 0001 — Launch by direct path, not a config-dir symlink

Status: accepted
Date: 2026-08 (decided across #12/#13, applied in #57; recorded retroactively
2026-08-10 — the reasoning previously lived only in comments in
`integration/shell-switch/registration.env`)

## Context

Quickshell can reach a config two ways: `-c <name>` resolves
`$XDG_CONFIG_HOME/quickshell/<name>/shell.qml`, and `-p <path>` takes the
file directly. The shell-switch research recommended the symlink route —
shorter, and how ghibli is installed. The assembly refinements on #13
overruled it (#12 had already settled it), and #57 registered the shell
accordingly without reopening the question.

## Decision

The shell launches by direct path: `qs -p $FOREST_REPO/shell.qml`. No
config-dir symlink exists. Where the research file and the decision
disagree, the decision wins — the research predates it.

## Consequences

- The repo checkout is the single source of truth; there is no second
  launch path to drift.
- `FOREST_PROCESS_PATTERN` names `shell.qml`, not the directory, so a
  shell-switch away from forest-shell cannot kill a running
  `capture-harness.qml` or `lock-harness.qml` from the same checkout.
- The launch and launcher commands must survive shell-switch's `sed`
  interpolation (no `|` or `&`) and its naive whitespace splitting — the
  reason SUPER+Space is the one bind with no `|| fallback`;
  `tools/binds-harness.sh` checks the two facts against each other.
- Constraint details stay documented in `registration.env` beside the
  values they constrain; this ADR records the decision and where it was
  made.
