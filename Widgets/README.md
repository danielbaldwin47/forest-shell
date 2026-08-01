# Widgets

The dumb reusable kit ([architecture #12](https://github.com/danielbaldwin47/forest-shell/issues/12) §3).

| File | What |
| --- | --- |
| `Icon.qml` | A Lucide glyph, addressed by name, recoloured live |
| `DebouncedLoader.qml` | Content lifetime for windows that outlive their visibility |
| `Strata.qml` | A row of receding strata — height and opacity as a range, on either axis |

One rule, and it is the whole point of the directory:

- **A widget never reads Services or Config.** Everything it needs arrives as a
  property, set by the caller. That is what makes it reusable across surfaces,
  testable in isolation, and safe to instantiate before startup has finished.

The practical consequence is that widgets do not read `Theme` either — a widget
that reaches for a token has decided what it means, and the surface can no
longer use it for something else. So `Icon` takes a `color`, and the call site
passes `Theme.textSecondary`. Defaults are chosen to be *visible* rather than
correct, so a widget with nothing bound looks unfinished instead of invisible.

`gallery.qml` at the repo root renders the kit against real tokens. It is a
second Quickshell entry point, dev-only, and never loaded by the shell.
