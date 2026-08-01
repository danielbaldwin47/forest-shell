# Control center

Sources: [#9](https://github.com/danielbaldwin47/forest-shell/issues/9), [#4](https://github.com/danielbaldwin47/forest-shell/issues/4), [#10](https://github.com/danielbaldwin47/forest-shell/issues/10), [#12](https://github.com/danielbaldwin47/forest-shell/issues/12), [#21](https://github.com/danielbaldwin47/forest-shell/issues/21), [#22](https://github.com/danielbaldwin47/forest-shell/issues/22), [#27](https://github.com/danielbaldwin47/forest-shell/issues/27), [#30](https://github.com/danielbaldwin47/forest-shell/issues/30), [.wayfinder/research/quickshell-capabilities.md](../../.wayfinder/research/quickshell-capabilities.md), [.wayfinder/prototypes/motion-choreo/findings.md](../../.wayfinder/prototypes/motion-choreo/findings.md)

## Shape

An anchored panel in the **shared drawer window**, lives in
`Surfaces/Drawers/ControlCenter/`. Summoned from the bar's control center button; anchored
top-right under that icon, with a beak pointing at it and the icon lit `accent-primary` teal while
open.

| Property | Value |
|---|---|
| Width | 400px |
| Panel padding | 16px |
| Section gap | 20px |
| Surface | `surface` at 90% fill, radius 16px, top-lit |
| Anchor | top-right, under the control center button |

Drawer rules from the multi-monitor policy apply unchanged: globally exclusive across screens,
opens on the focused screen, one `HyprlandFocusGrab` in existence, re-summoning the same drawer on
the same screen toggles it closed, an open drawer on a removed screen resets to closed. The IPC
target takes no screen argument.

Vertical order: sliders → toggle grid → recorder row → bottom strip.

## Motion

| Event | Spec |
|---|---|
| Open | 320 ms — scrim opacity → 0.10 and content together, no stagger; content is opacity plus a 1% scale settle (99 → 100) about the anchor icon |
| Close | 240 ms, opacity only |
| Arriving from another drawer | cross-drawer variant A: outgoing 140 ms, incoming 240 ms starting at +100 ms, scrim untouched |
| Drill-in / back | 140 ms content crossfade; the panel height animates 140 ms with fog ease |
| Tile and slider state change | 140 ms |

**Constraint:** nothing in the shell translates except the notification toast stack-shift. The
drill-in detail views replace the panel's content in place — they do not slide. Fog ease
`cubic-bezier(0.22, 1, 0.36, 1)` everywhere; `reducedEffects` collapses all of the above to 140 ms
opacity crossfades.

## Sliders

Three full-width rows at the top of the panel. Each row is a Lucide icon button (28px hit target),
a 4px track with an `accent-primary` fill, and a right-aligned percentage in `text-secondary`.
Clicking the icon toggles mute (volume, mic) or steps to the dim/restore value (brightness);
scrolling over a row adjusts by ±5%; Left/Right adjust by ±5% when the row has keyboard focus.

Adjusting a slider here does **not** raise the OSD — the value is already on screen. See
[utilities.md](utilities.md) for the OSD rules.

| Slider | Backend | Detail |
|---|---|---|
| Volume out | `Pipewire.defaultAudioSink` → `PwNodeAudio.volume` / `.muted` | Range 0–100%; no over-amplification in v1. Icon opens the audio detail view. |
| Mic | `Pipewire.defaultAudioSource` → `PwNodeAudio.volume` / `.muted` | Same range. Row is hidden when no source exists. |
| Brightness | read `/sys/class/backlight/<device>/brightness` + `max_brightness`; write `brightnessctl` | Floor 1%, never 0. |

**Constraint:** `PwObjectTracker { objects: [...] }` must bind every PipeWire node the panel reads
or its `volume` stays 0. This is the single most common Quickshell/PipeWire bug.

Brightness detail: `Services/Hardware/Brightness.qml` reads current and max via `FileView` with
`watchChanges: true` (so external `brightnessctl`/hardware-key changes are picked up without
polling) and writes with

```
brightnessctl -d <device> -c backlight set <percent>%
```

Writes are debounced 50 ms while dragging. `<device>` is the first entry in `/sys/class/backlight`,
overridable with `controlCenter.brightnessDevice` (default `""` = autodetect). Quickshell exposes
no brightness type at all — this subprocess is isolated inside the one singleton so a future native
module can replace it. External DDC/CI monitor brightness (`ddcutil`) is out of v1.

## Toggle grid

A fixed 3×3 grid, 12px gaps, tiles 116×72px, radius 10px. Order is fixed — the grid is not
registry-configurable in v1.

| | Column 1 | Column 2 | Column 3 |
|---|---|---|---|
| **Row 1** | Wi-Fi | Bluetooth | Do Not Disturb |
| **Row 2** | Night Light | Keep Awake | Dark/Light mode |
| **Row 3** | Power Profile | VPN | Wallpaper picker |

Tile states: **off** = `surface-raised` fill, `text-secondary` icon and label; **on** =
`accent-primary` fill, `bg-base` icon and label; **unavailable** (no hardware, service down) =
`text-muted` at 40% and inert. Amber is never used on a tile — it is reserved for attention.

Tiles with a detail view carry a chevron in the top-right corner: tapping the chevron opens the
detail, tapping anywhere else toggles. Each tile shows a secondary line with live substate (SSID,
device name, profile name).

| Tile | Icon | Backend | Toggle | Detail view |
|---|---|---|---|---|
| Wi-Fi | `wifi` | `Quickshell.Networking` → `Networking.wifiEnabled` | enable/disable radio | Network list |
| Bluetooth | `bluetooth` | `Quickshell.Bluetooth` → `BluetoothAdapter.enabled` | enable/disable adapter | Device list |
| Do Not Disturb | `bell-off` | notification service (state, not config) | on/off | — |
| Night Light | `sun-moon` | `hyprsunset` via `Process` | on/off | — |
| Keep Awake | `coffee` | `IdleInhibitor` | on/off | — |
| Dark/Light mode | `moon` / `sun` | `appearance.colorScheme` | `"dark"` ⇄ `"light"` | — |
| Power Profile | `gauge` | `Quickshell.Services.UPower` → `PowerProfiles.profile` | cycles available profiles | — |
| VPN | `shield` | `nmcli` | up/down the last-used profile | Connection list |
| Wallpaper picker | `image` | wallpaper service | opens picker | Wallpaper grid |

Notes that change implementation:

- **Wi-Fi signal strength.** Lucide ships a single `wifi` glyph with no strength variants. Strength
  is encoded by icon opacity — strong 1.0, fair 0.72, weak 0.48 — driven by
  `WifiNetwork.signalStrength`, with `wifi-off` at `text-muted` when disconnected. This matches the
  bar's status cluster exactly; do not substitute another icon family.
- **Night Light.** Enabling spawns a long-lived `hyprsunset --temperature <k>` process; disabling
  terminates it. Temperature and the optional schedule are `weatherTime` keys (see Settings).
- **Dark/Light mode.** The tile is live in v1 and writes `appearance.colorScheme`. Light mode
  resolves against the design system's **seed** light palette, with any token the seed does not
  define falling back to its dark value inside `Core/Theme.qml` — consumers stay mode-blind and
  nothing breaks. Visual completeness of light mode is post-v1 polish and is not an acceptance
  gate for any phase.
- **Keep Awake** is the caffeine toggle. It holds the `IdleInhibitor` in
  `Services/System/Idle.qml`, which suppresses the **entire** idle ladder — dim, lock, DPMS off,
  and suspend — because every stage sets `respectInhibitors: true`. Its on/off state lives in the
  runtime state file, not `settings.json`: it is situational rather than setup, and it survives a
  shell restart without syncing between machines. See the lock and session spec.
- **Power Profile** cycles `power-saver → balanced → performance` over
  `PowerProfiles.profile`, skipping `performance` when `hasPerformanceProfile` is `false`. The
  secondary line shows `degradationReason` when the firmware is throttling.
- **VPN** is the one networking control Quickshell's native module does not cover. Profiles come
  from `nmcli --terse --fields NAME,TYPE,DEVICE,STATE connection show`, filtered to `vpn` and
  `wireguard`; up/down are `nmcli connection up id <name>` / `nmcli connection down id <name>`. The
  list refreshes when the detail view opens and after each action — no polling timer.
- **Wallpaper picker** opens a thumbnail grid of `wallpaper.directory` (default
  `~/Pictures/Wallpapers`); selecting writes `wallpaper.path`. Palette derivation from the chosen
  image is the theming spec's territory.

## Drill-in detail views

A detail view replaces the panel's content in place, with a header of back chevron + title. `Esc`
or the chevron returns to the root view; closing the drawer resets to root — the last view is not
remembered.

| View | Contents | Backend |
|---|---|---|
| **Wi-Fi** | Connected network pinned first, then in-range networks sorted by signal; lock glyph for secured; join, password prompt for PSK, forget; connection failure reason shown inline | `WifiDevice.networks`, `Network.connect()` / `connectWithPsk()` / `disconnect()` / `forget()`, `connectionFailed` + `ConnectionFailReason` |
| **Bluetooth** | Adapter toggle, discovery toggle, paired devices then discovered; per-device battery when reported; connect / disconnect / pair / forget | `Bluetooth.devices`, `BluetoothDevice.connect()` / `pair()` / `forget()`, `battery`, `batteryAvailable` |
| **Audio** | Output device list, input device list, then a per-app mixer: one row per stream node with its own volume and mute | `Pipewire.preferredDefaultAudioSink` / `preferredDefaultAudioSource` for switching; `PwNode.isStream` nodes plus `PwNodeAudio` for the mixer |
| **VPN** | Profile list with connected state, connect/disconnect | `nmcli` as above |
| **Wallpaper** | Thumbnail grid, current wallpaper ringed teal | wallpaper service |

`WifiDevice.scannerEnabled` is `true` **only while the Wi-Fi detail view is open** — scanning is a
wakeup source and the idle budget is < 5 wakeups/s. Pairing that requires PIN or passkey
confirmation falls through to the system agent: Quickshell exposes pairing *state* but no
`BluetoothAgent` type.

## Recorder row

A full-width row between the grid and the bottom strip. Idle it reads "Record screen" with a
region/screen chooser; while recording it shows elapsed time and a stop button. Full spec,
including the gpu-screen-recorder command line and the wf-recorder fallback, is in
[utilities.md](utilities.md).

## Bottom strip

Three stacked elements, separated from the grid by a `border-subtle` hairline.

1. **Media card** — rendered only while `Mpris.players` is non-empty and the active player has
   metadata; hidden entirely otherwise (no empty placeholder). Cover art 48px, title and artist
   elided to one line each, previous / play-pause / next. The full media card with seek and player
   switching lives on the dashboard.
2. **Battery / power line** — `UPower.displayDevice` percentage, charging state, and
   `timeToEmpty` / `timeToFull` rendered as `2h 14m`. Shows the active `PowerProfiles.profile`
   on the right. Hidden on machines with no battery.
   **Constraint:** the T480 has two batteries. Reading `BAT0` alone reported 5% while the machine
   ran off `BAT1` at 64%. Aggregate energy across all `UPower.devices` where `isLaptopBattery` and
   `isPresent` are true — never take the first `BAT*`.
3. **Actions row** — a settings gear that opens the settings window (`Surfaces/Settings/`, a normal
   `FloatingWindow`, Hyprland animates it) and a power button that performs a cross-drawer
   transition to the session menu.

## Settings

Section `controlCenter`:

| Key | Type | Default |
|---|---|---|
| `brightnessDevice` | string | `""` (autodetect) |
| `brightnessStep` | int % | `5` |
| `volumeStep` | int % | `5` |
| `showMicSlider` | bool | `true` |
| `showMediaCard` | bool | `true` |
| `perAppMixer` | bool | `true` |

Keys owned by other sections that this panel reads or writes: `appearance.colorScheme`
(default `"dark"`), `wallpaper.path`, `wallpaper.directory` (default `"~/Pictures/Wallpapers"`),
`weatherTime.nightLightTemperature` (default `4000`), `weatherTime.nightLightSchedule`
(default `false`), `weatherTime.nightLightStart` (default `"20:00"`),
`weatherTime.nightLightEnd` (default `"07:00"`). Do Not Disturb is state, not config.

## IPC and shortcuts

```qml
IpcHandler {
  target: "controlcenter"
  function toggle(): void
  function open(): void
  function close(): void
  function openDetail(name: string): void   // wifi | bluetooth | audio | vpn | wallpaper
}
```

`GlobalShortcut` name: `forest-shell:controlCenter`. Hyprland binds use the
`qs ipc call TEST_ALIVE || <fallback>` idiom.

## Performance

- Content is unloaded while the drawer is closed; the window contributes zero wakeups.
- Every backend except brightness and VPN is native and event-driven — no timers anywhere in this
  panel.
- Brightness is read by `FileView` file-watch, not by polling.
- Wi-Fi scanning and `nmcli` VPN queries run only while their detail view is open.
- The fog scrim animates opacity only. No QML-side full-screen blur, ever — frosted glass is the
  optional Hyprland `layerrule = blur` and the panel must look correct with blur off.
