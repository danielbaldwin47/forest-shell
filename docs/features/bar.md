# Bar

Sources: [#9](https://github.com/danielbaldwin47/forest-shell/issues/9), [#10](https://github.com/danielbaldwin47/forest-shell/issues/10), [#12](https://github.com/danielbaldwin47/forest-shell/issues/12), [#22](https://github.com/danielbaldwin47/forest-shell/issues/22), [#27](https://github.com/danielbaldwin47/forest-shell/issues/27), [.wayfinder/prototypes/bar-ridgeline/findings.md](../../.wayfinder/prototypes/bar-ridgeline/findings.md)

The bar is a flush, full-width horizontal strip at the top of every screen, 32 logical px tall (48 device px at scale 1.5). It carries fourteen modules in three placement groups, a ridgeline workspace indicator, and no warm accent at rest.

## Window and topology

- One `PanelWindow` per screen, layer `overlay`, anchored top/left/right, namespace `forest-shell:bar`. Instantiated per screen and **kept alive** for the process lifetime.
- Exclusive zone = `height` when flush; `height + 2 × floatingMargin` when floating.
- The bar sits **above the fog scrim**. The shared drawer window is on layer `top`; the bar is on `overlay`, so it renders over the scrim and keeps its input region while a drawer is open. The drawer's `HyprlandFocusGrab` must list the bar window among its kept surfaces — clicking a bar icon while a drawer is open triggers the cross-drawer transition directly instead of dismissing.
- **Auto-hide never destroys the window.** Hiding sets `visible: false` and debounce-unloads the content inside; the layer surface is created once. Creating and destroying Wayland layer surfaces on show/hide is a known compositor-crash class.
- Blur, when the compositor provides it, arrives from the unconditional `layerrule = blur, forest-shell:*`. It is a no-op when `decoration:blur:enabled` is off globally, and nothing in the bar depends on it (see Constraints). Per-layer desaturation is not reachable from a layerrule and is not shipped.

## Geometry

| Property | Value |
|---|---|
| Position | top, horizontal, flush full-width |
| Height | 32 logical px |
| Inner horizontal padding | 12 px |
| Module gap | 14 px |
| Icon size | 16 px |
| Label size | 12 px |
| Floating margin (when `flush` is false) | 8 px |
| Floating radius (when `flush` is false) | 10 px (medium radius token) |

26 px crowds the icons against the edges and leaves the ridgeline no room to fall away; 36–40 px reads as a title bar. 32 leaves room for a 14 px active ridgeline unit with 9 px of quiet space beneath it.

## Axis-agnostic widget rule

Every bar module is written against an axis context, never against a hardcoded orientation. A module reads `along` / `across` sizes and an `isVertical` flag from the context its container provides; it never instantiates `Row`/`Column` directly, never sets `width`/`height` where `implicitAlong`/`implicitAcross` will do, and never positions by `x`/`y`. The bar container owns the axis and supplies the layout.

v1 ships `position: "top"` only — the coercer rejects any other value back to `"top"`. A vertical (left/right) bar lands post-v1 by teaching the container a second axis, with **no module rewrites**.

## Module inventory

Fourteen modules in eleven placement slots — the status cluster is one slot carrying four modules (Network, Bluetooth, Volume, Mic) as a single quiet icon group. Placement is a per-group ordered list of registry ids in settings; reordering and moving between groups is a config edit.

| Group | id | Module | Behavior |
|---|---|---|---|
| Left | `launcherButton` | Launcher button | Opens the launcher drawer |
| Left | `workspaces` | Workspaces (ridgeline) | Click switches workspace; scroll cycles occupied workspaces |
| Left | `activeWindow` | Active window | Focused window title, elided; display only |
| Center | `clock` | Clock | Opens the dashboard drawer |
| Center | `mediaMini` | Media mini (MPRIS pill) | Title + play state; click toggles play/pause; hidden when no player |
| Right | `tray` | System tray | StatusNotifierItem host; left-click activates, right-click opens the item menu |
| Right | `statusCluster` | Status cluster | Network + Bluetooth + Volume + Mic as one icon group; click opens the control center |
| Right | `battery` | Battery | Percentage + icon; hidden when no battery is present; click opens the control center |
| Right | `keyboardLayout` | Keyboard layout | Layout code; **auto-hides when only one layout is configured**; click cycles layout |
| Right | `notificationIndicator` | Notification indicator | Unread count; click opens the notification center |
| Right | `controlCenterButton` | Control center button | Opens the control center drawer |

The status cluster's four members are `network`, `bluetooth`, `volume`, `mic`. They are individually addressable in the registry but ship as one slot.

**Wi-Fi signal strength**: Lucide has a single `wifi` glyph and no strength variants. Strength is encoded by icon opacity — strong 1.0, fair 0.72, weak 0.48 — and disconnected uses the `wifi-off` glyph at `text-muted`.

**Battery aggregation**: the module sums across **all present `BAT*` supplies**, never the first one. Reading `BAT0` alone on a T480 reported 5% while the machine ran off `BAT1` at 64%.

### Optional modules — shipped in the registry, off by default

| id | Module | Notes |
|---|---|---|
| `systemMonitor` | CPU/RAM readout | Native sampling (`/proc/stat`, `/proc/meminfo`) |
| `brightness` | Brightness | `brightnessctl`-backed, scroll to adjust |
| `nightLight` | Night light toggle | |
| `recorderDot` | Screen-recorder indicator | Dot, visible only while recording |

"Off by default" means the id is absent from every placement list. Enabling a module is adding its id to `modulesLeft` / `modulesCenter` / `modulesRight`.

## Surface treatment

The bar's surface is a fixed stack, bottom to top:

1. Compositor blur behind the surface (layerrule; no-op when global blur is off).
2. `surface` fill at **86%** opacity.
3. Mist wash `rgba(190,206,209,0.10)`.
4. Top-edge lightening — the design brief's vertical luminance gradient, ~4–6% lightness delta over the top of the band.
5. 3% monochrome grain.
6. 1 px `border-subtle` bottom hairline.

The hairline is the bar's horizon: the bottom edge *is* a horizon line, which is why the flush band reads correctly with the rest of the language.

**Adaptive opacity** is an optional toggle, **off by default**. When on, the fill opacity ramps from `bar.surface.opacity` toward 1.0 as the wallpaper brightens: `opacity = surface.opacity + (1 − surface.opacity) × L`, where `L` is the mean relative luminance of the top 60 logical px of the current wallpaper. Sampled **once per wallpaper change** via `Services/Theming/`, never per frame.

## Ridgeline workspace indicator

Form is `strata` — rounded-top bands whose height and opacity both fall away with distance from the active workspace. `peaks` (triangular silhouettes) and `pills` are not shipped: `peaks` loses the flat top edge that makes strata read as strata, and `pills` is the generic idiom this shell is choosing not to ship.

| Property | Value |
|---|---|
| Unit width | 14 px |
| Unit gap | 4 px |
| Height — active | 14 px |
| Height — occupied | 9 px |
| Height — empty | 3 px |
| Height falloff | 2 px per step of distance from the active workspace |
| Haze (opacity) — active | 1.0 |
| Haze — occupied | 0.62 |
| Haze — empty | 0.22 |
| Haze falloff | 0.10 per step of distance from the active workspace |
| Horizon rule | none |
| Workspace ids | none |

Height and haze falloff both apply on top of the state height/haze, floored at the empty values. There is **no baseline rule** under the units and **no workspace number** anywhere: a 9 px id under a 14 px active unit consumes the whole 32 px bar.

Empty workspaces at 3 px / 0.22 vanish as intended. The accepted cost is that the row's length stops being countable — five slots cannot be told from nine at a glance.

**Slot set**: Hyprland's workspace list contains only *existing* workspaces, so slots `1..minSlots` are unioned in unconditionally and any higher-numbered existing workspace is appended. `Hyprland.workspaces` populates asynchronously — bind reactively, never read it once at startup.

Workspace changes animate at 140 ms on the fog ease (height + opacity together). This is the shell's most frequent animation; it is the only thing on the bar that moves at rest-state, and it moves only on a workspace change.

## The lamplight rule

**Amber (`accent-warm`) is reserved for attention.** The active workspace is `accent-primary` teal.

The bar at rest therefore carries **no warm element at all**, and amber anywhere on it means something wants you. Exactly one element carries amber at a time; when more than one qualifies, the most urgent takes it and the others fall back to their resting role. Urgent and destructive states use `accent-ember`, not amber.

The alternative — amber on the active workspace, yielding to attention — is rejected: it spends the one warm accent on a state that is always true.

`ridgeline.activeAccent` flips the active workspace to amber for users who want the other rule. It is a setting; the default is `"teal"`.

## Motion

Per the motion spec: ridgeline workspace shift 140 ms, bar reveal (auto-hide) 240 ms in / 140 ms out, fog ease throughout. `reducedEffects` collapses both to 140 ms opacity fades.

## Performance

Idle ≤ 0.5% CPU and < 5 wakeups/s on the T480 with the bar visible. The clock ticks **once per minute** unless `clockShowSeconds` is on. Nothing on the bar animates at idle. Evidence is `QSG_RENDER_TIMING=1` numbers, not feel.

## Settings

Section `bar` in `settings.json`. Sparse file — only changed keys are written.

| Key | Default | Notes |
|---|---|---|
| `position` | `"top"` | v1 accepts `"top"` only; other values coerce back |
| `flush` | `true` | `false` = floating island with margin + radius |
| `height` | `32` | logical px |
| `paddingHorizontal` | `12` | |
| `moduleGap` | `14` | |
| `floatingMargin` | `8` | applies when `flush` is `false` |
| `floatingRadius` | `10` | applies when `flush` is `false` |
| `autoHide` | `"never"` | `"never"` \| `"fullscreen"` \| `"always"` |
| `clockShowSeconds` | `false` | seconds force a 1 Hz tick — leave off |
| `monitors` | `[]` | empty = every screen; otherwise a list of connector names |
| `modulesLeft` | `["launcherButton","workspaces","activeWindow"]` | |
| `modulesCenter` | `["clock","mediaMini"]` | |
| `modulesRight` | `["tray","statusCluster","battery","keyboardLayout","notificationIndicator","controlCenterButton"]` | |

Nested `bar.surface` — the surface stack. This sub-object is **theme-flagged** as a whole (see
`features/settings.md`): themes snapshot it, layout keys above stay per-machine.

| Key | Default | Notes |
|---|---|---|
| `opacity` | `0.86` | **coerced into `[0.65, 1.0]`** |
| `mistWash` | `0.10` | alpha of the `rgb(190,206,209)` wash |
| `topLight` | `true` | top-edge lightening |
| `bottomHairline` | `true` | 1 px `border-subtle` |
| `grain` | `0.03` | monochrome grain opacity |
| `adaptiveOpacity` | `false` | |

Nested `bar.ridgeline` — also theme-flagged as a whole:

| Key | Default |
|---|---|
| `unitWidth` | `14` |
| `unitGap` | `4` |
| `heightActive` | `14` |
| `heightOccupied` | `9` |
| `heightEmpty` | `3` |
| `heightFalloff` | `2` |
| `hazeActive` | `1.0` |
| `hazeOccupied` | `0.62` |
| `hazeEmpty` | `0.22` |
| `hazeFalloff` | `0.10` |
| `minSlots` | `10` |
| `showHorizonRule` | `false` |
| `showWorkspaceIds` | `false` |
| `activeAccent` | `"teal"` (`"teal"` \| `"amber"`) |

Every value above is a default, not a constant. Flush-vs-floating, geometry, the whole surface stack, adaptive opacity and the entire ridgeline block are user-editable from the Bar tab.

## Constraints

These are measured on the T480 (UHD 620, scale 1.5, Quickshell 0.3.0, Qt 6.11.1) and lock the values above. Do not re-litigate them per wallpaper — a translucent bar has to hold against the brightest wallpaper it will ever see.

**"Near-flush with the wallpaper" is unreachable.** The board's signature is that every pin is bright at the top. An opaque `#141b17` bar sits at a **6.14:1** luminance edge against the brightest wallpaper and **1.08:1** against a dark-topped one. Flushness is a property of the wallpaper, not of the bar: it arrives free on a dark-topped image and cannot be bought on a bright-skied one. The bar is designed for the honest failure mode — an opaque-reading flush band that is legible everywhere.

**Translucency has a floor near 65%.** `text-secondary` under the right-hand cluster (always the worst case — it sits over the brightest sky):

| Surface fill | Contrast |
|---|---|
| opaque | 7.95:1 |
| **86%** | **7.12:1** |
| 78% | 6.44:1 |
| 70% | 5.61:1 |
| 60% | **4.44:1 — fails** |
| 45% | 2.89:1 |
| 20% | 1.25:1 |

The design system's body-text floor is 4.5:1. 86% is statistically indistinguishable from opaque while still moving with the wallpaper. This is why `bar.surface.opacity` clamps at 0.65.

**A fog-band bar is out.** Applying the fog-scrim recipe (blur + `saturate(0.8)` + the mist wash instead of a fill) to the bar puts small text over a bright sky: 4.41:1 centre and **2.89:1** right at 45% fill, 1.25:1 right at 20%. Blur belongs to the drawers, where a scrim sits between wallpaper and content.

## Build notes

- **Quickshell hot-reloads on any write inside the config directory**, silently resetting singleton state. Anything that writes — caches, screenshots, state — writes outside the shell's own tree.
- **`font.pixelSize` is an `int`.** The 10.5 px caps label needs `font.pointSize` with a `px × 72/96` helper in `Core/Theme.qml`.
- `grabToImage` snapshots the frame at call time; a capture fired right after a state change catches the transition mid-flight.
