# Design system

Sources: [#3](https://github.com/danielbaldwin47/forest-shell/issues/3), [#8](https://github.com/danielbaldwin47/forest-shell/issues/8), [#18](https://github.com/danielbaldwin47/forest-shell/issues/18), [#19](https://github.com/danielbaldwin47/forest-shell/issues/19), [.wayfinder/assets/board-design-brief.md](../.wayfinder/assets/board-design-brief.md), [.wayfinder/prototypes/icon-rendering/findings.md](../.wayfinder/prototypes/icon-rendering/findings.md), [assets/README.md](../assets/README.md)

The visual language is a warm lamp-lit cabin on a misty green mountainside: vast, cool and layered
outside; small, wooden and glowing inside. Depth reads as haze, not shadow. Structure reads as
stacked horizontal bands, not boxed grids.

`Core/Theme.qml` is the sole source of every token below. Consumers are mode-blind — no widget
ever checks whether the dark or light palette is active. `Core/Theme.qml` exposes each token as a
camelCase property with the hyphens removed: `bg-base` → `bgBase`, `accent-primary` →
`accentPrimary`, `space-4` → `space4`, `radius-md` → `radiusMd`.

Motion tokens live in [motion.md](motion.md).

## Color — dark palette

The dark palette is primary. **v1 ships dark-first.**

Backgrounds are not neutral black: they carry a green/olive cast (H 150–160). That cast is the
signature and must survive any future tuning. Contrast ratios are against `bg-base`.

| Token | Hex | Contrast | Role |
|---|---|---|---|
| `bg-base` | `#0b100d` | — | Deepest canvas |
| `bg-sunken` | `#070a08` | — | Wells, insets, terminal background |
| `surface` | `#141b17` | 1.10:1 vs base | Bar, panels — barely-there separation, on purpose |
| `surface-raised` | `#1c2621` | — | Popovers, notification cards |
| `surface-overlay` | `#243029` | — | Hover, menus, tooltips |
| `border-subtle` | `#2a3830` | — | Hairlines |
| `border-strong` | `#3c554d` | — | Focus rings, active edges |
| `text-primary` | `#e6ece8` | 16.0:1 | Primary text |
| `text-secondary` | `#a9b8b0` | 9.3:1 | Almost all bar and panel content |
| `text-muted` | `#7d8f86` | 5.6:1 | Still AA for body text |
| `accent-primary` | `#6fbec4` | 9.0:1 | **Glacier teal.** Interactive, active, focus |
| `accent-deep` | `#0c757b` | — | Saturated lake teal — fills, selected states |
| `accent-warm` | `#d8ac81` | — | **Lamplight.** Attention |
| `accent-ember` | `#e07a5f` | 6.5:1 | Campfire. Urgent, destructive |
| `accent-lichen` | `#afbd7a` | — | Sunlit meadow. Success, positive |
| `accent-stone` | `#9d9e8d` | — | Warm grey-green — inactive, disabled, dormant |

### The three-accent rule

- **Teal is interactive.** `accent-primary` for anything the user can act on, anything focused,
  anything active. `accent-deep` for the fill underneath a selected row or an on toggle.
- **Amber is attention.** `accent-warm` marks the one thing that wants the eye — the active
  workspace, the item needing action. **Exactly one element on screen carries it at a time.**
  Resist coloring a second.
- **Ember is urgency.** `accent-ember` for destructive confirmations, critical battery, failed
  operations. Never decorative.

`accent-lichen` (success) and `accent-stone` (dormant) are state colors outside the three-accent
hierarchy and do not compete for the amber slot.

Constraint: `accent-primary` is live at runtime — the opt-in wallpaper-coupled accent
([#6](https://github.com/danielbaldwin47/forest-shell/issues/6)) shifts it within a constrained
hue range. Nothing may bake it into an asset or a cached texture.

## Color — light palette (seed only)

The light table below is recorded as sampled and is **incomplete**. It is a seed for a future
light theme, not a shippable set. Do not build against it.

It is still **wired at runtime**: the control center's Dark/Light tile writes
`appearance.colorScheme`, and `Core/Theme.qml` resolves light mode from this seed with per-token
fallback to the dark value for anything the seed does not define. Consumers never know the
difference. Completing the palette is post-v1 polish.

| Token | Hex | Contrast | Notes |
|---|---|---|---|
| `bg-base` | `#eef1ec` | — | Warm-cool paper, not white |
| `surface` | `#f7f9f5` | — | Cards sit *above* the base |
| `surface-raised` | `#ffffff` | — | |
| `border-subtle` | `#dbe1da` | — | |
| `text-primary` | `#1b241f` | 14.0:1 | |
| `text-secondary` | `#46564d` | 6.8:1 | |
| `text-muted` | `#6b7a71` | 4.0:1 | Large text only |
| `accent-primary` | `#0c757b` | 4.8:1 | Teal darkens for a light background |
| `accent-secondary` | `#1a5f77` | 6.3:1 | Deeper lake blue — provisional, pending role symmetry |
| `accent-warm` | `#8a5a2f` | 5.1:1 | Wood brown |
| `accent-ember` | `#b0512f` | 4.5:1 | |

Missing entirely: `bg-sunken`, `surface-overlay`, `border-strong`, `accent-deep`,
`accent-lichen`, `accent-stone`. These gaps are filled when the light theme is actually built.

Because consumers are mode-blind, dark-first costs nothing later: a widget that reads
`Theme.surfaceRaised` keeps working when the light values land.

## Spacing

A 4px grid. Ten steps, no in-between values.

| Token | px | Token | px |
|---|---|---|---|
| `space-1` | 4 | `space-6` | 24 |
| `space-2` | 8 | `space-7` | 32 |
| `space-3` | 12 | `space-8` | 40 |
| `space-4` | 16 | `space-9` | 48 |
| `space-5` | 20 | `space-10` | 64 |

- Component internals: `space-1`–`space-4` (4–16px).
- Panel padding: `space-4`–`space-6` (16–24px).
- Section gaps: `space-7` and up (32px+).

Two fixed line weights sit outside the grid:

- **Hairline: 1px.** `border-subtle`. The primary separator in the whole shell — horizontal rules
  between strata, not boxes around them.
- **Accent rail: 2px.** A left-edge rail in an accent color marks a selected row or a
  notification's category (teal info, lichen success, ember urgent).

Component dimensions — bar height, launcher width, toast width, tile size — are per-feature spec
territory, not tokens. Do not add them here.

## Radii

| Token | px | Applies to |
|---|---|---|
| `radius-sm` | 6 | Buttons, chips, small controls |
| `radius-md` | 10 | Cards, notifications, popovers |
| `radius-lg` | 16 | Launcher, modals, large drawers |
| `radius-full` | full-round | Toggles, avatars |

Nothing in the shell has a sharp corner.

## Typography

Three families, each with exactly one job.

| Role | Family | Weights | Used for |
|---|---|---|---|
| UI / body | `IBM Plex Sans` | 400, 500 | Everything the shell draws as text |
| Mono | `IBM Plex Mono` | 400 | Terminal-adjacent readouts, code, fixed-column data |
| Display | `Newsreader` | 300 (Light) | The clock, and nothing else |

- **UI weights are 400 and 500 only.** The allowed range is 300–600; there are no blacks anywhere
  in the shell. Reach for 500 to mark a heading or an active label, never for emphasis inside a
  sentence.
- **Body line-height 1.55.**
- **Caps labels: 10.5px at +0.08em tracking.** All-caps is for tiny section labels only.
- **Large sizes take slight negative tracking.** Applies to the clock and to display-size numerals.
- **The serif is used once, never twice.** `Newsreader` Light appears on the lock screen clock and
  the dashboard clock. It appears in no other surface, at no other weight, in no other role.

### Referencing the fonts from QML

**Always the plain family name plus `font.weight`.** Never the legacy sub-family names fontconfig
also exposes (`IBM Plex Sans Medm`, `IBM Plex Mono SmBld`, `IBM Plex Sans Light`, …).

```qml
Text {
    font.family: "IBM Plex Sans"   // or "IBM Plex Mono", or "Newsreader"
    font.weight: 500
}
```

Constraint: Plex ships every non-Regular weight under its own fontconfig family, so
`Qt.fontFamilies()` lists 14 Plex entries and it is not obvious the canonical name reaches them.
It does — verified under Qt 6.11.1 / QtQuick, canonical-family-plus-weight is metrically identical
to naming the sub-family directly. `"IBM Plex Sans"` @ 500 and `"IBM Plex Sans Medm"` @ 400 both
measure 421.125 px wide; `"IBM Plex Mono"` @ 600 and `"IBM Plex Mono SmBld"` @ 400 both render 889
ink pixels, @ 500 = `Medm` = 790 px, @ 300 = `Light` = 520 px. A code review that "fixes" a family
name to a sub-family is a regression.

Weight map, both Plex families:

| `font.weight` | Face |
|---|---|
| 100 | Thin |
| 200 | ExtraLight |
| 300 | Light |
| 400 | Regular |
| **450** | **Text** |
| 500 | Medium |
| 600 | SemiBold |
| 700 | Bold |

Qt accepts arbitrary numeric weights, so Plex's Text weight is reachable at **450** despite having
no named QML constant.

Newsreader is a variable font and resolves 200–700 continuously off its `wght` axis, so
`font.weight: 300` gives the Light the clock calls for.

Constraint: Newsreader's `opsz` axis is **not** driven by `font.pixelSize`. Fontconfig pins the
16pt optical instance (also aliased as the family `Newsreader 16pt`). Set the axis explicitly if a
different optical size is ever wanted; setting a larger `pixelSize` alone will not do it.

### Where the fonts live

Fonts are **not vendored**. They are installed user-local into
`~/.local/share/fonts/forest-shell/` and picked up by fontconfig — no root, no collision with
pacman-managed font packages, trivially removable. Versions are pinned to upstream releases rather
than distro packages.

| Family | Source | Version | Path |
|---|---|---|---|
| IBM Plex Sans | IBM/plex release `@ibm/plex-sans@1.1.0` → `ibm-plex-sans.zip`, `fonts/complete/ttf/` | 1.1.0 | `~/.local/share/fonts/forest-shell/ibm-plex-sans/` |
| IBM Plex Mono | IBM/plex release `@ibm/plex-mono@2.5.0` → `ibm-plex-mono.zip`, `fonts/complete/ttf/` | 2.5.0 | `~/.local/share/fonts/forest-shell/ibm-plex-mono/` |
| Newsreader | google/fonts `ofl/newsreader`, variable TTFs (upright + italic) | `main` @ 2026-07-31 | `~/.local/share/fonts/forest-shell/newsreader/` |

Both Plex families ship 8 weights × upright/italic as static TTFs. All three carry SIL OFL 1.1
licenses alongside the font files.

Per-surface type sizes are per-feature spec territory. Only the caps-label size, the body
line-height and the family/weight rules are tokens.

## Visual motifs

These four treatments are what makes the shell recognizable. A feature that drops one is wrong
even if it hits every token.

### Fog-scrim, not dim-to-black

When a drawer or modal opens, the desktop recedes into **mist**, not darkness.

- Wash: `rgba(190, 206, 209, 0.10)` — a pale cool film over the desktop.
- Backdrop: `blur(14px) saturate(0.8)`.

Constraint: the blur is a **Hyprland layerrule**, never a QML full-screen blur — a QML blur over
the whole screen does not fit the T480 GPU budget. **Only opacity animates; blur never animates.**
The layerrule snaps on and off with scrim visibility.

`rgba(0,0,0,0.5)` and any other black dim is forbidden. The whole point of the treatment is that
receding content gets *lighter*, hazier and less saturated — atmospheric perspective, the way the
ridgelines on the board recede.

### Ridgeline strata

Horizontal division is the primary organizing device. Bands, hairline rules and stacked strata —
not boxed grids, not heavy card borders.

- The workspace indicator is a row of small forms whose **height and opacity** encode state:
  active tallest and most opaque, occupied-but-inactive at mid-haze, empty nearly vanished. It
  reads as a receding mountain range.
- Notifications stack as horizontal bands in `surface-raised` at `radius-md`, no border, separated
  by 1px hairlines.
- Large surfaces carry a subtle top-lit vertical gradient, a 4–6% lightness delta, dark at the
  bottom and brighter at the top. Every pin on the source board is built that way.
- 2–4% monochrome noise over large flat fills. It kills gradient banding and costs nothing.

Depth comes from the surface ladder and the hairline. **There are no cast shadows anywhere** — no
hard-edged drop shadows, no neon glow, no heavy glassmorphism, no pure black.

### Lamplight amber, reserved

`accent-warm` is the inhabited, touchable thing — the cabin window you walk toward. It is the
scarcest resource in the design system: **exactly one element carries it at a time.** The bar is
almost entirely `text-secondary` with a single amber focus; the launcher warms only the selected
row's icon.

Warm wood grain gets no literal texture — amber *is* the wood. At most one hero surface (the
launcher backdrop) carries a very low-opacity grain, and a single soft directional light wash
stands in for the board's god rays. Both are one-offs, never a repeated pattern.

## Icons

**Lucide**, pinned to **1.28.0** (released 2026-07-30). ISC license at
`assets/icons/lucide/LICENSE`.

Shape rules: stroked, never filled; **stroke width 1.5**; round caps and joins; 24px grid.

### The vendored set

All **1756** SVGs are committed to `assets/icons/lucide/` (1757 directory entries counting the LICENSE), **normalized in place**. There is no
second directory, no generated sibling, and no transform step between cloning the repo and running
the shell. Provenance is the pinned version plus `tools/vendor-lucide.sh`, which re-derives the set
from the 1.28.0 release: download → apply the two rewrites → write into `assets/icons/lucide/`.

Keeping the whole set means the filenames stay the lookup key with no manifest to maintain, and any
surface can reference any Lucide icon without a re-vendor round trip. The cost is 7 MB.

### Build-time normalization

`tools/vendor-lucide.sh` applies exactly two rewrites, both palette-independent:

| Rewrite | Why it is build time |
|---|---|
| `stroke-width="2"` → `"1.5"` | Palette-independent; nothing at runtime can change it |
| `stroke="currentColor"` / `fill="currentColor"` → `"#ffffff"` | White is a neutral base, not a palette choice |

Every one of the 1756 files carries `stroke="currentColor"` and `stroke-width="2"` exactly once —
no per-file overrides, no other widths.

Constraint: **nine** icons additionally carry `fill="currentColor"` on inner shapes —
`chart-scatter`, `images`, `key-round`, `palette`, `tag`, `tag-plus`, `tags`, `tag-x`, `vault`. A
rewrite that touches only `stroke` leaves those dots opaque black, and `MultiEffect` will not lift
them. The rewrite must cover `fill` too.

### Runtime recolor

Color is applied at runtime with `MultiEffect { colorization: 1.0 }` over the white source. This is
**pixel-identical** to a file with the color baked in — measured at 96px, `lit=5058 peak=184
near-peak=84.0%` for both; at 16px, `192 / 184 / 31.8%` for both. Dynamic color costs nothing in
fidelity, which is what the opt-in dynamic accent needs.

On an already-white source `colorization` alone is enough; `brightness: 1.0` is only needed to lift
a black source before colorization has anything to tint.

Performance, measured on the T480 (UHD 620) with every icon's color animating every frame — the
worst case, since static icons do not redraw at all:

| Icons | Render ms (mean) | p95 | fps |
|---|---|---|---|
| 60 | 0.02 | 0 | 60.2 |
| 120 | 0.32 | 1 | 59.9 |
| 400 | 3.38 | 6 | 46.3 |

`MultiEffect` only starts costing past ~200 simultaneously *animating* icons — far beyond a bar
plus an open launcher. The "render pass per icon" worry does not survive measurement.

### The `Icon` component

One component, `Icon.qml`, addressed **by name**, never by path. Callers never learn where the set
lives or that it was normalized.

```qml
Icon { name: "wifi"; size: 16; color: Theme.textMuted }
```

- `name` is the Lucide file stem. The filenames *are* the names; there is no manifest.
- `color` is live — changing it triggers no reload.
- `oversample` defaults to **3.0**: the SVG rasterizes at 3× the logical size and the GPU
  downsamples. At logical size, bar-sized icons are visibly mushy — `near-peak` climbs from 31.8%
  at `sourceSize=16` to 73.2% at `sourceSize=48` for a 16px icon.
- A name that does not resolve draws a hollow box and warns on stderr, rather than rendering
  nothing.

Swapping the rendering mechanism later is a change to this one file.

Constraint: **`oversample` is a fixed multiplier and must never be derived from
`Screen.devicePixelRatio`.** On the T480 at compositor scale 1.5, `devicePixelRatio` reports **2**
(Qt's fractional-scale rounding) — it gives the wrong answer on exactly the machine the shell is
calibrated to.

Constraint: **`MultiEffect` renders nothing at all under `QT_QPA_PLATFORM=offscreen`, silently.**
Every other mechanism still draws, so a headless screenshot test passes with the icons missing.
Icon rendering tests need a real GPU context.

### Icon constraints that are already settled

Three alternative mechanisms are ruled out by measurement. Do not reopen them:

- **Runtime SVG rewriting fed as a `data:` URI** is measurably lossy. Qt does not honour
  `sourceSize` on a `data:` URI — it rasterizes at the intrinsic 24×24 and scales. At 16px it never
  reaches full accent intensity (peak 159 vs 184) and only 1.6% of lit pixels land near peak,
  against 31.8% for a file path. `utf8` vs `base64`, and rewriting `width`/`height` inside the SVG,
  all render identically soft.
- **`QtQuick.VectorImage`** (Qt 6.11, CurveRenderer) renders `currentColor` as opaque black exactly
  like `Image`. The newer vector path is not a way around it.
- **`lucide.ttf`** colors correctly via `Text.color`, but its stroke weight is baked into the glyph
  outlines at 2px and is visibly heavier than 1.5 at 96px. There is no knob for it, so it cannot
  meet this spec.

Constraint: **Lucide has a single `wifi` glyph — there are no signal-strength variants.** The bar
and control center must encode signal strength some other way (opacity, partial styling) or
hand-draw variants in Lucide's grammar. Do not reach for a second icon set.

Constraint: `XMLHttpRequest` on a `file://` URL is refused unless `QML_XHR_ALLOW_FILE_READ=1` is
set, and it fails silently into an empty string. In the shell, read files with
`Quickshell.Io.FileView`, which has no such gate.
