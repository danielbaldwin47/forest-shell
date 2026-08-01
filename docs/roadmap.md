# Build roadmap

Sources: [#13](https://github.com/danielbaldwin47/forest-shell/issues/13), [#12](https://github.com/danielbaldwin47/forest-shell/issues/12), [#14](https://github.com/danielbaldwin47/forest-shell/issues/14), [#15](https://github.com/danielbaldwin47/forest-shell/issues/15), [#22](https://github.com/danielbaldwin47/forest-shell/issues/22), [#7](https://github.com/danielbaldwin47/forest-shell/issues/7)

Nine phases, ordered for **incremental daily-drivability**: the shell becomes Daniel's daily driver at the end of Phase 1 and stays continuously usable from then on. Every phase ends with the shell bootable and better than before — no phase leaves it broken.

## How to execute a phase

Build sessions are **Claude Opus 5 agent sessions**. A phase is several sessions, not one. Each session:

1. Reads `docs/README.md`, `docs/architecture.md`, `docs/design-system.md`, this phase's entry here, and the feature spec(s) the phase names.
2. Builds one shippable increment — the shell must boot and daily-drive after every session, not just every phase.
3. Runs against the exit gate's measurable criteria before calling work done. Perf numbers are measured on the T480 (`QSG_RENDER_TIMING=1`, Quickshell log timestamps, `powertop`).
4. If reality contradicts a spec, updates the spec doc in the same commit and notes why — `docs/` is the source of truth and must stay true.

Development runs on the `qs-upstream` prefix (see `architecture.md`) until Phase 7 swaps the system package.

## Standing gates (every phase, every session)

These are acceptance criteria permanently in force, not one-time checks:

- **Startup**: first frame (wallpaper + bar) ≤ 1.5 s, interactive ≤ 2 s, cold cache on the T480.
- **Idle**: ≤ 0.5 % CPU (60 s average, all shell processes), < 5 wakeups/s, **zero idle animation** — nothing pulses or loops unattended.
- **Animation**: zero dropped frames at 60 Hz, ≤ 8 ms GPU frame time, on the T480 at 1.5× scale.
- **No QML full-screen blur, ever.** Frosted glass is the optional Hyprland `layerrule = blur`; the shell must look correct with it off.
- **Keep-alive**: layer-shell windows are never created/destroyed at runtime and never move between outputs; hidden windows hold unloaded content and contribute zero wakeups.
- **Config**: every schema change ships its migration; `settings.json` is never rewritten outside migrations and the GUI.
- **Motion**: every new surface implements its row of the `motion.md` table when it lands, not later.
- **Amber is reserved for attention** — no new use of lamplight amber outside the attention cases the specs name.

---

## Phase 0 — Foundation

No visible shell yet; everything later stands on this.

- Repo skeleton per `architecture.md`: `shell.qml` staged startup gated on `Config.ready`; `Core/` (Theme, Config, Paths, Time, Logger, ServiceInit), empty layer directories.
- `Core/Theme.qml` with the full dark token set from `design-system.md`.
- Config system per `architecture.md`: spec table (`{ def, coerce, onChange }`), `settingsVersion: 1`, `Core/Migrations/` registry, sparse atomic writes, hot reload both directions with the save-cooldown, stateDir runtime file, self-seed on missing file.
- Icon pipeline: normalise the 1756 vendored Lucide SVGs **in place** (stroke 1.5, `currentColor` → white; `.wayfinder/prototypes/icon-rendering/preprocess.py` is the working starting point) and ship the name-addressed `Icon` widget (`MultiEffect` colorization, `oversample: 3.0`).
- `Surfaces/Background/`: per-screen wallpaper window.

**Exit gate**: boots via `qs-upstream`; wallpaper renders; a token-styled probe surface shows correct colors, type, and icons; config hot-reloads both directions and self-seeds from nothing; zero-screen survival (lid closed, no outputs) does not crash.

## Phase 1 — Bar

The shell becomes the daily driver at the end of this phase. Spec: `features/bar.md`.

- `Services/Compositor/`: the Hyprland facade — the only place `hyprctl`/dispatch lives. Bind reactively to workspaces/monitors (they populate asynchronously, ~1–3 s; never read once at startup).
- Bar surface: flush 32 px bar, the Standard-14 module inventory, ridgeline workspace indicator, surface treatment per spec; the 4 optional modules present in the registry but off.
- Native services the modules need: tray, MPRIS (mini pill), UPower, PipeWire volume/mic, NetworkManager + BlueZ status, keyboard layout.
- Keybind/IPC scaffolding: co-located `GlobalShortcut`s + `IpcHandler`s; Hyprland bind snippets using the `TEST_ALIVE || fallback` idiom.
- **shell-switch registration** per `shell-switch.md`, last step of the phase.

**Exit gate**: standing startup/idle/animation gates measured and passing; bar correct on external-monitor hotplug and zero-screen; registered in shell-switch and running as the daily driver.

## Phase 2 — Launcher + notifications

Specs: `features/launcher.md`, `features/notifications.md`.

- Shared drawer infrastructure per `architecture.md`: one drawer window per screen, single `HyprlandFocusGrab`, globally exclusive, follows focus, resets on hotplug, cross-drawer choreography per `motion.md`. Launcher is its first tenant.
- Launcher: all six providers. Ask Claude lands as `Services/Claude/` implementing the full CLI contract in the spec; the clipboard `;` provider brings the small cliphist service and the `wl-paste --watch` autostart line with it.
- Notifications: native `NotificationServer`, popups on the focused screen, the right-side notification center, per-app normal/silent/blocked rules, debounced history persistence.

**Exit gate**: drawer open/close holds the animation gate; launcher summonable within the interactive budget; Ask Claude streams a multi-turn conversation on subscription auth; notification matrix (urgency × DND × fullscreen × center-open) behaves per spec.

## Phase 3 — Control center + OSD

Spec: `features/control-center.md`; OSD section of `features/utilities.md`.

- Control center drawer: sliders, 3×3 toggle grid, drill-in detail views, media card, bottom strip. The session/power menu button stays hidden until Phase 4 ships its target.
- Services deepened: brightness (`brightnessctl` helper), power profile, night light, VPN (NetworkManager), DND, wallpaper-set path in `Services/Theming/` (fixed palette still).
- OSD surface: volume/brightness feedback riding the same services.

**Exit gate**: every toggle and slider round-trips real system state; OSD holds the animation gate; idle budget still passes with tray + control center services live.

## Phase 4 — Session & lock

Spec: `features/session-lock.md`.

- `WlSessionLock` lock surface, PAM (`login` stack + runtime-gated fprintd parallel context), 4-stage idle ladder with AC/battery split, the busctl logind helper with the systemd-inhibit delay lock, caffeine (Keep Awake) wiring, lock-screen notification count.
- Session drawer (lock / logout / suspend / reboot / shutdown); the control-center button un-hides.

**Exit gate**: lock → suspend → resume cycle is airtight (locker confirmed before sleep, every output covered); idle ladder fires per settings on both power sources and respects inhibitors; faillock lockout observed; caffeine suppresses the ladder.

## Phase 5 — Dashboard

Spec: `features/dashboard.md`.

- Dashboard drawer with the five registry-configurable cards: month-grid calendar, Open-Meteo weather, native-sampled system monitor, MPRIS media card, date/time header.

**Exit gate**: `/proc` sampling runs only while the dashboard is open (idle budget unchanged when closed); weather failures degrade quietly; card add/remove/reorder round-trips config.

## Phase 6 — Utilities + settings GUI + themes

Specs: `features/utilities.md`, `features/settings.md`.

- Screenshot: native region picker (`ScreencopyView` overlay, window-rect snapping, freeze mode) → clipboard + `~/Pictures/Screenshots`, optional swappy handoff.
- Screen recording: gpu-screen-recorder control surface with wf-recorder fallback; control-center start/stop; the optional bar dot module activates.
- Settings window: ten tabs per spec; theme presets (save/apply/delete, `themes/<name>.json`) with the stateDir undo slot.

**Exit gate**: every GUI control round-trips to sparse `settings.json` writes; hand-editing while the GUI is open converges without fighting; screenshot and recording produce correct artifacts on the T480 (VAAPI).

## Phase 7 — Runtime swap & old-stack retirement

Sources: [#14](https://github.com/danielbaldwin47/forest-shell/issues/14), [#15](https://github.com/danielbaldwin47/forest-shell/issues/15) caveat 7. Entry condition: forest-shell has been the uninterrupted daily driver through Phase 6 with no fallback to Noctalia/DMS.

> **Warning:** this phase removes packages and other shells' runtime. It is executed with Daniel at the keyboard, not autonomously: removing `dms-shell` and `noctalia-shell-git` deletes those shells, and the pacman swap replaces `/usr/bin/qs`.

1. `pacman -Rns dms-shell noctalia-shell-git` (both require the fork and block the swap).
2. `pacman -S quickshell` (replaces `noctalia-qs`; it declares the conflict, pacman handles the swap).
3. Update shell-switch: prune the retired shells' `SHELL_DB` entries; switch forest-shell's launch command from the `qs-upstream` wrapper to plain `qs -p /home/daniel/repos/forest-shell/shell.qml`; `hyprctl reload`.
4. Retire the dev prefix: delete `~/.local/opt/quickshell-upstream` and `~/.local/bin/qs-upstream`.

**Exit gate**: `qs --version` reports upstream Quickshell ≥ 0.3.0; forest-shell relaunches via shell-switch on the system binary; nothing on disk still references the prefix.

## Phase 8 — Dynamic theming

Spec: `features/dynamic-theming.md`. Deliberately last: the shell is complete and stable on the fixed forest palette before palettes start moving.

- `Services/Theming/` grows the constrained-accent mode (native `ColorQuantizer` + Oklab hue-clamp) and the full-dynamic mode (optional matugen); `themingMode` selects fixed / constrained / full-dynamic.
- Appearance-tab wiring; theme presets carry the mode choice.

**Exit gate**: all three modes switch live without restart; constrained-accent output holds the contrast bounds in the spec across the pin wallpapers; **no surface code changed** — palettes flow entirely through `Core/Theme.qml`, proving consumers are mode-blind.
