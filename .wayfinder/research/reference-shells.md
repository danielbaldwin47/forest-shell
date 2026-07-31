# Reference Shells: What Leading Quickshell Desktop Shells Ship

Research date: 2026-07-31. Purpose: set the feature bar and gather architecture patterns for
forest-shell, a from-scratch Quickshell desktop shell for Hyprland.

Sources: Noctalia and DankMaterialShell were inspected **directly from their installed QML trees on
this machine** (`/etc/xdg/quickshell/noctalia-shell/` and `/usr/share/quickshell/dms/`), which is
authoritative and current. caelestia and end-4's illogical-impulse were surveyed from their GitHub
repositories.

Versions inspected:

| Shell | Version on disk | Path |
|---|---|---|
| Noctalia | `noctalia-shell-git 4.7.5.r59` | `/etc/xdg/quickshell/noctalia-shell/` |
| DankMaterialShell | `dms-shell 1.5.2` | `/usr/share/quickshell/dms/` |

---

## 1. Noctalia Shell

Repo: <https://github.com/noctalia-dev/noctalia-shell>. Tagline "quiet by design". Explicitly scoped
as a **shell, not a DE** — it draws a boundary and pushes everything else to plugins.

### 1.1 Feature inventory

**Bar widgets** (30, in `Modules/Bar/Widgets/`) — every one is individually placeable and
individually configurable:

`ActiveWindow`, `AudioVisualizer`, `Battery`, `Bluetooth`, `Brightness`, `Clock`, `ControlCenter`,
`CustomButton`, `DarkMode`, `KeepAwake`, `KeyboardLayout`, `Launcher`, `LockKeys` (caps/num),
`MediaMini`, `Microphone`, `Network`, `NightLight`, `NoctaliaPerformance`, `NotificationHistory`,
`PowerProfile`, `SessionMenu`, `Settings`, `Spacer`, `SystemMonitor`, `Taskbar`, `Tray`, `Volume`,
`VPN`, `WallpaperSelector`, `Workspace`.

The bar supports horizontal and vertical orientation (`BarPillHorizontal`/`BarPillVertical`), an
auto-hide/peek mode with a `BarTriggerZone`, and a per-monitor exclusion zone.

**Panels** (`Modules/Panels/`) — each bar widget can open a dedicated panel:
Audio, Battery, Bluetooth, Brightness, Changelog, Clock (calendar), ControlCenter, Dock, Launcher,
Media, Network, NotificationHistory, SessionMenu, Settings, SetupWizard, SystemStats, Tray drawer,
Wallpaper (+ a Wallhaven browser popup).

**Launcher** (`Modules/Panels/Launcher/`) is provider-based — 8 providers in `Providers/`:
`ApplicationsProvider`, `CalculatorProvider`, `ClipboardProvider`, `CommandProvider`,
`EmojiProvider`, `SessionProvider`, `SettingsProvider`, `WindowsProvider`. Grid and list delegates,
fuzzy matching via a hand-rolled `Commons/FuzzySort.qml` (883 lines), clipboard image preview, and an
optional overlay-layer window mode.

**Control center** (`Modules/Panels/ControlCenter/Widgets/`, 11 toggles): AirplaneMode, Bluetooth,
CustomButton, DarkMode, KeepAwake, Network, NightLight, NoctaliaPerformance, Notifications (DND),
PowerProfile, WallpaperSelector. Users reorder these via settings.

**Cards** (`Modules/Cards/`) are reusable dashboard tiles shared between control center, dashboard
and desktop widgets: Audio, Brightness, CalendarHeader, CalendarMonth, Media, Profile, Shortcuts,
SystemMonitor, Weather.

**Desktop widgets** (`Modules/DesktopWidgets/Widgets/`, drag-positioned on the wallpaper):
DesktopClock, DesktopMediaPlayer, DesktopSystemStat, DesktopWeather, DesktopAudioVisualizer.

**Other surfaces**: lock screen (`Modules/LockScreen/` with PAM + fingerprint via `fprintd-verify`),
notifications with history and DND, OSD, toasts (`Modules/Toast/`), tooltips, a dock
(`Modules/Dock/` with context menu), screen corners (`ScreenCorners.qml`), a wallpaper background
layer with shader transitions, and an Overview background layer.

**Distinctive / unusual:**
- **Setup wizard** on first run (`Modules/Panels/SetupWizard/`): appearance → wallpaper → dock →
  customize. Plus a changelog panel shown after updates and a telemetry opt-in wizard.
- **Wallhaven integration** (`Services/UI/WallhavenService.qml`) — browse and download wallpapers
  from wallhaven.cc inside the shell.
- **Calendar backends**: Evolution Data Server and `khal`
  (`Services/Location/Calendar/`), driven by Python helper scripts.
- **Weather with animated shaders** — `Shaders/frag/weather_{cloud,rain,snow,stars,sun}.frag`.
- **Plugin ecosystem** (~100 plugins) installed by sparse git clone from a registry.
- **"Noctalia Performance" mode** — a global toggle that degrades animations/effects for battery.
- **Hooks** (`Services/Control/HooksService.qml`) — user shell snippets fired on wallpaper change,
  dark-mode change, unlock, idle, performance-mode toggle. Args are substituted as `$1` (path),
  `$2` (screen), `$3` (theme).
- **i18n** with a full translation pipeline (`Assets/Translations/`, `Scripts/dev/i18n-{push,pull}.sh`).
- **Audio spectrum visualizer** fed by `cava`, rendered with `wave_spectrum.frag`.

### 1.2 Architecture

Top-level layout:

```
shell.qml            # ShellRoot, ~260 lines, staged startup
Commons/             # Singletons: Settings, ShellState, Style, Color, I18n, Icons, Logger, Time,
                     #   Keybinds, FuzzySort, ThemeIcons + Migrations/
Services/            # 63 singletons, grouped by domain (see below)
Modules/             # Screen-attached UI: Bar, Panels, OSD, Dock, LockScreen, Notification,
                     #   DesktopWidgets, Background, MainScreen, Cards, Toast, Tooltip
Widgets/             # 52-file reusable UI kit, all `N`-prefixed (NButton, NSlider, …)
Assets/              # ColorScheme/, Fonts/, Templates/, Sounds/, Translations/, Wallpaper/
Shaders/frag+qsb/    # Wallpaper transitions, weather effects, graphs, color picker
Scripts/             # bash/, python/ (theming, calendar, network), dev/
Helpers/             # Plain .js helpers (QtObj2JS.js)
```

**Services are grouped by domain, not flat** — this is the single most copyable organizational idea:

```
Services/Compositor/  CompositorService (facade) + Hyprland, Niri, Sway, Labwc, Mango,
                      ExtWorkspace backends
Services/Control/     IPCService, HooksService, CustomButtonIPCService, CurrentScreenDetector
Services/Hardware/    Battery, Brightness
Services/Keyboard/    Clipboard, Emoji, KeyboardLayout, LockKeys
Services/Location/    Calendar (+backends), DarkMode, Location, NightLight
Services/Media/       Audio, Media, Spectrum
Services/Networking/  Network, Bluetooth, BluetoothRssi, VPN
Services/Noctalia/    GitHub, Plugin, PluginRegistry, Supporter, Telemetry, Update
Services/Power/       IdleInhibitor, Idle, PowerProfile
Services/System/      Font, Host, Notification, NotificationRules, ProgramChecker, Sound, SystemStat
Services/Theming/     AppTheme, ColorScheme, TemplateProcessor, TemplateRegistry
Services/UI/          Bar, BarWidgetRegistry, ControlCenterWidgetRegistry, DesktopWidgetRegistry,
                      LauncherProviderRegistry, Panel, SettingsPanel, SettingsSearch, ImageCache,
                      Toast, Tooltip, Wallhaven, Wallpaper
```

`CompositorService` is a **facade over per-compositor backends** — the rest of the shell never
touches Hyprland directly. Worth copying even for a Hyprland-only shell, as it isolates the IPC
surface.

**Registry pattern.** `Services/UI/BarWidgetRegistry.qml` maps widget name → `Component`, plus a
parallel `widgetSettingsMap` of name → settings QML path. `Modules/Bar/Extras/BarWidgetLoader.qml`
instantiates from the registry by name. Same pattern repeats for control-center widgets, desktop
widgets, and launcher providers. This is what makes "user reorders bar widgets in a GUI" tractable:
config stores a list of `{id, …}` objects; the loader resolves them through the registry. Plugins
register into the same registries at runtime.

**PanelService** (`Services/UI/PanelService.qml`, 421 lines) is a central panel broker: panels
self-register by name, and anything (IPC, bar widget, keybind) opens one via
`PanelService.getPanel(name, screen)`. It enforces "only one panel open at a time", handles
fallback-screen selection, context menus, and tray menus. Avoids N×M coupling between triggers and
panels.

**Settings and persistence.**
- `Commons/Settings.qml` (1296 lines) is a singleton wrapping a Quickshell `FileView` +
  `JsonAdapter` over `~/.config/noctalia/settings.json`.
- Config is **nested by section** — 25 top-level keys: `appLauncher`, `audio`, `bar`, `brightness`,
  `calendar`, `colorSchemes`, `controlCenter`, `desktopWidgets`, `dock`, `general`, `hooks`, `idle`,
  `location`, `network`, `nightLight`, `noctaliaPerformance`, `notifications`, `osd`, `plugins`,
  `sessionMenu`, `systemMonitor`, `templates`, `ui`, `wallpaper`, `settingsVersion`.
- `watchChanges: true` on the FileView plus a 200 ms debounce timer gives **hot reload on external
  edit** while coalescing atomic-replace writes into one reload.
- **Versioned migrations**: `settingsVersion` is currently 59, and `Commons/Migrations/` holds 25
  `MigrationNN.qml` files registered in `MigrationRegistry.qml`. On load, raw JSON is parsed
  separately from the adapter (because the adapter drops removed keys) and migrations run in order.
  This is the mature answer to "config schema evolves".
- Transient state is split out into `Commons/ShellState.qml` → `~/.cache/noctalia/shell-state.json`
  (display state, notification state, changelog seen, color scheme list). **Good separation: user
  intent vs. runtime cache.**

**Theming.** `Commons/Style.qml` holds all design tokens as `readonly property` — font sizes
(XXS→XXXL), weights, two radius scales (container `radiusM` vs. input `iRadiusM`), border widths,
margin scale, opacity scale — all multiplied by user-configurable ratios (`radiusRatio`,
`uiScaleRatio`, `screenRadiusRatio`). `Commons/Color.qml` holds the semantic palette
(`mPrimary`, `mOnPrimary`, `mSurface`, `mSurfaceVariant`, `mOutline`, `mShadow`, `mHover`, …).

**Noctalia does not use matugen.** It ships its own pure-Python Material Color Utilities
implementation in `Scripts/python/src/theming/lib/`: `hct.py`, `quantizer.py`, `scheme.py`,
`palette.py`, `contrast.py`, `material.py`, `image.py`, `renderer.py`, `theme.py`, `color.py`, driven
by `template-processor.py`. Scheme types are matugen-compatible names (`tonal-spot` default).
This removes a Rust binary dependency at the cost of owning the color science.

`Assets/Templates/` ships **31 app theme templates** applied on every scheme change: btop, cava,
vscode, discord (2 variants), emacs, fuzzel, gtk3, gtk4, helix, hyprland, hyprtoolkit, kcolorscheme,
labwc, mango, niri, pywalfox, qtct, scroll, spicetify, steam, sway, telegram, terminal, vicinae,
walker, yazi, zathura, zed, zen-browser, plus its own `noctalia.json`. Users can add their own via
`enableUserTheming` and a user TOML config. Predefined schemes live in `Assets/ColorScheme/`
(Ayu, Catppuccin, Dracula, Eldritch, Gruvbox, Kanagawa, Nord, Rosepine, Tokyo-Night, Noctalia-default),
each a JSON with `dark` and `light` variants.

**IPC.** `Services/Control/IPCService.qml` (940 lines) declares **29 `IpcHandler` targets**:
`bar`, `settings`, `calendar`, `notifications`, `toast`, `idleInhibitor`, `launcher`, `lockScreen`,
`brightness`, `monitors`, `darkMode`, `nightLight`, `colorScheme`, `volume`, `sessionMenu`,
`controlCenter`, `dock`, `wallpaper`, `wifi`, `network`, `bluetooth`, `airplaneMode`, `battery`,
`powerProfile`, `media`, `state`, `desktopWidgets`, `location`, `systemMonitor`, `plugin`.

Keybinds are wired in the compositor config as `qs -c noctalia ipc call <target> <method> [args]`.
Handlers are granular (`volume.increase`, `wallpaper.random <screen>`, `media.seekRelative <offset>`)
and several return JSON strings (`notifications.getHistory`, `state.all`, `wallpaper.get`), so the
shell doubles as a queryable state daemon for scripts/status tools.

**Custom Quickshell fork.** Noctalia ships `noctalia-qs`, its own Quickshell fork providing `/usr/bin/qs`.
Notable modules present: `Quickshell/Networking`, `Quickshell/Bluetooth`, `Quickshell/Services/Polkit`,
`Quickshell/WindowManager`, `Quickshell/DWL`. Forking is a real maintenance cost — a from-scratch shell
should stay on upstream Quickshell and accept the feature gaps.

### 1.3 External tools

Hard dependencies (`pacman -Qi noctalia-shell-git`): `noctalia-qs`, `imagemagick`, `brightnessctl`,
`ffmpeg`, `qt6-multimedia`, `python`, `wlr-randr`.
Optional: `cliphist` (clipboard), `wlsunset` (night light), `power-profiles-daemon`, `ddcutil`
(external display brightness).

Actually invoked from QML: `sh -lc` (65 `execDetached` sites — the dominant pattern), `python3`
(theming/calendar/bluetooth helpers), `wl-copy`/`wl-paste`, `xdg-open`, `nmcli`, `hyprctl`, `niri`,
`swaymsg`, `mmsg` (mango), `wlr-randr`, `ddcutil`, `brightnessctl`, `light`, `cliphist`, `rfkill`,
`bluetoothctl`, `wpctl`, `cava`, `btop`, `fastfetch`, `khal`, `loginctl`, `dbus-send`, `curl`
(Wallhaven/GitHub), `git` (plugin install), `nvidia-smi`, `nproc`, `fc-list`, `identify`
(ImageMagick), `fprintd-verify`, `wlsunset`.

**Notably absent: no `swww`, no `grim`/`slurp`, no `matugen`.** Wallpapers are rendered in-shell on a
background layer with GPU shader transitions (`Shaders/frag/wp_{fade,wipe,disc,honeycomb,pixelate,stripes}.frag`).
There is no built-in screenshot tool or screen recorder — those are left to the user's own tools.

---

## 2. DankMaterialShell (DMS)

Repo: <https://github.com/AvengeMedia/DankMaterialShell>. Material Design 3. This is the most
DE-complete of the four, and architecturally the most unusual: **it is a monorepo with a ~118,000-line
Go backend plus a QML frontend.**

### 2.1 Feature inventory

**Bar widgets** (32, `Modules/DankBar/Widgets/`):
`AppsDock` (+ overflow + context menu), `AudioVisualization`, `Battery`, `CapsLockIndicator`,
`ClipboardButton`, `Clock`, `ColorPicker`, `ControlCenterButton`, `CpuMonitor`, `CpuTemperature`,
`DiskUsage`, `DWLLayout`, `FocusedApp`, `GpuTemperature`, `IdleInhibitor`, `KeyboardLayoutName`,
`LauncherButton`, `Media`, `NetworkMonitor`, `NotepadButton`, `NotificationCenterButton`,
`PowerMenuButton`, `PrivacyIndicator`, `RamMonitor`, `RunningApps`, `SystemTrayBar`, `SystemUpdate`,
`Vpn`, `Weather`, `WorkspaceSwitcher`.

Bar structure is `LeftSection`/`CenterSection`/`RightSection` + `WidgetHost` + `BarCanvas`, with an
`AxisContext` abstraction so the same widgets work horizontally and vertically, and a
`DankBarHoverController` for auto-hide. Dedicated popouts for Battery, VPN, DWL layout, SystemUpdate.

**Control center** (`Modules/ControlCenter/`): pill/toggle widgets (audio out, audio in, brightness,
battery, disk usage, DND, color picker, compound pills) plus **detail sub-views** that slide in:
`AudioInputDetail`, `AudioOutputDetail`, `BatteryDetail`, `BluetoothDetail`, `BluetoothCodecSelector`,
`BrightnessDetail`, `DiskUsageDetail`, `DoNotDisturbDetail`, `NetworkDetail`. Plugins can inject
control-center tiles.

**DankDash** (`Modules/DankDash/`) — a dashboard popout with tabs: Overview (clock, calendar +
event editor, media, weather, system monitor, user info cards), MediaPlayer, Weather (+ forecast),
Wallpaper.

**Launcher** — `Modals/DankLauncherV2/` (24 files): app search with its own `Scorer.js`, section-based
results, grid/tile/list modes, a **Spotlight variant** (separate content + result row components), an
action panel, clipboard preview inline, app editing (`AppEditView`), context menu, and plugin-provided
launcher sources with trigger prefixes.

**Modals** (`Modals/`): AppPicker, BluetoothPairing, BrowserPicker, DankColorPicker, Changelog,
Clipboard history (12 files: editor, thumbnails, context menu, keyboard controller/hints),
DisplayConfirmation, FileBrowser (13 files — full file manager with sidebar, grid/list, save dialog,
sort menu, overwrite dialog), Greeter, Keybinds cheatsheet, Mux, NetworkInfo, NetworkWiredInfo,
Notification, PolkitAuth, PowerMenu, PowerProfile, ProcessList, Settings, SwitchUser, WifiPassword,
WifiQRCode, WindowRule, WorkspaceRename.

**OSDs** (9, `Modules/OSD/`): AudioOutput, Brightness, CapsLock, IdleInhibitor, MediaPlayback,
MediaVolume, MicVolume, PowerProfile, Volume.

**Lock screen** (`Modules/Lock/`, 13 files): PAM auth, on-screen keyboard (`Keyboard.qml`,
`CustomButtonKeyboard.qml`), power menu, fade-to-lock and fade-to-DPMS windows, and a
**video screensaver** (`VideoScreensaver.qml`, `VideoScreensaverPlayer.qml`).

**Settings UI** (`Modules/Settings/`, 57 files) — a full settings application with tabs:
About, Audio, AutoStart, Battery, Clipboard, CompositorLayout, DankBar, DankBarAppearance, DankDash,
DefaultApps, DesktopWidgets, DisplayConfig, DisplayWidgets, Dock, Frame, GammaControl, Greeter,
Keybinds, Launcher, Locale, LockScreen, MediaPlayer, Mux, NetworkEthernet, NetworkStatus, NetworkVpn,
NetworkWifi, Notifications, OSD, Plugins (+ browser + updates dialog), PowerSleep, Printer,
RunningApps, Sounds, SystemUpdater, ThemeBrowser, ThemeColors, TimeWeather, TypographyMotion, Users,
Wallpaper, Widgets, WindowRules, Workspaces, WorkspaceAppearance.

**Distinctive / unusual:**
- **Greeter / display manager.** DMS ships a full greetd greeter (`Modules/Greetd/`, `Modals/Greeter/`,
  `DMSGreeter.qml`, `assets/pam/`, `systemd/`) — the same shell runs as your login screen.
- **Notepad** (`Modules/Notepad/`) — tabbed persistent scratchpad with its own storage service.
- **ProcessList** (`Modules/ProcessList/`) — a full task manager: Processes, Performance, Disks,
  System views, with kill/renice context menu.
- **Mux** (`Services/MuxService.qml`, `Modals/MuxModal.qml`) — tmux/zellij session browser and attacher.
- **Frame** (`Modules/Frame/`) — a decorative screen-border frame layer with configurable thickness,
  rounding, color, opacity, blur, and per-screen prefs; integrates with a launcher "emerge" animation.
- **Workspace overviews** (`Modules/WorkspaceOverlays/`) — native Hyprland and Niri overview overlays.
- **Printer management** (`Services/CupsService.qml` + Go `internal/server/cups/` over IPP).
- **Tailscale** (`Services/TailscaleService.qml`), **VPN**, **Privacy indicator** (mic/cam in use).
- **System updater** (`Services/SystemUpdateService.qml`) with a bar widget and popout.
- **Trash** (`Services/TrashService.qml`) with a dock trash button and context menu.
- **Window rules** editor and **keybinds editor** that write to the compositor's config.
- **Display configuration** GUI (`Modules/Settings/DisplayConfig/`, 9 files) via wlr-output-management.
- **dank16** — a terminal 16-color scheme generator in the Go backend.
- **Blur**: `BlurService`, `BlurredWallpaperBackground`, `BlurredWallpaperLive`, plus a
  `niri-wpblur.kdl` shipped for Niri.
- **Polkit agent** (`Services/PolkitService.qml`, `Modals/PolkitAuth*.qml`).

### 2.2 Architecture

**Two-process split.** A Go daemon (`dms`) owns all system integration and exposes a JSON-RPC API
over a Unix socket at `/tmp/dms-ipc-<uid>.sock`. QML services are thin clients.

Go backend (`core/`, per `AGENTS.md`):
- `cmd/dms/` — CLI with 20+ subcommands; `cmd/dankinstall/` — TUI installer for 6 distros.
- `internal/` — 23 packages: `clipboard/` (ext-data-control-v1), `colorpicker/` (native Wayland),
  `screenshot/`, `brightness/` (DDC/CI + backlight), `bluez/`, `config/`, `dank16/`, `deps/`,
  `distros/`, `greeter/`, `keybinds/`, `matugen/`, `notify/` (notification daemon), `plugins/`,
  `server/` (15+ IPC submodules), `themes/`, `wayland/`, `windowrules/`.
- Native Wayland protocol clients: `wlr-gamma-control`, `wlr-screencopy`, `wlr-layer-shell`,
  `wlr-output-management`, `wlr-output-power-management`, `ext-data-control-v1`, `ext-workspace-v1`,
  `dwl-ipc-unstable-v2`, `keyboard-shortcuts-inhibit`, `wp-viewporter`.
- D-Bus clients: `org.bluez` (with pairing agent), NetworkManager, iwd, systemd-networkd,
  `org.freedesktop.login1`, Accounts, portal. D-Bus server: `org.freedesktop.ScreenSaver`
  (inhibition during media playback).

**This is the biggest strategic decision in DMS.** It buys robustness (real Wayland protocol clients
instead of shelling out; clipboard and screenshot without cliphist/grim) at the cost of a second
language, a build toolchain, and a daemon lifecycle. For forest-shell this is a fork in the road:
QML-only + external CLIs (Noctalia/caelestia model) vs. a companion daemon (DMS model).

QML frontend layout:

```
shell.qml            # 60 lines: three Loaders (wallpaper, ShellCore, DMSShell) + greeter branch
ShellCore.qml        # ~350 lines, core orchestration
DMSShell.qml         # ~32k, the actual surface tree
DMSShellIPC.qml      # ~75k, all IpcHandlers
Common/              # 40 files: Theme, SettingsData, SessionData, Paths, Anims, ModalManager,
                     #   PopoutManager, OSDManager, TrayMenuManager, DankSocket, I18n + .js helpers
Services/            # 63 flat singletons
Modules/             # DankBar, ControlCenter, DankDash, Notifications, OSD, Dock, Lock, Greetd,
                     #   Settings, Plugins, ProcessList, Notepad, Frame, WorkspaceOverlays, Network,
                     #   AppDrawer, BuiltinDesktopPlugins
Modals/              # Full-screen overlays
Widgets/             # 61-file reusable kit, all `Dank`-prefixed
matugen/             # configs/ (24 app configs) + templates/ (26 templates)
PLUGINS/             # 14 example plugins
translations/, assets/, scripts/, systemd/, Shaders/
```

**Staged async startup** is worth copying. `shell.qml` loads the wallpaper synchronously (so there is
never a flash of empty background), then loads `ShellCore.qml` asynchronously, and only when that
finishes does it set the source of `DMSShell.qml` with `core` injected. Env pragmas are declared at
the top of `shell.qml` (`QSG_RENDER_LOOP=threaded`, `QT_MEDIA_BACKEND=ffmpeg`, VAAPI hints,
`UseQApplication`, `AppId`).

**Settings and persistence.** Two generations coexist, which is instructive:
- Legacy: `Common/SettingsData.qml`, **3719 lines**, one `onXChanged: saveSettings()` handler per
  property. `~/.config/DankMaterialShell/settings.json` is a **flat object with 381 top-level keys**
  (`showLauncherButton`, `blurBorderOpacity`, `niriLayoutGapsOverride`, …).
- Newer: `Common/settings/SettingsSpec.js` declares a `SPEC` table — `{ def, coerce, onChange,
  persist }` per key — and `SettingsStore.js` does generic `parse`/`toJson`/`migrateToVersion`
  against it. The same pattern for session state (`SessionSpec.js`/`SessionStore.js`).

  ```js
  matugenScheme:  { def: "scheme-tonal-spot", onChange: "regenSystemThemes" },
  cornerRadius:   { def: 16, onChange: "updateCompositorLayout" },
  popupTransparency: { def: 1.0, coerce: percentToUnit },
  ```

  **The spec-table approach is the one to copy** — it collapses defaults, coercion, change reactions,
  migration and serialization into one declaration per setting. The 3719-line file is what you get
  without it.

**Theming.** `Common/Theme.qml` (2657 lines) is the M3 token singleton — `primary`, `surface`,
`surfaceContainer{Lowest,Low,,High,Highest}`, `primaryContainer`, `outline`, `onSurface_12/38`,
semantic `error`/`warning`/`info`/`success`, plus derived hover/pressed states via `withAlpha` and
`blend` helpers. Colors come from matugen output, a stock theme (`Common/StockThemes.js`), or a user
custom theme file; the shell falls back to computed values (`blend(...)`) for tokens matugen does not
emit.

`matugen/configs/*.toml` + `matugen/templates/*` theme 24 external apps: alacritty, dgop, emacs,
equibop, firefox, foot, ghostty, gtk3 (dark+light, with `gtk3-assets/`), hyprland, kcolorscheme,
kitty, mangowc, neovim, niri, pywalfox, qt5ct, qt6ct, vencord, vesktop, wezterm, zed, zenbrowser,
plus a built VS Code extension (`dms-theme.vsix`, `vsix-build/`).

**IPC.** `DMSShellIPC.qml` declares 28 targets / **194 functions**: `bar`, `clipboard`, `dankdash`,
`dash`, `defaultApp`, `desktopWidget`, `dock`, `file`, `hypr`, `inhibit`, `keybinds`, `launcher`,
`mic`, `mpris`, `notepad`, `outputs`, `plugins`, `powermenu`, `powerprofile`, `processlist`,
`screenshot`, `settings`, `spotlight`, `systemupdater`, `toast`, `tray`, `welcome`, `widget`.
Invoked as `dms ipc <target> <method>`.

**Keybinds.** `Services/KeybindsService.qml` **owns a managed keybind file** per compositor:
`~/.config/niri/dms/binds.kdl`, `~/.config/hypr/dms/binds.conf`, `~/.config/mango/dms/binds.lua`.
The shell reads, edits, validates and rewrites it from a GUI settings tab, and can repair a broken
include in the user's main config. It also parses the compositor's full bind list to power the
keybind cheatsheet modal. This is a genuine DE-grade feature almost nobody else has.

**Plugins.** `plugin.json` manifest with `id`, `name`, `version`, `type` (`launcher` | `daemon` |
widget | control-center), `component`, `settings`, `icon`, `trigger` (launcher prefix),
`capabilities`, and a `permissions` array (`settings_read`, `settings_write`, …). Loaded from
`$XDG_CONFIG_HOME/DankMaterialShell/plugins/`. `Modules/Plugins/` provides the settings primitives
(Toggle/Slider/String/Color/Selection/List) so plugin authors declare settings rather than build UI.

**Socket robustness.** `Common/DankSocket.qml` wraps Quickshell's `Socket` with exponential backoff
reconnect (400 ms base, 15 s cap, jitter). Necessary because the Go daemon can restart independently.

### 2.3 External tools

Hard deps (`pacman -Qi dms-shell`): `dgop`, `accountsservice`, `hicolor-icon-theme`, `python`,
`qt6-declarative`, `quickshell` (upstream — no fork).
Optional: `cava`, `cups-pk-helper`, `i2c-tools`, `iwd`, `matugen`, `networkmanager`,
`power-profiles-daemon`, `qt6-multimedia`, `qt6ct`, `systemd`, `wtype`.

Invoked from QML (by frequency): `niri` (76), **`dms` (65 — its own Go CLI)**, `matugen` (37),
`khal` (12), **`dgop` (9 — the author's separate Go system-monitor tool)**, `loginctl`, `hyprctl`,
`systemctl`, `gsettings`, `dconf`, `wpctl`, `pactl`, `notify-send`, `curl`, `xdg-open`, `swww`,
`swaybg`, `swaymsg`.

The key observation: **clipboard, screenshot, brightness, color picking, night mode, notifications
and DPMS all go through `dms`, not through cliphist/grim/brightnessctl/wlsunset.** DMS replaced the
usual CLI zoo with one Go binary.

**Action catalog.** `Common/KeybindActions.js` is effectively a written-down definition of "what a
DE-grade shell must expose". Action types are `dms` / `compositor` / `spawn` / `shell`, and the DMS
action list covers: launcher + spotlight bar (toggle/open/close), 10 default-app launches (browser,
file manager, mail, calendar, text editor, PDF, image, video, music), clipboard, notifications, task
manager, settings, power menu, control center, notepad (+expand/collapse), dashboard (per-tab),
wallpaper browser + next/prev, file browse (wallpaper/profile), color picker, keybinds cheatsheet,
lock (+ lock & outputs off + demo), idle inhibit, volume/mic/player volume at 1/5/10% steps, output
cycling, brightness at 1/5/10% + exponential toggle, theme light/dark/toggle, night mode, bar
show/hide/auto-hide per index, dock show/hide/auto-hide, full MPRIS transport, screenshots
(interactive/screen/window), compositor overview, workspace rename. It additionally embeds the
**compositor's own** action vocabulary (`NIRI_ACTIONS`, Hyprland equivalents) so users bind window
management from the shell's GUI.

---

## 3. caelestia-dots/shell

Repo: <https://github.com/caelestia-dots/shell>, with a companion Python CLI
(<https://github.com/caelestia-dots/cli>) and dotfiles repo
(<https://github.com/caelestia-dots/caelestia>). Hyprland-only. Architecturally the most interesting
of the four: **a QML shell plus a substantial C++ QML plugin**, with theming pushed out to the CLI.

### 3.1 Feature inventory

**Bar** — vertical, left edge. Entries ordered by a `bar.entries` list of `{id, enabled}`:
`logo`, `workspaces`, `spacer`, `activeWindow`, `tray`, `clock`, `statusIcons`, `power`.
Workspaces support per-monitor mode, window icons (regex → Material icon), an active trail, special
workspaces, and custom labels. `statusIcons` bundles caps/num lock, audio, mic, keyboard layout,
network, wifi, bluetooth, battery. Scroll on the bar changes workspace (top half), volume, or
brightness. Bar popouts: ActiveWindow, Audio, Battery, Bluetooth, Network (wireless + ethernet +
password prompt), LockStatus, KbLayout, TrayMenu.

**Launcher** — bottom-center, single search field, mode-switched by prefix (`>` actions, `@` special):
apps (default), `>calc` (libqalculate), `>scheme` (color scheme picker), `>variant` (M3 variant
picker), `>wallpaper` (wallpaper picker with live color preview). App search has field-scoped
sub-filters: `@i` id, `@c` categories, `@d` comment, `@e` exec, `@w` window class, `@g` generic name,
`@k` keywords, `@t` terminal apps. Favourites, hidden apps, vim keybinds, and per-category choice of
fzf vs fuzzysort. **Frecency ranking is backed by a real SQLite database** (`AppDb`, C++, at
`~/.local/state/caelestia/apps.sqlite`).

**Notifications** — Quickshell `NotificationServer` with actions, body markup, images and hyperlinks.
Persisted to JSON with a 1 s debounce. Popups suppressed on DND, when a sidebar is open, or when
fullscreen. The **sidebar is the notification center** (grouped by app, swipe-to-dismiss, expand
thresholds). Notifications also appear on the lock screen.

**OSD** — right-edge vertical stack of three sliders: speaker volume, mic volume, brightness. Each
has its own scroll target.

**Dashboard** — top-center, tabbed: Dash (datetime, calendar, user profile, media, resources,
weather), Media (details, **cava-driven visualiser around the cover art**, lyrics with a fetcher and
selector), Performance (CPU/GPU hero card, memory, storage, network sparklines, battery), Weather.

**Utilities panel** — bottom-right, three toggleable cards: keep-awake with elapsed timer, screen
recorder control + recording browser, and a quick-toggles grid (`wifi`, `bluetooth`, `mic`,
`settings`, `gameMode`, `dnd`, `vpn`).

**Lock screen** — `WlSessionLock`. Left column weather + fetch + media, center clock/profile/password,
right column resources + notifications. **Three PAM contexts**: `passwd`, `fprint` (gated on
`fprintd-list`), and `howdy` face unlock (gated on `command -v howdy`), with its own `pam.d` files in
`assets/pam.d/` and optional howdy-on-wake.

**Nexus** — a **full GUI settings application** (61 files) rendered as a `FloatingWindow`, titled
`Nexus — <page>`. Pages registered in `PageRegistry.qml` (metadata) + `PageCompRegistry.qml`
(components), grouped: Appearance (wallpaper & style, color select), Connectivity (network with
ethernet/VPN/saved-networks detail pages, Bluetooth pairing, audio with per-app volumes), System
(updates, plugins — both still placeholders), Shell (panels → dashboard/taskbar/launcher/sidebar/
utilities with drill-down; apps; services; language & region), About.

**Background** — the shell **renders the wallpaper itself** (`CachingImage`; no swww/hyprpaper), plus
an optional desktop clock and a cava-driven bottom visualiser that auto-hides when a non-floating
window exists.

**Area picker** — a **native region selector**, not slurp: a fullscreen `ScreencopyView` overlay that
snaps to Hyprland client rects (`hyprctl cursorpos -j` + `Hypr.toplevels`), supports freeze mode, and
saves the crop via C++ `CUtils.saveItem()`, then either `wl-copy` + `notify-send` or opens `swappy`.

**Other**: session menu (right-edge, configurable icons/commands, logind D-Bus with execDetached
fallback), window info panel with a live `ScreencopyView` preview, an in-shell **toast system**
separate from notifications, and a **game mode** that zeroes Hyprland animations/blur/shadow/gaps and
enables tearing.

**Delegated to the CLI, not in the shell**: clipboard history (`cliphist` + `fuzzel --dmenu`), emoji
picker (`fuzzel --dmenu` over a bundled list), fullscreen screenshot (`grim`), screen recording
(`gpu-screen-recorder`), and a window resizer daemon.

### 3.2 Architecture

```
shell.qml               # ~40-line ShellRoot
components/             # dumb reusable primitives: containers/ controls/ effects/
                        #   filedialog/ images/ misc/ widgets/
modules/                # feature panels: areapicker background bar dashboard drawers
                        #   launcher lock nexus notifications osd session sidebar
                        #   utilities windowinfo
                        #   + Shortcuts, ServiceLoader, IdleMonitors, BatteryMonitor, ConfigToasts
services/               # 18 QML singletons
utils/                  # 8 QML singletons + fzf.js / fuzzysort.js
plugin/src/Caelestia/   # C++ QML plugin, 7 URIs
extras/                 # `version` C++ binary
assets/                 # fonts, gifs, pam.d/, wrap_term_launch.sh
```

Import prefix is `qs.` (`import qs.services`). Three-layer separation is explicit: **components/**
are dumb and styled, **services/ + utils/** are singletons holding all state and side effects, and
**modules/`<feature>`/** are panels following a `Wrapper.qml` (visibility/animation/state) +
`Content.qml` (UI) convention. Some modules carry their own local service singletons
(`modules/launcher/services/{Apps,Actions,Schemes,M3Variants}.qml`) — service scoping by feature.

`modules/drawers/Panels.qml` composes **every on-screen panel into one layer-shell window** with a
shared input mask (`Regions.qml`) and drag/hover handling (`Interactions.qml`), varianted per screen.
This is a meaningfully different topology from Noctalia/DMS, which give each panel its own window.

`modules/ServiceLoader.qml` force-instantiates lazily-loaded singletons at startup — a small but
necessary trick, since a QML singleton that nothing references never runs.

`services/ShellState.qml` is a per-screen state hub: `Variants` over screens producing a
`PersistentProperties` object with per-panel open booleans, plus a `Components` registry that lets
Nexus find and highlight a live widget by `objectName`.

**Config: JSON on disk, C++ objects in memory.** The schema is declared in C++ headers under
`plugin/src/Caelestia/Config/` using macros:

```cpp
CONFIG_PROPERTY(Type, name, default...)         // per-monitor overridable
CONFIG_GLOBAL_PROPERTY(Type, name, default...)  // warns if set on an overlay
CONFIG_SUBOBJECT(Type, name)                    // nested
```

- Persists to `~/.config/caelestia/shell.json` and `~/.config/caelestia/shell-tokens.json`.
- **Per-monitor overrides** at `~/.config/caelestia/monitors/<screen>/shell.json`, using a resolve-mask
  pattern (`syncFromGlobal()` + `m_loadedKeys`) so only keys explicitly present in the overlay shadow
  the global.
- **Hot reload**: `QFileSystemWatcher` on file *and* directory, file-signature check to ignore sibling
  churn, 50 ms debounce, 50 ms retry for partially-written files. Emits
  `loaded`/`loadFailed`/`saved`/`saveFailed`/`unknownOption`, surfaced to the user as toasts by
  `modules/ConfigToasts.qml`.
- **Auto-save**: `connectAutoSave()` recursively connects `propertiesChanged` on every sub-object to a
  500 ms debounced writer. Any QML write to `GlobalConfig.x.y` persists. Unknown keys are preserved on
  rewrite; a 2 s `recentlySaved` cooldown prevents save→watch→reload loops.
- Two QML access paths: `GlobalConfig.bar.persistent` (writable singleton) and `Config.bar.persistent`
  (**read-only attached-property propagator**, `QQuickAttachedPropertyPropagator`, resolving to the
  per-monitor overlay for whatever screen the item tree sits under — set once per window via
  `contentItem.Config.screen: screen.name` and inherited down). `Tokens` mirrors this for design tokens.

**This config system is the single best idea in caelestia.** It is what makes a GUI settings app
tractable: rows just write to `GlobalConfig` and persistence is automatic.

```qml
ToggleRow { checked: Config.bar.persistent; onToggled: GlobalConfig.bar.persistent = checked }
```

**Design tokens** (`plugin/src/Caelestia/Config/tokens.hpp`) are a second user-editable config file
exposing `RoundingTokens`, `SpacingTokens`, `PaddingTokens`, `FontSizeTokens`, `AnimDurationTokens`,
`AnimCurves` (M3 expressive easing as bezier coefficients), `AppearanceTokens`, and `SizeTokens`
(per-component: `sizes.bar.innerWidth`, `sizes.launcher.itemWidth`, `sizes.osd.sliderWidth`, …). Used
as `Tokens.padding.large`, `Tokens.rounding.extraLarge`. `appearance.*.scale` multipliers layer on top.

**Theming — own Material You impl, in the CLI, not matugen.** Color generation is Python in
`cli/src/caelestia/utils/material/` using the `materialyoucolor` package + Pillow, supporting all 9 M3
variants. 14 bundled static schemes. Output → `~/.local/state/caelestia/scheme.json`, which
`services/Colours.qml` watches via `FileView { watchChanges: true }` and loads into `M3Palette`
(all M3 roles + `m3success*` + `term0..15`). A parallel `M3TPalette` implements transparency:
`Colours.layer(colour, layerIdx)` blends by **wallpaper luminance** computed by the C++
`ImageAnalyser`. `Colours.reloadHyprRules()` pushes `layerrule blur`/`ignore_alpha` into Hyprland live
whenever transparency changes. App theming is entirely CLI-side via templates for hyprland, GTK3/4,
Qt, btop, htop, nvtop, cava, fuzzel, thunar, discord (via dart-sass), spicetify, zed, chromium policy,
Papirus folders, plus **terminal OSC escape sequences written to every `/dev/pts/*`** and cached for
replay by `assets/wrap_term_launch.sh`.

**IPC** — two Quickshell-native mechanisms:

1. **`IpcHandler` targets**, invoked as `caelestia shell <target> <fn>` (a thin wrapper over
   `qs -c caelestia ipc call`): `drawers` (toggle/list/isOpen), `nexus`, `toaster`
   (info/success/warn/error), `notifs`, `lock`, `mpris`, `picker`, `wallpaper`, `gameMode`,
   `idleInhibitor`, `brightness` (accepts `0.1`, `+0.1`, `10%`, `+10%`, `10%-`), `audio`, `hypr`.
2. **Hyprland global shortcuts** — `components/misc/CustomShortcut.qml` wraps
   `GlobalShortcut { appid: "caelestia" }`, so binds are `bind = ..., global, caelestia:<name>`. These
   are D-Bus global shortcuts, so **they keep working while the session is locked** — a real advantage
   over `exec`-based binds. Registered: `nexus`, `showall`, `dashboard`, `session`, `launcher`,
   `launcherInterrupt`, `sidebar`, `utilities`, `screenshot`, `screenshotFreeze`, `screenshotClip`,
   `screenshotFreezeClip`, `mediaToggle/Prev/Next/Stop`, `brightnessUp/Down`, `lock`, `clearNotifs`.

The CLI has **no daemon of its own** — `caelestia shell <msg>` just shells out to `qs -c caelestia ipc call`.

**Hyprland integration** goes deeper than the others: `Caelestia.Internal.HyprExtras` is a raw
`QLocalSocket` client for the Hyprland request/event sockets giving `message()`, `batchMessage()`,
`applyOptions(hash)`, `refreshOptions()`, an `options` hash and a `usingLua` flag. Game mode uses
`applyOptions()` to live-patch compositor settings. `hyprdevices.cpp` exposes keyboards with
`capsLock`/`numLock`/`activeKeymap`.

**C++ plugin** (`plugin/src/Caelestia/`, 7 QML URIs):

| URI | Contents |
|---|---|
| `Caelestia` | `CUtils` (screenshot crop-save, findChild, version), `Qalculator` (libqalculate), `AppDb` (SQLite frecency), `Requests` (HTTP), `Toaster`/`Toast`, `ImageAnalyser` (wallpaper luminance) |
| `Caelestia.Config` | `GlobalConfig`, `Config` (attached), `TokenConfig`, `Tokens` (attached), `MonitorConfigManager`, `FontBuilder` |
| `Caelestia.Services` | `BeatTracker` (aubio tempo), `CavaProvider` (libcava), `AudioCollector`/`AudioProvider` (libpipewire capture on a worker thread), `Cpu`, `Gpu`, `Memory`, `Storage`, `SensorsLib` (lm-sensors), `SessionManager` (logind D-Bus + sleep/resume/lock signals), `Lyrics` (lrclib.net, music.163.com, local `.lrc`) |
| `Caelestia.Internal` | `HyprExtras`, `HyprDevices`, `SparklineItem`, `VisualiserBars`, `CircularBuffer`, M3 indeterminate progress ports |
| `Caelestia.Components` | `ButtonRow`, `LazyListView`, `WavyLine` |
| `Caelestia.Blobs` | GPU-shader metaball material (`blob.vert`/`.frag`) — the gooey morphing in Nexus |
| `Caelestia.Images` | `ImageCacher`, `CachingImageProvider` |
| `Caelestia.Models` | `FileSystemModel` (recursive, image-filtered — backs the wallpaper browser) |

Build: CMake ≥ 3.19, C++20, Ninja, Qt 6.9, pkg-config for `libqalculate`, `libpipewire-0.3`, `aubio`,
`libcava`, lm-sensors.

**Idle management is in-shell**: `general.idle.timeouts` is a list of
`{timeout, idleAction, returnAction, inhibitWhenAudio, inhibitWhenCharging, respectInhibitors}`
handled by `modules/IdleMonitors.qml` + logind. No swayidle.

### 3.3 External tools

From the shell: `caelestia` (the CLI — scheme/wallpaper/record), `hyprctl`, `nmcli` (+ `nmcli monitor`
event stream), `ddcutil`, `brightnessctl`, `asdbctl` (Apple Studio Display, optional), `swappy`,
`wl-copy`, `notify-send`, `pidof`, `xmllint` (parsing xkb rules XML), `fish` + `qalc`, `fprintd-list`,
`howdy`, `quickshell --version`, plus `sh` for sysfs reads. Reads `/etc/os-release`, `/sys/class/net/*`,
`/sys/class/dmi/*`, `/proc/*`.

From the CLI: `grim`, `slurp`, `swappy`, `wl-clipboard`, `cliphist`, `fuzzel`, `gpu-screen-recorder`,
`notify-send`, `dart-sass`, `dconf`, `papirus-folders`, `xdg-open`, `dbus-send`, `hyprctl`.
Python deps: `pillow`, `materialyoucolor`.

Network APIs called directly from the shell: `ip-api.com`, `nominatim.openstreetmap.org`,
`open-meteo.com`, `lrclib.net`, `music.163.com`, `img.youtube.com`.

**No matugen, no swww, no grim/slurp in the shell itself, no app2unit.** App launching uses
Quickshell's `DesktopEntry.execute()` directly.

---

## 4. end-4 illogical-impulse (dots-hyprland)

Repo: <https://github.com/end-4/dots-hyprland>, branch `main`. The Quickshell implementation lives at
`dots/.config/quickshell/ii/` in the repo, installed to `~/.config/quickshell/ii/` and run as `qs -c ii`.
(The `ii-ags` branch holds the dead AGS version — ignore it.) User config is
`~/.config/illogical-impulse/config.json`.

This is the most feature-maximalist and the least conventional of the four. It is a dotfiles repo
with a shell inside it, so shell logic and compositor config are deliberately co-designed.

### 4.1 Feature inventory

**Two complete panel families.** `shell.qml` selects one via `Config.options.panelFamily`:
`ii` (the classic Material 3 look, `modules/ii/`) or `waffle` (**a pixel-accurate Windows 11
recreation** with Fluent icons, acrylic, start menu, task view, action center, `modules/waffle/`).
Cycle with `Super+Ctrl+P`. Waffle falls back to `ii` implementations for cheatsheet, OSK, overlay,
screen translator and wallpaper selector.

**Bar** (`modules/ii/bar/`, plus a `verticalBar/` variant): left = distro/custom icon button +
active window (scroll = brightness); center = RAM/swap/CPU ring resources with popup, MPRIS media
pill, workspaces (app icons, number-on-Super-hold), clock + popup, util buttons (**screen snip,
screen record, color picker, OSK toggle, mic mute, dark-mode toggle, performance profile**), battery
+ popup; right = status cluster (sink/source muted, xkb layout, unread count, network, bluetooth),
SNI tray with pin/unpin whitelist, weather. Supports auto-hide, bottom placement, corner styles
(hug/float/plain), borderless, per-monitor lists, and responsive collapsing.

**Overview + launcher** (`modules/ii/overview/`) — one panel hosting both a **workspace overview grid**
with live window thumbnails, drag-to-move windows across workspaces, middle-click close; and the
search widget. Search brain is `services/LauncherSearch.qml`, prefix-dispatched:

| Prefix | Kind | Backend |
|---|---|---|
| (none) | Apps | `DesktopEntries` + fuzzysort |
| `=` / leading digit | Math | `qalc -t` |
| `$` | Shell command | `bash -c`; `sudo` opens a terminal |
| `?` | Web search | configurable engine |
| `;` | Clipboard history | `services/Cliphist.qml` |
| `:` | Emoji picker | `services/Emojis.qml` |
| `/` | Actions | built-ins + user scripts |

Built-in `/` actions: `accentcolor`, `dark`, `light`, `wallpaper`, `konachanwallpaper`, `todo <text>`,
`superpaste N` (paste last N clipboard entries sequentially via ydotool), `wipeclipboard`.
**Any executable dropped in `~/.config/illogical-impulse/actions/` is auto-registered** (watched via
`FolderListModel`) — a very cheap extensibility mechanism.

**Left sidebar** — the AI/utility sidebar, tabs gated by `policies.ai` / `policies.weeb`:
1. **Intelligence** — a full LLM chat: markdown rendering, code blocks with copy/run, `<think>` blocks,
   LaTeX, file attachment, web-search annotations, model picker, temperature, saved chats, prompt picker.
2. **Translator** — `translate-shell` with a language list from `trans -list-languages`.
3. **Anime** — a booru image browser (yande.re, Konachan, Zerochan, Danbooru, Gelbooru, waifu.im) with
   NSFW gate, tag autocomplete, download.

**Right sidebar** — the system sidebar: uptime/distro header with reload and settings buttons; optional
quick sliders (volume/mic/brightness); a **quick-toggles panel in two styles** (classic pill row, or an
Android-14-style resizable drag-reorderable grid) with toggles for AntiFlashbang, Audio, Bluetooth,
CloudflareWarp, ColorPicker, DarkMode, EasyEffects, GameMode, IdleInhibitor, Mic, MusicRecognition,
Network, NightLight, Notification silence, OnScreenKeyboard, PowerProfiles, ScreenSnip; expandable
dialogs for wifi, bluetooth, per-app volume mixer, night light; a notification list; and a collapsible
tabbed bottom group with **Calendar, To Do, and a Pomodoro timer + stopwatch**.

**Region selector** (`modules/ii/regionSelector/`) — one unified tool with rect and circle modes, and
**smart target regions**: it pre-detects Hyprland windows and layers *and* **image content regions via
OpenCV MSER**, so you can one-click-snip a picture inside a webpage. Five actions: Copy
(`magick … | wl-copy`), Edit (`swappy`/`satty`), **Search** (upload to uguu.se, open Google Lens),
**OCR** (`tesseract` across all installed langs → clipboard), and Record / RecordWithSound
(`wf-recorder`).

**Screen translator** (`modules/ii/screenTranslator/`) — grabs the screen, OCRs via **Google Cloud
Vision**, translates via **Google Cloud Translate**, and paints translated text *in place over the
original words*, sampling per-paragraph text color via OpenCV. Auth is a GCP service-account key in
the keyring, exchanged for a token by a Python helper.

**Widget overlay** (`modules/ii/overlay/`, `Super+G`) — a free-floating draggable/resizable widget
canvas whose contents, positions, sizes, pinned and clickthrough flags persist. Widgets: a **gaming
crosshair that parses Valorant crosshair codes**, an FPS limiter, a recorder panel, resource graphs, a
volume mixer, scratch notes, and an arbitrary pinned floating image/GIF.

**Other**: on-screen keyboard (types via `ydotool`), a cheatsheet with a keybind viewer fed by
`hyprctl binds -j` grouped by the `description` field — **plus a periodic table tab**; a dock; a
`WlSessionLock` lock screen with fingerprint PAM that **dispatches every monitor to workspace
2147483647 on lock** so windows aren't visible; a wallpaper selector with breadcrumb file browsing and
thumbnail generation, supporting **video wallpapers via `mpvpaper`**; desktop background widgets
including a Material-expressive analog **"cookie" clock** (configurable N-sided shape, optional AI
styling from Gemini wallpaper categorization) placed by an OpenCV **least-busy-region** analysis;
a session screen; a polkit agent; media controls with a `cava` visualizer; screen corners that double
as clickless sidebar openers; **music recognition via `songrec`**; **anti-flashbang** (both a Hyprland
`screen_shader` and a backlight-scaling scheme driven by screenshot lightness analysis); night light
via `hyprsunset`; a **conflict killer** that detects and offers to kill `kded6`/`mako`/`dunst`; an
update checker; LaTeX rendering via MicroTeX; a separate settings app (`qs -p settings.qml`); i18n
across 14 locales with **AI-generated translations on demand**; and a **work-safety mode** that blurs
NSFW wallpapers and clipboard images when connected to a matching SSID.

Screen zoom is *not* in the shell — it's a Hyprland keybind mutating `cursor:zoom_factor`.

### 4.2 Architecture

```
shell.qml            # ShellRoot: picks panel family, bootstraps singletons
settings.qml         # standalone settings app
welcome.qml, killDialog.qml, GlobalStates.qml, ReloadPopup.qml
panelFamilies/       # IllogicalImpulseFamily.qml, WaffleFamily.qml, PanelLoader.qml
modules/
  common/            # family-agnostic: Config, Appearance, Directories, Persistent, Icons, Images
    functions/       # ColorUtils DateUtils FileUtils Fuzzy NotificationUtils Session StringUtils …
    models/          # LauncherSearchResult, WorkspaceModel, quickToggles/, gCloud/, hyprland/
    panels/lock/     # shared lock screen
    utils/           # ScreenshotAction, TempScreenshotProcess, ImageDownloaderProcess
    widgets/         # ~120 M3 widgets + widgetCanvas/ + shapes/ (git submodule)
  ii/                # panel family "ii"
  waffle/            # panel family "waffle"
  settings/          # settings app pages
services/            # ~55 QML singletons + ai/ gCloud/ network/ subfolders
scripts/             # ai/ cava/ colors/ hyprland/ images/ keyring/ musicRecognition/
                     #   thumbnails/ videos/
defaults/ai/prompts/, assets/icons/, translations/
```

Per-panel convention: a `Scope` containing a `Loader`/`Variants` over screens producing a
`PanelWindow`, **with its own `IpcHandler` and `GlobalShortcut`s declared at the bottom of the same
file**, and content split into a sibling `XxxContent.qml`. This co-locates a feature's trigger surface
with its implementation — the opposite of Noctalia/DMS, which centralize IPC in one big file. Both
work; co-location scales better per-feature, centralization is easier to audit.

`PanelLoader.qml` is just `LazyLoader { active: Config.ready && extraCondition }`, so **nothing is
instantiated until the JSON config has loaded**. Clean fix for the "renders once with defaults, then
snaps" problem.

**Services are QML singletons** (`pragma Singleton`), no checked-in `qmldir` files.
`GlobalStates.qml` is a central open/closed state bag (`sidebarLeftOpen`, `overviewOpen`,
`overlayOpen`, `screenLocked`, `superDown`, …) — panels bind `Loader.active` to it, and keybinds/IPC
just flip booleans. `services/GlobalFocusGrab.qml` manages **a single shared `HyprlandFocusGrab`**
with "persistent" (bar, OSK) vs "dismissable" (sidebars, cheatsheet) participants — this solves the
"many layer-shell panels fighting over focus" problem, which is a real and non-obvious issue.

**Config.** Two JSON files, both `FileView` + `JsonAdapter`:

| File | Singleton | Purpose |
|---|---|---|
| `~/.config/illogical-impulse/config.json` | `modules/common/Config.qml` | user settings (633-line schema) |
| `~/.local/state/quickshell/states.json` | `modules/common/Persistent.qml` | runtime state (AI model, overlay widget geometry, pomodoro, sidebar tab, …) |

```qml
FileView {
    path: Directories.shellConfigPath
    watchChanges: true
    onFileChanged:    fileReloadTimer.restart()   // 50 ms debounce → reload()
    onAdapterUpdated: fileWriteTimer.restart()    // 50 ms debounce → writeAdapter()
    onLoaded:         root.ready = true
    onLoadFailed: e => if (e == FileViewError.FileNotFound) writeAdapter()  // self-seeds defaults
    JsonAdapter { … }
}
```

Fully bidirectional and hot: editing the JSON live-updates the shell, and any UI toggle writes back.
Shell scripts mutate the same file with `jq`. `Config.setNestedValue("bar.borderless", "true")` is the
dotted-path setter used by the launcher and the AI tool. The **self-seeding on FileNotFound** is a neat
trick — no separate "write default config" step. Same split as Noctalia (user intent vs runtime state).

**Theming — matugen plus its own Python layer.** Driven by `scripts/colors/switchwall.sh`:
1. Optional scheme auto-detection (`scheme_for_image.py`, OpenCV colorfulness heuristic → one of 8
   `scheme-*` variants).
2. `gsettings` for GTK color-scheme/theme.
3. **`matugen`** renders `~/.config/matugen/config.toml` templates → `colors.json` (what the shell
   reads), `hyprland/colors.lua`, hyprlock colors, fuzzel, gtk3/gtk4, KDE, wallpaper path.
4. `generate_colors_material.py` (venv: `materialyoucolor`, PIL) produces **terminal** colors
   (`term0..15`) with harmony/threshold/fg-boost knobs.
5. `applycolor.sh` writes kitty theme + escape sequences to every `/dev/pts/*`, `SIGUSR1` to kitty.
6. `kde-material-you-colors` for Qt/KDE apps; a script for VS Code.

Shell side, `services/MaterialThemeLoader.qml` `FileView`-watches `colors.json` and assigns into
`Appearance.m3colors`; `modules/common/Appearance.qml` derives the whole design system — layered
colors (`colLayer0/1/2` + Hover/Active/Border), rounding, sizes, fonts, and M3 expressive animation
curves. **Transparency is auto-computed from wallpaper vibrancy** via a `ColorQuantizer` and a fitted
quadratic.

**IPC and keybinds.** IPC targets (`qs -c ii ipc call <target> <fn>`): `panelFamily`, `bar`, `search`,
`sidebarLeft`, `sidebarRight`, `mediaControls`, `cheatsheet`, `osk`, `osd`/`osdVolume`, `overlay`,
`region`, `screenTranslator`, `session`, `lock`, `wallpaperSelector`, `wallpapers`, `brightness`,
`theme`, `mpris`, `cliphistService`.

Global shortcuts are registered by name and invoked from Hyprland as `global, quickshell:<name>`.
**Hyprland config is now Lua**, not hyprlang — `hyprland.lua` requiring `hyprland/{env,execs,general,
rules,colors,keybinds}.lua`, with user overrides in `hypr/custom/*.lua`:

```lua
local qsIsAlive = "qs -c $qsConfig ipc call TEST_ALIVE"
hl.bind("SUPER + Tab", hl.dsp.global("quickshell:overviewWorkspacesToggle"),
        {description = "Shell: Toggle overview"})
-- every shell binding has a non-Quickshell fallback:
hl.bind("SUPER + V", hl.dsp.exec_cmd(qsIsAlive .. " || pkill fuzzel || cliphist list | fuzzel … | wl-copy"))
```

**The `qs ipc call TEST_ALIVE || <fallback>` idiom is worth stealing** — the WM config stays usable
when the shell isn't running, which matters enormously during development.

Two feedback loops back into Hyprland: `services/HyprlandConfig.qml` writes to
`~/.config/hypr/hyprland/shellOverrides/main.lua` via `hyprconfigurator.py --set/--reset` (marked
"DO NOT EDIT — MANAGED BY THE SHELL"), used for the anti-flashbang shader and damage tracking; and
`services/HyprlandData.qml` polls `hyprctl clients/monitors/layers/workspaces -j` for data Quickshell
doesn't expose.

Clipboard is watched from the compositor autostart, not the shell:

```
wl-paste --type text  --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'
wl-paste --type image --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'
```

**Python helpers** run in a dedicated venv at `~/.local/state/quickshell/.venv` (installed with `uv`).
Notable: `find_regions.py` (OpenCV MSER content detection for the snip tool), `least_busy_region.py`
(desktop widget placement + dominant color), `text_color.py` (screen translator), `thumbgen.py`,
`hyprconfigurator.py`, `generate_colors_material.py`, `scheme_for_image.py`. venv deps include
`opencv-contrib-python`, `numpy`, `materialyoucolor`, `pillow`, `google-auth`, `libsass`,
`kde-material-you-colors`. **No first-party C++** — the only native component is third-party MicroTeX.

**AI subsystem** (`services/Ai.qml` + `services/ai/`) uses a strategy pattern (`ApiStrategy` base with
Gemini/OpenAI/Mistral implementations), auto-discovers locally installed **Ollama** models, and
supports arbitrary OpenAI-compatible endpoints. Requests are made by **writing a bash script to
`/tmp/quickshell/ai/request.sh` and running it with `curl --no-buffer`**, stream-parsed via
`SplitParser` — a workaround for QML's lack of a streaming HTTP client. API keys live in the system
keyring via `secret-tool`, injected as the process's `API_KEY` env var. Tool calling includes
`get_shell_config`, `set_shell_config(key,value)` and `run_shell_command`. `policies.ai` gates it:
`0` disabled, `1` enabled, `2` local-only.

### 4.3 External tools

The longest dependency list of the four, organized into `illogical-impulse-*` meta-packages:

- **Hyprland/Wayland**: `hyprctl`, `hyprsunset`, `hyprpicker`, `hyprshot`, `hypridle`, `hyprlock`,
  `wl-copy`/`wl-paste`, `grim`, `slurp`, `wf-recorder`, `wtype`, `ydotool`
- **Image/capture**: `magick` + `identify`, `tesseract`, `swappy`, `satty`, `ffmpeg`, `mpvpaper`
- **Theming**: **`matugen`**, `gsettings`, `kde-material-you-colors`, `kitty`, `kdialog`
- **Audio/media**: `wpctl`, `pactl`, `playerctl`, `cava`, `songrec`, `easyeffects`
- **System**: `brightnessctl`, `ddcutil`, `nmcli`, `warp-cli`, `secret-tool`, `loginctl`, `systemctl`,
  `checkupdates`
- **Generic**: `bash`, `jq`, `bc`, `curl`, `wget`, `qalc`, `trans` (translate-shell), `cliphist`,
  `fuzzel` (fallback launcher), `wlogout` (fallback session), `notify-send`, `xdg-open`, `python3`
- **Other**: `/opt/MicroTeX/LaTeX`, `geoclue`, `gnome-keyring-daemon`

Python venv: `pillow`, `materialyoucolor`, `material-color-utilities`, `libsass`,
`kde-material-you-colors`, `numpy`, `opencv-contrib-python`, `google-auth`, `requests`, `psutil`,
`pywayland`, `pycairo`, `pygobject`.

---
## 5. Comparison summary

### 5.1 At a glance

| | Noctalia | DMS | caelestia | illogical-impulse |
|---|---|---|---|---|
| Scale (QML) | 418 files / ~119k lines | 572 files / ~211k lines | ~200 files | ~400 files across 2 families |
| Native code | none (own QS fork) | **~118k lines Go** | **C++ QML plugin (7 URIs)** | none (3rd-party MicroTeX only) |
| Scripting | Python (theming, calendar) | Go | Python (in the CLI) | **Python venv (OpenCV, MaterialYou)** |
| Compositors | 6 (facade + backends) | 6 | Hyprland only | Hyprland only |
| Quickshell | **own fork (`noctalia-qs`)** | upstream | upstream(-git) | upstream (pinned commit) |
| Config format | nested JSON, 25 sections | **flat JSON, 381 keys** | JSON, C++-declared schema | nested JSON, 633-line schema |
| Config hot reload | yes (debounced FileView) | yes | yes (QFileSystemWatcher + debounce) | yes (debounced FileView) |
| Config migrations | **25 versioned migrations** | spec-table `migrateToVersion` | unknown-key preservation | none found |
| Per-monitor config | partial (bar monitors list) | partial | **yes, full overlay system** | partial (screenList) |
| Settings GUI | yes (in-shell panel, 24 tabs) | yes (57 files, ~45 tabs) | yes (**Nexus**, 61 files, floating window) | yes (separate `qs -p settings.qml` app) |
| Color generation | **own Python Material You** | matugen | **own Python Material You (in CLI)** | matugen + own Python layer |
| App theme templates | 31 | 24 + a VS Code `.vsix` | ~20 + terminal OSC | ~10 + terminal OSC |
| Wallpaper rendering | **in-shell + GPU shaders** | in-shell (+ swww/swaybg paths) | **in-shell** | **in-shell** (+ mpvpaper for video) |
| Screenshot | none (external) | **own Go, wlr-screencopy** | **native picker + C++ crop** | grim + magick + OCR/Lens |
| Clipboard | cliphist | **own Go, ext-data-control-v1** | cliphist (via CLI) | cliphist (watched from WM autostart) |
| Plugin system | yes (~100 plugins, git registry) | yes (typed manifest + permissions) | no | user action scripts only |
| IPC | 29 targets | 28 targets / 194 fns | 13 targets + D-Bus global shortcuts | ~20 targets + global shortcuts |

### 5.2 The union feature list — the "DE-grade bar"

Ordered by how many of the four ship it. **4/4 = table stakes; anything at 1/4 is a differentiator,
not an obligation.**

**Tier 1 — all four ship it. Non-negotiable for a DE-grade shell.**

- Status bar: workspaces (with per-monitor awareness), active window, clock, system tray (SNI + DBusMenu),
  battery, network, bluetooth, volume/mic, and a settings/launcher entry point
- Bar configurability: per-monitor placement, orientation or position, auto-hide, widget ordering
- Application launcher with fuzzy search, plus at minimum a calculator mode
- Notification daemon: popups, history/center, DND, actions, images, per-app grouping, **persistence to disk**
- OSD for volume and brightness
- Control center / quick toggles: wifi, bluetooth, audio, brightness, DND, night light, idle inhibit
- Lock screen (`WlSessionLock` + PAM)
- Session/power menu (logind D-Bus)
- Wallpaper handling **rendered by the shell itself** — none of the four uses swww as the primary path
- Wallpaper-derived Material You theming, propagated to external apps via templates
- Light/dark mode toggle
- Media/MPRIS controls with cover art
- Weather
- Calendar
- System resource monitoring: CPU / RAM / disk / temperatures
- Audio visualizer via cava
- Multi-monitor via `Variants { model: Quickshell.screens }`
- A GUI settings application
- IPC surface + compositor keybind integration
- A reusable, prefixed widget kit (`N*`, `Dank*`, `Styled*`, M3 widgets)

**Tier 2 — three of four. Expected in a mature shell.**

- Dock with pinned + running apps (Noctalia, DMS, end-4)
- Desktop widgets on the wallpaper (Noctalia, DMS, end-4)
- Clipboard history UI (DMS, caelestia, end-4)
- Emoji picker (Noctalia, caelestia, end-4)
- Screen recorder control (DMS, caelestia, end-4)
- Idle management with configurable timeouts and inhibitors (caelestia and end-4 in-shell; DMS in Go)
- Toast system distinct from freedesktop notifications (Noctalia, DMS, caelestia)
- Polkit agent (DMS, caelestia via logind, end-4)
- Per-app volume mixer (DMS, caelestia, end-4)
- Plugin or extension system (Noctalia, DMS; end-4 has drop-in action scripts)
- Setup wizard / first-run experience (Noctalia, DMS, end-4)
- i18n (Noctalia, DMS, end-4)

**Tier 3 — one or two. Differentiators, deliberately chosen.**

- Screenshot / region picker built into the shell (DMS, caelestia, end-4)
- Keybind cheatsheet from `hyprctl binds -j` (DMS, end-4)
- **Keybind editor that writes the compositor config** (DMS)
- Display configuration GUI via wlr-output-management (DMS)
- Workspace overview overlay (DMS, end-4)
- Greeter / display manager (DMS)
- Task manager / process list (DMS, end-4 partially)
- File browser (DMS)
- Notepad / scratchpad (DMS, end-4)
- Printer management (DMS)
- Window rules editor (DMS)
- tmux/zellij session manager (DMS)
- Fingerprint and face unlock (Noctalia fprintd; caelestia fprintd + howdy; end-4 fprintd)
- Wallpaper browser fetching from the internet (Noctalia/Wallhaven, end-4/Konachan)
- Lyrics fetching (caelestia)
- Beat detection / tempo via aubio (caelestia)
- AI chat sidebar (end-4)
- Screen OCR + translation overlay (end-4)
- Gaming crosshair overlay, FPS limiter (end-4)
- Game mode that live-patches compositor settings (caelestia, end-4)
- Anti-flashbang (end-4)
- Music recognition (end-4)
- Second complete UI skin / panel family (end-4)
- Periodic table (end-4 — included for calibration on how far the tail goes)

### 5.3 Architecture patterns worth copying

**1. Three-layer separation, consistently applied.** All four converge on the same shape under
different names:

| Layer | Noctalia | DMS | caelestia | end-4 |
|---|---|---|---|---|
| Dumb reusable UI | `Widgets/` (`N*`) | `Widgets/` (`Dank*`) | `components/` | `modules/common/widgets/` |
| State + side effects | `Services/` | `Services/` | `services/` + `utils/` | `services/` |
| Screen-attached panels | `Modules/` | `Modules/` + `Modals/` | `modules/` | `modules/<family>/` |
| Shared tokens/config | `Commons/` | `Common/` | `plugin/…/Config` + `Tokens` | `modules/common/` |

Establish this on day one. The distinction that matters most is **"dumb widget" vs "panel"**: dumb
widgets never read config or services directly and can be reused anywhere.

**2. Services as `pragma Singleton`.** Universal across all four. Corollaries worth noting:
- **Group services by domain once you exceed ~20.** Noctalia's `Services/{Compositor,Hardware,Media,
  Networking,Power,System,Theming,UI,…}/` is far more navigable than DMS's flat 63 files.
- **A singleton nothing references never initializes.** caelestia solves this with an explicit
  `ServiceLoader.qml`; Noctalia with explicit `init()` calls in `shell.qml`. Pick one and be
  consistent — implicit instantiation order is a recurring source of bugs.
- **Scope feature-local services to the feature.** caelestia's
  `modules/launcher/services/Apps.qml` is right: not everything belongs in the global namespace.

**3. Registry + loader for anything user-orderable.** Noctalia's `BarWidgetRegistry` (name →
`Component`, plus name → settings QML path) with a `BarWidgetLoader` that resolves by name is the
pattern that makes GUI bar customization tractable, and it is what plugins hook into. Repeat it for
control-center tiles, desktop widgets, and launcher providers.

**4. Provider / prefix-based launcher.** Noctalia (8 provider files), caelestia (`>`/`@` prefixes),
end-4 (7 prefixes) and DMS (plugin sources with a `trigger` field) all converge on this. Build the
launcher as a dispatcher over pluggable providers from the start; retrofitting is painful.

**5. A declarative settings spec, not per-property boilerplate.** The clearest lesson in the set.
DMS shows both the wrong and the right answer in the same codebase: a 3719-line `SettingsData.qml`
with one `onXChanged: saveSettings()` per property, alongside a newer `SettingsSpec.js`:

```js
matugenScheme:     { def: "scheme-tonal-spot", onChange: "regenSystemThemes" },
cornerRadius:      { def: 16, onChange: "updateCompositorLayout" },
popupTransparency: { def: 1.0, coerce: percentToUnit },
```

One declaration per setting yields defaults, coercion, change reactions, serialization and migration
generically. caelestia achieves the same in C++ with `CONFIG_PROPERTY` macros plus a recursive
auto-save that makes *any* write persist. **Design this before writing the second setting.**

**6. Split user config from runtime state.** Three of four do this explicitly:
`~/.config/noctalia/settings.json` vs `~/.cache/noctalia/shell-state.json` (Noctalia);
`Common/SettingsData` vs `SessionData` (DMS); `Config.qml` vs `Persistent.qml` →
`~/.local/state/quickshell/states.json` (end-4). Panel open/closed state, last-selected tab, window
geometry and cached lists are *not* user preferences and must not churn the config file.

**7. Debounced, bidirectional `FileView` + `JsonAdapter`.** The shared idiom:

```qml
FileView {
    path: configPath
    watchChanges: true
    onFileChanged:    reloadTimer.restart()    // debounce 50-200ms
    onAdapterUpdated: writeTimer.restart()
    onLoadFailed: e => if (e == FileViewError.FileNotFound) writeAdapter()  // self-seed defaults
    JsonAdapter { }
}
```

Debouncing is mandatory, not optional: editors write atomically (write temp + rename), which fires both
a file *and* a directory event. caelestia goes further with a file-signature check, a retry loop for
partially-written files, and a 2 s post-save cooldown to break save→watch→reload loops. **Budget for
all three.**

**8. Versioned config migrations.** Noctalia is at `settingsVersion: 59` with 25 migration files.
Critically, it parses the **raw JSON separately from the adapter**, because `JsonAdapter` silently drops
keys that no longer exist in the schema — so migrations that need to read a removed key must see the raw
text. Set this up early; it is very hard to retrofit once users have configs.

**9. A design-token singleton, scaled by user ratios.** Noctalia's `Style.qml` and caelestia's
`Tokens` both expose the full token set — font sizes, weights, **two radius scales** (container vs
input), border widths, margin scale, opacity scale, animation durations, M3 easing curves — with user
multipliers (`radiusRatio`, `uiScaleRatio`, `appearance.*.scale`). caelestia additionally exposes them
as a **second user-editable file** (`shell-tokens.json`). Never hardcode a number in a panel.

**10. A panel broker.** Noctalia's `PanelService` (self-registration by name,
`getPanel(name, screen)`, one-open-at-a-time, fallback screen selection) prevents N×M coupling between
triggers (IPC, bar widgets, keybinds) and panels. end-4's `GlobalStates.qml` boolean bag is the
lighter-weight version of the same idea.

**11. One shared focus grab.** end-4's `GlobalFocusGrab.qml` with "persistent" vs "dismissable"
participants is the non-obvious fix for multiple layer-shell panels fighting over
`HyprlandFocusGrab`. Expect this problem; it appears the moment you have two dismissable popups.

**12. Gate all panel instantiation on config readiness.** end-4's
`LazyLoader { active: Config.ready && … }` and Noctalia's
`Loader { active: i18nLoaded && settingsLoaded && shellStateLoaded }` both prevent the
"renders with defaults, then snaps" flash.

**13. Staged async startup.** DMS loads the wallpaper synchronously (never a bare background), then
`ShellCore` asynchronously, then injects it into the main shell. Noctalia splits critical services
(wallpaper, image cache, theme) from `Qt.callLater`-deferred ones (location, idle, power profile,
GitHub, telemetry) plus a 1500 ms timer for the rest. First-frame time is a real UX property.

**14. Compositor facade even if you only target one.** Noctalia's
`Services/Compositor/CompositorService.qml` over per-compositor backends, and DMS's equivalent, keep
`hyprctl` calls out of 400 files. Worth doing for Hyprland-only, purely as an isolation boundary.

**15. Prefer D-Bus global shortcuts over `exec` keybinds.** caelestia's `GlobalShortcut { appid }` →
`bind = ..., global, caelestia:<name>` and end-4's `quickshell:<name>` avoid a process spawn per
keypress **and keep working while the session is locked**. Use `IpcHandler` for scripting and
introspection; use global shortcuts for interactive keybinds.

**16. Make the WM config degrade gracefully.** end-4's
`qs ipc call TEST_ALIVE || <fallback>` idiom on every binding keeps the compositor usable when the
shell is down — which, during development of a from-scratch shell, is most of the time.

**17. Return JSON from IPC.** Noctalia's `state.all`, `notifications.getHistory`, `wallpaper.get`
make the shell queryable by external scripts and status tools at near-zero cost.

**18. Ship app theme templates.** Every shell does it, and it is a large share of the perceived
polish. The common set: GTK3/4, Qt (qt5ct/qt6ct/kcolorscheme), kitty/foot/alacritty/ghostty,
btop, cava, fuzzel, neovim, zed, discord, spicetify, firefox/zen, plus **terminal OSC escape
sequences written to live `/dev/pts/*`** (caelestia and end-4) for instant retheming of open terminals.

**19. Cache aggressively, and centralize paths.** All four have an image cache service and a `Paths`
singleton resolving XDG dirs. DMS's `Common/Paths.qml` using `QtCore.StandardPaths` is the cleanest.

**20. Reconnect with backoff on any socket.** DMS's `DankSocket.qml` (400 ms base, 15 s cap, jitter)
— necessary for anything that can restart independently.

**21. A launch-prefix setting.** DMS's `SettingsData.launchPrefix` (plus a `DMS_DEFAULT_LAUNCH_PREFIX`
env fallback) lets users route app launches through `app2unit`/`uwsm`/`systemd-run` without the shell
committing to one. It also supports per-app overrides: dGPU offload, extra flags, env vars, and
terminal handling. Cheap to add, and it sidesteps a genuinely contentious design question.

### 5.4 Decisions forest-shell must make explicitly

These are the places where the four genuinely diverge, so there is no default to copy.

**a) Native companion process, or QML + CLIs?**
DMS (Go daemon) and caelestia (C++ QML plugin) both concluded that pure QML plus shelling out is not
enough. They solve different problems: DMS's Go backend replaces the *external tool zoo*
(clipboard, screenshot, brightness, notifications, DPMS all become `dms`); caelestia's C++ plugin adds
*capabilities QML lacks* (SQLite frecency, libqalculate, pipewire capture, aubio, config reflection,
custom shaders). Noctalia proves you can avoid both — at the cost of forking Quickshell and writing
~8.4k lines of Python. **A C++ QML plugin is the cheaper of the two native options** and is where the
highest-leverage wins are (config schema + reflection, image analysis, audio capture).

**b) Matugen, or your own Material You?**
Noctalia and caelestia both wrote their own (Python, `materialyoucolor` or hand-rolled HCT/quantizer).
DMS and end-4 use matugen. Own implementation = no Rust dependency, full control over scheme
variants and terminal color derivation; matugen = far less code and a well-tested template engine.
For a from-scratch shell, **start with matugen and keep the color source behind a service boundary**
(a `ColorService` emitting an M3 palette) so it can be swapped later.

**c) One layer-shell window with all panels, or a window per panel?**
caelestia composes everything into one `PanelWindow` per screen with a shared input-region mask;
Noctalia and DMS give each panel its own window. The single-window approach simplifies focus, input
masking and cross-panel animation; the per-window approach isolates redraws (Noctalia explicitly puts
bar content in a separate window "to prevent fullscreen redraws"). This is hard to change later.

**d) IPC centralized or co-located?**
Noctalia (940 lines) and DMS (75k) centralize all `IpcHandler`s in one file. caelestia and end-4
declare them at the bottom of the panel they control. Co-location scales better per feature;
centralization is easier to audit and document.

**e) Flat or nested config?**
DMS's flat 381-key JSON versus Noctalia's 25-section nested JSON. Nested is clearly better for
navigation and for section-scoped reload, but nesting complicates a generic spec table. caelestia's
answer — a nested schema declared as sub-objects, with a dotted-path setter — is the best of both.

### 5.5 Pitfalls

**Config and settings**

1. **Per-property save boilerplate.** DMS's 3719-line `SettingsData.qml` is the cautionary tale.
   Spec table from the start.
2. **`JsonAdapter` drops unknown keys.** Both a migration hazard (read raw JSON separately, as Noctalia
   does) and a data-loss hazard for hand-edited configs (caelestia explicitly preserves unknown keys
   on rewrite).
3. **Save→watch→reload loops.** Writing the config triggers your own file watcher. Needs a cooldown
   (caelestia uses 2 s) or an explicit "I wrote this" flag.
4. **Atomic writes fire twice.** Editors write-temp-then-rename, producing both a file event and a
   directory event; and the file may be momentarily empty or partial. Debounce plus a retry loop.
5. **No migration path.** Very hard to retrofit once users have configs in the wild.

**Startup and lifecycle**

6. **Rendering before config loads.** Gate everything on a `ready` flag.
7. **Singletons that never initialize** because nothing references them. Force-instantiate explicitly.
8. **Blocking the first frame.** Defer non-critical services (`Qt.callLater` + a timer), as Noctalia does.

**Wayland / compositor**

9. **Rapid layer-shell surface destruction can crash compositors.** Noctalia's `AllScreens.qml`
   carries an explicit comment: the bar window stays alive when hidden (`visible: false`) and content
   is debounce-unloaded *inside* it, precisely to avoid rapid surface create/destroy churn. This is a
   real, reported crash class.
10. **Multiple panels fighting over focus grab.** Needs a single shared arbiter.
11. **Per-monitor lifecycle.** Monitors appear and disappear; `Variants` delegates must handle
    teardown, and panels must have a fallback-screen story (Noctalia's `findFallbackScreen()`).
12. **Exclusion zones interacting with auto-hide.** All four have separate exclusion-zone components
    (`BarExclusionZone`, `FrameExclusions`, `Exclusions`) — it does not stay simple.

**Theming**

13. **Fullscreen redraws from theme changes.** Isolate bar/panel content into their own windows if
    animating colors globally.
14. **Not every M3 token comes out of matugen.** DMS computes missing ones via `blend()` fallbacks —
    plan for a derived layer over the generated palette.
15. **External app theming is unbounded scope.** 31 templates (Noctalia) is a lot of surface area;
    each is an ongoing compatibility burden. Start with GTK, Qt, and terminals.

**Scope**

16. **The tail is enormous.** DMS is 211k lines of QML plus 118k of Go and still has "under
    construction" pages; caelestia's Nexus ships `PlaceholderComp` for Updates and Plugins. Both
    Noctalia's README and caelestia's structure explicitly draw a scope boundary and push the rest to
    plugins — **decide forest-shell's boundary before building, not after.**
17. **A plugin system is a public API.** DMS's manifest with `permissions` and `capabilities`, and
    Noctalia's registry-based entry points, both had to be designed deliberately. Adding one late
    means either breaking plugin authors or freezing internals.
18. **A GUI settings app is roughly a quarter of the shell.** 57 files (DMS), 61 (caelestia Nexus),
    ~90 (Noctalia's tabs + widget settings). It is only tractable on top of a declarative settings
    spec plus registries — which is the strongest argument for getting §5.3 items 3 and 5 right first.
