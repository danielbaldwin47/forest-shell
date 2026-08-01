# Services

Cross-surface state and side effects, as `pragma Singleton` singletons grouped by
domain ([architecture #12](https://github.com/danielbaldwin47/forest-shell/issues/12) §3):

| Directory | Owns |
| --- | --- |
| `Compositor/` | The Hyprland facade — the only place `hyprctl` / dispatch lives |
| `Media/` | MPRIS players, volume, sinks |
| `Hardware/` | Battery, brightness, sensors, input devices |
| `Networking/` | Wi-Fi, Bluetooth, VPN |
| `System/` | Session, logind, updates, disk — `SessionLock` (#47) |
| `Theming/` | The three palette modes behind `Core/Theme.qml` |
| `Claude/` | The Claude CLI subprocess and its session state |

Two rules that hold across all of them:

- A service that runs unconditionally must be named in `Core/ServiceInit.qml` —
  a singleton nothing references is never constructed.
- A service that only one surface uses is not a service: it lives with its
  surface (`Surfaces/Drawers/Launcher/services/`), not here.

`System/SessionLock.qml` is the first one to land, and it tests both rules.

It is not named in `Core/ServiceInit.qml`, because it listens to nothing and
does nothing until someone asks it to lock — the lock surface constructs it, and
until the idle ladder (#48) gives it a subscription of its own there is nothing
for a force-touch to start.

It is a service rather than a file under `Surfaces/Lock/` even though the lock
surface is its only consumer *today*, because "who uses it" is the wrong reading
of the second rule — the question is who is allowed to **decide**. Locking is
reached from the session menu (#44), the idle ladder and the pre-suspend hook
(#48) as well as the lock's own IPC target, and the spec ([#30]) requires all of
them to converge on one `lock()`. A door that lives inside the room it opens
would make every one of those callers reach through `Surfaces/`.

[#30]: https://github.com/danielbaldwin47/forest-shell/issues/30

The other directories are still empty; they exist so nothing has to move when
their ticket lands.
