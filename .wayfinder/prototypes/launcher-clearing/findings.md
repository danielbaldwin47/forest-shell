# Launcher as a clearing — prototype findings

Issue [#11](https://github.com/danielbaldwin47/forest-shell/issues/11). Throwaway Quickshell
prototype, run on the T480 (UHD 620, Hyprland scale 1.5, upstream Quickshell 0.3.0, Qt 6.11.1).
46 scene captures in `shots/`, grouped into twelve labelled comparison sheets in `sheets/`.
`./tools/build.sh` regenerates all of it; `./run-live.sh` runs the thing over the real desktop.

Everything is judged against a **procedural** stand-in desktop, not the Pinterest pins — those are
copyrighted reference material, gitignored, and can't ship as screenshots in a public repo. The
three stand-ins bracket the real difficulty: a high-key misty ridgeline (`ridge`), a dark forest
floor (`forest`), and high-frequency foliage under a blown-out sky (`busy`).

## Decided

Daniel's calls on the four HITL questions, 2026-07-31. Sheet `9-decided.jpg` is the result;
`shots/38-chosen-query.jpg` is the reference frame.

| | |
| --- | --- |
| scrim | **pale mist**, as the brief has it — `rgba(190,206,209,0.10)` over the compositor's blur |
| results | **card**, radius 16, `surface` @90%, holding field *and* results, top-lit |
| category | **on every row** |
| field | hairline rule under the field; with the card it is an internal divider, not a horizon |
| horizon | **32%** of screen height |
| column | 720 logical px wide, centred |
| rows | 46px, icon 22, title 14.5, subtitle 12, category caps 10.5 at +0.08em |
| selection | `accent-deep` @18% fill + 2px `accent-primary` left rail + full-saturation icon |

The card is what makes pale mist work. §1 below is the record of *why* the question was open —
a pale scrim genuinely cannot carry text directly — and the card answers it by never asking the
scrim to: every piece of text except the footer legend now sits on an opaque surface. Measured on
the card, `text-muted` on `surface`@90% is 4.26–4.43:1 depending on wallpaper, and identical to two
decimal places with the compositor's blur on or off. (4.26 is a shade under the 4.5:1 target: the
card is 90% opaque, so a bright wallpaper still leaks through. Row *subtitles* are the only thing
in that role — either take the card to ~94% or move subtitles to `text-secondary`. Titles are
`text-primary`/`text-secondary` and clear it comfortably.)

Two consequences worth carrying into the launcher spec:

- **The horizon metaphor is weaker than it was.** The rule still separates field from results, but
  it no longer spans the screen, and the boxed-vs-horizon distinction (§6) largely collapses once
  the field lives inside a card. What the clearing still buys is the emptiness *around* the card.
- **The footer legend is now the only UI on bare scrim**, and it is the one thing that measures
  badly — see §3.

The dusk variant stays in the prototype (`F1`) and in the shots, unused. If a later surface needs
text directly on the scrim, §1's numbers are the reason it will have to be revisited.

## 1. Pale mist cannot carry text directly — which is what the card is for

Sheet `1-scrim.jpg`, and the failure is loudest in `2-panel.jpg` A and `5-ask-claude.jpg` A.

The brief's §6.1 move — `rgba(190,206,209,0.10)` over a blur, "recede into mist, never dim to
black" — is derived from the pins, where fog is *bright*. But the shell is dark-first: light text
on a scrim. A pale wash **lightens exactly the surface the text has to sit on**, so over the
high-key wallpaper the contrast collapses. Body text at `text-secondary` over pale mist is
unreadable, and a wall of prose (the Ask Claude transcript) is the worst case on the board.

Dimming to black fixes contrast and throws away the whole design language — it reads like every
other launcher (`shots/02-scrim-dim.jpg`).

**Dusk** keeps the mechanic and inverts the direction: still blur, still desaturate, still a
top-lit gradient with more veil near the horizon — but veiled toward the palette's own
`bg-base #0b100d` rather than toward white. Atmospheric perspective still reads (the ridgelines
still recede, they just recede into evening), and every text role clears its contrast target on
all three wallpapers. `3-legibility.jpg` is the direct comparison; C and D are dusk.

**This was decided the other way**, and the decision is sound: keep the brief's pale mist and put
the text on a card instead of on the scrim. The constraint above is real but it only ever applied
to text sitting *on* the fog, and after the card decision the launcher has almost none. §6.1 of the
brief stands unchanged. What the section is still good for is the next surface that wants prose on
bare fog — the numbers say it will need either a card of its own or the dusk variant.

## 2. Plate or no plate — decided: card

Sheet `2-panel.jpg`. The brief asks for "layered horizontal bands… stacked strata over boxed
grids and heavy card borders" (§5), then the pale scrim forces a plate under the rows just to
keep them legible — a box, arrived at by accident.

Under dusk, the plate is unnecessary: rows on hairlines float directly on the fog and the
composition reads as strata (`shots/32-apps-query-dusk-panel-none.jpg`). The rounded card
variant (`shots/09-panel-card.jpg`) is legible too and looks like a competent launcher from any
other project. It is the option to pick only if the floating version feels too weightless in
motion — which is a live-run judgement, not a screenshot one.

**Decided: card**, and it carries the pale-mist decision with it (see §1). The two answers are one
answer: the card is what lets the scrim stay pale.

## 3. The blur is the compositor's, and on this machine it is off

A layer surface cannot blur what is behind it from inside QML: `MultiEffect` only reaches items
in its own scene. So the scrim's blur is entirely `layerrule = blur, forest-shell:launcher` —
and that rule is **inert unless `decoration:blur:enabled` is on globally**, which it is not here:

```
decoration:blur:enabled = 0        # currently, on this machine
decoration:blur:size    = 3
decoration:blur:passes  = 1
```

So the shell cannot assume its signature effect exists. What it *can* do is find out — verified
against upstream 0.3.0, this works and returns in a few ms at startup:

```qml
Process {
    running: true
    command: ["hyprctl", "getoption", "decoration:blur:enabled", "-j"]
    stdout: StdioCollector {
        onStreamFinished: Theme.compositorBlur = JSON.parse(this.text).int === 1
    }
}
```

### The measurement that settles it

Blur changes **texture, not luminance**. A Gaussian is a weighted average; it smears detail around
but leaves the mean roughly where it was. So blur can never fix a contrast problem — and, equally,
its absence can never cause one. `./tools/measure-contrast.py` prints the table below from the
captures (sheets `10-veil-ladder.jpg`, `11-veil-ladder-prose.jpg`, `12-footer-detail.jpg`):

| | busy wall | | ridge wall | |
| --- | --- | --- | --- | --- |
| | blur on | blur off | blur on | blur off |
| `text-muted` on the card | 4.43:1 | 4.43:1 | 4.26:1 | 4.26:1 |
| footer legend on bare scrim | 2.39:1 | 2.39:1 | 1.96:1 | 1.96:1 |

Identical to two decimal places in both directions. The card insulates its contents completely, and
the footer is equally bad either way. **Compositor blur is therefore cosmetic, not load-bearing** —
it makes the wallpaper calm behind the card, and that is all it does.

### The heavier-veil fallback is refuted

The earlier candidate — step the veil up when blur is unavailable — is actively wrong for a *pale*
mist, because a pale veil raises the luminance of the surface the light footer text sits on:

| veil (blur off) | footer legend contrast |
| --- | --- |
| 0.10 (spec) | 2.39:1 |
| 0.18 | 2.10:1 |
| 0.26 | 1.85:1 |

Sheet `12-footer-detail.jpg` is the crop. Every rung down makes it worse, and none of it touches
the card. Do not ship a veil ladder.

### What the shell should ask of Hyprland

Nothing mandatory. Ship `layerrule = blur, forest-shell:*` — it is a no-op when global blur is off,
so it costs nothing to always set — and document `decoration:blur:enabled` as an *optional* step
that makes the shell look better. It changes every window's appearance and costs iGPU time on the
T480, so it is the user's call, and nothing breaks if the answer is no.

### The real defect this uncovered

The footer legend is under-contrast **regardless of blur**: 1.96:1 over the ridge wallpaper,
2.39:1 over the busy one, against a 4.5:1 target for 11.5px text. The cause is not the scrim, it is
the role — `text-muted` at 0.55–0.75 opacity. Full-opacity `text-secondary` in the same place
measures 4.84:1 on ridge and 6.73:1 on busy with no backing plate at all. That is the fix; it
belongs in the launcher spec, and the same "muted text on bare scrim" pattern should be checked
wherever else it shows up.

Blur size 3 / passes 1 is also nowhere near the spec's 14px; `run-live.sh --blur` uses size 8 /
passes 3, which is roughly right, and restores your setting on exit. `F8` steps the veil live if
you want to re-check the ladder above with real compositor blur behind it.

## 4. The brief's amber rule does not survive real app icons

§6.5 says "only the selected row's icon warms to `#d8ac81`". That works for the monochrome Lucide
glyphs the non-app providers use, and is impossible for apps: their icons are full-colour PNGs.

What works instead is the board's own mechanic applied to the icons: **unselected rows sit in the
haze** — icon desaturated 65%, lifted 6% in brightness, 72% opacity, title dropped to
`text-secondary`; the selected row comes forward at full saturation. Selection then reads even
with the fill and rail removed, and the row list looks like depth rather than a highlight bar.
Sheet `7-rows.jpg` A vs B. Amber survives where it can: on Lucide-icon providers the selected
icon warms, and it stays the one amber element on screen.

## 5. Ask Claude

`5-ask-claude.jpg`. The transcript replaces the results list, keeps the same column and the same
horizon; the field turns into "Reply…" and grows a model chip (`haiku`, warm, mono) on the right.
Turn labels are the caps micro-label already in the type scale (`YOU` muted, `CLAUDE` teal).

Two things the screenshots settle. The streaming caret reads better as a 7×15 block than as a text
cursor. And the shared column is **too wide for prose**: 720px at 14.5px runs ~105 characters a
line, well past a comfortable measure, and it shows — the transcript in `5-ask-claude.jpg` reads
like a paragraph in a spreadsheet. The row list wants the full 720; the transcript wants ~600.
Recommendation: keep one column for the field and the rule, and cap the *text* measure inside it.
Everything else about this provider — how a turn ends, where the cost/latency goes, what happens
on tool denial — is spec work off the back of the CLI contract (#16), not a visual question.

## 6. Geometry

`6-geometry.jpg`. The horizon fraction trades sky for rows. On this 1280×720 logical screen, with
46px rows, the list capped to what fits above the legend:

| horizon | rows visible | reads as |
| --- | --- | --- |
| 22% | 10 | field floating high in empty sky, list dominates the screen |
| **32%** | **8** | sky above, strata below, legend clear — the clearing |
| 42% | 7 | field near centre, list crowds the legend, no sky left |

The boxed field (D) is not worse in isolation — it is just a different shell; it stops being a
horizon and the whole clearing metaphor goes with it.

A first pass let the list run off the bottom of the screen behind the legend whenever a query
matched more than the fold. The list is now capped at what fits and says `N more` in the muted
role. Scrolling past the cap is unspecified — the prototype does not scroll, and the real one has
to decide whether the fold scrolls or is simply where results stop.

## 7. Small calls the shots make

- **Category label on every row** (`APP`, `ACTION`, …) is noisy when every row is an app.
  `7-rows.jpg` C shows the alternative: label on the selected row only. Either is defensible;
  the selected-only version is quieter and matches "exactly one thing at a time".
  **Decided: on every row.**
- **Provider legend + key hints** at the bottom (`= calc ; clipboard : emoji / actions ? ask
  claude`) is how the six providers become discoverable at all; the prefix that is active
  brightens. `7-rows.jpg` D is the version without it — cleaner, and undiscoverable.
- **The provider chip** on the left of the field turns the punctuation into a room you are in
  ("Calculate", "Ask Claude") the moment the prefix resolves.
- **God ray** (a 5%→0 top-lit wash over the whole scrim) is on by default and nearly invisible;
  `shots/11-godray-off.jpg` is the comparison. It survives because it costs nothing.

## Traps for whoever builds this (all silently produce a plausible wrong result)

- **`grabToImage` is asynchronous.** Applying the next scene right after requesting a grab lands
  the *next* state in the file. Every capture looked fine and every one was off by one. The scene
  may only advance inside the callback.
- **`win.contentItem` cannot be grabbed** — "item has no QML engine". Put the content in a
  QML-declared `Item` and grab that.
- **`DesktopEntries.applications` is empty** in a detached/background shell, and stays empty even
  with `XDG_DATA_DIRS`/`XDG_DATA_HOME` exported into the process (both upstream 0.3.0 and the
  noctalia fork, 194 entries on disk). Icon-theme lookup via `Quickshell.iconPath` works in the
  same process. The prototype uses a baked fixture instead; the real launcher will need this
  understood before it trusts the model.
- **`font.pixelSize` is an int** and the type scale has half-pixel steps (14.5, 12.5, 10.5). Sizes
  go through `font.pointSize` with a `px * 72/96` helper — worth putting in `Core/Theme.qml` once.
- **`MultiEffect` renders nothing under `QT_QPA_PLATFORM=offscreen`** (carried over from #19, and
  it bites here twice: icons *and* the scrim blur). The capture has to run on the real session.
- **Blur strength is not a length.** `blurMax: 48` turns the wallpaper to soup and the scrim stops
  reading as atmosphere-over-a-place; the landmarks have to survive. `blur: 0.5, blurMax: 32` is
  the in-process approximation of the spec's 14px.

## What this hands to the launcher ticket

Settled here, ready to be specified:

1. Scrim is the brief's pale mist at 0.10; the card is what makes it work (§1, §2).
2. Results and field live on one card, radius 16, `surface`@90%, top-lit. Category on every row.
3. Compositor blur is optional and cosmetic. Always set the layerrule; never require global blur;
   never ship a veil ladder (§3).
4. Detect blur at startup via `hyprctl getoption` if anything ever needs to adapt — verified
   working, snippet in §3.
5. Footer legend moves to full-opacity `text-secondary`; the current muted role measures 1.96:1 (§3).
6. Selection = `accent-deep`@18% + 2px rail + full-saturation icon; unselected rows sit in the haze,
   because real app icons cannot take the brief's amber (§4).
7. Horizon at 32%, 720px column, 46px rows, list capped at the fold with an `N more` label (§6).

Still open, and not a screenshot question:

- **Does the fold scroll, or is it where results stop?** (§6)
- **Prose measure inside the shared column** — 720px runs ~105 characters; the transcript wants
  ~600 (§5). Needs a live read, not a still.
- **Motion.** Nothing here tests open/close, and the card was chosen partly on how it will behave
  in motion. `run-live.sh` is the way to check it.
