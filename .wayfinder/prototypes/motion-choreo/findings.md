# Motion spec — findings (issue #27)

Resolved 2026-07-31 by HITL grilling plus two interactive HTML prototypes (this directory).
These findings are the motion spec; the design-system doc in `docs/` should absorb the
table verbatim.

## Assets

- `motion-elements.html` — static visual reference: every surface the spec covers, real
  prototype captures for bar/ridgeline and launcher, labeled stand-ins for the rest.
- `motion-proto.html` — interactive choreography prototype: drawer open/close,
  cross-drawer variants A/B, opacity-only vs 1% scale settle, 1×/4× slow motion.
  Open either file directly in a browser; both are fully self-contained.

## Governing rule

**Step = how much of the screen the motion touches.**

- 140ms — in-place state changes inside a visible surface.
- 240ms — a single surface entering/leaving at an edge.
- 320ms — fog-scale events; the whole screen changes meaning.

Exits run one step faster than entrances, **floor 140** (the 140 class is symmetric —
no fourth micro-step gets added to the design system).

## Per-surface table

| Surface | Enter | Exit | Notes |
|---|---|---|---|
| Drawer open (launcher / control centre / dashboard / session) | 320 | 240 | Scrim (opacity → 0.10) and content enter together, no stagger. Content = opacity + 1% scale settle (99% → 100%). Transform origin: launcher settles about its own centre; anchored panels about their anchor icon. |
| Cross-drawer (variant A) | out 140, in 240 starting at +100ms (~40ms overlap) | — | Scrim untouched — the fog is continuous; only what's inside changes. Each drawer enters/leaves at its own anchor. |
| Notification toast | 240, condense in place | 140 | No translation on enter/exit. Stack-shift is 140 and is the only translate in the shell (closing a gap can't fade). |
| OSD | 240 | 140 | Value updates in place at 140. |
| Bar reveal (fullscreen case) | 240 | 140 | |
| Ridgeline workspace shift | 140 | — | In place; heights/haze animate. |
| Selection move (result lists) | cut + 140 fill/rail fade at the new row | — | Position changes instantly; fill and rail materialize at the new row, interruptible under key-repeat. No traveling rail. |
| Settings window | compositor | compositor | Normal window; Hyprland's own animation applies, no windowrule override. Shell animates only tab-content crossfade, 140. |

## Global rules

- Fog ease `cubic-bezier(0.22, 1, 0.36, 1)` everywhere.
- Exits are opacity-only; an interrupted entrance freezes its transform where it is.
- Scrim animates opacity only; blur never animates (Hyprland layerrule, snaps with
  scrim visibility — a visible cost of the rejected variant B, which pops blur off and
  back on mid-swap).
- Nothing slides except the toast stack-shift. Surfaces materialize out of fog.
- No entrance stagger anywhere (launcher rows, control-centre tiles). Cheapest possible
  entrance, and a row cascade would fight live provider repopulation anyway.
- `reducedEffects` (#22's single knob — no separate `reducedMotion`): all motion
  collapses to opacity-only 140 crossfades. No scale, no travel, no stagger, no
  ridgeline glide. Surfaces still fade; hard cuts read as broken.

## Decisions that reach beyond motion

- **Bar renders above the fog scrim** and stays clickable while a drawer is open —
  clicking another bar icon triggers the cross-drawer transition directly. This is what
  makes anchoring read; #12 had not settled bar-vs-scrim stacking.
- **Anchored panels get two anchoring cues**: a beak pointing at the anchor icon, and
  the icon lit teal while its drawer is open (teal-for-active, matching the ridgeline).
- **Shared drawer window ≠ shared placement.** #12's one-window/one-focus-grab topology
  stands, but each drawer anchors independently: launcher centered, control centre
  top-right under its icon.
- **Launcher footer legend moves inside the card** — thin strip on the card's bottom
  edge (`text-secondary` on surface, hairline above). Fixes #11's contrast defect by the
  same mechanism that made the card work: no text sits on bare fog. Launcher spec must
  carry this amendment.

## Budget read (T480, #22: 8ms GPU frame, 60Hz zero-drop)

Everything chosen is cheap by construction: scrim is one quad animating opacity; drawer
entrances composite a cached content texture (opacity + 1% scale); all else is
small-item property animation. Variant A peaks at two live surface textures for ~40ms.
The one genuine risk: **results arriving during the 320ms launcher entrance force the
cached texture to re-render per frame** — provision: rows render outside the animated
layer (or the entrance animates card chrome only); measure at build time. Fallback
ladder if any surface misses budget: drop its scale-settle (opacity-only), then adopt
its `reducedEffects` behavior as default.
