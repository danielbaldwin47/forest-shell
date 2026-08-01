# Quickshell Capabilities & Gaps (mid-2026)

Research for **forest-shell** — a from-scratch Quickshell desktop shell for Hyprland on Arch/CachyOS,
built native-first (implement in Quickshell where reasonable, external tools only where necessary).

**Question:** What does Quickshell provide natively, and where are the gaps that force external tools
or direct DBus work?

---

## 0. Version & provenance (read this first)

| Fact | Value |
| --- | --- |
| Upstream current release | **v0.3.0**, released ~4 May 2026. Docs at `https://quickshell.org/docs/v0.3.0/types/` |
| Installed locally | **`noctalia-qs` 0.0.12-1.1** (CachyOS repo), built 21 May 2026, revision `76c13298` |
| What that package is | *"Custom fork of Quickshell powering Noctalia Shell"* — it `Provides: quickshell quickshell-git` and `Conflicts With: quickshell quickshell-git` |
| Modules on disk | `/usr/lib/qt6/qml/Quickshell/` |
| Binaries | `/usr/bin/quickshell`, `/usr/bin/qs` |

**Caveat worth acting on:** the machine currently has a *fork*, not upstream Quickshell, because
`noctalia-qs` was pulled in as a dependency of `dms-shell` / `noctalia-shell-git`. Its module surface
matches upstream v0.3.0 almost exactly, with these local extras not present in the upstream v0.3.0 docs
index: `Quickshell.Niri`, `Quickshell.DWL`, `Quickshell.X11`, `Quickshell.Wayland.BackgroundEffect`
(`https://quickshell.org/docs/v0.3.0/types/Quickshell.Niri/` returns 404). None of those matter for a
Hyprland-only shell, but **forest-shell should install upstream `quickshell` and let it replace
`noctalia-qs`** so you are building against the documented API surface rather than a fork's.

The docs are versioned per release (`/docs/v0.3.0/…`); there is no `/docs/` or `/docs/master/` index —
both 404. Always cite a pinned version URL.

**Modules shipped** (upstream v0.3.0 index):
`Quickshell`, `Quickshell.Bluetooth`, `Quickshell.DBusMenu`, `Quickshell.Hyprland`, `Quickshell.I3`,
`Quickshell.Io`, `Quickshell.Networking`, `Quickshell.Services.Greetd`, `Quickshell.Services.Mpris`,
`Quickshell.Services.Notifications`, `Quickshell.Services.Pam`, `Quickshell.Services.Pipewire`,
`Quickshell.Services.Polkit`, `Quickshell.Services.SystemTray`, `Quickshell.Services.UPower`,
`Quickshell.Wayland`, `Quickshell.Widgets`, `Quickshell.WindowManager`.

---

## 1. Verdict table

| Area | Verdict | Type / filler |
| --- | --- | --- |
| Layer-shell windows | **NATIVE** | `PanelWindow`, `WlrLayershell` |
| Popups | **NATIVE** | `PopupWindow`, `PopupAnchor`, `HyprlandFocusGrab` |
| Multi-monitor | **NATIVE** | `Quickshell.screens`, `ShellScreen`, `Variants` |
| Session lock | **NATIVE** | `WlSessionLock`, `WlSessionLockSurface` |
| PAM auth | **NATIVE** | `PamContext` |
| Notification server | **NATIVE** | `NotificationServer`, `Notification` |
| System tray | **NATIVE** | `SystemTray`, `SystemTrayItem`, `DBusMenu*` |
| Audio (PipeWire) | **NATIVE** | `Pipewire`, `PwNode`, `PwNodeAudio`, `PwObjectTracker` |
| Audio visualiser | **NATIVE** | `PwNodePeakMonitor`, `PwAudioSpectrum` |
| MPRIS media control | **NATIVE** | `Mpris`, `MprisPlayer` |
| Battery / power | **NATIVE** | `UPower`, `UPowerDevice`, `PowerProfiles` |
| **Brightness** | **GAP** | no type at all → `brightnessctl` / `ddcutil` via `Process` |
| Network (WiFi/wired) | **NATIVE** | `Networking`, `WifiDevice`, `Network` (NetworkManager DBus backend) |
| Bluetooth | **NATIVE** | `Bluetooth`, `BluetoothAdapter`, `BluetoothDevice` (BlueZ backend) |
| Hyprland workspaces/events/IPC | **NATIVE** | `Hyprland` singleton, `HyprlandWorkspace`, `HyprlandEvent`, `dispatch()` |
| Hyprland global shortcuts | **NATIVE** | `GlobalShortcut` |
| Screencopy / screenshot | **PARTIAL** | `ScreencopyView` + `captureFrame()` displays & grabs; **no file encoding** → `grabToImage()` or `grim` |
| **Screen recording** | **GAP** | nothing → `wf-recorder` / `gpu-screen-recorder` via `Process` |
| Clipboard read | **PARTIAL** | `Quickshell.clipboardText` — only while a QS window is focused |
| **Clipboard history / write** | **GAP** | → `wl-clipboard` + `cliphist` via `Process` |
| Idle inhibit | **NATIVE** | `IdleInhibitor` |
| Idle detection | **NATIVE** | `IdleMonitor` (**hypridle not required**) |
| Greetd greeter | **NATIVE** | `Greetd` |
| Polkit agent | **NATIVE** | `PolkitAgent`, `AuthFlow` |
| Shell IPC (keybinds → panels) | **NATIVE** | `IpcHandler` + `qs ipc call` |
| Config reload | **NATIVE** | hot reload by default, `PersistentProperties`, `Reloadable` |
| User settings format | **NATIVE** | `FileView` + `JsonAdapter` |
| App launcher index | **NATIVE** | `DesktopEntries`, `DesktopEntry`, `DesktopAction` |
| Window list / taskbar | **NATIVE** | `ToplevelManager`, `Toplevel` |
| **Generic DBus calls** | **GAP** | no QML DBus binding → `busctl` / `gdbus` via `Process` |

Bottom line: **Quickshell v0.3.0 is far more batteries-included than its reputation suggests.**
Network and Bluetooth in particular became first-class native modules, which historically were the
biggest reason shells shelled out to `nmcli`/`bluetoothctl`. The genuine remaining gaps are short:
**brightness, screen recording, clipboard history, and arbitrary DBus.**

---

## 2. Per-area detail

### 2.1 Layer-shell windows, popups, multi-monitor — NATIVE

- `PanelWindow` — *"decorationless window attached to screen edges by anchors"*; the portable
  bar/dock primitive. Backed by `Anchors`, `ExclusionMode`, `margins`.
- `WlrLayershell` — the wlroots layer-shell surface directly, when you need the raw knobs:
  `layer`, `namespace`, `keyboardFocus`, `exclusiveZone`, `exclusionMode`, `margins`, `aboveWindows`,
  `focusable`. Use this when `PanelWindow` is too abstract (e.g. overlay layer, `WlrKeyboardFocus.Exclusive`).
- `PopupWindow` + `PopupAnchor` (+ `PopupAdjustment`, `Edges`) — anchored transient windows with
  flip/slide adjustment. `FloatingWindow` for ordinary toplevels (settings dialogs).
- Multi-monitor: `Quickshell.screens` is a live list of `ShellScreen` that updates on hotplug.
  The canonical pattern is `Variants { model: Quickshell.screens }` — *"creates instances of a
  component based on a given model"* — instantiating one panel per screen and destroying them on
  unplug automatically. `Quickshell.Hyprland.monitorFor(screen)` maps a `ShellScreen` to a
  `HyprlandMonitor`.
- `Quickshell.Wayland.BackgroundEffect { blurRegion }` gives compositor-side background blur
  (present in the local build; verify availability in upstream before depending on it).

Docs: `https://quickshell.org/docs/v0.3.0/types/Quickshell/`,
`https://quickshell.org/docs/v0.3.0/types/Quickshell.Wayland/`

### 2.2 Session lock + PAM — NATIVE

- `WlSessionLock { locked, secure, surface }` — real `ext-session-lock-v1`, not a fake overlay. The
  compositor keeps the lock surface up even if the shell process dies (`secure`).
- `WlSessionLockSurface { contentItem, screen, color, width, height }` — instantiated per monitor
  automatically.
- `PamContext` — full conversation-style PAM auth: properties `active`, `config`, `configDirectory`,
  `user`, `message`, `messageIsError`, `responseRequired`, `responseVisible`; method `respond()`;
  signals `completed(PamResult)`, `error(PamError)`.

A complete lock screen — fingerprint prompts included, since `PamContext` follows the PAM
conversation — is a **pure-QML build**. No `swaylock`/`hyprlock` needed.

Docs: `https://quickshell.org/docs/v0.3.0/types/Quickshell.Wayland/WlSessionLock/`,
`https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Pam/`

### 2.3 Notification server — NATIVE

`NotificationServer` is a full `org.freedesktop.Notifications` daemon implementation. You must **not**
run dunst/mako alongside it — they contend for the same bus name.

Capability flags you advertise to clients: `bodySupported`, `bodyMarkupSupported`,
`bodyHyperlinksSupported`, `bodyImagesSupported`, `actionsSupported`, `actionIconsSupported`,
`imageSupported`, `inlineReplySupported`, `persistenceSupported`, plus `extraHints`.

`Notification` exposes `appName`, `appIcon`, `summary`, `body`, `urgency`, `actions`, `image`,
`expireTimeout`, `resident`, `transient`, `desktopEntry`, `hints`, `hasInlineReply`,
`inlineReplyPlaceholder`, and `sendInlineReply()` — so inline reply (Telegram-style) works natively.
`expireTimeout` is in **milliseconds**, with `-1` for "the server decides" — measured on a live
0.3.0 session (#74), not read off the type, which is a bare `double`.
`keepOnReload` preserves the notification list across hot reloads. `Retainable`/`RetainableLock` let
you keep a notification alive for a close animation after the client dismisses it.

Docs: `https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Notifications/`

### 2.4 System tray — NATIVE

`SystemTray.items` → `SystemTrayItem { id, title, status, category, icon, tooltipTitle,
tooltipDescription, hasMenu, menu, onlyMenu }` with methods `scroll()` and `display()`. This is a
StatusNotifierItem host — it also registers the `org.kde.StatusNotifierWatcher` side, so no
`snixembed`/`status-notifier-watcher` helper is needed for modern apps.

Context menus come via `Quickshell.DBusMenu` (`DBusMenuHandle`, `DBusMenuItem`) surfaced through the
generic `QsMenuOpener` / `QsMenuEntry` / `QsMenuHandle` / `QsMenuAnchor` types, so you render tray
menus with your own QML and theming rather than a native Qt menu.

Note: legacy XEmbed tray icons (very old GTK2/Java apps) are **not** supported — that is an
SNI-only world. In practice on a 2026 Hyprland desktop this is a non-issue.

Docs: `https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.SystemTray/`

### 2.5 Audio (PipeWire) + MPRIS — NATIVE

`Pipewire` singleton: `nodes`, `links`, `linkGroups`, `defaultAudioSink`, `defaultAudioSource`,
`preferredDefaultAudioSink`, `preferredDefaultAudioSource`, `ready`. Setting the `preferred*`
properties is how you switch output devices — no `wpctl` shelling.

`PwNode { id, name, description, nickname, isSink, isStream, type, properties, audio, ready }`, with
`PwNodeAudio { muted, volume, channels, volumes }` for per-channel and aggregate volume/mute control.

**Important gotcha:** `PwObjectTracker { objects: [...] }` must bind the nodes you care about.
PipeWire object properties are not populated until tracked — a very common source of
"why is `volume` always 0" confusion.

Extras that remove common helpers:
- `PwNodePeakMonitor { node, enabled, peaks, peak, channels }` — live peak levels.
- `PwAudioSpectrum { node, bandCount, barCount, frameRate, lowerCutoff, upperCutoff, noiseReduction, smoothing, values, idle }` — a **native FFT visualiser**. This eliminates the usual `cava` subprocess entirely.
- `PwNodeLinkTracker`, `PwLinkGroup`, `PwLink` — per-app routing / which stream is on which sink.

MPRIS: `Mpris.players` → `MprisPlayer` with playback state, metadata, position, loop/shuffle, and
transport controls; `MprisPlaybackState`, `MprisLoopState`. Standard media widget is pure QML.

Docs: `https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Pipewire/`,
`https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Mpris/`

### 2.6 UPower / battery — NATIVE; brightness — GAP

Native:
- `UPower { displayDevice, devices, onBattery }`.
- `UPowerDevice { type, powerSupply, energy, energyCapacity, changeRate, timeToEmpty, timeToFull, percentage, isPresent, state, healthPercentage, healthSupported, iconName, isLaptopBattery, nativePath, model, ready }` — battery health and time-to-empty included.
- `PowerProfiles { profile, hasPerformanceProfile, degradationReason, holds }` +
  `powerProfileHold` — power-profiles-daemon integration, so a perf/balanced/saver toggle is native.

**Gap — brightness.** There is no brightness or backlight type anywhere in the module set (verified by
grepping every `.qmltypes` for `brightness`/`backlight`: zero hits). Conventional fillers, best first:

1. **`brightnessctl`** via `Process` — simplest, handles both backlight and LED classes, no root
   with the standard udev rules shipped by the Arch package.
2. **logind DBus** — `org.freedesktop.login1.Session.SetBrightness(subsystem, name, brightness)`,
   which is the "correct" unprivileged path, but see §2.13: you have no QML DBus binding, so this
   still means `busctl call` through `Process`.
3. **`ddcutil`** via `Process` for external DDC/CI monitors — unavoidable regardless; nothing in
   Quickshell speaks DDC.

Reading current/max brightness can be done natively with `FileView` on
`/sys/class/backlight/*/brightness` (with `watchChanges: true` for external changes), but **writing**
needs one of the above. A reasonable design: read via `FileView`, write via `brightnessctl`.

Docs: `https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.UPower/`

### 2.7 Network — NATIVE (this changed recently)

`Quickshell.Networking` is a real NetworkManager client. The docs state: *"For now, the only backend
available is the NetworkManager DBus interface. Both DBus and NetworkManager must be running to use
it."* (`NetworkBackendType` exists, implying iwd/other backends later.)

- `Networking { devices, backend, wifiEnabled, wifiHardwareEnabled, canCheckConnectivity, connectivityCheckEnabled, connectivity }` — airplane-mode toggle and captive-portal detection included.
- `NetworkDevice { type, name, address, connected, state, nmManaged, autoconnect }`.
- `WifiDevice { networks, scannerEnabled, mode }` — `scannerEnabled` drives scanning.
- `WifiNetwork { signalStrength, security }`, `WifiSecurityType`.
- `Network { name, nmSettings, connected, known, state, stateChanging }` with methods
  **`connect()`, `connectWithPsk()`, `connectWithSettings()`, `disconnect()`, `forget()`** and a
  `connectionFailed` signal plus `ConnectionFailReason` (so you can tell "bad password" from
  "out of range").

A full WiFi picker — scan, list, join with password, forget, wired status — is a **pure-QML build**.
`nmcli` scripting is no longer the convention. Only exotic cases (VPN profile management, 802.1X
enterprise provisioning, editing arbitrary connection profiles) would push you back to `nmcli`.

Docs: `https://quickshell.org/docs/v0.3.0/types/Quickshell.Networking/`

### 2.8 Bluetooth — NATIVE

*"Bluetooth management APIs provided by the BlueZ DBus interface. Both DBus and BlueZ must be running."*

- `Bluetooth { defaultAdapter, adapters, devices }`.
- `BluetoothAdapter { name, enabled, state, discoverable, discoverableTimeout, discovering, pairable, pairableTimeout, devices, adapterId, dbusPath }`.
- `BluetoothDevice { address, name, deviceName, icon, state, connected, paired, bonded, pairing, trusted, blocked, wakeAllowed, batteryAvailable, battery, adapter, dbusPath }` with methods
  **`connect()`, `disconnect()`, `pair()`, `cancelPair()`, `forget()`** and writable `trusted` / `blocked`.

Note `batteryAvailable` / `battery` — headphone battery percentage is native. A full BT manager panel
is a **pure-QML build**; `bluetoothctl` is not needed. The one thing to check when you get there is
pairing-agent behaviour (PIN/passkey confirmation prompts) — the type list exposes pairing *state*
but a `BluetoothAgent` type is not present, so confirmation-required pairings may still fall back to
the system agent.

Docs: `https://quickshell.org/docs/v0.3.0/types/Quickshell.Bluetooth/`

### 2.9 Hyprland integration — NATIVE

`Hyprland` singleton:
- Properties: `monitors`, `workspaces` (*"sorted by id"*), `toplevels`, `activeToplevel`,
  `focusedMonitor`, `focusedWorkspace`, event/request socket paths, and `usingLua` (Hyprland's Lua
  config mode changes dispatcher syntax — branch on this).
- Functions: **`dispatch()`** (*"Execute a hyprland dispatcher"*), `monitorFor(screen)`,
  `refreshMonitors()`, `refreshWorkspaces()`, `refreshToplevels()` for actions that don't emit events.
- Signal: **`rawEvent`** — *"emitted for every event that comes in through the hyprland event socket"*,
  plus typed `HyprlandEvent`. This is the live IPC feed; you do not poll `hyprctl`.

Also: `HyprlandWorkspace`, `HyprlandMonitor`, `HyprlandToplevel`,
`HyprlandWindow` (Hyprland-specific `QsWindow` properties), and:
- **`GlobalShortcut`** — registers a compositor global shortcut from QML (via
  `hyprland-global-shortcuts-v1`). Bind in QML, trigger from a Hyprland keybind, no socket plumbing.
- **`HyprlandFocusGrab`** — *"input focus grabber"*; the correct way to make a launcher/menu
  dismiss on outside click while holding keyboard focus.

Compositor-agnostic alternatives if you ever want portability: `ToplevelManager`/`Toplevel`
(wlr-foreign-toplevel) for a window list, and `Quickshell.WindowManager`
(`WindowManager`, `Windowset`, `WindowsetProjection`, `ScreenProjection`) as a generic
workspace abstraction over Hyprland/Niri/I3/DWL.

Docs: `https://quickshell.org/docs/v0.3.0/types/Quickshell.Hyprland/`,
`https://quickshell.org/docs/v0.3.0/types/Quickshell.Hyprland/Hyprland/`

### 2.10 Screenshot / screencopy — PARTIAL; recording — GAP

`ScreencopyView { captureSource, paintCursor, live, hasContent, sourceSize, constraintSize }` +
method **`captureFrame()`** (*"Capture a single frame. Has no effect if `live` is true."*).

`captureSource` accepts:
- `null` — clears the image,
- a **`ShellScreen`** — a whole monitor,
- a **`Toplevel`** — a single window, requiring `hyprland-toplevel-export-v1` (fine on Hyprland).

So live monitor/window thumbnails — window switchers, workspace previews, a screen-share picker — are
**pure QML**. That's a genuinely strong feature.

**What's missing:** no encode-to-file. `ScreencopyView` is a QtQuick `Item`, so the standard
`grabToImage(callback)` → `result.saveToFile(path)` gets you a PNG without external tools, which is
enough for a basic screenshot action. But for a real screenshot tool you still want:
- region selection UI — buildable in QML over a fullscreen `ScreencopyView`,
- clipboard copy of the image — **not possible natively** (see §2.11) → `wl-copy`,
- JPEG/quality/annotation options → `grim` + `slurp` remains the low-friction path.

**Screen recording is a hard GAP** — nothing in Quickshell encodes video. Use `wf-recorder`,
`gpu-screen-recorder`, or `wl-screenrec` driven by `Process`, with the QML side owning only the
UI/indicator and the start/stop lifecycle.

Docs: `https://quickshell.org/docs/v0.3.0/types/Quickshell.Wayland/ScreencopyView/`

### 2.11 Clipboard — PARTIAL / GAP

`Quickshell.clipboardText` exists, but the docs carry a decisive caveat:
*"Under wayland the clipboard will be empty unless a quickshell window is focused."*

That is a Wayland security property (`wl_data_device` requires focus), not a Quickshell defect. It
makes the native property useful only inside a focused QS surface (e.g. paste into your own launcher
input) and **useless for a clipboard-history daemon**, which by definition must observe copies made
in other applications.

There is no clipboard *write* API and no image clipboard support at all.

**Filler (conventional and unavoidable):**
- `wl-clipboard` (`wl-copy` / `wl-paste --watch`) via `Process` — `wl-paste --watch` uses the
  wlr data-control protocol and sees all copies regardless of focus.
- `cliphist` for the history store, driven by `wl-paste --watch cliphist store`, queried with
  `cliphist list` / `cliphist decode` through `Process` + `StdioCollector`.

The QML side owns the picker UI; the daemon and store are external.

### 2.12 Idle management — NATIVE (hypridle not needed)

Both halves are native:
- **`IdleInhibitor { enabled, window }`** — `idle-inhibit-unstable-v1`. A "keep awake" toggle, or
  auto-inhibit while a `MprisPlayer` is playing or a fullscreen `Toplevel` exists, is pure QML.
- **`IdleMonitor { enabled, timeout, respectInhibitors, isIdle }`** — `ext-idle-notify-v1`.
  *"Provides a notification when a wayland session is marked idle."* Note `respectInhibitors`, which
  makes the monitor honour active inhibitors automatically.

So the whole idle chain — dim at N seconds, lock at M, DPMS off at P — can be expressed as a few
`IdleMonitor` instances with different timeouts, each driving QML state, with the lock handled by
`WlSessionLock` (§2.2). **`hypridle` and `swayidle` are both unnecessary.**

The one action still needing a helper is **DPMS off**: use `Hyprland.dispatch("dpms off")`, which is
native-adjacent (Hyprland IPC, no subprocess).

Also present: `ShortcutInhibitor` — *"prevents compositor keyboard shortcuts from being triggered"*,
useful for a lock screen or a VM/remote-desktop surface.

Docs: `https://quickshell.org/docs/v0.3.0/types/Quickshell.Wayland/`

### 2.13 Greetd / greeter — NATIVE

`Greetd { available, state, user }`, methods `createSession(user)`, `respond(response)`, `launch()`,
signals `authMessage`, `authFailure`, `error`; `GreetdState` enum.

The shell runs **as the greeter**, launched by greetd (configure greetd to exec `qs -c greeter`).
Two documented caveats:
- `respond()` may only be called in response to an `authMessage()` with `responseRequired: true`.
- *"greetd expects the greeter to terminate as soon as possible after setting a target session"* —
  so run exit animations **before** `launch()`, not after. The `launched()` signal fires immediately
  before automatic exit (there is a `quit` parameter for manual control).

This means forest-shell can ship its login screen and its lock screen from the same QML component
set, differing only in whether auth goes through `Greetd` or `PamContext`.

Docs: `https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Greetd/Greetd/`

### 2.14 Polkit agent — NATIVE (bonus)

`PolkitAgent { isRegistered, isActive, flow }` and `AuthFlow { message, iconName, actionId, cookie,
identities, selectedIdentity, isResponseRequired, inputPrompt, responseVisible, supplementaryMessage,
supplementaryIsError, isCompleted, isSuccessful, isCancelled, failed }` with `request`, `submit`,
`showError`, `showInfo`, `completed`.

Replaces `polkit-gnome` / `lxqt-policykit` / `hyprpolkitagent` with a themed in-shell dialog.

### 2.15 IPC into the shell — NATIVE

`IpcHandler { target, enabled }` exposes QML functions and signals to the CLI. This is the mechanism
for keybind-triggered panels.

```qml
IpcHandler {
  target: "rect"
  function setColor(color: color): void { rect.color = color; }
  function getColor(): color { return rect.color; }
  signal radiusChanged(newRadius: int)
}
```

```bash
qs ipc call rect setColor orange
qs ipc call rect getColor            # -> #ffffa500
qs ipc show target rect              # list functions/signals
qs ipc prop get target.propertyName
```

Constraints: functions need **explicit type signatures**, max 10 arguments, and argument types are
limited to `string`, `int`, `bool`, `real`, `color`. Signals take zero or one argument. Targets are
unique per instance; `qs ipc -i <id>` / `--pid` select among multiple running instances.

Pattern for forest-shell: one `IpcHandler { target: "launcher" }`, `target: "sidebar"`, etc., each
with a `toggle()`, bound in `hyprland.conf` as `bind = SUPER, Space, exec, qs ipc call launcher toggle`.

Alternative for a Hyprland-only shell: `GlobalShortcut` (§2.9) registers the binding from QML itself,
avoiding the `qs ipc` subprocess spawn per keypress. Prefer `GlobalShortcut` for latency-sensitive
toggles and `IpcHandler` for scripting/automation.

Docs: `https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/IpcHandler/`

### 2.16 Reloading & config conventions — NATIVE

**Config discovery** (from `qs --help`): configs are named directories under each XDG config dir as
`<xdg dir>/quickshell/<config name>/shell.qml`. If `~/.config/quickshell/shell.qml` exists it is
registered as the `default` config and subdirectories are ignored. Selection via `-c <name>`
(`QS_CONFIG_NAME`) or `-p <path>` (`QS_CONFIG_PATH`). `-d/--daemonize` detaches;
`-n/--no-duplicate` (default on) prevents a second instance of the same config.

**Reloading** is hot and automatic on file change. The supporting types:
- `PersistentProperties` — *"holds properties that can persist across a config reload"* (keep panel
  open/closed state across edits).
- `Reloadable` / `Scope` — *"propagates reloads to child items in order"*.
- `Quickshell.reload(hard)` — soft reload reuses windows, hard reload recreates them.
- `NotificationServer.keepOnReload` — don't lose the notification list while editing.

**User settings format.** There is no opinionated settings system; the convention is `FileView` +
`JsonAdapter`:
- `FileView { path, watchChanges, blockLoading, blockWrites, atomicWrites, adapter }` with
  `setText()` / `setData()` and `loadFailed` / `saveFailed` signals.
- `atomicWrites` defaults to **true** (temp file + rename) — safe against a crash mid-write.
- `blockLoading: true` is recommended for config read at startup so data exists before UI init.
- `watchChanges: true` + `onFileChanged: reload()` gives live settings edits from an external editor.
- `JsonAdapter` / `JsonObject` bind a JSON file to QML properties bidirectionally — declare a
  settings singleton, mutate properties, and it writes back.

Recommended layout for forest-shell: a `Settings` singleton wrapping a `FileView` with a
`JsonAdapter` at `${Quickshell.configDir}/settings.json`, with `Quickshell.dataDir` / `stateDir` /
`cacheDir` for runtime state (all exposed on the `Quickshell` singleton, alongside `env()`,
`iconPath()`, `execDetached()`).

Docs: `https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/FileView/`,
`https://quickshell.org/docs/v0.3.0/types/Quickshell/Quickshell/`

### 2.17 The cross-cutting gap: no generic DBus binding

Verified by grepping every shipped `.qmltypes`: the only DBus-named types are `DBusMenuHandle` and
`DBusMenuItem`. **There is no `DBusInterface` / `DBusObject` / `DBusProxy` QML type.**

Consequence: Quickshell's DBus support is *curated* — you get the services someone wrote a C++ module
for (notifications, tray, MPRIS, UPower, NetworkManager, BlueZ, polkit, greetd), and nothing else.
For any other bus service (logind session/suspend/reboot, systemd units, GeoClue, portals,
`org.freedesktop.UPower.KbdBacklight`, per-app custom services) you must shell out:

```qml
Process {
  command: ["busctl", "--user", "call", "org.example", "/path", "org.example.Iface", "Method"]
  stdout: StdioCollector { onStreamFinished: parse(text) }
}
```

`Process` + `StdioCollector` / `SplitParser` / `DataStreamParser` is workable but is a subprocess per
call with no signal subscription. For *watching* a DBus signal, `Process` with a long-running
`busctl monitor` / `dbus-monitor` and a `SplitParser` is the usual hack — noticeably less pleasant
than the native modules. `Socket` / `SocketServer` exist but speak raw Unix sockets, not DBus.

**Design implication:** when evaluating a feature for forest-shell, the first question is not
"is there a CLI tool?" but "**is there a Quickshell module?**" — if yes it's pure QML and pleasant;
if no, the cost is roughly the same whether the filler is a CLI tool or `busctl`, so pick the CLI
tool for ergonomics.

---

## 3. Implications for forest-shell

### 3.1 Pure-QML builds (no helper process, no external daemon)

These should be implemented natively, and **any conflicting system daemon must be removed/masked**:

| Feature | Types | Daemon to remove |
| --- | --- | --- |
| Bar / dock / panels | `PanelWindow`, `WlrLayershell`, `Variants` + `Quickshell.screens` | waybar |
| Workspace widget, window title | `Hyprland`, `HyprlandWorkspace`, `rawEvent` | — |
| Notification center + popups | `NotificationServer`, `Notification` | **dunst / mako (must not run)** |
| System tray + menus | `SystemTray`, `SystemTrayItem`, `DBusMenu*` | — |
| Volume / output switcher / mixer | `Pipewire`, `PwNodeAudio`, `PwObjectTracker` | — |
| Audio visualiser | `PwAudioSpectrum`, `PwNodePeakMonitor` | **cava** |
| Media player widget | `Mpris`, `MprisPlayer` | playerctl |
| Battery / power profiles | `UPower`, `PowerProfiles` | — |
| WiFi picker + wired status | `Networking`, `WifiDevice`, `Network` | nmcli scripting, nm-applet |
| Bluetooth manager | `Bluetooth`, `BluetoothDevice` | bluetoothctl scripting, blueman-applet |
| Lock screen | `WlSessionLock`, `PamContext` | **hyprlock / swaylock** |
| Login greeter | `Greetd` | gtkgreet / tuigreet |
| Idle: dim / lock / DPMS | `IdleMonitor`, `IdleInhibitor`, `Hyprland.dispatch("dpms off")` | **hypridle / swayidle** |
| Polkit prompts | `PolkitAgent`, `AuthFlow` | **hyprpolkitagent / polkit-gnome** |
| App launcher | `DesktopEntries`, `DesktopEntry`, `HyprlandFocusGrab` | rofi / wofi / fuzzel |
| Window switcher w/ live previews | `ToplevelManager`, `Toplevel`, `ScreencopyView` | — |
| Keybind-driven panel toggles | `GlobalShortcut` and/or `IpcHandler` | — |
| Settings persistence | `FileView` + `JsonAdapter` | — |

That is the large majority of a desktop shell. Note especially that **hypridle, hyprlock,
hyprpolkitagent, dunst, and cava all become unnecessary** — a meaningful reduction in moving parts
versus a typical Hyprland setup.

### 3.2 Needs a helper (design the QML/helper seam deliberately)

| Feature | Helper | Seam |
| --- | --- | --- |
| **Brightness (set)** | `brightnessctl` via `Process` | Read via `FileView` on `/sys/class/backlight/*`; write via helper. Wrap in one `Brightness` singleton so the subprocess is an implementation detail. |
| **External monitor brightness** | `ddcutil` | Same singleton, different backend; slow (~100ms+), debounce and never block UI. |
| **Clipboard history** | `wl-paste --watch cliphist store` + `cliphist list/decode` | Long-running `Process` for the watcher; `Process` + `StdioCollector` for queries. QML owns picker UI only. |
| **Copy to clipboard (incl. images)** | `wl-copy` | `Quickshell.clipboardText` is read-only and focus-limited — do not build on it. |
| **Screen recording** | `wf-recorder` / `gpu-screen-recorder` | QML owns indicator + start/stop; helper owns encoding. |
| **Screenshot to file** | `grabToImage()` native, or `grim`+`slurp` | Prefer native `ScreencopyView` + `grabToImage` for the simple case; `grim`/`slurp` if you want annotation/JPEG/region parity with existing tools. Copy-to-clipboard still needs `wl-copy`. |
| **Wallpaper** | `swww` / `hyprpaper`, or a QS `PanelWindow` on `WlrLayer.Background` | Actually buildable natively as a background-layer window with an `Image` — worth doing to drop the daemon, at the cost of holding decoded images in the shell process. |
| **Arbitrary DBus (logind suspend/reboot, systemd)** | `busctl` via `Process` | Wrap each in a small singleton; accept subprocess-per-call. Power menu actions are infrequent so this is fine. |
| **VPN / 802.1X profiles** | `nmcli` | Only if you go beyond `connectWithPsk` / `connectWithSettings`. |

### 3.3 Immediate action items

1. **Replace `noctalia-qs` with upstream `quickshell`.** They conflict, and `noctalia-qs` is only
   installed as a dependency of `dms-shell` / `noctalia-shell-git`. Building forest-shell against a
   third party's fork means the docs at `quickshell.org` may not describe your runtime.
2. **Pin the docs version you develop against** (`v0.3.0` today) — the site has no stable
   `/docs/latest/` alias and unversioned URLs 404.
3. **Audit for daemon conflicts before first run** — a running dunst/mako will silently steal the
   notification bus name and `NotificationServer` will appear broken.
4. **Remember `PwObjectTracker`** when building the audio widget; missing it is the single most
   common Quickshell/PipeWire bug.
5. **Plan the helper seam early**: one QML singleton per external-tool-backed capability
   (`Brightness`, `Clipboard`, `Recorder`, `Power`), so the subprocess dependency is isolated and can
   be swapped for a native module if upstream adds one.

---

## Sources

All primary, pinned to upstream v0.3.0:

- Module index — https://quickshell.org/docs/v0.3.0/types/
- Core — https://quickshell.org/docs/v0.3.0/types/Quickshell/ · https://quickshell.org/docs/v0.3.0/types/Quickshell/Quickshell/
- Io / IpcHandler / FileView — https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/ · https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/IpcHandler/ · https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/FileView/
- Wayland (layer shell, lock, idle, screencopy) — https://quickshell.org/docs/v0.3.0/types/Quickshell.Wayland/ · https://quickshell.org/docs/v0.3.0/types/Quickshell.Wayland/ScreencopyView/
- Hyprland — https://quickshell.org/docs/v0.3.0/types/Quickshell.Hyprland/ · https://quickshell.org/docs/v0.3.0/types/Quickshell.Hyprland/Hyprland/
- Notifications — https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Notifications/
- SystemTray — https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.SystemTray/
- Pipewire — https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Pipewire/
- Mpris — https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Mpris/
- UPower — https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.UPower/
- Networking — https://quickshell.org/docs/v0.3.0/types/Quickshell.Networking/
- Bluetooth — https://quickshell.org/docs/v0.3.0/types/Quickshell.Bluetooth/
- Pam — https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Pam/
- Greetd — https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Greetd/Greetd/
- Upstream repo — https://git.outfoxxed.me/quickshell/quickshell

Local verification (authoritative for what is actually installed): `qs --version`, `qs --help`,
`qs ipc --help`, and the shipped `.qmltypes` metadata under `/usr/lib/qt6/qml/Quickshell/`, from
which every property/method/signal name in this document was extracted.
