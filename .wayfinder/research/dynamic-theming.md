# Dynamic & wallpaper-coupled theming — mechanism research

**Question:** what is the best mechanism for forest-shell's two optional theming modes?

- **Mode A — full dynamic (opt-in):** whole palette derived from the wallpaper.
- **Mode B — constrained wallpaper-coupled accent:** fixed forest palette everywhere, but `accent-primary` shifts toward the wallpaper's dominant saturated hue inside a bounded band (teal ↔ blue ↔ sage, never red/purple). Proposed in `board-design-brief.md` §6.6: *"Worth prototyping; risky if unconstrained."*

**Bottom line:** use two different mechanisms. Mode A should shell out to **matugen** (already packaged in Arch `extra`, installed here at 4.1.0). Mode B should **not** go anywhere near a Material-You scheme generator — it should be a ~60-line in-shell computation using Quickshell's built-in `ColorQuantizer` plus Oklab math in QML JS. Evidence for both below, including a working prototype measured against all 25 board reference images.

---

## (a) How the reference shells do it

All three converged on the **same architecture** and none of them extract colour in QML:

> *external generator process → writes JSON to `$XDG_STATE_HOME`/config dir → QML `FileView { watchChanges: true }` → singleton with `property color` per role → bindings update the whole UI.*

This is the pattern to copy regardless of which generator is chosen.

### Noctalia (inspected locally — installed at `/etc/xdg/quickshell/noctalia-shell/`)

Noctalia **does not use matugen. It reimplemented it in Python**, dependency-free.

- Entry point: `Scripts/python/src/theming/template-processor.py`, invoked from `Services/Theming/TemplateProcessor.qml:352` as
  `python3 template-processor.py "$NOCTALIA_WP_PATH" --scheme-type <type> --config <toml> --default-mode <mode>`.
- `Scripts/python/src/theming/lib/` is a full ~5000-line Material-You stack: `hct.py` (1071 lines — CAM16 + HCT, where *"Tone: CIELAB L\* lightness (0-100)"*), `quantizer.py` (815, Wu + k-means), `palette.py`, `scheme.py`, `material.py`, `contrast.py`, `renderer.py`.
- `image.py` parses PNG via `struct`+`zlib` by hand and falls back to ImageMagick — *"without external dependencies"*. No Pillow, no numpy.
- Nine scheme types (`TemplateProcessor.qml:25`): five M3 (`tonal-spot`, `content`, `fruit-salad`, `rainbow`, `monochrome`) plus four of their own (`vibrant`, `faithful`, `dysfunctional`, `muted`). Different quantizers per type — the header comments state the M3 path uses *"Wu quantizer + Score algorithm (matches matugen)"* while the others use k-means with different scoring functions.
- They keep a dev harness, `Scripts/dev/template-processor-analysis.py`, that runs real `matugen` side by side and prints a per-colour diff table — so the Python port is **deliberately matugen-compatible**, and matugen is the reference implementation they validate against.
- Delivery: `ColorSchemeService.qml` writes `~/.config/noctalia/colors.json` through a `FileView`+`JsonAdapter` (16 `m*` roles); `Commons/Color.qml:426` reads it back with `watchChanges: true`, a 200 ms debounce timer (*"so atomic replacements only trigger one reload"*), and a `skipTransition` flag so the first load doesn't animate.
- Dynamic is **opt-in and off by default**: `Settings.qml:737` → `property bool useWallpaperColors: false`. Ten hand-tuned static schemes ship in `Assets/ColorScheme/` (Gruvbox, Nord, Kanagawa, Rose Pine, …).

### Caelestia

Also **no matugen, no QML extraction**. A bundled Python CLI in the separate `caelestia-dots/cli` repo, built on the `materialyoucolor` PyPI package.

- `cli/src/caelestia/utils/material/score.py`:
  ```python
  def score(image: str) -> Hct:
      return Score.score(ImageQuantizeCelebi(image, 1, 128))
  ```
  Celebi = Wu + WSMeans k-means, then Google's Score algorithm (`TARGET_CHROMA=48`, `WEIGHT_PROPORTION=0.7`), finishing with `DislikeAnalyzer.fix_if_disliked(primary)`.
- It quantizes a **128×128 thumbnail**, not the wallpaper (`utils/wallpaper.py::get_thumb()`).
- Delivery: `cli` writes `~/.local/state/caelestia/scheme.json` atomically (tempfile + `os.replace`); `shell/services/Colours.qml` has `FileView { path: `${Paths.state}/scheme.json`; watchChanges: true }`, maps every key to an `m3<Name>` property.
- QML → CLI is one-way `Quickshell.execDetached(["caelestia", "scheme", "set", …])`. A neat trick worth stealing: hover-preview runs `caelestia wallpaper -p <path>`, which prints the scheme JSON to stdout **without applying it**, and loads it into a separate `preview` palette.
- The shell's own C++ `ImageAnalyser` (`shell/plugin/src/Caelestia/imageanalyser.cpp`) computes a dominant colour and luminance — but it is used **only for transparency tuning and icon colourising, not for theming**.
- Dynamic is opt-in: the default scheme is `catppuccin/mocha/dark`; colour generation only runs when `name == "dynamic"`. 20 static schemes ship.
- Constraint knobs: `variant` (9 M3 variants), `flavour`, `mode`, plus an auto-picker (`get_smart_opts()`) using a Hasler–Süsstrunk colourfulness metric, disableable via `--no-smart` / `services.smartScheme: false`.

### DankMaterialShell (DMS) — inspected locally at `/usr/share/quickshell/dms/` (`dms-shell 1.5.2`)

The one that **does** use matugen — the closest precedent for Mode A. Line numbers below are from the GitHub `master` tree; the installed 1.5.2 matches structurally (probe at `Common/Theme.qml:147`, `dms-colors.json` + `watchChanges` at `:2226`–`:2229`, nine scheme options at `:485`ff).

- QML → Go companion binary → real Rust matugen:
  ```
  Theme.qml → Process: dms matugen queue …
    → dms CLI (Go, core/) → unix socket → exec.Command("matugen", …)
      → <stateDir>/dms-colors.json.tmp → atomic rename → dms-colors.json
        → Theme.qml FileView { watchChanges: true } → Theme.matugenColors
  ```
- Call site `quickshell/Common/Theme.qml:1398` builds `["dms","matugen","queue","--state-dir",…,"--kind",…,"--matugen-type",…]`; Go builds the real argv in `core/internal/matugen/matugen.go:352` — `{kind, value, "-m", mode, "-t", type, "-c", cfg, "--contrast", n, "--import-json-string", data}`.
- **No port of Material Color Utilities anywhere in the stack.** `core/go.mod` carries one colour library (`go-colorful`), used only for `dank16`, a 16-colour ANSI terminal palette derived from matugen's output and injected *back* via `--import-json-string`.
- Availability probe (verified locally, `Theme.qml:147`):
  ```js
  Proc.runCommand("matugenCheck", ["sh", "-c", "command -v matugen"], (output, code) => {
      matugenAvailable = (code === 0) && !envDisableMatugen;
  ```
  plus a `DMS_DISABLE_MATUGEN=1` killswitch. matugen is nonetheless effectively required: without it `setDesiredTheme()` no-ops and only the built-in `StockThemes.js` palettes work.
- Output at `~/.cache/DankMaterialShell/dms-colors.json`, written via a synthesized `[templates.dank]` TOML block to a `.tmp` and renamed. Unchanged bytes → exit code 2. Consumed at `Theme.qml:1931`. `IpcHandler { target: "theme" }` exposes only mode toggles, not colours.
- Also uses Quickshell's `ColorQuantizer` in QML — but only for **album-art accent** (`Services/MediaAccentService.qml`), not theming. Same split as caelestia.
- 10 stock themes in `Common/StockThemes.js` (default `purple`); dynamic is `currentThemeName === "dynamic"`. Notably, **even stock themes are routed through matugen** (`matugen color hex <primary> --import-json-string …`) so they propagate to GTK/Qt/terminals.
- Constraint knobs are only `matugenScheme` (9 variants) and `matugenContrast`. **No hue-lock or saturation clamp exists** — `scheme-monochrome`/`scheme-neutral` are the entire "constrain the palette" story, same as caelestia.

**The takeaway across all three:** every shell that wants a *bounded* palette solves it by picking a less chromatic M3 *variant*. **Nobody constrains hue.** Mode B has no prior art to copy, which is also why no existing tool will do it for you.

### What nobody does

**No shell extracts colours in QML for theming purposes.** Every one of them shells out. That is a strong signal for Mode A — and, as argued below, a much weaker signal for Mode B, because Mode B needs one number, not a palette.

---

## (b) matugen's fit for a "constrained" mode

Everything here was tested first-hand against `matugen 4.1.0-1.1` (Arch `extra`, installed) using the board's 25 reference images.

### What it gives you

```
matugen image <PATH> | color hex <HEX> | web-image <URL> | json <FILE>
  -t, --type    scheme-content | scheme-expressive | scheme-fidelity | scheme-fruit-salad
                | scheme-monochrome | scheme-neutral | scheme-rainbow
                | scheme-tonal-spot (default) | scheme-vibrant
  -m, --mode    light | dark            -j, --json  hex|rgb|rgba|hsl|hsla|strip
  --dry-run     (no templates, no hooks, no wallpaper)     --contrast  -1..1
  --lightness-dark / --lightness-light  (affine lightness remap)
  --prefer      darkness | lightness | saturation | less-saturation | value | closest-to-fallback
  --fallback-color <STRING>     --source-color-index 0..4     -r, --resize-filter
  -c, --config <FILE>           # [config] + [templates.NAME] input_path/output_path/post_hook
```

**It accepts a source colour directly** (`matugen color hex '#6fbec4'` / `color rgb` / `color hsl`) — there is no `--source-color` flag; it's a subcommand — so it can be driven from a colour you computed yourself rather than from an image. `--dry-run -j hex` gives you the JSON with no side effects. `matugen json <FILE>` runs the template engine alone with no scheme at all.

`config.toml` (`~/.config/matugen/config.toml`) has `[config]` (`fallback_color`, `prefer`, `contrast`, `source_color_index`, `caching`, delimiters, `import_json_files`), `[config.wallpaper]`, `[config.custom_colors]`, and `[templates.NAME]` with `input_path`, `output_path` (path *or array*), `input_path_modes = {light=…, dark=…}`, `mode`, `type`, `index`, `pre_hook`, `post_hook`, `enabled`.

One config feature is worth flagging for Mode B, because it is the closest matugen comes to the right idea: **`[config.custom_colors]`** lets you declare arbitrary fixed colours that get **harmonized against the source colour** by default (`name = { color = "#hex", blend = true }`), with `{{ name_source }}` available for the unharmonized original. That is "keep my palette, nudge it toward the wallpaper" as a config primitive — but it harmonizes via the same ±15° `Blend.harmonize` analysed below, so it inherits the same degeneracy.

### Three operational gotchas found by testing

1. **matugen 4.x hard-fails when run without a TTY unless you pass `--prefer` or `--source-color-index`.** A bare `matugen image foo.jpg --dry-run -j hex < /dev/null` gives:
   ```
   Error: Multiple source colors found, no preference was inputted, and a terminal was not detected.
          Use --prefer=PREFERENCE to find suitable colors without needing user input.
   ```
   Any Quickshell `Process` invocation **must** pin one of those flags.
2. **Template type errors panic rather than error.** `{{ ... | harmonize: {{colors.source_color.default | to_color}} }}` (missing `.hex`) produces `The application panicked (crashed). Message: Cant convert map to FilterReturnType`. Templates need care and the exit code needs checking.
3. **The released binary lags the repo — verify flags against the installed version, not the source tree.** matugen's `main` branch has `--show-source-colors` (prints ranked candidate hexes and exits before any scheme generation — the cleanest possible "just give me the extracted colour" probe), plus `-t scheme-smart` and `-m smart` (auto-pick variant/mode from image colourfulness). **None of the three exist in 4.1.0**, the version in Arch `extra`:
   ```
   error: unexpected argument '--show-source-colors' found
   error: invalid value 'smart' for '--mode <MODE>'  [possible values: light, dark]
   error: invalid value 'scheme-smart' for '--type <TYPE>'
   ```
   Worth revisiting when the next release lands: `--show-source-colors` would make matugen a plausible *extractor* for Mode B (Celebi quantization at 112×112, chroma < 5 dropped, then Score) — better clusters than `ColorQuantizer`'s averaging. Until then the `--dry-run --json hex --source-color-index 0` probe (what DMS uses at `matugen.go:847`) is the way to read a source colour without side effects.

### Can its output be constrained? Partly — and not in the way Mode B needs.

**Source-colour selection is constrainable.** `--prefer` and `--source-color-index 0..4` choose among matugen's ~5 extracted candidates. `--prefer closest-to-fallback --fallback-color '#6fbec4'` sounds exactly right for forest-shell — but it only picks the *nearest of five candidates*; it does not bound the result. On pin24 (a warm amber wallpaper) it selected `#a29a77`, yielding a primary of `#d8c770` — yellow-olive, nowhere near teal.

**The generated scheme is take-it-or-leave-it.** Measured across all 25 board images, `-t scheme-tonal-spot -m dark --prefer saturation`:

| | hue range (Oklab) | WCAG contrast vs `bg-base` `#0b100d` |
|---|---|---|
| matugen `primary` | **49.6° … 256.2°** — orange, yellow, green, blue, violet | 11.23 … 11.32 |

The contrast stability is real and is worth understanding: M3 pins dark-mode `primary` at **tone 80**, and HCT tone *is* CIELAB L\* (`hct.py:714` — *"Tone: CIELAB L\* lightness (0-100)"*), so contrast against any fixed background barely moves. **M3 gives you contrast preservation for free and hue constraint not at all.** That is precisely the inverse of what Mode B needs, and it is exactly the "risky if unconstrained" failure the design brief anticipated.

matugen also rewrites `surface`/`background` toward the source hue, which would destroy the forest palette's signature — the green/olive cast at H 150–160 in the near-black backgrounds (`board-design-brief.md` §2).

### The post-processing filters — and why they don't save it

`matugen color hex '#6fbec4' --filter-docs-html` (undocumented; requires a subcommand) dumps the authoritative filter list:

`set_red` `set_green` `set_blue` `set_alpha` `set_hue` `set_saturation` `set_lightness` `lighten` `auto_lightness` `saturate` `grayscale` `invert` `blend` `harmonize` `to_color` `format`, plus string filters `snake_case` `lower_case` `camel_case` `pascal_case` `kebab_case` `replace`. (The README's `to_upper`/`to_lower` do not exist.) Colour keywords are `{{ colors.<name>.<light|dark|default>.<format> }}`, and `source_color` is always injected as a role, so `{{ colors.source_color.default.hex }}` gets you the raw extracted colour inside any template.

Three matter:

**`harmonize`** — *"Harmonizes a color with another using harmonization. This shifts the hue of the original color toward the target color."* This is Material's `Blend.harmonize`, which shifts the design colour's **HCT hue** toward the key colour while *"leav[ing] the original color recognizable"*, capped by:
```js
const rotationDegrees = Math.min(differenceDegrees * 0.5, 15.0);
```
**Maximum 15°, chroma and tone untouched.** Conceptually this is exactly Mode B, and Material shipped it, which is good validation for the whole idea.

Measured across the 25 images (`"#6fbec4" | to_color | harmonize: {{colors.source_color.default.hex | to_color}}`):

| | result |
|---|---|
| accent hue range | 186.3° … 217.2° (±15° as designed) |
| contrast vs `#0b100d` | **8.97 … 9.01** (fixed accent = 8.99) — excellent |
| distinct outputs | **5**, and **12 of 25 images collapsed to the identical `#70bfb6`** |

Contrast-safe but **degenerate**. Because the rotation saturates at 15°, every wallpaper more than 30° from teal lands on the same endpoint — an orange wallpaper (`#d3691f`) and a green one (`#678c10`) both produce `#70bfb6`. It cannot even distinguish "shift toward sage" from "shift toward warm"; it just clamps. For a feature whose entire point is visible-but-bounded response to the wallpaper, ±15° with 5 possible outputs is too blunt, and the sage end of the intended band (~118–140°) is unreachable.

**`blend`** — *"Blends two colors together using hue blending"*, `blend: <Color>, <0.0–1.0>`. This is MCU's `Blend.hctHue`: *"Blends hue from one color into another. The chroma and tone of the original color are maintained."* Unlike `harmonize` it takes an explicit amount with no 15° cap, so it is the one matugen filter that could express an arbitrary bounded shift. But the *amount* is a fixed constant in a template, not a function of the measured hue distance, so it cannot implement "rotate by the shortest arc, clamped into a band" — a wallpaper 10° away and one 170° away get pulled by the same fraction. It also cannot express a hard band boundary.

**`set_hue` / `set_saturation` / `set_lightness` operate in HSL**, per their own docs (hue 0-360, saturation 0-100, lightness 0-100). Verified: `"#ff0000" | set_lightness: 50` returns `#ff0000` unchanged — pure HSL. **This makes them useless for contrast-preserving work.** Holding HSL L and S fixed and sweeping hue moves WCAG contrast against `#0b100d` from 4.38 to 10.26 — a **134% spread**:

| H (HSL, L=0.60 S=0.40) | 0 | 60 | 120 | 180 | 240 | 300 |
|---|---|---|---|---|---|---|
| CR vs `#0b100d` | 5.35 | **10.26** | 8.80 | 9.29 | **4.38** | 5.84 |

Yellow at 10.26:1 and blue at 4.38:1 from the *same* nominal lightness. Any hue manipulation done in HSL silently breaks accessibility.

### Verdict on matugen

| | verdict |
|---|---|
| **Mode A (full dynamic)** | **Yes — use it.** Best-in-class extraction, in Arch `extra`, M3 tone guarantees, template system for GTK/Qt/terminal fanout for free, and it is the reference every other shell benchmarks against. |
| **Mode B (constrained accent)** | **No.** Its scheme output is unconstrained in hue; `harmonize` is bounded but degenerate (±15°, 5 distinct values); `blend` takes a constant amount rather than a measured distance; its hue/lightness filters are HSL and contrast-unsafe. Adding a hard binary dependency and a subprocess round-trip to obtain *one hue number* is the wrong trade. Revisit if `--show-source-colors` ships. |

---

## (c) Recommended approach

### Colour space: Oklab/OKLCH for Mode B

Three candidates, and the choice matters:

- **HSL** — disqualified. Not perceptually uniform; 134% contrast swing under hue rotation (above). This is what `Qt.hsla()` and QML's `color.hslLightness` give you, so the obvious QML-native path is the wrong one.
- **HCT** (Material's) — tone *is* CIELAB L\*, so contrast is well-behaved, and `Blend.harmonize` proves the technique. But it requires CAM16, which is a large, numerically fiddly implementation (Noctalia's `hct.py` is 1071 lines) — too much to port into QML JS for one feature.
- **Oklab / OKLCH** — **recommended.** Designed to fix exactly this: CIELAB *"poorly predicts blue hues"* and HSV shows *"yellow, magenta and cyan appear much lighter than red and blue"*, whereas Oklab *"maintains uniform perceived lightness while varying hue"* and lets you *"alter [lightness] without affecting the other two"*. Conversion is ~15 lines each way with a cube-root nonlinearity — trivially portable to QML JS, with public-domain reference code. HSLuv is a reasonable alternative (CIELUV-based, gamut-normalised saturation) but has no advantage here and less tooling.

**OKLCH coordinates of the existing forest palette** (computed from `board-design-brief.md`):

| role | hex | L | C | H | CR vs `#0b100d` |
|---|---|---|---|---|---|
| `accent-primary` (glacier teal) | `#6fbec4` | 0.753 | 0.078 | **201.9°** | 8.99 |
| `accent-lichen` (sage) | `#afbd7a` | 0.771 | 0.091 | **118.2°** | 9.49 |
| light `accent-secondary` (lake blue) | `#1a5f77` | 0.455 | 0.076 | **225.9°** | 2.69 |
| `accent-deep` (lake teal) | `#0c757b` | 0.513 | 0.085 | 201.3° | 3.52 |
| `accent-warm` (lamplight) | `#d8ac81` | 0.774 | 0.077 | 65.6° | 9.27 |
| `accent-ember` (campfire) | `#e07a5f` | 0.688 | 0.133 | 35.8° | 6.51 |
| `bg-base` | `#0b100d` | 0.166 | 0.010 | 158.8° | 1.00 |

The palette hands you the band for free: **sage 118° → teal 202° → lake blue 226°**. Take **H ∈ [118°, 240°]**. Warm (65.6°) and ember (35.8°) sit outside it, so the clamp structurally cannot collide with the warm accents — which is the whole point of the brief's "never red/purple" rule.

### The contrast-preservation strategy

**Rotate hue only. Never touch L or C.** Because Oklab L is perceptually uniform, holding L and C fixed while rotating H keeps WCAG contrast nearly constant. Measured, holding L=0.753 C=0.078:

| sweep | CR vs `#0b100d` | spread |
|---|---|---|
| full 360° | 8.41 … 9.03 | 7.3% |
| **band 118°–240°** | **8.86 … 9.06** | **2.3%** |

And for the light theme, where contrast headroom is much tighter:

| accent | band CR range | fixed baseline | in gamut |
|---|---|---|---|
| light `accent-primary` `#0c757b` on `#eef1ec` | 4.74 … 4.90 | 4.79 | all |
| light `accent-secondary` `#1a5f77` on `#eef1ec` | 6.11 … 6.33 | 6.25 | all |

Every hue in the band stays in sRGB gamut at the fixed chroma, and dark-theme AA (4.5:1) never comes close to being threatened. **Light-theme `accent-primary` is the tight one at 4.74:1** — only 0.24 above AA. Two mitigations: (i) run a final WCAG check and, if `CR < 4.5`, binary-search Oklab **L** (not hue) until it passes — the same shape as Noctalia's `contrast.py::ensure_contrast()`, but in Oklab instead of HSL; (ii) raise the band floor for the light theme from 118° to ~140°, which also dodges Material's `DislikeAnalyzer` zone (*"dark yellow-green that is not neutral"*, hue 90–111 / chroma > 16 / tone < 65) — at H=118 the light accent renders `#636d31`, a muddy olive.

### Mode B: the recommended mechanism (in-shell, zero dependencies)

Quickshell ships a quantizer, so no external process is needed:

```qml
ColorQuantizer {
  id: wallQuantizer
  source: Qt.resolvedUrl(WallpaperService.current)
  depth: 4          // 2⁴ = 16 colours
  rescaleSize: 64   // docs: "recommended to rescale, otherwise the
                    // quantization process will take much longer"
}
```
It runs off-thread (`QRunnable`) and exposes `colors : list<color>`. Note its algorithm is recursive median-cut *"by averaging out the image's color data recursively"* — averaging makes clusters muddier than matugen's Wu+Score, which matters for threshold tuning below. **It exposes no per-cluster population counts** (only `colors`), so weight by chroma rather than area.

Algorithm:

1. Convert each quantized colour to OKLCH (~15 lines of JS).
2. Discard achromatic and extreme-lightness clusters: `C ≥ chromaMin`, `0.25 < L < 0.90`.
3. **Chroma-weighted circular mean** of the surviving hues → dominant saturated hue `h`, plus a concentration `R = |Σ C·e^{iH}| / Σ C` ∈ [0,1] measuring hue agreement.
4. If no candidates survive, or `R < 0.55` (hues disagree — a rainbow or a neutral wallpaper), **keep the fixed accent**. Failing closed is the whole safety story.
5. Shift: `d = shortestArc(h − 201.9)`, clamp `|d| ≤ maxShift`, then clamp the result into `[118°, 240°]`.
6. Rebuild the accent as `oklchToSrgb(L_fixed, C_fixed, H_new)` — **the fixed palette's own L and C**.
7. Verify WCAG against `bg-base`; if short, binary-search L.
8. Animate. Noctalia's `skipTransition` + `isTransitioning` pattern is worth copying so the first load doesn't animate and widgets can suppress their own transitions during a theme change.

Only `accent-primary` (and optionally `accent-deep`, sharing the hue) moves. `accent-warm`, `accent-ember`, `accent-lichen`, all backgrounds, surfaces and text stay **exactly** as specified — preserving the green-cast backgrounds and the three-accent structure the brief calls for.

### Prototype results (all 25 board reference images)

Simulating `ColorQuantizer` output (16 median-cut colours at 64×64, **no population counts**), `maxShift = 30°`:

| pin | dominant hue | R | final hue | accent | CR |
|---|---|---|---|---|---|
| pin01 | 210.7 | 0.89 | 210.7 | `#71bdcb` | 9.00 |
| pin04 | 210.1 | 0.88 | 210.1 | `#70bdca` | 8.98 |
| pin08 | 120.1 | 1.00 | 171.9 | `#7abfa9` | 9.00 |
| pin09 | 258.2 | 1.00 | 231.9 | `#7bb8d8` | 8.86 |
| pin18 | 246.9 | 1.00 | 231.9 | `#7bb8d8` | 8.86 |
| **pin24** | **63.5** (warm amber) | 0.96 | **171.9** | `#7abfa9` | 9.00 |
| pin25 | 195.2 | 0.99 | 195.2 | `#70bfbe` | 9.03 |
| pin02, 03, 11, 12, 15, 17, 19, 22 | — | — | *fallback* | `#6fbec4` | 8.99 |

**Contrast across every image: 8.86 – 9.03, against a fixed-accent baseline of 8.99.** The guardrail fires correctly — pin24's amber wallpaper at 63.5° is pulled into the band instead of turning the UI orange. Compare matugen's unconstrained `primary` on the same corpus: hues from 49.6° to 256.2°.

Threshold sensitivity (fallback count is the knob to tune — median-cut averaging suppresses chroma, so the default 0.04 is too strict):

| colours | `chromaMin` | coupled | fallback | CR range |
|---|---|---|---|---|
| 16 | 0.04 | 17 | 8 | 8.86 – 9.03 |
| **16** | **0.025** | **23** | **2** | **8.94 – 9.03** |
| 32 | 0.03 | 21 | 4 | 8.86 – 9.04 |
| 64 | 0.03 | 22 | 3 | 8.90 – 9.04 |

`maxShift` sensitivity (with area weighting, band `[118, 240]`):

| maxShift | distinct hues | CR range |
|---|---|---|
| 15° | 9 | 8.93 – 9.03 |
| **25–30°** | **11** | **8.86 – 9.03** |
| 40° | 13 | 8.83 – 9.04 |

**Recommended defaults:** `depth: 4`, `rescaleSize: 64`, `chromaMin ≈ 0.025`, `minConcentration ≈ 0.55`, `maxShift = 25–30°`, band `[118°, 240°]` dark / `[140°, 240°]` light. `maxShift` is the one to expose to users; note that ≥25° is where the band clamp starts doing real work rather than the shift cap, which is what makes the response feel wallpaper-driven rather than binary.

### Mode A: the recommended mechanism (matugen + file watch)

```
matugen image <wallpaper> \
  -t scheme-tonal-spot -m dark \
  --prefer saturation \          # REQUIRED — otherwise non-TTY hard-fails
  --dry-run -j hex > ~/.local/state/forest-shell/scheme.json
```

Then a `FileView { path: …; watchChanges: true }` singleton exactly as Noctalia and caelestia do, with a ~200 ms debounce so atomic replaces don't double-fire, and an atomic write (tempfile + rename) on the producer side.

- Treat matugen as an **optional runtime dependency**. Probe for it — Noctalia does this in `ProgramCheckerService.qml`, DMS at `Theme.qml:151` with `command -v matugen` plus a `DMS_DISABLE_MATUGEN=1` killswitch — and grey out Mode A when absent. Never let a missing binary break the fixed default. This is where forest-shell should differ from DMS, which routes *even its static themes* through matugen and is therefore broken without it.
- Write to a `.tmp` and `rename()`, as both DMS and caelestia do, so the `FileView` never observes a partial file. DMS's "unchanged output → exit 2" convention is a cheap way to skip redundant reloads.
- Expose `-t` (9 variants) and `--contrast` in settings; `scheme-content` and `scheme-fidelity` stay closest to the wallpaper, `scheme-neutral` is the most restrained and the best fit for the forest aesthetic if a middle ground is wanted.
- If forest-shell later wants to theme external apps (GTK, Qt, btop, terminal), matugen's `[templates.NAME]` config gets that for free — the single largest argument for choosing it over a bundled extractor.
- Skip the Noctalia route (porting Material You into the repo). It is ~5000 lines of Python to avoid one packaged dependency, and it only makes sense because Noctalia also wants to ship 9 custom scheme types.

### Why two different mechanisms is the right answer

Mode A wants a *palette*, and generating a good M3 palette is genuinely hard — delegate it. Mode B wants a *single hue number*, and the hard part is not extraction but the **constraint and contrast preservation**, which no external tool will do for you: matugen's schemes are hue-unconstrained, its `harmonize` is degenerate at ±15°, and its hue filters are HSL and contrast-destroying. Keeping Mode B in-shell means it works with zero dependencies, runs off-thread, needs no subprocess or file round-trip, and — most importantly — the clamp is in your code where it can be tested.

---

## Sources

**Inspected locally**
- DankMaterialShell (`dms-shell 1.5.2`): `/usr/share/quickshell/dms/Common/Theme.qml`
- Noctalia (`noctalia-shell-git`, installed): `/etc/xdg/quickshell/noctalia-shell/Services/Theming/{ColorSchemeService,TemplateProcessor,AppThemeService}.qml`, `Commons/{Color,Settings}.qml`, `Helpers/ColorsConvert.js`, `Scripts/python/src/theming/{template-processor.py,lib/*.py}`, `Scripts/dev/template-processor-analysis.py`
- Quickshell `ColorQuantizer`: `/usr/lib/qt6/qml/Quickshell/quickshell-core.qmltypes`; header + doc comments at https://github.com/quickshell-mirror/quickshell/blob/master/src/core/colorquantizer.hpp; docs https://quickshell.org/docs/v0.2.1/types/Quickshell/ColorQuantizer/
- matugen 4.1.0-1.1 (Arch `extra`): `matugen --help`, `matugen image|color --help`, `matugen color hex '#6fbec4' --filter-docs-html`, and template/extraction runs over all 25 images in `.wayfinder/assets/pins/`

**Primary documentation**
- matugen — https://github.com/InioX/matugen
- Material Color Utilities `Blend.harmonize` — https://github.com/material-foundation/material-color-utilities/blob/main/typescript/blend/blend.ts
- Material Color Utilities `DislikeAnalyzer` — https://github.com/material-foundation/material-color-utilities/blob/main/typescript/dislike/dislike_analyzer.ts
- Björn Ottosson, *A perceptual color space for image processing* (Oklab) — https://bottosson.github.io/posts/oklab/
- HSLuv — https://www.hsluv.org/
- Qt `color` QML basic type — https://doc.qt.io/qt-6/qml-color.html
- caelestia shell — https://github.com/caelestia-dots/shell/blob/main/services/Colours.qml
- caelestia cli — https://github.com/caelestia-dots/cli/blob/main/src/caelestia/utils/material/{score,generator}.py, `utils/{scheme,wallpaper,colourfulness}.py`
- DankMaterialShell — https://github.com/AvengeMedia/DankMaterialShell (branch `master`): `quickshell/Common/{Theme.qml,StockThemes.js,settings/SettingsSpec.js}`, `quickshell/Services/MediaAccentService.qml`, `quickshell/matugen/templates/dank.json`, `core/internal/matugen/matugen.go`, `core/internal/dank16/dank16.go`, `docs/CUSTOM_THEMES.md`

**Version note:** matugen CLI/filter facts above are from the **installed 4.1.0** binary, verified by execution. Repo `main` additionally has `--show-source-colors`, `-t scheme-smart` and `-m smart`, which 4.1.0 rejects. Re-verify against the installed version before relying on any flag.

**Project context**
- `.wayfinder/assets/board-design-brief.md` §2 (palette), §6.6 (wallpaper-coupled accent)
