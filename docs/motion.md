# Motion

Sources: [#8](https://github.com/danielbaldwin47/forest-shell/issues/8), [#27](https://github.com/danielbaldwin47/forest-shell/issues/27), [.wayfinder/prototypes/motion-choreo/findings.md](../.wayfinder/prototypes/motion-choreo/findings.md), [.wayfinder/assets/board-design-brief.md](../.wayfinder/assets/board-design-brief.md)

Fog moves; it does not snap. Surfaces materialize out of haze rather than sliding in from
somewhere. Nothing in the shell overshoots, bounces or springs.

Motion tokens live in `Core/Theme.qml` alongside the color tokens, exposed camelCase:
`fogEase`, `motionFast`, `motionStandard`, `motionSlow`.

## The ease

| Token | Value |
|---|---|
| `--fog-ease` | `cubic-bezier(0.22, 1, 0.36, 1)` |

**Every transition in the shell uses this curve, in both directions, with no exceptions.** There
is no second easing. Overshoot, bounce and spring curves are forbidden.

In QML:

```qml
easing.type: Easing.Bezier
easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
```

## The step system

Three durations. **Step = how much of the screen the motion touches.**

| Token | Value | Meaning |
|---|---|---|
| `--motion-fast` | 140ms | In-place state change inside an already-visible surface |
| `--motion-standard` | 240ms | A single surface entering or leaving at an edge |
| `--motion-slow` | 320ms | Fog-scale event — the whole screen changes meaning |

Pick the step by asking how much of the screen changes, not by how important the change feels. A
hover, a toggle, a value readout, a ridgeline reflow: 140. A toast, an OSD, a bar reveal: 240. A
drawer opening over the desktop: 320.

### The exit rule

**Exits run one step faster than entrances, floor 140.** So 320 in → 240 out, 240 in → 140 out,
140 in → 140 out. The 140 class is symmetric; **no fourth micro-step is ever added** to close the
gap.

Exits are **opacity-only**. Nothing scales or translates on the way out. An entrance interrupted by
an exit **freezes its transform where it is** and fades from there.

## Per-surface table

| Surface | Enter | Exit | Notes |
|---|---|---|---|
| Drawer open (launcher / control center / dashboard / session) | 320 | 240 | Scrim (opacity → 0.10) and content enter together, no stagger. Content = opacity + 1% scale settle (99% → 100%). Transform origin: launcher settles about its own center; anchored panels about their anchor icon. |
| Cross-drawer | out 140, in 240 starting at +100ms (~40ms overlap) | — | Scrim untouched — the fog is continuous; only what is inside changes. Each drawer enters and leaves at its own anchor. |
| Notification toast | 240, condense in place | 140 | No translation on enter or exit. Stack-shift is 140 and is the only translate in the shell (closing a gap cannot fade). |
| OSD | 240 | 140 | Value updates in place at 140. |
| Bar reveal (fullscreen case) | 240 | 140 | |
| Ridgeline workspace shift | 140 | — | In place; heights and haze animate. |
| Selection move (result lists) | cut + 140 fill/rail fade at the new row | — | Position changes instantly; fill and rail materialize at the new row, interruptible under key-repeat. No traveling rail. |
| Settings window | compositor | compositor | Normal window; Hyprland's own animation applies, no windowrule override. The shell animates only tab-content crossfade, 140. |

## Global rules

- **Fog ease everywhere**, entrance and exit alike.
- **Exits are opacity-only.** Interrupted entrances freeze their transform.
- **The scrim animates opacity only. Blur never animates.**
- **Nothing slides except the toast stack-shift.** Surfaces materialize out of fog.
- **No entrance stagger anywhere** — not launcher rows, not control-center tiles, not notification
  groups. This is the cheapest possible entrance, and a row cascade would fight live provider
  repopulation anyway.
- **Zero idle animation.** Every animation is event-driven; nothing runs when the user is not
  doing something.

## The fog scrim

The scrim is a single quad at `rgba(190, 206, 209, 0.10)`. Its blur (`blur(14px) saturate(0.8)`) is
a Hyprland layerrule, not a QML effect, and it **snaps** on and off with scrim visibility rather
than animating.

Constraint: animating the blur is not an option that was passed over for taste — a QML full-screen
blur does not fit the T480 GPU budget, and the layerrule has no animatable parameter. Any design
that tears the scrim down and rebuilds it mid-interaction pops the blur off and back on, visibly.

## Entrances

A drawer entrance is two properties on a cached content texture:

- `opacity` 0 → 1 over 320ms.
- `scale` 0.99 → 1.00 over 320ms — a **1% settle**, not a zoom.

Both run on fog ease, both start at the same instant as the scrim's opacity ramp. Nothing is
delayed, nothing cascades.

Transform origin is where the surface belongs:

- **Launcher** — its own center. It is a clearing that opens in the middle of the screen.
- **Anchored panels** (control center, dashboard, session menu) — the bar icon they belong to. The
  panel settles out of its icon.

Anchored panels carry two anchoring cues that are not motion but make the motion read: a **beak**
pointing at the anchor icon, and the icon itself **lit teal** (`accent-primary`) for as long as its
drawer is open, matching the ridgeline's teal-for-active.

## Cross-drawer choreography

Switching from one drawer to another — launcher → control center — happens inside the one shared
drawer window, under one focus grab, without the scrim ever moving.

1. Outgoing contents fade out over **140ms**, at their own anchor.
2. At **+100ms**, incoming contents begin their **240ms** entrance at *their* anchor — a ~40ms
   overlap where both surfaces are live.
3. **The scrim is untouched throughout.** Opacity stays at 0.10, blur stays on. The fog is
   continuous; only what stands in it changes.

Total ~340ms. Peak cost is two live surface textures for ~40ms.

The incoming entrance is the standard 240 edge-surface entrance, not the 320 drawer entrance — the
fog-scale event already happened when the first drawer opened.

**The shared drawer window is not a shared placement.** One window and one focus grab per screen
stands, but each drawer anchors independently: launcher centered, control center top-right under
its icon. The cross-drawer transition is therefore two different anchors, not a crossfade in place.

## Stacking: the bar sits above the fog

**The bar renders above the fog scrim and stays clickable while a drawer is open.** Clicking another
bar icon while the control center is open triggers the cross-drawer transition directly — no close,
no reopen. This is what makes anchoring read at all: the icon a panel points at has to stay visible
and live.

## Toasts

Notification toasts are the one place the shell moves anything sideways or vertically, and even
there the motion is minimal.

- **Enter: 240ms, condense in place.** The card materializes where it will live. It does not drift
  in from above and it does not slide from the edge.
- **Exit: 140ms**, opacity-only, fading and desaturating into the fog.
- **Stack-shift: 140ms.** When a toast is dismissed, the cards below it close the gap by
  translating. This is the shell's **only** translate — a closing gap cannot be expressed as a
  fade.

## Selection

Selection inside a result list — launcher rows, list views — **cuts**. The highlighted row changes
instantly; the `accent-deep` fill and the 2px `accent-primary` rail then fade in at the new row
over **140ms**.

**There is no traveling rail.** A rail that animates between rows cannot keep up with key-repeat
and reads as lag. The 140ms fill fade is fully interruptible: holding a cursor key produces a
sequence of cuts, each fade abandoned by the next.

## Settings window

The settings window is a normal Hyprland window. **Its open and close animation belongs to the
compositor** — no windowrule override, no shell-side entrance. The shell animates exactly one thing
inside it: tab-content crossfade at **140ms**.

## The launcher legend

The launcher's keyboard-hint legend lives **inside the results card** — a thin strip on the card's
bottom edge, `text-secondary` on `surface`, with a 1px `border-subtle` hairline above it. It is not
a footer floating below the card.

Constraint: no text ever sits on bare fog. The scrim is a pale wash over live wallpaper, so text
placed directly on it has no contrast guarantee at all. This is the same mechanism that put the
results in a card in the first place.

## `reducedEffects`

There is **one** knob, `reducedEffects`. There is no separate `reducedMotion`.

When `reducedEffects` is on, **all motion collapses to opacity-only 140ms crossfades**:

- No scale settle.
- No translate — including the toast stack-shift.
- No stagger (there was none to remove).
- No ridgeline glide; workspace state changes crossfade.
- Cross-drawer becomes a straight 140ms crossfade with no offset.

Surfaces still fade. **Motion is not reduced to zero** — hard cuts read as broken, not as calm.

## Budget

The T480 budget is an 8ms GPU frame with zero dropped frames at 60Hz.

Everything specified here is cheap by construction: the scrim is one quad animating opacity; drawer
entrances composite a cached content texture (opacity + 1% scale); everything else is small-item
property animation. The cross-drawer transition peaks at two live surface textures for ~40ms.

One genuine risk: **results arriving during the launcher's 320ms entrance force the cached texture
to re-render every frame.** Provision — rows render outside the animated layer, or the entrance
animates card chrome only. Measure this at build time rather than assuming it.

Fallback ladder if any surface misses budget:

1. Drop that surface's scale settle (opacity-only entrance).
2. Adopt that surface's `reducedEffects` behavior as its default.
