# Bar & ridgeline prototype — findings

Throwaway prototype for [issue #10](https://github.com/danielbaldwin47/forest-shell/issues/10).
Built and measured on the **T480 (UHD 620, Hyprland scale 1.5, 1280×720 logical,
Quickshell 0.3.0 upstream, Qt 6.11.1)** — the machine the performance and
legibility decisions calibrate to.

## What it is

A real layer-shell bar on the real screen, carrying the Standard-14 module
inventory from the [feature inventory](https://github.com/danielbaldwin47/forest-shell/issues/9)
in the [design-system tokens](https://github.com/danielbaldwin47/forest-shell/issues/8),
with every geometry and ridgeline parameter on a live slider.

```sh
qs-upstream -p .wayfinder/prototypes/bar-ridgeline/shell.qml   # bar + knobs window
./capture.sh                                                   # regenerate shots/
python3 measure.py /tmp/forest-bar-shots/raw                   # regenerate the tables
```

It paints its **own wallpaper strip** under the bar rather than sitting on the
live desktop. That is not cosmetic: it covers the existing shell's bar, and it
means flushness is judged against a wallpaper from the board's own family
instead of whatever happens to be set. Input is masked to the bar rectangle, so
the rest of the strip clicks through to the windows underneath.

Live where it is cheap: workspaces and the active-window title (Hyprland),
clock, battery (`/sys`). Mocked where it is not: tray, MPRIS, network state —
this asks about surface and proportion, not plumbing. `Vars.mock` pins a
plausible workspace state (1, 2, 3, 5 occupied, 3 active) so the ridge's
falloff is visible in screenshots without opening windows across a live session.

Sheets in [`shots/`](shots/): `sheet-height`, `sheet-edge`, `sheet-ridge`,
`sheet-wallpaper`.

## 1. "Nearly flush with the wallpaper" cannot hold on this board

The brief asks for a bar in `#141b17` that reads as forest floor, *near-flush
with the wallpaper*. The same brief also records, as its strongest structural
observation, that **every pin is dark at the bottom and bright at the top**.
Those two facts are in direct conflict at the top edge of the screen.

Measured on the captured frames — bar band vs the 60 logical px of wallpaper
directly beneath it:

| wallpaper | bar L | wallpaper L | ΔL | contrast |
|---|---|---|---|---|
| forest-landscape (bright sky) | 0.017 | 0.362 | 0.345 | **6.14:1** |
| mountain-lake | 0.017 | 0.292 | 0.275 | **5.09:1** |
| deer_in_pine_forest | 0.017 | 0.177 | 0.160 | 3.38:1 |
| sunset-in-thick-forest (dark top) | 0.017 | 0.009 | 0.008 | 1.14:1 |
| mountain-snow-minima (dark top) | 0.017 | 0.012 | 0.005 | 1.08:1 |
| natures-mountain-waters | 0.017 | 0.099 | 0.082 | 2.22:1 |

A 6:1 edge is not "barely-there separation" — it is a header band as hard as any
other shell's. Flushness is a property of the **wallpaper**, not of the bar: it
arrives free on a dark-topped image and is unreachable on a bright-skied one.
So the decision is not "how flush should the bar be" but **which failure mode to
design for**, and the prototype makes the three candidates concrete
(`shots/sheet-edge.jpg`):

- **Opaque flush band** — honest, legible everywhere, and the horizon-line
  motif reads correctly because the bar's bottom edge *is* a horizon. It simply
  is not flush on bright wallpapers.
- **Fog band** — blurred + desaturated wallpaper with the brief's mist wash
  (§6.1) instead of a fill. Ruled out below on measurement.
- **Floating island** — shrinks the band to a rounded slab with wallpaper on all
  sides. Reads lighter, but the radius breaks the stacked-strata language, and
  the band is still there, just smaller.

## 2. The fog band is out, on contrast, not on taste

Applying the fog-scrim recipe (blur + `saturate(0.8)` + `rgba(190,206,209,0.10)`)
to the bar itself is the most on-brief idea available — and it fails, because
the thing being blurred is a bright sky. Contrast of `text-secondary`
(`#a9b8b0`, the brief's "almost all content" colour) against what the band
actually resolves to under each cluster:

| variant | left | centre | right |
|---|---|---|---|
| opaque flush | 7.94:1 | 7.94:1 | 7.95:1 |
| flush @ 86% opacity | 7.67:1 | 7.49:1 | 7.12:1 |
| **fog band, 45% surface** | 5.27:1 | **4.41:1** | **2.89:1** |
| **fog band, 20% surface** | **3.26:1** | **2.39:1** | **1.25:1** |

The right-hand cluster — tray, status icons, battery — lands on the brightest
part of the sky and drops to **2.89:1**, well under the 4.5:1 body-text floor
the design system holds itself to; at 20% surface it is 1.25:1, which is
invisible, and the sheet shows exactly that. Worse, the number moves with the
wallpaper, so the bar would be legible on Tuesday and not on Wednesday.

Blur is right for the drawers, where a dark scrim sits between the wallpaper and
the content. It is wrong for a surface that must carry small text at 12px over
whatever the user set as a background. **This does not need to be re-litigated
per wallpaper — a translucent bar has to be validated against the brightest
wallpaper it will ever see, and it fails there.**

(The prototype simulates the blur inside its own surface so it can be captured.
The shipping shell would delegate it to Hyprland with a `layerrule`, which looks
the same and costs the shell nothing — the conclusion is unaffected.)

## 3. The ridgeline works, and reads as a range

Height + opacity encoding, with both falling away by distance from the active
workspace, is legible at bar sizes and does read as receding strata rather than
as a progress bar (`shots/sheet-ridge.jpg`). Specifics the sheet settles:

- **Width is the whole ballgame.** At `w14` the units are as wide as they are
  tall and read as *blocks* — a row of buttons, not a ridge. At `w9 gap3` the
  horizontal rhythm outruns the vertical and the range appears. At `w6 gap2`
  with a 16px active it reads as a bar chart again, too spiky.
- **Empty workspaces at h3 / 22% opacity vanish as intended** — but they vanish
  *completely enough* that the row's length stops being countable. That is the
  brief's stated intent and a real cost: you cannot tell 5 slots from 9 at a
  glance.
- **`peaks`** (literal triangular silhouettes) is the most on-motif and the most
  at risk of kitsch; it also loses the flat top edge that makes the strata read
  as strata. It survives at `w16 gap2` because the triangles overlap into a
  skyline.
- **`pills`** — the conventional idiom, included as a control — is instantly
  readable and completely generic. It is the thing forest-shell would be
  choosing *not* to ship.
- **The id under the active peak** is cramped at a 32px bar: 9px type with the
  peak above it eats the full height. Either the bar grows or the number goes.

### The single-lamplight rule has a collision

The brief says exactly one element carries `accent-warm` at a time, and names
*both* "the active workspace" and "the item needing attention" as candidates.
Those coexist constantly — there is always an active workspace, and
notifications arrive on top of it. The prototype makes the choice visible
(amber-active vs teal-active rows): amber genuinely reads as the one warm,
inhabited thing on the bar, and teal reads as ordinary UI chrome.

The resolvable form of the rule: **amber belongs to the active workspace by
default and yields to attention** — when a notification or an urgent state
claims the lamplight, the active workspace falls back to teal. One warm element,
always, and the warmth moves to whatever most deserves being walked toward.
That is a decision for the map, not something the prototype can settle alone.

## 4. Sizing

`shots/sheet-height.jpg` at 26 / 30 / 32 / 36 / 40 logical px, with 12px inner
padding, 14px module gaps, 15–16px icons and 12px labels:

- **26px** is tight — the icons crowd the edges and the ridgeline has no room to
  fall away.
- **30–32px** is the band where the content sits with air around it and the bar
  still reads as a strip rather than a panel. 32 leaves room for a 14px active
  peak with 9px of quiet space beneath.
- **36–40px** reads as a panel and starts to feel like a title bar; it is what
  the "id under the active peak" variant would need.

At Hyprland scale 1.5 these are logical px — a 32px bar is 48 device px.

## Practical notes for the build (cost me time here)

- **Quickshell hot-reloads on any write inside the config directory.** The
  capture script originally wrote its PNGs next to the QML and silently reset
  every knob mid-run, producing sheets where half the variants were the
  defaults. Anything that writes must write outside the shell's own tree.
- **`grabToImage` snapshots the frame at call time**, so a capture fired right
  after a change catches the 240ms transition mid-flight — one variant came out
  literally half-way between teal and amber. Let motion settle first.
- **`font.pixelSize` is an `int`.** The design system's 10.5px caps label is not
  expressible that way; the real shell needs `font.pointSize` (or a rounded
  11px) for that one token.
- **`MultiEffect` blur works fine under a real GPU context** at bar sizes — the
  fog band was ruled out on contrast, never on cost.
- Hyprland's workspace list only contains *existing* workspaces, so a fixed slot
  range has to be unioned in; and `Hyprland.workspaces` populates asynchronously
  (confirmed again — bind reactively, never read once at startup).
