# Settings

The settings window ([#54](https://github.com/danielbaldwin47/forest-shell/issues/54)
builds the frame and four tabs; [#55](https://github.com/danielbaldwin47/forest-shell/issues/55)
builds the other six).

| File | What |
| --- | --- |
| `SettingsWindow.qml` | Singleton: who may open the window, and the `settings` IPC target |
| `SettingsView.qml` | The `FloatingWindow` — tab rail on the left, one page on the right |
| `SettingsTabs.qml` | The ten tabs as pure data. No Quickshell imports; `tests/` loads it |
| `Controls/` | The config-bound form kit, shared by every tab |
| `Tabs/` | The implemented tabs, plus the parts only one tab uses |

`BarModuleCluster.qml` and `NotificationRuleRow.qml` live in `Tabs/` rather than
`Controls/` on purpose: each is one tab's editor for one key, not a form control
anything else could hold. A second caller is what moves a file up to `Controls/`.

## Opening it

```qml
SettingsWindow.toggle()            // the control centre's gear (#45)
SettingsWindow.show("launcher")    // a launcher action (#40)
```

```sh
qs ipc call settings show launcher
qs ipc show target settings        # the whole external surface
```

Neither the control centre nor the launcher exists yet, so the IPC target is
currently the only way in — and the way the ticket's first acceptance criterion
is exercised until they land and call the same functions.

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
- **Hand-editing always works.** A tab that has not been built lists what its
  section already holds rather than pretending the section is empty.

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
