# forest-shell — Design Language Brief

Source: Pinterest board [mountain-forest](https://www.pinterest.com/danielbaldwin47/mountain-forest/) (danielbaldwin47).
Method: all 25 pins fetched via the board's RSS feed at 736px; k-means/median-cut color extraction over the corpus. All colors below are sampled from the actual images. Typography and UI-treatment sections are interpretation, clearly marked. Local pin copies: `.wayfinder/assets/pins/` (gitignored — copyrighted reference material).

Structural observation: **every pin is vertical, roughly 9:16 or 2:3** — a phone-wallpaper collection. Compositions are built around a vertical gradient: dark foreground floor, luminous middle, bright sky top. That vertical light gradient is the single most transferable idea on the board.

## 1. Mood and atmosphere

The board is **not** the moody, desaturated, Nordic forest genre:

- **Lush, saturated, hopeful.** Vivid greens, glacial turquoise water, blue skies with big cumulus. Roughly two-thirds of pins have open sky and strong daylight.
- **Atmospheric layering is the defining device.** (~8 pins) Ridgelines of conifers receding into mist, each layer lighter and lower-contrast than the one in front. Fog sits *between* elements. Depth-through-haze, not depth-through-shadow.
- **Warm human refuge inside cool wilderness.** Log cabin with smoking chimney, campfire beside Adirondack chairs, coffee cup on a wet wooden deck (twice), string-lit timber pavilion, rustic wood-and-stone kitchen, ivy-swallowed stone house. **Small, warm, wooden, inhabited things placed against vast cool nature** — the warm elements are always the smallest area of the frame and always the focal point.
- **Water everywhere.** Streams, waterfalls, glacial lakes, turquoise river under a rope bridge, a cenote with god rays. Water is where the saturation lives.
- Several images are AI-generated or heavily graded — the aesthetic embraces a slightly *rendered*, more-vivid-than-life quality. Don't aim for documentary naturalism.

**One-line summary:** a warm lamp-lit cabin on a misty green mountainside — vast, cool, and layered outside; small, wooden, and glowing inside.

## 2. Color palette

### Dark theme (primary)

Backgrounds sampled from deep shadow pixels — **not neutral black**; they carry a green/olive cast (H 150–160). That's the signature.

| Role | Hex | Notes |
|---|---|---|
| `bg-base` | `#0b100d` | Deepest canvas. Sampled near `#09110e` forest-floor shadow |
| `bg-sunken` | `#070a08` | Wells, insets, terminal bg |
| `surface` | `#141b17` | Bar, panels. 1.10:1 vs base — barely-there separation, on purpose |
| `surface-raised` | `#1c2621` | Popovers, notification cards |
| `surface-overlay` | `#243029` | Hover, menus, tooltips |
| `border-subtle` | `#2a3830` | Hairlines |
| `border-strong` | `#3c554d` | Focus rings, active edges — sampled directly from the board |
| `text-primary` | `#e6ece8` | 16.0:1 on base |
| `text-secondary` | `#a9b8b0` | 9.3:1 |
| `text-muted` | `#7d8f86` | 5.6:1 — still AA for body text |
| `accent-primary` | `#6fbec4` | **Glacier teal.** The board's signature color. 9.0:1 |
| `accent-deep` | `#0c757b` | Saturated lake teal for fills, selected states |
| `accent-warm` | `#d8ac81` | **Lamplight.** Sampled from cabin windows and string lights |
| `accent-ember` | `#e07a5f` | Campfire. Urgent/destructive. 6.5:1 |
| `accent-lichen` | `#afbd7a` | Sage-yellow-green, sunlit meadow. Success/positive |
| `accent-stone` | `#9d9e8d` | Warm grey-green, rock and dry grass |

Three-accent structure — **cool teal for interactive, warm amber for attention, ember for urgency** — falls directly out of the imagery. Teal is the water you look at; amber is the window you walk toward. Keep amber rare and small, mirroring the pins.

### Light theme

The board supports a genuine light variant — misty-ridge and snow-peak pins are high-key cool whites (`#d4dbe0`, `#dde6eb`, `#e8eaec` all sampled).

| Role | Hex | Notes |
|---|---|---|
| `bg-base` | `#eef1ec` | Warm-cool paper, not white |
| `surface` | `#f7f9f5` | Cards sit *above* the base |
| `surface-raised` | `#ffffff` | |
| `border-subtle` | `#dbe1da` | |
| `text-primary` | `#1b241f` | 14.0:1 |
| `text-secondary` | `#46564d` | 6.8:1 |
| `text-muted` | `#6b7a71` | 4.0:1 — large text only |
| `accent-primary` | `#0c757b` | Teal darkens for light bg. 4.8:1 |
| `accent-secondary` | `#1a5f77` | Deeper lake blue. 6.3:1 |
| `accent-warm` | `#8a5a2f` | Wood brown. 5.1:1 |
| `accent-ember` | `#b0512f` | 4.5:1 |

## 3. Texture and material

Ranked by how strongly the board supports each:

1. **Atmospheric haze — the strongest cue.** Not blur; *lightening plus desaturation with distance*. Elements further back in the z-stack get lighter, lower-contrast, less saturated — the inverse of the usual dark-theme raised-surface convention; it works because the fog is bright. A scrim behind a modal should read as **pale mist**, not black dim: `rgba(190, 206, 209, 0.10)` over slight backdrop blur, not `rgba(0,0,0,0.5)`.
2. **Vertical luminance gradient.** Every pin is dark at the bottom, bright at the top. Give large surfaces a subtle top-lit gradient (~4–6% lightness delta).
3. **Wood grain — sparingly, only warm.** Present in 6 pins. Real grain texture will look kitsch; instead reserve *warm amber* for the role wood plays — the inhabited, touchable thing. At most a very low-opacity grain on one hero surface (launcher backdrop).
4. **Wet stone / moss.** Mid-tone desaturated green-grey with fine mottling. Good for inactive/disabled states — present but dormant.
5. **Grain/noise — yes, fine and low.** 2–4% monochrome noise over large flat fills; kills banding in gradients.
6. **God rays.** In 3 pins. Risky motif — use only as a one-off soft directional light wash on the launcher background.

Explicitly **avoid**: heavy glassmorphism, neon glow, harsh drop shadows, pure black. The board has no hard-edged shadows anywhere — soft, diffuse, ambient occlusion rather than cast shadow.

## 4. Typography *(inferred — no type in the source images)*

Humanist, not geometric, not decorative.

- **UI / body:** **Inter Tight** (pick), or IBM Plex Sans / Public Sans. Avoid Poppins/Montserrat (reads "startup") and anything woodsy/rustic (craft-brewery label).
- **Monospace:** **Berkeley Mono** if licensed, else **IBM Plex Mono** or **Iosevka**.
- **Display / large clock:** a light-weight serif — **Newsreader** or **Source Serif 4** Light, for the clock only. One serif touch echoes the cabin warmth. Use once, never twice.
- **Treatment:** line-height 1.5–1.6 body, slight negative tracking on large sizes, all-caps only for tiny section labels at +0.08em. Weight range 300–600; no heavy blacks.

## 5. Iconography and shape language

**Rounded and organic, but disciplined.** Soft-edged forms everywhere; compositions strongly structured by horizon lines and verticals.

- **Corner radii:** 6px small (buttons, chips), 10px medium (cards, notifications), 16px large (launcher, modals), full-round for avatars/toggles. Nothing sharp.
- **Icons:** stroked, not filled. 1.5px stroke, round caps/joins, 24px grid. **Phosphor (Regular)** edges out Lucide.
- **Structural rule: layered horizontal bands.** The most repeated composition is stacked ridgelines. Use horizontal division as the primary organizing device — bands, hairline rules, stacked strata over boxed grids and heavy card borders.
- **Motion:** slow, eased, drifting. Fog moves, it doesn't snap. `cubic-bezier(0.22, 1, 0.36, 1)` at 240–320ms for panels. Nothing bouncy or springy.

## 6. UI treatment ideas

1. **Fog-scrim overlays instead of dim-to-black.** When the launcher or a modal opens, the desktop recedes into *mist* — backdrop-blur + pale cool wash (`#beced1` at ~10%) + slight desaturation. The board's atmospheric-perspective mechanic applied literally; the most distinctive thing forest-shell could ship.
2. **Bar as forest floor: dark, with a lamplight focus.** Bar in `#141b17`, barely-perceptible top-edge lightening, nearly flush with the wallpaper. Almost all content in `text-secondary`. Exactly one element at a time carries `accent-warm` — the active workspace or the item needing attention. Resist coloring more than one thing.
3. **Workspace indicator as a ridgeline.** Workspaces as a row of small forms whose *height and opacity* encode state — active tallest and most opaque, neighbors progressively shorter and hazier. Occupied-but-inactive at mid-haze; empty ones nearly vanish. Reads as a receding mountain range.
4. **Notifications as strata that settle downward.** Cards in `surface-raised`, 10px radius, no border — separated by 1px hairlines, stacking as horizontal bands. New ones **drift** in from above and settle; dismissed ones fade and desaturate into the fog. 2px left accent rail: teal info, lichen success, ember urgent.
5. **Launcher as a clearing.** Full-screen, fog-scrimmed. Search field is a single hairline rule — a horizon line — not a box. Results panel subtly lighter at top (sky → forest floor). Selected row: low-opacity `#0c757b` fill + 2px `#6fbec4` left rail; only the selected row's icon warms to `#d8ac81`.
6. **Optional: wallpaper-coupled accent.** Sample the dominant saturated hue from the wallpaper and shift `accent-primary` toward it within a constrained range (teal↔blue↔sage, never red/purple). Worth prototyping; risky if unconstrained.
