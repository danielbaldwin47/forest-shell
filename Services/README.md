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

`Compositor/Compositor.qml` is the first of them (#35). It reports workspaces as
plain data, focuses them, and owns the one `hyprctl` call the shell makes — the
layer rule that asks Hyprland to blur behind the bar. Everything above it speaks
in workspace ids and intentions, which is what keeps Hyprland's two awkward
facts (empty workspaces do not exist; window counts are a stale snapshot until
you ask again) in one file.

The rest are empty until their ticket lands; the directories exist so nothing
has to move when they do.
