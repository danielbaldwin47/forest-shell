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

`icons/lucide/` holds the **pristine** upstream Lucide SVG set — 1756 icons,
vendored so icon lookups need no network and no npm dependency.

- Pinned version: **lucide 1.28.0** (released 2026-07-30)
- Source: [`lucide-icons-1.28.0.zip`](https://github.com/lucide-icons/lucide/releases/tag/1.28.0) release asset, `icons/*.svg` only (the sibling `*.json` metadata is not vendored)
- License: ISC (`icons/lucide/LICENSE`)

To re-sync, download the release asset for the new tag and replace the directory
wholesale; do not hand-edit files in it.

### Two things upstream SVGs do not do

Upstream icons open with `stroke="currentColor" stroke-width="2"`, and neither
survives contact with QML as-is:

1. **`currentColor` does not resolve.** Qt's SVG renderer draws the stroke
   **opaque black** regardless of any QML color — verified by rendering
   `wifi.svg` through `Image` and sampling the result (1316 px of `#000000`).
   An `Image` has no color property to override it either.
2. **Stroke weight is wrong.** The spec calls for **1.5px**; upstream is 2.

Substituting a literal hex color and `stroke-width="1.5"` renders exactly as
asked (sampled `#66E0C8`, 893 ink px), so the raw assets are sound — they just
need either a preprocessing step, a runtime recolor
(`MultiEffect` / `ShaderEffect` colorization), or the Lucide **icon font**
(`lucide-font-1.28.0.zip` from the same release), where `Text.color` just works.
Choosing among those is
[the icon rendering strategy ticket](https://github.com/danielbaldwin47/forest-shell/issues/19).
