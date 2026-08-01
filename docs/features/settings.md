# Settings window and theme presets

Sources: [#9](https://github.com/danielbaldwin47/forest-shell/issues/9), [#21](https://github.com/danielbaldwin47/forest-shell/issues/21), [#26](https://github.com/danielbaldwin47/forest-shell/issues/26), [#27](https://github.com/danielbaldwin47/forest-shell/issues/27), [#10](https://github.com/danielbaldwin47/forest-shell/issues/10), [#8](https://github.com/danielbaldwin47/forest-shell/issues/8), [#6](https://github.com/danielbaldwin47/forest-shell/issues/6)

Two things live here: the settings GUI, and the theme-preset system that sits on top of it.

## The contract

**`settings.json` with hot reload is the source of truth. The GUI is a client of it, never the
other way around.** Hand-editing always works, an external edit is reflected live in an open
settings window, and every value the GUI writes goes through the same spec-table store a hand-edit
goes through.

Consequences that shape every decision below:

- The GUI covers the **named surfaces** — the controls a user is expected to reach for. Long-tail
  options may stay JSON-only until they earn a control. A key with no GUI control is not a bug.
- The GUI never writes a key the user did not change. The file stays sparse: only keys differing
  from their defaults are present, so new shell versions' updated defaults flow through
  automatically and reset-to-default is key deletion.
- Comments are impossible — strict JSON, because GUI writes would destroy them. Discovery of
  available options is the GUI's job, not the file's.
- **Exception, one direction only:** every key flagged `theme: true` in the spec table must have a
  GUI control, because themes are authored by setting values in the GUI and saving them.

## The window

`Surfaces/Settings/` — a **floating window** (`FloatingWindow`), a normal Wayland toplevel, not a
layer-shell surface and not part of the shared drawer window.

| | |
|---|---|
| Default size | 960 × 640 logical px |
| Minimum size | 800 × 560 |
| Layout | 176 px vertical tab rail on the left, 24 px content padding, one scroll area per tab |
| Instances | One. Re-opening focuses and raises the existing window. |
| Motion | **Compositor-managed** (#27). Hyprland animates open, close, move, and resize; the shell animates nothing about the window itself. The only shell-side motion is a 140 ms crossfade of tab content on tab change. |
| Last tab | Persisted in the state file, restored on open. |

Entry points: the settings gear in the control center's bottom strip; the launcher `/` actions
provider (`/settings`, and per-page actions that deep-link a tab); `IpcHandler { target: "settings" }`
with `open(tab)` / `close()`. No default keybind.

## Tabs

Ten tabs. Nine map 1:1 onto the nine top-level sections of `settings.json`; About has no config.
The mapping is the point — hand-editing lands exactly where the GUI put you.

| Tab | Section | Covers |
|---|---|---|
| Appearance | `appearance` | Palette overrides, theming mode, **theme presets** (below), `reducedEffects` |
| Bar | `bar` | Position, flush/floating, height, padding, module gap, module list and order, surface (opacity / blur / mist / hairline / grain / adaptive opacity), ridgeline block |
| Launcher | `launcher` | Providers, prefixes, result counts, frecency, and the **Claude section** (default model, effort level, tool allowlist, permission mode) |
| Control Center | `controlCenter` | Slider set, toggle-grid contents and order, bottom-strip options |
| Dashboard | `dashboard` | Card registry: add / remove / reorder |
| Notifications | `notifications` | Popup placement and timeouts, DND behavior, history size, and the **per-app rules list** (normal / silent / blocked per app that has notified) |
| Weather & Time | `weatherTime` | Open-Meteo location (geocoded place name or IP auto), units, clock format, seconds visibility |
| Wallpaper | `wallpaper` | Current wallpaper, source directory, fit mode, per-screen assignment |
| System | `system` | Screenshot and recorder options, the idle ladder, lock surface options, session commands |
| About | — | Shell version, Quickshell version, resolved config and state paths, a button that opens `settings.json` in `$EDITOR`, links |

Per-tab detail belongs to each feature's own spec; this document owns the window, the interaction
rules, and the theme system.

## Control behavior

- Widgets come from `Widgets/` — switch, slider, spin box, dropdown, text field, color field,
  reorderable list — and never read `Config` or a service directly; the tab passes values in and
  changes out.
- A control whose key is **present in the sparse file** (i.e. differs from the default) shows a
  revert affordance next to it. Activating it deletes the key.
- Each section has a **Reset section** action, which deletes every key in that section and confirms
  first. There is no global reset in the GUI; deleting `settings.json` does that.
- Writes are debounced and atomic, with the ~2 s post-save cooldown that breaks the
  save → watch → reload loop. A control being dragged does not write per frame.
- **Bad values arriving from a hand-edit** surface here: the invalid key falls back to its default
  and the control shows an inline warning with the value that was rejected, matching the
  notification the config store already raises. Invalid JSON leaves the shell on the last-good
  config; the settings window shows a banner with the parse error location and every control
  disabled until the file parses again.

## Theme presets

A **theme** is a named, sparse fragment of theme-flagged keys. It is a snapshot, not a live link.
The config schema does almost all the work; the theme system is a thin layer on top of it.

### What a theme is made of

The flag lives per-key in the spec table (`theme: true`); the theme system derives everything else
from it. A theme carries **skin, not layout**:

| Travels with a theme | Does not travel |
|---|---|
| `appearance.paletteOverrides` (whole object) | `bar.position`, flush vs floating, `bar.height`, padding, module gap |
| `appearance.themingMode` | `bar.modules` — the bar's module list and order |
| everything under `appearance.dynamic` | `appearance.reducedEffects` |
| everything under `bar.surface` — opacity, mist wash, top light, hairline, grain, adaptive opacity | every other section: `launcher`, `controlCenter`, `dashboard`, `notifications`, `weatherTime`, `wallpaper`, `system` |
| everything under `bar.ridgeline` — shape, unit width, gap, heights, falloffs, haze, active accent | |

**Rule for new keys:** anything added under `appearance.paletteOverrides`, `appearance.dynamic`,
`bar.surface`, or `bar.ridgeline` is theme-flagged automatically. Anything added anywhere else is
not, unless its spec entry says so explicitly.

Layout and the module list are excluded on purpose: they are **per-machine**. The desktop has no
volume or battery module and uses ethernet rather than wifi; the T480 is the opposite. A theme that
moved those would fight the two-machine setup every time it was applied.

### Storage

- `~/.config/forest-shell/themes/<name>.json` — one file per theme, in the config directory
  alongside `settings.json`.
- Each file is **sparse** (only the theme-flagged keys the theme actually sets) and carries its own
  top-level `settingsVersion`.
- **Identity is the filename.** The display name is the filename minus `.json`; rename is a file
  rename; there is no `name` field inside the file. One source of truth.
- Migrations reuse the config schema's raw-JSON migration pass, run per file at startup right after
  `settings.json` migrates, with the same `<name>.json.bak-vN` backup convention.
- A theme file that fails to parse, or fails to migrate, appears greyed in the list with the parse
  error as its subtitle and Apply disabled. The shell never rewrites it.

```json
{
  "settingsVersion": 1,
  "appearance": {
    "themingMode": "constrained",
    "paletteOverrides": { "accent-primary": "#7abfa9" }
  },
  "bar": {
    "surface": { "opacity": 0.78, "grain": 0.05 }
  }
}
```

### Apply is a copy

Applying a theme is one atomic rewrite of `settings.json`:

1. Snapshot the current values of every theme-flagged key into the undo slot (below).
2. Delete every theme-flagged key from `settings.json`.
3. Merge the theme file's keys in.
4. Set `appearance.lastAppliedTheme` to the theme's name.
5. Write once, through the normal GUI write path — same debounce, same atomic write, same cooldown.

Hot reload picks the file up and `Core/Theme.qml` re-derives. **There is no live link.** Editing a
setting after applying a theme does not modify the theme file, and editing a theme file does not
change the running config. Later edits diverge silently, by design — the alternative is a
two-writer system with no clear owner.

`appearance.lastAppliedTheme` is a **breadcrumb only**. Nothing reads it except the GUI, to show
which entry is highlighted. It goes stale the moment a theme-flagged key is edited by hand, and
that is acceptable.

Color tokens crossfade at 240 ms fog ease on apply (`Behavior on color` inside `Core/Theme.qml`).
The crossfade is suppressed on first load and whenever `reducedEffects` is true.

### Shipped themes: none

**Zero theme files ship.** `themes/` does not exist until the user saves one.

**"Forest (default)"** appears in the GUI as a built-in entry, implemented as a reset: delete every
theme-flagged key from `settings.json`. The sparse-file rule restores the defaults, which are the
forest palette and the bar/ridgeline defaults from the bar spec. It is not a file and cannot be
renamed or deleted.

The **light palette is not a theme.** It stays deferred (v1 ships dark-first) and will land as a
palette variant/mode, not as a preset file.

### Interaction with wallpaper-dynamic theming

A wallpaper-derived palette is **never a theme**. It is a mode's *output*: it lives in runtime
state and is never written to `settings.json` or to a theme file.

The mode **choice** does travel, because `appearance.themingMode` is theme-flagged — so a saved
look restores whether its accent follows the wallpaper, without freezing whatever accent the
wallpaper happened to produce when the theme was saved.

Resolution order, once and for all:

```
spec-table defaults  ←  theme-applied static values in settings.json  ←  dynamic layer per mode
```

The dynamic layer is last and lives outside the config file entirely. See
[dynamic-theming.md](dynamic-theming.md).

### GUI (Appearance tab)

A single list, in this order:

1. **Previous settings** — the undo slot. Hidden until a first apply has populated it.
2. **Forest (default)** — the built-in reset entry.
3. User themes, alphabetical by filename.

Actions:

| Action | Behavior |
|---|---|
| **Apply** | Immediate and live via hot reload. **No confirmation.** |
| **Save current as…** | Prompts for a name. Writes the current values of every theme-flagged key that differs from default. Saving over an existing name **confirms** first. |
| **Rename** | Renames the file. Rejects a name that collides or is not a valid filename. |
| **Delete** | **Confirms**, then removes the file. |

Save/rename/delete are disabled for the two built-in entries.

### Undo slot — "Previous settings"

A single automatic slot in `Quickshell.stateDir` — **ephemeral, auto-managed, never synced between
machines**, per the config/state split (config is portable setup; this is a scratch buffer).

- The shell snapshots the current values of all theme-flagged keys into the slot **on every
  apply** — user theme, Forest (default), or Previous settings itself — and then applies.
- Because applying Previous settings snapshots first, it **toggles**: apply a theme, dislike it,
  apply Previous settings, change your mind, apply Previous settings again.
- The entry is hidden until the first apply populates it.
- State keys: `theme.previous` (object of theme-flagged keys) and `theme.previousFrom` (the name
  that was current when the snapshot was taken, shown as the entry's subtitle).
- The slot is not a history. There is exactly one, it is overwritten every time, and it does not
  survive a state-file deletion.

## Acceptance checks

1. Editing `settings.json` in an external editor updates an open settings window without a reload
   and without the window writing anything back.
2. Changing a control and then deleting its key by hand returns the control to its default and
   removes the revert affordance.
3. A theme saved on one machine, copied to the other, and applied changes the palette and bar
   surface and leaves bar height, position, and the module list untouched.
4. Apply a theme, then Previous settings, then Previous settings again: the config toggles between
   exactly two states.
5. Apply Forest (default) on a config with theme-flagged keys set: those keys disappear from
   `settings.json` and every other key survives.
6. Corrupt a theme file: it greys out in the list, Apply is disabled, the shell keeps running, and
   the file is not rewritten.
