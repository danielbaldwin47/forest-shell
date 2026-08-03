# Design-system assets

Provenance and QML usage notes for the fonts and icons pinned by the
[design system spec](https://github.com/danielbaldwin47/forest-shell/issues/8).
Installed and verified by [issue #18](https://github.com/danielbaldwin47/forest-shell/issues/18)
on 2026-07-31.

## Fonts

Fonts are **not vendored** in this repo — they are installed into the user font
directory `~/.local/share/fonts/forest-shell/` and picked up by fontconfig.
Nothing is installed system-wide, so no root is needed and nothing collides with
pacman-managed font packages.

| Family | Source | Version | Install path |
| --- | --- | --- | --- |
| IBM Plex Sans | [IBM/plex release `@ibm/plex-sans@1.1.0`](https://github.com/IBM/plex/releases/tag/%40ibm%2Fplex-sans%401.1.0), `ibm-plex-sans.zip` → `fonts/complete/ttf/` | 1.1.0 | `~/.local/share/fonts/forest-shell/ibm-plex-sans/` |
| IBM Plex Mono | [IBM/plex release `@ibm/plex-mono@2.5.0`](https://github.com/IBM/plex/releases/tag/%40ibm%2Fplex-mono%402.5.0), `ibm-plex-mono.zip` → `fonts/complete/ttf/` | 2.5.0 | `~/.local/share/fonts/forest-shell/ibm-plex-mono/` |
| Newsreader | [google/fonts `ofl/newsreader`](https://github.com/google/fonts/tree/main/ofl/newsreader), variable TTFs | upstream `main` @ 2026-07-31 | `~/.local/share/fonts/forest-shell/newsreader/` |

Both Plex families ship 8 weights × upright/italic as static TTFs. Newsreader is
a **variable** font (`opsz`, `wght` axes), upright + italic.

Licenses ship alongside the fonts (`LICENSE.txt` / `OFL.txt`); all three are
SIL Open Font License 1.1.

### Family names QML must reference

Use the plain family name and set `font.weight` — **never** the legacy
sub-family names fontconfig also exposes (`IBM Plex Sans Medm`,
`IBM Plex Sans SmBld`, `IBM Plex Mono Light`, …):

```qml
Text {
    font.family: "IBM Plex Sans"   // or "IBM Plex Mono", or "Newsreader"
    font.weight: 500               // Font.Medium
}
```

Verified against Qt 6.11.1 / QtQuick: weight-to-face resolution on the canonical
family is exact — a canonical-family probe at each weight produced glyph metrics
identical to naming the sub-family directly (e.g. `"IBM Plex Sans"` at 500 and
`"IBM Plex Sans Medm"` at 400 both measure 421.125 px; `"IBM Plex Mono"` at 600
and `"IBM Plex Mono SmBld"` at 400 both render 889 ink pixels).

Weight map for both Plex families:

| `font.weight` | Face |
| --- | --- |
| 100 | Thin |
| 200 | ExtraLight |
| 300 | Light |
| 400 | Regular |
| 450 | Text |
| 500 | Medium |
| 600 | SemiBold |
| 700 | Bold |

Note 450 → **Text**: Qt accepts arbitrary numeric weights, so Plex's Text weight
is reachable even though QML has no named constant for it.

Newsreader resolves weights 200–700 continuously off the variable axis;
`font.weight: 300` gives the Light called for by the clock. Its `opsz` axis is
**not** driven by `font.pixelSize` — fontconfig pins the default 16pt optical
instance (it is also exposed as the alias family `Newsreader 16pt`). Set the
axis explicitly if a different optical size is ever wanted.

## Icons

`icons/lucide/` holds the **forest-shell-normalized** Lucide SVG set — all 1756
icons, vendored so icon lookups need no network and no npm dependency.

- Pinned version: **lucide 1.28.0** (released 2026-07-30)
- Source: [`lucide-icons-1.28.0.zip`](https://github.com/lucide-icons/lucide/releases/tag/1.28.0) release asset, `icons/*.svg` only (the sibling `*.json` metadata is not vendored)
- License: ISC (`icons/lucide/LICENSE`) — untouched by the normalization

To re-sync or bump the version, run `tools/vendor-lucide.sh [version]`; it
downloads, normalizes and replaces the directory wholesale. Do not hand-edit
files in it — `tests/run.sh` checks the invariants below on every run.

### Why the set is not pristine

Upstream icons open with `stroke="currentColor" stroke-width="2"`, and neither
survives contact with QML as-is:

1. **`currentColor` does not resolve.** Qt's SVG renderer draws the stroke
   **opaque black** regardless of any QML color — verified by rendering
   `wifi.svg` through `Image` and sampling the result (1316 px of `#000000`).
   An `Image` has no color property to override it either.
2. **Stroke weight is wrong.** The spec calls for **1.5px**; upstream is 2.

Neither is fixable at runtime, so [#19](https://github.com/danielbaldwin47/forest-shell/issues/19)
resolved to bake both in and recolor at runtime, and
[#34](https://github.com/danielbaldwin47/forest-shell/issues/34) did it. The set
carries two rewrites against upstream — the second applied to `fill` as well as
`stroke`:

| upstream | vendored |
| --- | --- |
| `stroke-width="2"` | `stroke-width="1.5"` |
| `stroke="currentColor"` | `stroke="#ffffff"` |
| `fill="currentColor"` (9 icons: `chart-scatter`, `images`, `key-round`, `palette`, `tag`, `tag-plus`, `tags`, `tag-x`, `vault`) | `fill="#ffffff"` |

White is a neutral base, not a palette choice: `MultiEffect { colorization: 1.0 }`
over a white source is **pixel-identical** to a file with the color baked in
(measured), so the color stays dynamic at no cost in fidelity. Rewriting only
`stroke` would leave those nine icons' inner dots black, and `MultiEffect` will
not lift black.

### Using them

`Widgets/Icon.qml` is the only thing that reads this directory. Icons are
addressed by **name** — the file stem — so the filenames are the lookup key and
there is no manifest to keep in step:

```qml
Icon { name: "wifi"; size: 16; color: Theme.textSecondary }
```

The `gallery.qml` entry point (`qs -p ~/repos/forest-shell/gallery.qml`)
renders the size ramp, the token roles and the oversample comparison on a real
session — which is where fractional scale and `MultiEffect` can actually be
judged.
