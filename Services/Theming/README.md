# Theming

The three palette modes behind `Core/Theme.qml`, and the one optional
dependency in the shell.

| Mode (`appearance.mode`) | What the wallpaper is allowed to say | Needs |
| --- | --- | --- |
| `forest` | Nothing. The shipped palette, untouched | — |
| `accent` | Two roles: `accentPrimary` and `accentDeep`, rotated inside the sage–lake band ([#58]) | — |
| `dynamic` | All seventeen. matugen generates the palette from the wallpaper ([#59]) | `matugen` |

All three land in the same place. A mode writes its result to
`appearance.dynamic` and `Core/Theme.qml` reads that key back, layering it under
the user's own `appearance.paletteOverrides`. Consumers stay mode-blind:
a surface reads `Theme.accentPrimary` and has no way to discover which mode
produced it, or whether one did.

The mode *choice* travels with a theme preset (#56); what a mode produced never
does. `appearance.dynamic` is flagged `derived` in the schema for exactly that
reason — it is what this machine sampled from this wallpaper, so a preset
replaces it wholesale rather than carrying last week's sample onto another
machine.

## Full dynamic needs matugen

[matugen](https://github.com/InioX/matugen) is optional and is the only path
that themes anything outside the shell. Without it:

- the mode is greyed out in the settings window with a line saying what to
  install — `Matugen.available` is the binding, and it is false until a
  `matugen --version` answers;
- a config file that names the mode anyway (a hand-edit, or a settings file
  copied from a machine that had it) leaves the shipped palette standing and
  says so once in the log. It is a missing option, not a fault, and nothing
  throws.

Install it with `pacman -S matugen` on Arch, or `cargo install matugen`
anywhere.

## What the shell asks matugen for

    matugen image <wallpaper> --json hex --prefer saturation --mode dark --quiet --dry-run

Three of those flags are load-bearing:

- `--prefer saturation` — on an image with more than one candidate source
  colour matugen asks the terminal which to use, and a shell that spawned it has
  no terminal to ask; without this it exits 1 on most real wallpapers.
- `--dry-run` — see the opt-in below. This is what keeps a wallpaper change from
  writing files outside the shell.
- `--mode` — only decides which row matugen calls `default`. Both the dark and
  the light row are in the JSON either way, so the dark/light flip is a re-map
  rather than a second read of the wallpaper.

The output is a Material 3 scheme of fifty semantic roles. The mapping onto the
shell's seventeen is a table at the top of `MatugenPolicy.qml` — the backgrounds
come off M3's `surface_container_*` elevation ladder, `fogWash` takes
`inverse_surface` because it is the one M3 role that flips sides with the mode,
and the accent structure is M3's primary/secondary/tertiary triad rather than
the brief's teal/amber/ember one, which is where the generated look stops being
the forest look.

## The contrast floor

A generated palette is the least trustworthy input the contrast floor will ever
see: nobody authored it, nobody looked at it, and the wallpaper that produced it
arrived this morning. matugen's tones hold AA for *M3's* pairings, which are not
the shell's — nothing in M3 has an opinion about `accentStone` as a label on
`surfaceOverlay`.

So every generated palette goes through a legibility pass before anything wears
it. The floors are `tests/tst_tokens.qml`'s, restated as data in
`MatugenPolicy.rules`: body text at 4.5:1 on all five backgrounds, muted text at
the 3:1 large-text floor the design brief chose for it, accent labels at 4.5:1
on the four surfaces a label lands on, `textPrimary` at 4.5:1 on the
`accentDeep` fill, and the two borders at visibility rather than legibility. A
role that falls short has its *lightness* walked until it clears — hue and
chroma untouched, since rescuing contrast by rotating would turn the colour the
wallpaper earned into a different one and call it the same. The backgrounds
themselves are never moved: their spacing is what makes an overlay look raised.

Both halves are gated. `tests/tst_matugenpolicy.qml` runs real matugen output
through the whole contract at seam 1, and `tools/matugen-harness.sh` ends by
handing the palette the *running shell* generated to
`tools/capture-harness.sh --contrast`, which measures the composite a table
cannot predict: a translucent bar fill over a photograph (#79).

## External templates are opt-in

matugen's other half is a template engine: given a `~/.config/matugen/config.toml`
it renders colour files for other applications, reloads the apps those templates
name, and runs whatever post-hooks are configured — kitty, foot, GTK, Discord,
whatever you have written a template for.

The shell does **not** do this by default. `--dry-run` is on the command line
until `appearance.matugenTemplates` is turned on ("Restyle other apps" in the
Appearance tab, visible only in full-dynamic mode). Off, matugen only ever hands
a palette back to the shell and writes nothing.

Turning it on means every wallpaper change writes those files, reloads those
apps and runs those hooks. Nothing happens until you have written templates of
your own — the shell ships none and configures none. matugen's own
documentation covers the format; the config it reads is yours, at
`$XDG_CONFIG_HOME/matugen/config.toml`.

The knob is not theme-flagged: a preset carries a *look*, and this is a decision
about whether the shell may restyle other people's applications on this machine.

## The seams

| What | Where |
| --- | --- |
| The band, the shift cap, the fail-closed reading (#58) | `tests/tst_accentpolicy.qml` |
| The mapping, both matugen output shapes, the strict exit status, the contrast contract (#59) | `tests/tst_matugenpolicy.qml` |
| The accent's lifecycle under a real shell | `tools/theming-harness.sh` |
| The generated palette's lifecycle, the templates opt-in, the absent binary | `tools/matugen-harness.sh` |
| A generated palette over a real wallpaper, pixel-exact | `tools/capture-harness.sh --contrast --palette` |

[#58]: https://github.com/danielbaldwin47/forest-shell/issues/58
[#59]: https://github.com/danielbaldwin47/forest-shell/issues/59
