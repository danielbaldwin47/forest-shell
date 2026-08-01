# Services

Cross-surface state and side effects, as `pragma Singleton` singletons grouped by
domain ([architecture #12](https://github.com/danielbaldwin47/forest-shell/issues/12) §3):

| Directory | Owns |
| --- | --- |
| `Compositor/` | The Hyprland facade — the only place `hyprctl` / dispatch lives |
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

`Compositor/` is the first of these to land
([#35](https://github.com/danielbaldwin47/forest-shell/issues/35)). It holds the
facade singleton and the pure workspace-row rule beside it — the same split as
`Core/Config.qml` against `Core/SettingsSchema.qml`, so the part with no
Quickshell imports is reachable from `tests/`:

| File | What |
| --- | --- |
| `Compositor.qml` | The facade: the workspace row per screen, `focusWorkspace`, `blurLayer` |
| `WorkspaceSlots.qml` | Fixed slots unioned with Hyprland's live workspaces, as data |

The rest are empty until their ticket lands; the directories exist so nothing
has to move when they do.
