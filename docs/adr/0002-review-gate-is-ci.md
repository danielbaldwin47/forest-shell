# 0002 — The review gate is CI, and review happens before the PR opens

Status: accepted
Date: 2026-08-05 (gate installed and made a required check; sequencing
settled in the review-before-pr PR #213; recorded retroactively 2026-08-10)

## Context

The review convention lived in skill text alone, and it lost twice: PR #128
was merged by hand over `Review: findings held`, and by 2026-08-05, 10 of 14
post-fix PRs carried that same contentless token. A held finding must be
written out and resolved, not tokenized past a gate no machine reads.

## Decision

Two halves, adopted together:

1. **Mechanical gate.** `.github/workflows/review-gate.yml` reads the PR
   body's **last** `Review:` line and passes only `Review: clean`;
   `review-line` is a required status check on `main`. `findings held` gets
   its own named rejection.
2. **Review before the PR exists.** A pre-review PR has no valid `Review:`
   line, so it is born gate-red and forces a second full review after fixes
   land just to satisfy the check. So the review runs on the branch, and
   the PR opens with the review record already in its body. Review weight
   follows what the diff touches: executable changes get two-axis
   `/code-review`; pure prose gets one inline pass recorded as
   `Review: clean — prose only, single-pass`.

## Consequences

- A PR opened per the convention is green from its first gate run; the gate
  only ever fires on drift.
- Commits pushed after opening re-trigger the gate on an unchanged body —
  the convention (re-review the new diff, append a fresh `Review:` line)
  covers the window the gate cannot see.
- The full sequencing prose lives in `CLAUDE.md` § Session workflow; this
  ADR records why it exists and what it replaced.
