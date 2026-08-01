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
| `System/` | Session, logind, updates, disk |
| `Theming/` | The three palette modes behind `Core/Theme.qml` |
| `Claude/` | The Claude CLI subprocess and its session state |

Two rules that hold across all of them:

- A service that runs unconditionally must be named in `Core/ServiceInit.qml` —
  a singleton nothing references is never constructed.
- A service that only one surface uses is not a service: it lives with its
  surface (`Surfaces/Drawers/Launcher/services/`), not here.

Two of them exist so far, both landed by the notification ticket (#42):

- `Notifications/` — `NotificationServer`, the live popup list, do-not-disturb
  and the persisted history. The rules about an arriving notification are split
  into `NotificationPolicy.qml`, which imports nothing but QtQuick so `tests/`
  can reach them; the singleton next door is the wiring.
- `Compositor/` — deliberately thin, and only as wide as its callers: the
  focused screen and whether that screen is showing a fullscreen window. The
  workspace model and `dispatch()` land with the ridgeline (#35) and the shared
  drawer window (#38).
