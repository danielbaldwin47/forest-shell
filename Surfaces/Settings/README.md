# Settings

The settings window ([#54](https://github.com/danielbaldwin47/forest-shell/issues/54)
built the frame and four tabs; [#55](https://github.com/danielbaldwin47/forest-shell/issues/55)
built the other six, so all ten are live).

| File | What |
| --- | --- |
| `SettingsWindow.qml` | Singleton: who may open the window, and the `settings` IPC target |
| `SettingsView.qml` | The `FloatingWindow` — tab rail on the left, one page on the right |
| `SettingsTabs.qml` | The ten tabs as pure data. No Quickshell imports; `tests/` loads it |
| `AboutFacts.qml` | The version, the credits, and the changelog-seen rule. Also pure data |
| `Controls/` | The config-bound form kit, shared by every tab |
| `Tabs/` | The implemented tabs, plus the parts only one tab uses |

`NotificationRuleRow.qml`, `IdleStage.qml` and `ThemeSection.qml` live in
`Tabs/` rather than `Controls/` on purpose: each is one tab's editor for one key
group, not a form control anything else could hold. `ThemeSection.qml` is the
theme list ([#56](https://github.com/danielbaldwin47/forest-shell/issues/56)) —
it holds the window's one free-text field that is not a config key, since a
theme name is not in `settings.json` at all, and every file it touches belongs
to `Core/Themes.qml`. A second caller is what moves a file up to
`Controls/`, and that is exactly what happened to `OrderedList.qml`: it was the
Bar tab's `BarModuleCluster.qml` until #55 gave it two more callers — the
dashboard's cards and the control centre's grid are the same shape, an ordered
list of names where membership is the enable flag.

## Opening it

```qml
SettingsWindow.toggle()            // the control centre's gear (#45)
SettingsWindow.show("launcher")    // a launcher action (#40)
```

```sh
qs ipc call settings open              # the remembered tab
qs ipc call settings showTab launcher  # a named one
qs ipc call settings close
qs ipc show                            # the whole external surface
```

`tools/settings-harness.sh` drives all of it inside a nested Hyprland.

There is deliberately no `show` on the IPC surface
([#77](https://github.com/danielbaldwin47/forest-shell/issues/77)). `show` is
also a subcommand of `ipc` itself, and the client's parser takes the literal
token: every form of `qs ipc call settings show` — with an argument, without
one, after `--` — is parsed as `qs ipc show`, prints the target listing and
exits 0 without calling anything. `open` and `showTab` are the names that work.
`SettingsWindow.show(tab)` is unaffected; it is QML-facing and never sees the
CLI.

## The keyboard

Every control is reachable without a pointer
([#77](https://github.com/danielbaldwin47/forest-shell/issues/77)):

| Key | What |
| --- | --- |
| Tab / Shift-Tab | through the window: the rail is one stop, then the page |
| Up / Down | the tab rail — selection follows focus |
| Left / Right | the choice in a one-of-many chip row; one step on a slider |
| Home / End | a slider's ends |
| Space / Enter | activate: toggle a switch, pick a chip, press a button |
| Escape | close the window |

The decisions are in `Controls/KeyPolicy.qml`, which imports nothing but QtQuick
so `tests/` can check them; the controls hold `activeFocusOnTab`, a `FocusRing`
and a call into it. Tab traversal is also what scrolls a page — a control
focused below the fold is brought into view by `TabPage`.

A `FocusRing` is drawn only for `activeFocus`, and tapping a control does not
take focus, so a pointer user collects no rings behind them. The rail is the one
exception: selecting a tab rebuilds the page under whatever held the keyboard,
so the rail takes it back — however the tab was selected — and its ring is
around the selected row while it does.

In a many-of-many chip row (`SettingChips`) Tab moves between the chips and
Space toggles each: there is no "the choice" for an arrow key to move.

## Ground rules

- **Every write goes through `Config.set`.** No control touches a file. That is
  what makes the GUI's promises true by construction: writes are sparse, unknown
  keys survive, and a value the schema refuses is refused here too.
- **Every value is a binding on `Config.values`.** Nothing is cached, so an
  external edit to `settings.json` moves the controls with nothing subscribed
  and nothing polled.
- **The schema is the single declaration.** A theme-flagged group declares its
  knobs once (`SettingsSchema.group()`), and the coercer *and* the controls are
  both derived from that — a slider cannot offer a value the file would clamp.

  A *plain* leaf cannot reach that, and the exception is worth naming: its
  bounds live inside the closure `Coerce.integer` returns and nothing can read
  them back, so a slider on one has to be told its track at the call site. Where
  a tab does that, the track is declared in a pure-QML policy object the tab
  reads back — `Tabs/BarTabPolicy.qml` — and a test round-trips both ends
  through that leaf's own coercer, which is the only way left to ask a plain
  leaf what it accepts. The same object lists which leaves its tab covers, so
  "every key in this section has a control" is checkable at all: the tabs↔
  sections test only reaches section depth, and
  [#72](https://github.com/danielbaldwin47/forest-shell/issues/72) was five bar
  keys with no control that nothing failed on.
- **Hand-editing always works.** A tab that has not been built lists what its
  section already holds rather than pretending the section is empty.
- **The prose has a floor and the control has a ceiling.** `SettingRow` divides
  its width by `Controls/RowMetrics.qml`: a hint always keeps a readable
  measure, and a control too wide for what is left is the thing that gives. A
  control that can wrap reads `availableWidth` off the row's slot and sets its
  own width from it
  ([#80](https://github.com/danielbaldwin47/forest-shell/issues/80) — before
  this, three chips on the Appearance tab were off the right edge of the
  window).

  `Controls/OrderedList.qml` and `Tabs/NotificationRuleRow.qml` were audited
  for the same shape and do not have it: neither sits in a `SettingRow` slot,
  and in both the text column is the one on `Layout.fillWidth` and elides, so
  the controls beside it keep their width and stay on screen.

  The rule cuts the other way too, which #55's System tab is what found: a
  control that is *narrower* than what the slot allows and cannot show its value
  is the same bug seen from the other side. Every session command was longer
  than `SettingText`'s flat 132px box, so the tab that configures what ends your
  session read `tl dispatch exit`. A field now sizes to the value it holds,
  clamped by `slotCeiling` — and clamped with `Math.min` rather than assigned,
  because the slot's implicit width is its child's and a control that *takes*
  the ceiling widens the row that computed it.

## Why `Controls/` is not in `Widgets/`

`Widgets/README.md` draws the line at reading services: everything there takes
its value as a property, which is what makes it reusable and testable in
isolation. These controls read `Config` by design — a `ConfigBinding` *is* a
dotted path into the config engine — so they belong to the surface that uses
them.

When the control centre wants a switch, what moves to `Widgets/` is the switch:
a dumb `Switch { checked; onToggled }`, with `SettingSwitch` becoming the
three-line binding wrapper around it. Doing that now would be designing a
reusable API from one call site.
