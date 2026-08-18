# 0003 — The list-identity loops stay where they are

Status: accepted
Date: 2026-08-14 (asked by #195, which fixed the tile grid's Repeater the way
#192 fixed the sliders')

## Context

A `Repeater` whose model is a JS array resets when that array's *identity*
changes. Three files therefore hold a hand-written loop that answers "is this
the same list as last time?", so a model is reassigned only when the answer is
no:

- `Surfaces/Drawers/DashboardRegistry.qml` — `same(before, after)`
- `Surfaces/Drawers/DrawerPolicy.qml` — `sameScreens(before, after)`
- `Surfaces/Drawers/ControlCenterPolicy.qml` — `sameIds(a, b)` (#192)

#192 noted the third one and left it. #195 asked the question directly,
because latching the tile grid was the moment a fourth would have appeared.

## Decision

**No shared helper. `sameIds` is reused for the tiles, so #195 adds no fourth
copy, and the three stay where they are.**

Two reasons, and the first is the load-bearing one:

1. **They are not the same function.** `sameScreens` sorts both sides before
   comparing — a set comparison, because two monitors named in a different
   order are the same two monitors. `same` and `sameIds` compare in order,
   because a `Repeater` model reordered *is* a different model and has to
   reset. Merging them would mean one function with a flag, and a caller
   picking the wrong flag gets a bug that no test of the helper can catch:
   an order-blind check on a Repeater model silently stops honouring #55's
   reordering, and an order-sensitive one on the screen list resets every
   surface whenever the compositor enumerates outputs differently.

2. **A shared home exists, and the remaining pair do not earn it.** All three
   sit in `Surfaces/Drawers/`, where sibling QML types are visible to each
   other with no import at all — `ControlCenterPolicy` already instantiates
   `DrillInPolicy` that way. So reachability is not the obstacle, and the
   honest reason is smaller: after reason 1 there are *two* callers of an
   identical five-line loop, and a five-line loop with two callers does not
   earn a type of its own. Extracting it would move the answer away from both
   questions and leave each site saying less than it says now.

## Consequences

- The duplication is deliberate and will not be flagged again; this ADR is
  the answer.
- What is genuinely shared is the *reason*, and that is written down at each
  site: each of the three says which Repeater it protects and what a reset
  would cost there.
- If a fourth caller does appear and it needs the ordered form, that is the
  point to revisit — three sites is duplication, and four with a fifth in
  sight is a missing module. A sibling under `Surfaces/Drawers/` is the home
  if all callers stay there; `Core/` if one does not.
