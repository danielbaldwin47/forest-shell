# Wallpaper-dynamic theming

Sources: [#6](https://github.com/danielbaldwin47/forest-shell/issues/6), [#12](https://github.com/danielbaldwin47/forest-shell/issues/12), [#26](https://github.com/danielbaldwin47/forest-shell/issues/26), [#8](https://github.com/danielbaldwin47/forest-shell/issues/8), [.wayfinder/research/dynamic-theming.md](../../.wayfinder/research/dynamic-theming.md)

**This ships last.** It is a self-contained increment: nothing else in the shell depends on it, and
everything it touches is behind one settings key and one derived-palette layer that is the identity
function until this lands. Build it after every other feature is working.

Two optional modes, two completely different mechanisms, because they have opposite requirements.
Mode A wants a whole palette and generating a good one is genuinely hard — delegate it. Mode B
wants a single hue number, and its hard part is the constraint and contrast preservation, which no
external tool will do for you.

## Modes

`appearance.themingMode`, default `"fixed"`:

| Value | Behavior | Dependency |
|---|---|---|
| `"fixed"` | The forest palette exactly as specified. No derivation, no file watching, no subprocess. | none |
| `"constrained"` | Fixed forest palette everywhere, except `accent-primary` and `accent-deep`, whose **hue** follows the wallpaper inside a bounded band. | none |
| `"dynamic"` | Whole palette derived from the wallpaper by matugen. | matugen (optional) |

The key exists in the spec table from day one. Until this feature ships, values other than
`"fixed"` coerce to `"fixed"`. It is theme-flagged, so the mode choice travels with a theme preset.

## Plumbing

```
Services/Theming/Theming.qml           # singleton: mode router, exposes derivedPalette
Services/Theming/Matugen.qml           # mode "dynamic": probe, Process, scheme.json FileView
Services/Theming/ConstrainedAccent.qml # mode "constrained": ColorQuantizer + the clamp
Services/Theming/Oklab.js              # pragma library: sRGB ↔ Oklab ↔ OKLCH, WCAG contrast
```

`Theming.derivedPalette` is a map of token name → color, empty in `"fixed"` mode.
`Core/Theme.qml` resolves each token as:

```
spec default  ←  appearance.paletteOverrides[token]  ←  Theming.derivedPalette[token]
```

**Consumers are mode-blind.** No widget, surface, or service ever checks `themingMode`, checks
dark vs light, or reads `Services/Theming/` directly. They read `Theme.<token>` and nothing else.
This is the entire reason the increment is safe to add last.

Token color changes animate with the 240 ms fog-ease `Behavior on color` already inside
`Core/Theme.qml`, suppressed on first load and under `reducedEffects`.

Both modes are driven by the wallpaper service's current path, debounced 200 ms so an atomic
replacement or a rapid wallpaper cycle triggers one derivation rather than several.

## Mode A — full dynamic (matugen)

The architecture all three reference shells converged on: external generator writes JSON to state,
`FileView { watchChanges: true }` reads it back, one singleton exposes a property per role,
bindings update the UI.

### Invocation

```
matugen image <wallpaper> -t scheme-tonal-spot -m dark --prefer saturation --dry-run -j hex
```

- **Constraint: `--prefer` is not optional.** matugen 4.x hard-fails with no TTY unless `--prefer`
  or `--source-color-index` is passed: *"Multiple source colors found, no preference was inputted,
  and a terminal was not detected."* Any `Process` invocation that drops it breaks silently in
  production and works when you test it by hand.
- `--dry-run` means no templates, no hooks, no wallpaper side effects. `-j hex` puts the scheme on
  stdout.
- `-t` and `--contrast` come from settings. `-m dark` is fixed while the shell is dark-first.
- Exit code is checked. matugen **panics rather than errors** on template type problems, so a
  non-zero exit or unparseable stdout is treated as "no scheme" and the fixed palette stands.

stdout is captured with `StdioCollector` and written atomically (`FileView { atomicWrites: true }`,
temp file + rename) to `${Quickshell.stateDir}/scheme.json`. A second `FileView` with
`watchChanges: true` and a 200 ms debounce reads it back. The round trip is deliberate: the file is
the cache that makes restarts instant, and it lets an external process drive the shell's palette
by writing the same file.

### Optional dependency

matugen is probed once at startup with `["sh", "-c", "command -v matugen"]`, plus a
`FOREST_DISABLE_MATUGEN=1` environment killswitch. When it is absent or disabled:

- `"dynamic"` behaves exactly as `"fixed"` — the shell is fully correct with no matugen installed.
- The GUI greys out the `"dynamic"` option with "matugen not installed" as the reason.

**A missing binary never breaks the default look.** This is where forest-shell deliberately differs
from DMS, which routes even its static themes through matugen and is therefore broken without it.

### Role mapping

matugen's dark scheme roles map onto forest tokens:

| forest token | matugen dark role |
|---|---|
| `bg-base` | `surface_dim` |
| `bg-sunken` | `surface_container_lowest` |
| `surface` | `surface_container` |
| `surface-overlay` | `surface_container_high` |
| `border-subtle` | `outline_variant` |
| `border-strong` | `outline` |
| `text-primary` | `on_surface` |
| `text-secondary` | `on_surface_variant` |
| `accent-primary` | `primary` |
| `accent-deep` | `primary_container` |
| `accent-secondary` | `secondary` |
| `accent-lichen` | `tertiary` |
| `accent-warm` | **not derived** — stays `#d8ac81` |
| `accent-ember` | **not derived** — stays `#e07a5f` |

`accent-warm` (attention, exactly one element at a time) and `accent-ember` (urgent/destructive)
are **semantic, not decorative**, and stay fixed in every mode. The three-accent rule survives
dynamic theming or dynamic theming is not worth having.

After mapping, `text-primary` and `text-secondary` are checked against `bg-base` and
`accent-primary` against `surface`. Any pair below 4.5:1 has the **foreground token's Oklab L**
binary-searched until it passes — the same helper Mode B uses. M3 pins dark-mode `primary` at
tone 80 and HCT tone *is* CIELAB L\*, so this rarely fires, but the wallpaper decides the
backgrounds here and the check is cheap.

## Mode B — constrained wallpaper-coupled accent

No dependency, no subprocess, no file round trip. Quickshell's built-in `ColorQuantizer` plus about
60 lines of Oklab math in QML JS.

**No prior art exists.** Every reference shell that wants a bounded palette solves it by picking a
less chromatic Material variant; **nobody constrains hue**, and no external tool will do it. Three
things that look like they would work, do not:

- **Constraint: never manipulate hue in HSL.** Holding HSL L and S fixed and sweeping hue moves WCAG
  contrast against `bg-base` `#0b100d` from **4.38 to 10.26 — a 134% spread** (yellow 10.26:1, blue
  4.38:1, from the same nominal lightness). `Qt.hsla()` and `color.hslLightness` are the obvious
  QML-native path and they are the wrong one. matugen's `set_hue` / `set_saturation` /
  `set_lightness` filters are HSL for the same reason.
- matugen's `harmonize` is bounded but **degenerate**: it caps rotation at 15°, so across the 25
  board reference images it produced **5 distinct outputs and 12 of 25 collapsed to the identical
  `#70bfb6`** — an orange wallpaper and a green one landing on the same color. The sage end of the
  band is unreachable.
- matugen's raw `primary` across the same corpus ranges **49.6° … 256.2°** — orange, yellow, green,
  blue, violet. That is exactly the unconstrained failure this mode exists to avoid.

### The band

Oklab is the right space: contrast is well-behaved under hue rotation, and the conversion is ~15
lines each way with a cube-root nonlinearity — trivially portable to QML JS.

OKLCH coordinates of the forest palette, which hand the band over for free:

| role | hex | L | C | H | CR vs `#0b100d` |
|---|---|---|---|---|---|
| `accent-primary` (glacier teal) | `#6fbec4` | 0.753 | 0.078 | **201.9°** | 8.99 |
| `accent-lichen` (sage) | `#afbd7a` | 0.771 | 0.091 | **118.2°** | 9.49 |
| light `accent-secondary` (lake blue) | `#1a5f77` | 0.455 | 0.076 | **225.9°** | 2.69 |
| `accent-deep` (lake teal) | `#0c757b` | 0.513 | 0.085 | 201.3° | 3.52 |
| `accent-warm` (lamplight) | `#d8ac81` | 0.774 | 0.077 | 65.6° | 9.27 |
| `accent-ember` (campfire) | `#e07a5f` | 0.688 | 0.133 | 35.8° | 6.51 |
| `bg-base` | `#0b100d` | 0.166 | 0.010 | 158.8° | 1.00 |

**Band: sage 118° → teal 202° → lake blue 226°, taken as H ∈ [118°, 240°].** Warm (65.6°) and
ember (35.8°) sit outside it, so the clamp structurally cannot collide with the warm accents —
which is the "never red/purple" rule, enforced by geometry rather than by taste.

### Contrast preservation

**Rotate hue only. Never touch L or C.** Holding L = 0.753 and C = 0.078 fixed:

| sweep | CR vs `#0b100d` | spread |
|---|---|---|
| full 360° | 8.41 … 9.03 | 7.3% |
| **band 118°–240°** | **8.86 … 9.06** | **2.3%** |

Every hue in the band stays in sRGB gamut at the fixed chroma. Dark-theme AA is never threatened.
The tight case is the light theme's `accent-primary` at **4.74:1** against `#eef1ec` — only 0.24
above AA — which is why the light band floor is **140°**, not 118° (this also dodges Material's
`DislikeAnalyzer` zone; at H = 118 the light accent renders `#636d31`, a muddy olive). The light
palette is deferred, so the light band is spec'd and unused in v1.

### Algorithm

```qml
ColorQuantizer {
  id: wallQuantizer
  source: Qt.resolvedUrl(Wallpaper.current)
  depth: 4          // 2^4 = 16 colors
  rescaleSize: 64
}
```

`ColorQuantizer` runs off-thread (`QRunnable`) and exposes `colors : list<color>`. It is recursive
median-cut — it *averages* clusters, which makes them muddier and less chromatic than matugen's
Wu+Score, and it exposes **no per-cluster population counts**. Both facts are why the thresholds
below are what they are: weight by chroma, not by area, and set `chromaMin` low.

1. Convert each quantized color to OKLCH.
2. Discard achromatic and extreme-lightness clusters: keep `C ≥ chromaMin` and `0.25 < L < 0.90`.
3. Take the **chroma-weighted circular mean** of the surviving hues → dominant hue `h`, plus a
   concentration `R = |Σ C·e^{iH}| / Σ C` ∈ [0,1] measuring how much the hues agree.
4. **Fail closed:** if no candidates survive, or `R < minConcentration`, keep the fixed accent and
   stop. A rainbow or a neutral wallpaper produces the forest palette, not a guess.
5. `d = shortestArc(h − 201.9)`; clamp `|d| ≤ maxShift`; clamp the result into the band.
6. Rebuild: `oklchToSrgb(L_fixed, C_fixed, H_new)` — **the fixed palette's own L and C**.
7. Verify WCAG against `bg-base`; if short, binary-search Oklab **L** (never hue) until it passes.
8. Publish into `Theming.derivedPalette` and let `Core/Theme.qml`'s color behavior animate it.

**Only `accent-primary` and `accent-deep` move**, sharing the hue. `accent-warm`, `accent-ember`,
`accent-lichen`, every background, every surface, and all text stay exactly as specified —
preserving the green-cast near-black backgrounds (H 150–160) that are the palette's signature.

The final hue is cached in the state file as `theme.derivedAccentHue` so a restart paints the
coupled accent on the first frame instead of flashing the fixed accent and snapping. The
computation re-runs anyway and corrects the cache if the wallpaper changed while the shell was down.

### Defaults

| Key | Default | Notes |
|---|---|---|
| `depth` | `4` | 16 colors. Not exposed. |
| `rescaleSize` | `64` | Quantizing the full wallpaper is much slower. Not exposed. |
| `appearance.dynamic.chromaMin` | `0.025` | Median-cut averaging suppresses chroma; the intuitive `0.04` is too strict — it fell back on 8 of 25 pins vs 2 at `0.025`. JSON-only. |
| `appearance.dynamic.minConcentration` | `0.55` | Below this the wallpaper's hues disagree; fall back. JSON-only. |
| `appearance.dynamic.maxShift` | `30` | Degrees. **The one knob exposed in the GUI.** Below ~25° the shift cap does all the work and the response feels binary; at 30° the band clamp starts doing real work and the accent reads as wallpaper-driven. |
| `appearance.dynamic.bandMin` / `bandMax` | `118` / `240` | Dark band. Light band floor is `140`. JSON-only. |

## Settings

All under `appearance`, all theme-flagged, all edited on the Settings **Appearance** tab.

```json
{
  "appearance": {
    "themingMode": "fixed",
    "dynamic": {
      "matugenScheme": "scheme-tonal-spot",
      "matugenContrast": 0.0,
      "maxShift": 30,
      "chromaMin": 0.025,
      "minConcentration": 0.55,
      "bandMin": 118,
      "bandMax": 240
    }
  }
}
```

GUI controls: a three-way mode selector; a scheme dropdown over matugen's nine variants
(`scheme-content`, `scheme-expressive`, `scheme-fidelity`, `scheme-fruit-salad`,
`scheme-monochrome`, `scheme-neutral`, `scheme-rainbow`, `scheme-tonal-spot`, `scheme-vibrant`) and
a contrast slider (−1 … 1), both disabled unless the mode is `"dynamic"` and matugen is present;
and a max-shift slider (0–45°) enabled only in `"constrained"`. Everything else stays JSON-only
until it earns a control.

`scheme-content` and `scheme-fidelity` stay closest to the wallpaper; `scheme-neutral` is the most
restrained and the best fit for the forest aesthetic when a middle ground is wanted.

## Relationship to theme presets

- `appearance.themingMode` and everything under `appearance.dynamic` are **theme-flagged**, so a
  saved theme restores *whether and how* the accent follows the wallpaper.
- **A derived palette is never a theme.** `Theming.derivedPalette` is never written to
  `settings.json` and never written to a theme file. Its only persistence is
  `${Quickshell.stateDir}/scheme.json` (mode A) and `theme.derivedAccentHue` (mode B), both caches.
- Saving a theme while in `"constrained"` mode captures the mode, not the color the wallpaper
  happened to produce. Applying it on a machine with a different wallpaper produces a different
  accent, which is the intended behavior.
- See [settings.md](settings.md) for the theme system and the full resolution order.

## Version notes

Verified against **matugen 4.1.0-1.1** (Arch `extra`), the installed version. matugen's `main`
branch additionally has `--show-source-colors`, `-t scheme-smart`, and `-m smart`; **4.1.0 rejects
all three.** Re-verify any flag against the installed binary before depending on it.

`--show-source-colors` is worth revisiting when it ships in a release: it would make matugen a
plausible *extractor* for Mode B (Celebi quantization at 112×112, chroma < 5 dropped, then Score —
better clusters than `ColorQuantizer`'s averaging). It would replace step 1, never the clamp.

## Acceptance checks

1. **25-pin regression harness.** Run the constrained pipeline over every image in
   `.wayfinder/assets/pins/` and assert: final hue ∈ [118°, 240°] or fallback, and contrast against
   `bg-base` ∈ [8.8, 9.1] for every non-fallback result. The measured prototype range is
   **8.86 – 9.03** against a fixed-accent baseline of **8.99**, with at most 2 fallbacks at
   `chromaMin 0.025`. This is a gate, not a smoke test.
2. `pin24` (warm amber, dominant hue 63.5°) must produce a **teal-green** accent (`#7abfa9`,
   hue 171.9°), never an orange UI.
3. A neutral greyscale wallpaper produces the exact fixed accent `#6fbec4`.
4. Uninstall/rename matugen: `"dynamic"` renders identically to `"fixed"`, the GUI greys the
   option, and nothing logs an error loop.
5. Switching wallpapers rapidly triggers one derivation per settle, not one per change.
6. With `themingMode: "fixed"`, `Services/Theming/` performs no subprocess, no file watch, and no
   quantization, and idle CPU is unchanged.
