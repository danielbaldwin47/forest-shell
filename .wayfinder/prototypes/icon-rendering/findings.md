# Icon rendering strategy — findings

Prototype for [issue #19](https://github.com/danielbaldwin47/forest-shell/issues/19).
Everything below was measured, not reasoned about.

**Rig:** ThinkPad T480, Intel UHD 620, Hyprland at fractional scale 1.5,
Qt 6.11.1, `qml6` probes (upstream Quickshell 0.3.0 is the runtime target, but
none of this needs Quickshell itself).

## The short version

Preprocess the **stroke width** only. Recolour at **runtime**.

The ticket framed preprocessing as "bakes the palette in", but the two rewrites
an SVG needs are separable, and only one of them belongs at build time:

| rewrite | when | why |
| --- | --- | --- |
| `stroke-width="2"` → `"1.5"` | build time | palette-independent; nothing at runtime can change it |
| `stroke/fill="currentColor"` → `"#ffffff"` | build time | white is a neutral base, not a palette choice |
| actual colour | runtime | `MultiEffect { colorization: 1.0 }` |

White-plus-`MultiEffect` is **pixel-identical** to a file with the colour baked
in (measured below), so the dynamic path costs nothing in fidelity.

## What each mechanism actually did

`probe.qml` renders all seven candidates side by side → `probe.png`.

| | mechanism | result |
| --- | --- | --- |
| A | pristine SVG in `Image` | **opaque black** — `currentColor` unresolved, as #18 found |
| B | pristine + `MultiEffect` (`brightness: 1.0`, `colorization: 1.0`) | correct colour, but stroke stays **2px** |
| C | normalized (white, 1.5) + `MultiEffect` (`colorization: 1.0`) | **correct colour and 1.5 stroke** |
| D | SVG rewritten in QML, fed as a `data:` URI | correct colour, **visibly soft** |
| E | `QtQuick.VectorImage` (Qt 6.11, CurveRenderer) | **opaque black** — the newer vector path doesn't resolve `currentColor` either |
| F | `lucide.ttf` icon font + `Text.color` | correct colour, stroke locked to the font's **2px** design |
| G | colour baked into the SVG file | correct, but one file per (icon, colour) |

Note on B: a black source needs `brightness: 1.0` to lift it to white *before*
`colorization` has anything to tint. On an already-white source, `colorization`
alone is enough.

## C is pixel-identical to G

`probe4.qml` renders the same icon, same accent, three ways on a black field;
the PNG is then measured per-pixel (`lit` = pixels above the noise floor,
`near-peak` = share of lit pixels within 15% of maximum intensity — a proxy for
edge crispness).

```
                            96px                                16px
G pre-baked file    lit=5058 peak=184 near-peak=84.0% | lit=192 peak=184 near-peak=31.8%
C white+MultiEffect lit=5058 peak=184 near-peak=84.0% | lit=192 peak=184 near-peak=31.8%
D data: URI         lit=5859 peak=184 near-peak=63.6% | lit=309 peak=159 near-peak= 1.6%
```

C and G agree to the pixel. **D is measurably lossy**, and at bar size it
collapses: it never even reaches full accent intensity (peak 159 vs 184) and
almost nothing lands near peak.

`probe3.qml` ruled out the obvious explanations — `data:...;utf8,` vs
`data:...;base64,`, and rewriting `width`/`height` inside the SVG instead of
setting `sourceSize`, all render identically soft. Qt does not honour
`sourceSize` on a `data:` URI; it rasterizes at the SVG's intrinsic 24×24 and
scales. Runtime SVG rewriting is therefore only viable if the rewritten file is
written to **disk** first — which is just G with a cache to invalidate.

## The icon font is the wrong shape for this design system

`lucide.ttf` does exactly what the ticket said: `Text.color` and
`font.pixelSize` work, it sits in the text pipeline, and the release ships a
name → codepoint map (`codepoints.json`, 2027 entries; `info.json`, 2007 — the
two agree). At 96px the weight difference against a 1.5 stroke is obvious, and
there is no knob for it: the stroke is baked into the glyph outlines.

Since [the design system spec](https://github.com/danielbaldwin47/forest-shell/issues/8)
calls for 1.5, the font can't satisfy it. It would also mean carrying a second
copy of the icon set and giving up per-icon SVG edits.

## MultiEffect is free at shell-realistic counts

`probe5.qml`, UHD 620, every icon's colour animating every frame (worst case —
static icons don't redraw at all):

| icons | render ms (mean) | p95 | fps |
| --- | --- | --- | --- |
| 60 | 0.02 | 0 | 60.2 |
| 120 | 0.32 | 1 | 59.9 |
| 400 | 3.38 | 6 | 46.3 |

For reference at 400: plain `Image` 0.03 ms / 60 fps, icon font 0.36 ms /
51.5 fps. So `MultiEffect` only starts costing past ~200 simultaneously
*animating* icons — far beyond a bar plus an open launcher. The
"render pass per icon" worry in the ticket doesn't survive measurement.

## Oversample the raster; don't trust `devicePixelRatio`

`probe6.qml`, one 16px icon at four `sourceSize` values, zoomed
nearest-neighbour into `probe6-zoom.png`:

```
sourceSize=16  near-peak=31.8%   (mushy — thick, soft strokes)
sourceSize=24  near-peak=18.6%
sourceSize=32  near-peak=28.9%
sourceSize=48  near-peak=73.2%   (tightest, cleanest)
```

Rasterize at **3× the logical size** and let the GPU downsample.

And a trap: on this display `Screen.devicePixelRatio` reports **2** while the
compositor scale is **1.5** (Qt's fractional-scale rounding). Computing
`sourceSize` from it gives the wrong answer on exactly the machine we calibrate
to — use a fixed multiplier instead.

## Corpus facts the preprocessor has to respect

- 1757 SVGs, 7.0 MB. Every one carries `stroke="currentColor"` and
  `stroke-width="2"` exactly once — no per-file overrides, no other widths.
- **Nine** additionally carry `fill="currentColor"` on inner shapes:
  `chart-scatter`, `images`, `key-round`, `palette`, `tag`, `tag-plus`, `tags`,
  `tag-x`, `vault`. Rewriting only `stroke` leaves those dots black and
  `MultiEffect` will not lift them. The rewrite must cover `fill` too.

## Two gotchas worth remembering

- `XMLHttpRequest` on a `file://` URL is refused unless
  `QML_XHR_ALLOW_FILE_READ=1` is set — it fails silently into an empty string.
  In the real shell use `Quickshell.Io.FileView`, which has no such gate.
- `MultiEffect` needs a real GPU context. Under `QT_QPA_PLATFORM=offscreen` it
  renders **nothing at all**, with no warning — every other mechanism still
  draws, so a headless screenshot test would silently "pass" with the icons
  missing.

## The seam

One component, `Icon.qml`, addressed by **name** — never by path, so callers
never learn where the set lives or that it was normalized:

```qml
Icon { name: "wifi"; size: 16; color: Theme.fgMuted }
```

- `name` is the Lucide file stem. Nothing else needs a manifest: the filenames
  *are* the names.
- `color` is live — no reload, which is what the opt-in dynamic accent from
  [#6](https://github.com/danielbaldwin47/forest-shell/issues/6) needs.
- `oversample` defaults to 3.0 (above).
- A name that doesn't resolve draws a hollow box and warns on stderr, rather
  than rendering nothing.

Swapping the mechanism later is a change to this one file.

## Where the normalized set lives

Decided with Daniel, 2026-07-31: **normalize the vendored set in place**, and
keep **all 1757** icons.

`assets/icons/lucide/` holds the forest-shell-normalized SVGs — there is no
second directory, no generated sibling, and no transform step between cloning
the repo and running the shell. Provenance is the pinned version plus a
`tools/vendor-lucide.sh` that re-derives the set from the Lucide 1.28.0 release
(download → apply the two rewrites → write into `assets/icons/lucide/`), so the
pristine originals stay reproducible without being carried.

Keeping the full set means the filenames remain the lookup key with no manifest
to maintain, and the launcher or settings UI can reference any Lucide icon
without a re-vendor round trip. The cost is 7 MB in a personal repo.

Doing the in-place rewrite and writing `tools/vendor-lucide.sh` is **build
work**, not a decision — it belongs to a build-plan phase, not to this map.

## Files

| file | what |
| --- | --- |
| `Icon.qml` | the proposed seam |
| `demo.qml` | mock bar + size ramp, accent cycling live (`demo-0/1/2.png`) |
| `preprocess.py` | the normalizer — both rewrites, `--all` for the full set |
| `probe.qml` | all seven mechanisms side by side |
| `probe2.qml` | stroke weight at 96/24/16px |
| `probe3.qml` | why the `data:` URI is soft |
| `probe4.qml` | the pixel-identity measurement |
| `probe5.qml` | perf, `--mode plain\|effect\|font --count N` |
| `probe6.qml` | `sourceSize` vs devicePixelRatio |

Run them with `QML_XHR_ALLOW_FILE_READ=1 QT_ASSUME_STDERR_HAS_CONSOLE=1 qml6 <file>`,
on a real Wayland session (not offscreen). `gen/` is generated — run
`preprocess.py` first.
