# Launcher as a clearing — prototype findings

Issue [#11](https://github.com/danielbaldwin47/forest-shell/issues/11). Throwaway Quickshell
prototype, run on the T480 (UHD 620, Hyprland scale 1.5, upstream Quickshell 0.3.0, Qt 6.11.1).
36 scene captures in `shots/`, grouped into eight labelled comparison sheets in `sheets/`.
`./tools/build.sh` regenerates all of it; `./run-live.sh` runs the thing over the real desktop.

Everything is judged against a **procedural** stand-in desktop, not the Pinterest pins — those are
copyrighted reference material, gitignored, and can't ship as screenshots in a public repo. The
three stand-ins bracket the real difficulty: a high-key misty ridgeline (`ridge`), a dark forest
floor (`forest`), and high-frequency foliage under a blown-out sky (`busy`).

## Verdict

The clearing works — full-screen scrim, a hairline horizon for the field, strata below it, no box
anywhere. One thing in the brief does not survive contact: **the mist has to be dark.**

Recommended defaults, all visible in `shots/32-apps-query-dusk-panel-none.jpg`:

| | |
| --- | --- |
| scrim | **dusk** — blur + desaturate, veiled toward `bg-base` at 55%, plus a 10%→1% pale top-lit gradient |
| results | **no plate** — rows sit directly on the scrim, separated by hairlines |
| field | **hairline horizon**, no box; rule brightest at centre, dissolving at both ends |
| horizon | **32%** of screen height |
| column | 720 logical px wide, centred |
| rows | 46px, icon 22, title 14.5, subtitle 12, category caps 10.5 at +0.08em |
| selection | `accent-deep` @18% fill + 2px `accent-primary` left rail + full-saturation icon |

## 1. Pale mist is the one idea in the brief that fails

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

This is a change to the design brief's §6.1, not just to the launcher: the same scrim will back
the control centre, the dashboard and the session menu through the shared drawer window (#12).

## 2. With dusk, the results plate can go away — which is what the brief actually wanted

Sheet `2-panel.jpg`. The brief asks for "layered horizontal bands… stacked strata over boxed
grids and heavy card borders" (§5), then the pale scrim forces a plate under the rows just to
keep them legible — a box, arrived at by accident.

Under dusk, the plate is unnecessary: rows on hairlines float directly on the fog and the
composition reads as strata (`shots/32-apps-query-dusk-panel-none.jpg`). The rounded card
variant (`shots/09-panel-card.jpg`) is legible too and looks like a competent launcher from any
other project. It is the option to pick only if the floating version feels too weightless in
motion — which is a live-run judgement, not a screenshot one.

## 3. The blur is the compositor's, and on this machine it is off

A layer surface cannot blur what is behind it from inside QML: `MultiEffect` only reaches items
in its own scene. So the scrim's blur is entirely `layerrule = blur, forest-shell:launcher` —
and that rule is **inert unless `decoration:blur:enabled` is on globally**, which it is not here:

```
decoration:blur:enabled = 0        # currently, on this machine
decoration:blur:size    = 3
decoration:blur:passes  = 1
```

So the shell cannot assume its signature effect exists. Two consequences for the spec:

- The scrim must read as a scrim **with zero blur**. Sheet `8-no-compositor-blur.jpg`: dusk
  survives it on ordinary wallpapers (B), and on the high-frequency one the detail cuts through
  the veil and the panel gets noisy (C) — legible, but no longer calm. Pale mist without blur
  (A) is a wash of grey.
- Enabling blur is a **global** Hyprland setting, so forest-shell asking for it changes every
  other window's appearance and costs iGPU time on the primary machine. That is a user-facing
  install decision, not something the shell can quietly switch on. Candidate: ship a
  `launcher.scrimVeil` value that steps up (say 0.55 → 0.70) when blur is unavailable, and
  document the layerrule + global blur in the install steps.

Blur size 3 / passes 1 is also nowhere near the spec's 14px; `run-live.sh --blur` uses size 8 /
passes 3, which is roughly right, and restores your setting on exit.

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

## Open — needs a human

1. **Dusk vs pale mist.** The evidence says the brief's pale scrim can't carry dark-first text;
   dusk is the proposal. It changes a line of the design brief.
2. **Plate or no plate** under the rows (`2-panel.jpg`) — the floating version is the brief's own
   language, the card version is safer in motion.
3. **Category label everywhere or selected-only** (`7-rows.jpg` B vs C).
4. **What forest-shell asks of Hyprland**: require global blur in the install steps, or ship a
   heavier veil and treat blur as a bonus.
