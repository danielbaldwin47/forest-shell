# Architecture

Sources: [#12](https://github.com/danielbaldwin47/forest-shell/issues/12), [#4](https://github.com/danielbaldwin47/forest-shell/issues/4), [#14](https://github.com/danielbaldwin47/forest-shell/issues/14), [#15](https://github.com/danielbaldwin47/forest-shell/issues/15), [#21](https://github.com/danielbaldwin47/forest-shell/issues/21), [#22](https://github.com/danielbaldwin47/forest-shell/issues/22), [.wayfinder/research/quickshell-capabilities.md](../.wayfinder/research/quickshell-capabilities.md), [.wayfinder/research/reference-shells.md](../.wayfinder/research/reference-shells.md)

forest-shell is a from-scratch Quickshell (QML) desktop shell for Hyprland on CachyOS. It is
**pure QML plus CLI helpers**: no C++ QML plugin, no companion daemon, no build step, full hot
reload. Every capability Quickshell covers natively is implemented natively; the four genuine gaps
are filled by external tools, each wrapped in exactly one service singleton so the subprocess is an
implementation detail that a future native module can replace.

## 1. Runtime

The target runtime is **upstream Quickshell 0.3.0** (official `extra` package). Documentation is
pinned to `https://quickshell.org/docs/v0.3.0/types/` — the site has no `/docs/latest/` alias and
unversioned URLs 404.

### 1.1 Development: side-by-side prefix

The machine's system-wide `quickshell` is `noctalia-qs` 0.0.12, an **archived** third-party fork
(archived 2026-07-15) pulled in as a dependency of `dms-shell` and `noctalia-shell-git`. It stays
installed and untouched during development. Upstream 0.3.0 lives in a private, non-root prefix:

| Item | Value |
| --- | --- |
| Prefix | `~/.local/opt/quickshell-upstream` |
| Wrapper | `~/.local/bin/qs-upstream` → `~/.local/opt/quickshell-upstream/qs-upstream` |
| Version reported | `Quickshell 0.3.0 (revision , distributed by Arch Linux)` |
| System `qs` | still `noctalia-qs 0.0.12`, pacman-owned |

The wrapper is:

```sh
PREFIX="$HOME/.local/opt/quickshell-upstream"
export LD_LIBRARY_PATH="$PREFIX/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QML_IMPORT_PATH="$PREFIX/usr/lib/qt6/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
exec "$PREFIX/usr/bin/quickshell" "$@"
```

Every development run, prototype and manual test uses:

```sh
qs-upstream -p /home/daniel/repos/forest-shell
```

`-p` accepts either `shell.qml` or the directory containing it. The binary is deliberately **not**
named `qs`, so Noctalia/DMS/Ghibli and shell-switch keep working.

**Constraint:** `LD_LIBRARY_PATH` is mandatory — without it the binary dies at
`libdwarf.so.2: cannot open shared object file`. Never invoke `$PREFIX/usr/bin/quickshell` directly.

The prefix is built by extracting the official `quickshell 0.3.0-2.1` package from
`cachyos-extra-v3` plus `cpptrace 1.0.4` and `libdwarf 2.3.2` (upstream links against both; neither
is installed system-wide). To rebuild it:

```sh
mkdir -p /tmp/qsdl && cd /tmp/qsdl
for u in $(pacman -Sp quickshell); do curl -sSL -O "$u"; done
rm -rf ~/.local/opt/quickshell-upstream && mkdir -p ~/.local/opt/quickshell-upstream
for f in *.pkg.tar.zst; do tar -I zstd -xf "$f" -C ~/.local/opt/quickshell-upstream \
  --exclude=.PKGINFO --exclude=.BUILDINFO --exclude=.MTREE; done
ln -sfn quickshell ~/.local/opt/quickshell-upstream/usr/bin/qs
```

The final `ln` is required on every rebuild: the package ships `usr/bin/qs` as an *absolute* symlink
to `/usr/bin/quickshell`, which inside the prefix points back at the fork. The hand-written
`qs-upstream` wrapper lives at the prefix root and survives re-extraction.

Qt coupling is satisfied today (package built against Qt 6.11.x, system has 6.11.1). A Qt
major/minor bump desyncs the prefix — re-extract to fix. There is no QML shadowing risk: upstream
bakes its QML modules into the binary as `qrc:` resources, so the on-disk tree is only
`qmldir`/`qmltypes` for tooling; `QML_IMPORT_PATH` is set so qmlls reads upstream's types rather
than the fork's.

### 1.2 API drift from the fork

**Constraint:** target upstream's API, never fork examples. Known differences: `Quickshell.exit()`
and `Hyprland.messageSync()` do not exist in upstream 0.3.0, and `Quickshell.configDir` is
deprecated in favour of **`Quickshell.shellDir`**.

**Constraint:** `Hyprland.workspaces` and `Hyprland.monitors` populate asynchronously — they are
empty at `Component.onCompleted` even after `refreshWorkspaces()`, and fill within ~1–3 s. Bind
reactively; never read once at startup.

### 1.3 The pacman swap is a build-plan phase

Replacing the fork system-wide is **not** a development task. It happens as an explicit phase of the
build plan, once forest-shell is daily-drivable. Sequencing is forced: `noctalia-qs` declares
`Conflicts With: quickshell` and is `Required By: dms-shell, noctalia-shell-git`, so those two
packages must be removed *before* `pacman -S quickshell` will go through. Old-stack retirement
precedes the swap. DMS depends only on the virtual `quickshell` and survives it; the Noctalia 4.x
QML stack and Ghibli do not, and are retired in the same phase. Until that phase runs, `qs` is the
fork and `qs-upstream` is forest-shell.

## 2. Native capability map

Quickshell 0.3.0 is far more batteries-included than its reputation. The evaluation question for any
feature is **"is there a Quickshell module?"**, not "is there a CLI tool?" — if there is a module the
work is pure QML; if not, the cost is the same whether the filler is a CLI tool or `busctl`, so pick
the CLI tool for ergonomics.

### 2.1 Native

| Area | Types |
| --- | --- |
| Layer-shell windows | `PanelWindow`, `WlrLayershell` |
| Popups / focus grab | `PopupWindow`, `PopupAnchor`, `HyprlandFocusGrab` |
| Multi-monitor | `Quickshell.screens`, `ShellScreen`, `Variants` |
| Session lock | `WlSessionLock`, `WlSessionLockSurface` (real `ext-session-lock-v1`) |
| PAM auth | `PamContext` |
| Notification server | `NotificationServer`, `Notification` (full `org.freedesktop.Notifications`) |
| System tray | `SystemTray`, `SystemTrayItem`, `Quickshell.DBusMenu` |
| Audio | `Pipewire`, `PwNode`, `PwNodeAudio`, `PwObjectTracker` |
| Audio visualiser | `PwAudioSpectrum` (native FFT), `PwNodePeakMonitor` |
| Media control | `Mpris`, `MprisPlayer` |
| Battery / power profiles | `UPower`, `UPowerDevice`, `PowerProfiles` |
| Network | `Networking`, `NetworkDevice`, `WifiDevice`, `WifiNetwork`, `Network` (NetworkManager) |
| Bluetooth | `Bluetooth`, `BluetoothAdapter`, `BluetoothDevice` (BlueZ) |
| Hyprland IPC | `Hyprland` singleton, `dispatch()`, `rawEvent`, `HyprlandWorkspace`, `HyprlandMonitor` |
| Global shortcuts | `GlobalShortcut` |
| Idle detect / inhibit | `IdleMonitor`, `IdleInhibitor`, `ShortcutInhibitor` |
| Greeter | `Greetd` |
| Polkit agent | `PolkitAgent`, `AuthFlow` |
| Screencopy (display + grab) | `ScreencopyView`, `captureFrame()` |
| App index | `DesktopEntries`, `DesktopEntry`, `DesktopAction` |
| Window list | `ToplevelManager`, `Toplevel` |
| Shell IPC | `IpcHandler` + `qs ipc call` |
| Settings persistence | `FileView`, `JsonAdapter`, `PersistentProperties` |

Because these are native, **hypridle, hyprlock, hyprpolkitagent, dunst/mako, cava, waybar,
nm-applet, blueman-applet and playerctl are all unnecessary** and must not run alongside the shell.

**Constraint:** a running dunst or mako silently steals the `org.freedesktop.Notifications` bus name
and `NotificationServer` appears broken. Audit for daemon conflicts before first run.

**Constraint:** `PwObjectTracker { objects: [...] }` must bind the PipeWire nodes you read, or
`volume` stays 0. This is the single most common Quickshell/PipeWire bug.

### 2.2 Gaps and their fillers

Four real gaps. Each gets exactly one service singleton owning the subprocess.

| Gap | Filler | Seam |
| --- | --- | --- |
| Brightness (write) | `brightnessctl` via `Process`; `ddcutil` for external DDC/CI monitors | `Services/Hardware/` — read current/max natively with `FileView` on `/sys/class/backlight/*/brightness` (`watchChanges: true` catches external changes), write via helper. `ddcutil` is slow (~100 ms+): debounce, never block UI. |
| Screen recording | `gpu-screen-recorder` via `Process` | `Services/System/` — QML owns indicator and start/stop lifecycle only. |
| Clipboard history | `wl-paste --watch cliphist store` (long-running `Process`) + `cliphist list` / `cliphist decode` (`Process` + `StdioCollector`); `wl-copy` for writes | `Services/System/` — QML owns the picker UI only. |
| Arbitrary DBus | `busctl` via `Process` + `StdioCollector` | One small singleton per bus service (logind suspend/reboot, systemd units). Subprocess per call, no signal subscription. |

**Constraint:** `Quickshell.clipboardText` is empty unless a Quickshell window is focused (a Wayland
`wl_data_device` property, not a Quickshell defect). Clipboard history cannot be built on it, and
there is no clipboard write API and no image clipboard support.

**Constraint:** there is no generic DBus binding in QML — the only DBus-named types are
`DBusMenuHandle` and `DBusMenuItem`. Quickshell's DBus support is curated per module.

Screenshot-to-file is PARTIAL: `ScreencopyView` is a QtQuick `Item`, so
`grabToImage(cb)` → `result.saveToFile(path)` produces a PNG with no external tool. Copy-to-clipboard
of the image still needs `wl-copy`. Wallpaper is native — a `PanelWindow` on the background layer
with an `Image`, no `swww`/`hyprpaper`. DPMS off is `Hyprland.dispatch("dpms off")`.

## 3. Repo layout

The repo root **is** the Quickshell config dir, with `shell.qml` at top level.

```
shell.qml        # entry, staged startup, gates on Config.ready
Core/            # Theme, Config, ConfigSpec, State, StateSpec, Paths, Time, Logger, ServiceInit
  Migrations/    #   ordered settings migrations, one file per version
Services/        # cross-surface state + side effects; singletons grouped by domain
  Compositor/    #   Hyprland facade — the only place hyprctl/dispatch lives
  Media/  Hardware/  Networking/  System/  Theming/  Claude/
Surfaces/        # screen-attached UI
  Bar/  Drawers/{Launcher,ControlCenter,Dashboard,Session,Notifications}/  Osd/
  Notifications/  Lock/  Background/  Settings/
Widgets/         # dumb reusable kit — never reads Services or Config
Assets/          # icons/lucide/ (vendored), sounds
Shaders/         # .frag sources + precompiled .qsb (qsb run at dev time; no runtime build)
docs/            # specs, ADRs, roadmap
```

Layer rules:

- **`Core/`** — no UI, no domain logic. Tokens, config store, paths, logging, service bootstrap.
- **`Services/`** — `pragma Singleton`, one per domain concern, grouped by domain directory. All
  side effects (subprocesses, DBus, sockets, files) live here. Services never import `Surfaces/`.
  Feature-local services live with their surface, e.g.
  `Surfaces/Drawers/Launcher/services/`, not in the global namespace.
- **`Surfaces/`** — one directory per screen-attached UI unit. A surface owns its windows, its
  `IpcHandler`, and its `GlobalShortcut`s.
- **`Widgets/`** — dumb, reusable, stateless. May import `Core/Theme.qml`; everything else arrives
  as properties. A widget that reads a service or `Config` belongs in `Surfaces/`.

Imports use the `qs.` config-root namespace (e.g. `import qs.Core`, `import qs.Widgets`).

**Glossary:** *Surface* = a screen-attached UI unit with its own directory under `Surfaces/`.
*Module* is reserved for bar modules per the feature inventory. Do not use "module" for anything else.

## 4. Window topology

Hybrid, for two different reasons — small windows keep redraws cheap, one shared window keeps focus
sane.

### 4.1 Own layer-shell window per screen, kept alive

Bar, OSD, notification popups, Lock, Background each own their windows. These update frequently and
QtQuick redraws the whole window on any change, so small windows keep the T480 iGPU happy.

**Constraint:** rapid layer-shell surface create/destroy churn is a known compositor-crash class.
Hidden windows stay alive — `visible: false` with content debounce-unloaded *inside* the window.
Never destroy and recreate a window to hide it, and never move a layer-shell window between outputs.

### 4.2 One shared drawer window per screen

Launcher, Control Center, Dashboard, Session menu and the Notification center are composed into a
**single** drawer window per screen: shared input mask, a single `HyprlandFocusGrab`, free
cross-drawer animation, one continuous frame. (The notification *popups* are their own window; the
*center* is drawer content — see `features/notifications.md`.) The window object is created per screen at startup and never destroyed; it is mapped only
while a drawer is open, and holds unloaded content while closed (zero wakeups).

Behaviour:

- **Globally exclusive.** At most one drawer is open across all screens. Summoning a drawer while
  another is open elsewhere closes it there and opens on the focused screen.
- **Follows focus.** A drawer always opens on the focused screen. IPC drawer targets take no screen
  argument in v1.
- **Toggles.** Re-summoning the same drawer on the same screen closes it.
- **One focus grab.** Exactly one `HyprlandFocusGrab` exists at a time — this is what eliminates the
  multi-panel focus fight.
- **Resets on hotplug.** An open drawer on a removed screen resets to closed; there is no migration
  to another screen and no per-monitor state is remembered.

### 4.3 Layer-shell namespaces

Every layer-shell window sets `WlrLayershell.namespace` to `forest-shell:<surface>` — `forest-shell:bar`,
`forest-shell:drawer`, `forest-shell:osd`, `forest-shell:notifications`, `forest-shell:background`.
Hyprland `layerrule`s (blur in particular) match on these names, so they are a stable public
interface: do not rename them casually.

## 5. Startup

Staged, with a single readiness gate.

1. **Synchronous stage** — `Config`, `Theme`, `Background`. The wallpaper is visible on the first
   frame; there is never a bare background.
2. **Gate** — every surface instantiates under `Config.ready`
   (`LazyLoader { active: Config.ready && … }`). Nothing renders with defaults and then snaps.
3. **Deferred stage** — `Qt.callLater` after the first frame, then a one-shot 1500 ms timer for the
   tail: weather, /proc stats sampling, Claude warmup, tray. Untimed, but must not jank the
   compositor.

**Constraint:** a `pragma Singleton` that nothing references never initializes.
`Core/ServiceInit.qml` force-touches every unconditionally-running service; a new always-on service
is not live until it is listed there.

## 6. Configuration

### 6.1 Two files

| File | Path | Contents |
| --- | --- | --- |
| Settings | `~/.config/forest-shell/settings.json` | User intent, nested by section, hand-editable, portable between machines |
| State | `${Quickshell.stateDir}/state.json` | Runtime state that must never churn the config file |

**Intent lives in settings even when toggled often**: dark/light mode, current wallpaper, night-light
schedule. `settings.json` alone captures "my setup" and is portable between the T480 and the desktop.
**DND is the deliberate exception** — situational, not setup — and lives in state, alongside
open-panel/last-tab state, notification history, weather cache, Claude session id, seen-changelog and
other seen flags.

### 6.2 Sections

Nine top-level sections plus `settingsVersion`, mirroring the settings GUI tabs 1:1 (the About tab
has no config). Keys are camelCase.

```
appearance, bar, launcher, controlCenter, dashboard,
notifications, weatherTime, wallpaper, system
```

Hand-editing therefore maps directly onto the GUI. Feature docs own their own keys within these
sections; architecture owns `settingsVersion` and `appearance.reducedEffects`.

### 6.3 Spec table

One nested `SPEC` object in `Core/ConfigSpec.js` mirrors the section structure. Per key:

| Field | Meaning |
| --- | --- |
| `def` | Default value. Also fixes the key's type. Required. |
| `coerce` | Optional `function(raw) -> value \| undefined`. `undefined` means "not coercible". |
| `onChange` | Optional string naming an action in `Core/ConfigActions.qml`, invoked after commit. |

```js
appearance: {
    reducedEffects: { def: false, onChange: "applyEffectLevel" },
},
```

`Core/Config.qml` is a generic store that derives parsing, serialization, defaults, saving and
migration from the spec — **no per-property boilerplate, no `onXChanged: save()` per key**. Access is
both typed (`Config.appearance.reducedEffects`) and dotted-path
(`Config.get("bar.showBattery")`, `Config.set("appearance.reducedEffects", true)`).

`Core/StateSpec.js` + `Core/State.qml` reuse the same spec-and-store pattern for the state file.

### 6.4 Sparse file

`settings.json` stores **only keys that differ from their default**. Reset-to-defaults, per section
or whole-file, is key deletion. Updated defaults in new shell versions therefore flow through
automatically. Discovering available options is the GUI's job, not the file's.

**Constraint:** `JsonAdapter` silently drops keys it does not know. Unknown keys in the user's file
are preserved on rewrite — the store reads raw JSON alongside the adapter and merges unknown keys
back on save.

### 6.5 Bad config

- **Invalid JSON:** the shell keeps running on the last-good config, raises a notification with the
  error location, and retries on the next file change. **The file is never touched.**
- **Bad individual value:** coerce if the spec can, otherwise fall back to that key's default and
  notify. Other keys are unaffected.
- The shell **never rewrites the user's file** except during migrations and explicit GUI actions.
- Strict JSON, no comments — GUI writes would destroy them.

### 6.6 Hot reload

Both directions, with the standard guards:

- `FileView { watchChanges: true }`, reload debounced ~100 ms.
- Writes are debounced and atomic (`atomicWrites` defaults true).
- `onLoadFailed` with `FileViewError.FileNotFound` self-seeds defaults.
- ~2 s post-save cooldown plus an explicit "I wrote this" flag breaks save→watch→reload loops.

**Constraint:** atomic writes fire twice (a file event and a directory event) and the file may be
momentarily empty or partial. Debounce *and* retry; do not treat one event as one change.

### 6.7 Migrations

`settingsVersion` exists from day one and migrations run from day one — they are very hard to
retrofit.

At startup, silently and without blocking:

1. Copy `settings.json` → `settings.json.bak-vN` (kept, one backup per version).
2. Run the ordered migration functions from `Core/Migrations/` against **raw JSON parsed separately
   from the adapter** — the adapter drops keys a migration may need to read.
3. Bump `settingsVersion`.

Notify only on failure, and continue running on the backup. Migration is the only unattended path
that rewrites the user's file.

### 6.8 Not in v1

No per-monitor overlay system. Per-screen needs are explicit settings keys, and there are none in v1.

## 7. Theming

`Core/Theme.qml` is the **sole token source** — semantic color roles, spacing, radii, type scale,
motion durations and easings. No raw hex and no magic numbers anywhere else in the tree, including
`Widgets/`.

The palette is swappable data inside `Theme`. `Services/Theming/` owns the three color modes:

1. **Fixed forest** — the shipped palette. Default.
2. **Constrained accent** — accent derived from the wallpaper via the native `ColorQuantizer`, with
   an Oklab hue clamp keeping it inside the forest range.
3. **Full dynamic** — optional `matugen`. This is the only mode that themes external apps.

**Consumers are mode-blind.** No surface, widget or service ever checks which mode is active or
whether the palette is dark or light; they read semantic roles from `Theme` only. Dark-first, with
the light palette seed wired into the structure from day one.

## 8. Keybinds and IPC

Two mechanisms, both co-located with the surface they drive. **There is no central IPC file.**

- **`GlobalShortcut`** for interactive keybinds. Hyprland side:
  `bind = ..., global, forest-shell:<name>`. No subprocess per keypress, and it keeps working while
  the session is locked.
- **`IpcHandler`** for scripting, automation and the shell-switch integration. Target names are the
  surface name, lowercase (`launcher`, `controlcenter`, `dashboard`, `session`, `bar`, `lock`).
  Query targets return JSON strings so external scripts and status tools can read shell state
  cheaply.

`IpcHandler` functions need explicit type signatures, take at most 10 arguments, and argument types
are limited to `string`, `int`, `bool`, `real`, `color`. Signals take zero or one argument.

The launcher toggle is a **required** entry point from day one — shell-switch binds it
unconditionally to Super+Space (see [shell-switch.md](shell-switch.md)):

```qml
IpcHandler {
    target: "launcher"
    function toggle(): void { /* ... */ }
}
```

**Hyprland config side:** every forest-shell bind written into the user's own Hyprland config uses
the `TEST_ALIVE || fallback` idiom, so the compositor stays usable whenever the shell is down —
which, while building a shell from scratch, is most of the time:

```
bind = SUPER, Space, exec, qs -p /home/daniel/repos/forest-shell/shell.qml ipc call launcher toggle || fuzzel
```

The one exception is the Super+Space bind generated by shell-switch: its template interpolates
through `sed`, so the command must not contain `|`, and that bind therefore carries no fallback.
shell-switch launches forest-shell by direct path — there is no `~/.config/quickshell/forest`
symlink and no `-c` config name.

## 9. Multi-monitor

**Calibration fact:** both real machines are effectively single-monitor at 1.5× fractional scale
(T480 `eDP-1` 1920×1080@1.5×, never docked; desktop one 4K@1.5×). Multi-monitor is a **correctness
tier** — it must not break, and it gets zero tuning.

Instantiation is uniform per screen, driven by `Variants { model: Quickshell.screens }`:

| Surface | Policy |
| --- | --- |
| Background | every screen |
| Bar | every screen |
| Lock | every screen (the session-lock protocol covers all outputs) |
| OSD | window per screen, renders only on the focused screen |
| Notification popups | window per screen, renders only on the focused screen |
| Drawers | window per screen, one open globally, on the focused screen |

There are no "bar on primary only" settings keys in v1 — dead settings when monitors are never
plural.

Hotplug is fully reactive: `Variants` creates and destroys per-screen surfaces automatically. An open
drawer on a removed screen resets to closed. OSD and notifications follow Hyprland's own refocus
after monitor removal — there is no shell-side fallback ranking. Resolution and scale changes
re-layout live, with no restart. **Zero-screen survival is an explicit test case**: lid closed,
nothing attached, the shell idles without crashing.

## 10. Performance budgets

These are acceptance gates, not aspirations. All numbers are measured on the T480 (Intel UHD 620) at
1.5×; the desktop with a discrete GPU is a zero-tuning correctness tier.

### 10.1 Startup (cold cache)

| Milestone | Budget |
| --- | --- |
| First frame — wallpaper + bar rendered | **≤ 1.5 s** from process launch |
| Interactive — keybinds live, launcher summonable | **≤ 2 s** |
| Deferred stage (tray/weather/stats/Claude warmup) | untimed, must not jank the compositor |

Measured from Quickshell log timestamps.

### 10.2 Idle (laptop battery is a first-class motive)

- CPU **≤ 0.5 %** as a 60-second average, all shell processes summed. Aspiration ~0.2 %.
- **< 5 wakeups/s** — the shell stays out of powertop's top offenders. The clock ticks 1/min aligned
  to the minute unless seconds are actually visible.
- **Zero idle animation.** Nothing pulses, breathes or marquees unattended. Fog and lamplight motifs
  are event-driven, never ambient loops.
- **Poll only while visible.** `/proc` stats sampling runs only while the dashboard is open. Tray,
  MPRIS, UPower and network are native and event-driven — no timers.
- Unmapped windows hold unloaded content and contribute zero wakeups. This is what makes the
  keep-alive rule in §4 checkable.

### 10.3 Animation

- **Zero dropped frames at 60 Hz** for drawer open/close, OSD, and notification slide, at 1.5×
  (a 2880×1620 buffer — fill rate is the scarce resource on UHD 620).
- **≤ 8 ms GPU frame time**, leaving headroom for foreground apps.
- Verify with `QSG_RENDER_TIMING=1`.

**Constraint: no QML-side full-screen blur, ever.** The fog scrim animates opacity only. Frosted
glass is a Hyprland `layerrule = blur` on the namespaces in §4.3, it is optional, and the shell must
look correct with blur off.

### 10.4 Degrade knob

One manual settings key, **`appearance.reducedEffects: bool`, default `false`**. There is no runtime
GPU auto-detection. When `true`, in cost order:

1. Hyprland blur layerrule off.
2. Drop shadows and decorative `MultiEffect`s off. Icon colorization stays — measured negligible and
   needed for correctness.
3. All transitions collapse to opacity-only fades at the fastest motion step (140 ms).

`reducedEffects: true` is a fully supported look, not a broken mode: the shell stays correct and
legible.

**This knob is the user's escape hatch, not the performance strategy.** A budget miss with the knob
off means simplifying the design — never auto-flipping the knob.
