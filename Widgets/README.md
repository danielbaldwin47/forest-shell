# Widgets

The dumb reusable kit ([architecture #12](https://github.com/danielbaldwin47/forest-shell/issues/12) §3).

| File | What |
| --- | --- |
| `Icon.qml` | A Lucide glyph, addressed by name, recoloured live |
| `DebouncedLoader.qml` | Content lifetime for windows that outlive their visibility |
| `Ridgeline.qml` | A row of forms whose height and opacity encode state, read as receding strata |
| `Sparkline.qml` | A minute of a fraction as a fixed-slot row, newest at the right |

One rule, and it is the whole point of the directory:

- **A widget never reads Services or Config.** Everything it needs arrives as a
  property, set by the caller. That is what makes it reusable across surfaces,
  testable in isolation, and safe to instantiate before startup has finished.

The practical consequence is that widgets do not read `Theme` either — a widget
that reaches for a token has decided what it means, and the surface can no
longer use it for something else. So `Icon` takes a `color`, and the call site
passes `Theme.textSecondary`. Defaults are chosen to be *visible* rather than
correct, so a widget with nothing bound looks unfinished instead of invisible.

The same rule is what makes `Ridgeline` a widget rather than a workspace
indicator: it takes a list of cells and knows nothing about workspaces, so the
compositor wiring, the settings and the token roles all live one level up in
`Surfaces/Bar/Modules/Workspaces.qml`. Widgets are also built **axis-agnostic**
where the axis could plausibly change ([feature inventory #9](https://github.com/danielbaldwin47/forest-shell/issues/9):
a vertical bar lands post-v1 without rewrites).

`gallery.qml` at the repo root renders the kit against real tokens. It is a
second Quickshell entry point, dev-only, and never loaded by the shell.
