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
| `System/` | Session, logind, updates, disk, the tray — `SessionLock` (#47) |
| `Theming/` | The three palette modes behind `Core/Theme.qml` |
| `Claude/` | The Claude CLI subprocess and its session state |

Two rules that hold across all of them:

- A service that runs unconditionally must be named in `Core/ServiceInit.qml` —
  a singleton nothing references is never constructed.
- A service that only one surface uses is not a service: it lives with its
  surface (`Surfaces/Drawers/Launcher/services/`), not here.

A third rule, added by #36, because two of these services collide by name with
the upstream module they wrap:

- **A facade that shadows an upstream singleton imports it under an alias.**
  `Quickshell.Networking` and `Quickshell.Bluetooth` each export a singleton
  named after the module, and so do we. Inside `Networking.qml` and
  `Bluetooth.qml`, `Nm.` and `Bz.` mean upstream's; everywhere else in the
  shell the unqualified name means the facade. Two types with one name is the
  failure mode Core/Config.qml documents for a singleton called `State` — no
  error anywhere, every property reading back `undefined`. Where a *bar module*
  would collide instead, the service takes the different name: the backlight
  facade is `Backlight`, because `Surfaces/Bar/Modules/Brightness.qml` is
  already `Brightness`.

Ten of them exist so far:

- `Notifications/` (#42) — `NotificationServer`, the live popup list,
  do-not-disturb and the persisted history. The rules about an arriving
  notification are split into `NotificationPolicy.qml`, which imports nothing
  but QtQuick so `tests/` can reach them; the singleton next door is the wiring.
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
  someone asks it to lock — the lock surface constructs it, and until the idle
  ladder (#48) gives it a subscription of its own there is nothing for a
  force-touch to start. It is a service rather than a file under
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

[#30]: https://github.com/danielbaldwin47/forest-shell/issues/30

The rest are empty until their ticket lands; the directories exist so nothing
has to move when they do.
