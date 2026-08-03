# Services

Cross-surface state and side effects, as `pragma Singleton` singletons grouped by
domain ([architecture #12](https://github.com/danielbaldwin47/forest-shell/issues/12) §3):

| Directory | Owns |
| --- | --- |
| `Compositor/` | The Hyprland facade — the only place `hyprctl` / dispatch lives |
| `Notifications/` | The freedesktop daemon, popups, DND, history and per-app rules |
| `Media/` | MPRIS players, volume, sinks |
| `Hardware/` | Battery, brightness, sensors, input devices |
| `Networking/` | Wi-Fi, Bluetooth, VPN |
| `Launcher/` | The launcher's providers and the dispatcher that routes to them |
| `System/` | Session, logind, updates, disk, the tray — `SessionLock` (#47), `SystemStats` (#50) |
| `Weather/` | The forecast behind the dashboard's weather card (#50) |
| `Screenshot/` | The region picker's freeze, selection, save and handoff (#51) |
| `Recorder/` | Screen recording over the two encoders, and the fallback between them (#52) |
| `Theming/` | The three palette modes behind `Core/Theme.qml` — the constrained accent (#58) is built, the full dynamic one (#59) is not |
| `Claude/` | The Claude CLI subprocess and its session state |

Two rules that hold across all of them:

- A service that runs unconditionally must be named in `Core/ServiceInit.qml` —
  a singleton nothing references is never constructed.
- A service that only one surface uses is not a service: it lives with its
  surface (`Surfaces/Drawers/Launcher/services/`), not here.

A third rule, added by #36, because two of these services collide by name with
the upstream module they wrap:

- **A facade that shadows an upstream singleton imports it under an alias.**
  `Quickshell.Networking`, `Quickshell.Bluetooth`, `Quickshell.Services.Mpris`
  and `Quickshell.Services.SystemTray` each export a singleton named after the
  module, and so do we — `Nm.`, `Bz.`, `Mp.` and `Sni.` respectively. Inside `Networking.qml` and
  `Bluetooth.qml`, `Nm.` and `Bz.` mean upstream's; everywhere else in the
  shell the unqualified name means the facade. Two types with one name is the
  failure mode Core/Config.qml documents for a singleton called `State` — no
  error anywhere, every property reading back `undefined`. Where a *bar module*
  would collide instead, the service takes the different name: the backlight
  facade is `Backlight`, because `Surfaces/Bar/Modules/Brightness.qml` is
  already `Brightness`.

Nineteen of them exist so far:

- `Notifications/` (#42) — `NotificationServer`, the live popup list,
  do-not-disturb and the persisted history. The rules about an arriving
  notification are split into `NotificationPolicy.qml`, which imports nothing
  but QtQuick so `tests/` can reach them; the singleton next door is the wiring.
  Since #43 the same split carries what the centre *shows*: `groups()`,
  `withoutApp()`, `withoutRow()` and `unreadSince()` are pure functions here,
  and `Surfaces/Drawers/NotificationCenter.qml` is only the picture. The surface
  sets `centerOpen` while it is up — the service reads that flag, and no
  service ever imports a surface to get it.
- `Compositor/` (#35, #42) — the Hyprland facade. It reports workspaces as
  plain data, focuses them, owns the one `hyprctl` call the shell makes — the
  layer rule that asks Hyprland to blur behind the bar, spelled and read by
  `LayerRulePolicy.qml` on the QtQuick-only side of the line so `tests/` can
  reach both halves of it (#78) — and answers the two
  questions the popups ask: the focused screen, and whether that screen is
  showing a fullscreen window. Everything above it speaks in workspace ids and
  intentions, which is what keeps Hyprland's two awkward facts (empty
  workspaces do not exist; window counts are a stale snapshot until you ask
  again) in one file.
- `System/SessionLock.qml` (#47) — and it tests both rules. It is not named in
  `Core/ServiceInit.qml`, because it listens to nothing and does nothing until
  someone asks it to lock — and until the idle ladder (#48) gives it a
  subscription of its own there is nothing for a force-touch to start. Since
  #71 it is in fact constructed at startup anyway, by the notification service:
  that is what writes its `notificationCount`, and it is on the deferred list.
  Nothing about the rule changes — a service that must run whether or not
  anything is looking at it still has to be named there, and this one need not,
  because whoever constructs it it does nothing until asked. It is a service
  rather than a file under
  `Surfaces/Lock/` even though the lock surface is its only consumer *today*,
  because "who uses it" is the wrong reading of the second rule — the question
  is who is allowed to **decide**. Locking is reached from the session menu
  (#44), the idle ladder and the pre-suspend hook (#48) as well as the lock's
  own IPC target, and the spec ([#30]) requires all of them to converge on one
  `lock()`. A door that lives inside the room it opens would make every one of
  those callers reach through `Surfaces/`.

- `Media/Audio.qml`, `Networking/Networking.qml`, `Networking/Bluetooth.qml`,
  `Hardware/Power.qml`, `Hardware/Backlight.qml` (#36) — the system service
  layer behind the bar's status cluster, battery and brightness readout. Four
  of the five are pure wiring over a native Quickshell client (PipeWire,
  NetworkManager, BlueZ, UPower — #4 surveyed all four as native, which is why
  nothing here shells out to `wpctl`, `nmcli` or `bluetoothctl`), and each
  keeps its decisions in a `*Policy.qml` beside it so `tests/` can reach them.
  `Backlight` is the exception and the reason the CLI-wrapper rule exists
  (#12): there is no brightness type anywhere in Quickshell, so it reads
  `/sys/class/backlight` through a `FileView` and writes through
  `brightnessctl` — one subprocess, exit status read (#78), coalesced so a held
  key cannot kill the run in flight.

  All five are named in `Core/ServiceInit.qml`'s deferred list, and they have
  to be: each native backend only starts when something first touches its
  singleton, and then takes about a second to answer. A service constructed
  when the user first opens a panel would spend that second reporting a machine
  with no radios and no battery.

- `Media/Mpris.qml`, `System/SystemTray.qml` (#37) — the two services behind
  bar modules whose *contents* belong to other applications. Both are native
  clients (`Quickshell.Services.Mpris`, `Quickshell.Services.SystemTray`), both
  keep their decisions in a policy beside them, and both are in the deferred
  list for a sharper version of the same argument: the StatusNotifier host is
  registered by the singleton being constructed, so a tray that waited for the
  bar module would lose the icon of every application that started before it.
  `Mpris`'s difficulty is which player the pill is about when several are on
  the bus, and it is entirely in `MprisPolicy.qml`.

  `SystemTray` is the other side of the naming rule above: it carries the
  upstream singleton's name and imports it as `Sni.`, because
  `Surfaces/Bar/Modules/Tray.qml` is already `Tray` — the same trade
  `Backlight` made for `Brightness`, taken the other way round.

  `Compositor/` grew two things for the same ticket, and one of them is a
  parser: Quickshell models no input devices at all, so the keyboard layout is
  read out of `hyprctl devices -j` by `KeyboardPolicy.qml` and re-read after
  each `activelayout` event. That policy also remembers the trap —
  `switchxkblayout` is a hyprctl *command*, not a dispatcher, and sending it
  through `Hyprland.dispatch` answers `Invalid dispatcher` and changes
  nothing.

- `Launcher/` (#39, #40) — one directory per the second rule's *inverse*. The
  launcher surface is the only thing that draws these, but it is not the only
  thing allowed to decide: `Providers.qml` is the dispatcher, and what a query
  routes to, what it matches and what Enter means are questions a keybind and a
  script have to be able to reach as well.

  `Apps.qml` (#39) is the desktop-entry model, the launch and the frecency
  write. `Calculator.qml`, `Actions.qml` and the pure `EmojiPolicy.qml` (#40)
  are the other three; the emoji provider has no singleton because it is a
  compiled-in table and a search over it, which needs no Quickshell at all.

  Only `Calculator` is in `Core/ServiceInit.qml`'s deferred list beside `Apps`,
  and for a smaller reason than the native backends have: it probes once for
  `qalc`, and a probe that only ran when the user first typed `=` would show
  "Working…" and then "not installed" instead of saying so immediately.

  It is also where the CLI-wrapper rule (#12) is exercised a second time, more
  sharply than `Backlight` exercises it. Measured against Quickshell 0.3.0, a
  `Process` whose binary does not exist emits **no `exited` signal at all** —
  only `running` going false — so there is no exit code to read and the absence
  of `started` is the only signal that the tool is missing. Keying the message
  off empty output instead would be the #78 shape exactly, and
  `tools/launcher-harness.sh` check 20 restarts the shell against a PATH with
  everything on it but `qalc` to prove it does not.

  `Actions.qml` is the one file under `Services/` that imports a surface
  (`qs.Surfaces.Settings`). That is sanctioned rather than accidental:
  `SettingsWindow.qml`'s own header names this caller, and
  `Core/SurfaceBusPolicy.qml` explains why the settings window is deliberately
  not on the surface bus.

  It no longer implies that nothing under `Surfaces/Settings/` imports
  `qs.Services.*`: since #71 `Tabs/NotificationsTab.qml` imports
  `qs.Services.Notifications`, because the list of apps that have notified is
  the notification service's history and reading it through anything else would
  be a copy of it. The chain is still acyclic —
  `Services.Launcher` → `Surfaces.Settings` → `Surfaces.Settings.Tabs` →
  `Services.Notifications`, and the notification service imports neither
  surface. That is the thing to re-check before another import is added at
  either end: the invariant is that the arrows do not close, not that they
  never leave `Services/`.

- `System/SystemStats.qml` and `Weather/Weather.qml` (#50) — the dashboard's two
  data cards, and between them the two ends of the force-touch rule.

  `Weather` is on the deferred list for what it does *not* do there: naming it
  constructs it, and construction reads the cached forecast out of `state.json`
  — a file read, no network. Without the line the cache would only be read the
  first time a dashboard opened, so every session's first open would show an
  empty card while a request was in flight. The request itself waits for a card
  to appear over a stale reading, and the refresh timer runs only while one is
  on screen; a shell nobody has opened the dashboard on makes no HTTP at all.
  It is also the one service here that speaks to the network, and the one place
  the shell uses `XMLHttpRequest` rather than a subprocess — there is no tool to
  wrap, so there is no exit status to read and no missing binary to report.

  `SystemStats` is deliberately **not** named in `Core/ServiceInit.qml`, and it
  is the sharpest case for the rule cutting the other way. It is the one service
  that costs something continuously — four file reads a second — so it samples
  only while something holds a subscription (`watch()` / `release()`), which the
  dashboard card takes while it is on screen and the optional bar module takes
  for the session. Nothing to force-touch: there is no startup work, and a
  singleton nobody has subscribed to has nothing to start. Both edges are
  logged, because "sampling stopped when the drawer closed" is an acceptance
  criterion and a lifecycle nothing logs has two candidate causes (#81);
  `tools/drawer-harness.sh` reads those two lines.

- `Screenshot/Screenshot.qml` (#51) and `Recorder/Recorder.qml` (#52) — the two
  services that own a rectangle, and the one place a service hands work to
  another one.

  The picker grew a mode rather than the recorder growing a second selection
  UI: `Screenshot.pickRegion()` runs the same freeze, the same window snapping
  and the same Escape, and `commit()` emits `regionPicked` instead of writing a
  file. `slurp` would have been a second overlay with different keys and no
  snapping. `regionCancelled` exists for the same reason both edges of
  `SystemStats`' subscription are logged: a consumer waiting on a rectangle has
  to be told when one is not coming, or it stays armed until an unrelated pick
  answers it.

  The recorder is the sharpest case in the shell for the CLI-wrapper rule below.
  Its preferred encoder can be *absent* and it can be *present and unable to
  initialise* — `gpu-screen-recorder` needs a working VA-API driver underneath
  it, and that is a separate package. The first has no exit code to read at all
  (a `Process` whose binary is missing emits no `exited`, only `running` going
  false — #40); the second exits non-zero in about 200ms. `RecorderPolicy.
  shouldFallback` takes both facts and answers once, and the fallback is exactly
  one hop to `wf-recorder`, because a machine that records in software is a
  better outcome than one that does not record.

  Stopping is `SIGINT` and never `SIGTERM`: both tools flush the muxer and write
  the container index on the former and neither does on the latter, so a
  `SIGTERM` leaves an mp4 that exists, is the right size, and will not play.

- `Theming/Theming.qml` (#58) — the palette-mode switch, and the one service in
  the shell that publishes nothing. It computes the wallpaper-coupled accent and
  writes it to `appearance.dynamic`; `Core/Theme.qml` reads that key back and
  layers it under the user's own overrides.

  A settings key and not a property on the singleton, for three reasons that
  each hold on their own. Core cannot import upwards, and `Core/Theme.qml` is
  what every surface reads. Consumers stay mode-blind — a surface reads
  `Theme.accentPrimary` and has no way to discover that a mode produced it,
  which is what keeps a global feature from becoming a per-surface one. And the
  quantizer answers off-thread, so a property would start empty and the first
  frame would paint the shipped teal and then jump; a file that survived the
  last session does not.

  It is therefore also the purest case for the `ServiceInit` rule: *nothing*
  references it, so without a line in the deferred list the mode would be
  selectable in the settings window and simply never run.

[#30]: https://github.com/danielbaldwin47/forest-shell/issues/30

The rest are empty until their ticket lands; the directories exist so nothing
has to move when they do.
