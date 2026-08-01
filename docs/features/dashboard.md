# Dashboard

Sources: [#9](https://github.com/danielbaldwin47/forest-shell/issues/9), [#4](https://github.com/danielbaldwin47/forest-shell/issues/4), [#8](https://github.com/danielbaldwin47/forest-shell/issues/8), [#12](https://github.com/danielbaldwin47/forest-shell/issues/12), [#21](https://github.com/danielbaldwin47/forest-shell/issues/21), [#22](https://github.com/danielbaldwin47/forest-shell/issues/22), [#27](https://github.com/danielbaldwin47/forest-shell/issues/27), [.wayfinder/research/quickshell-capabilities.md](../../.wayfinder/research/quickshell-capabilities.md), [.wayfinder/prototypes/motion-choreo/findings.md](../../.wayfinder/prototypes/motion-choreo/findings.md)

## Shape

A single-view panel in the **shared drawer window**, opened from the bar's Clock module. Lives in
`Surfaces/Drawers/Dashboard/`. There are no tabs — everything the dashboard shows is visible in one
scroll.

| Property | Value |
|---|---|
| Width | 480px |
| Panel padding | 16px |
| Gap between cards | 12px |
| Card radius | 10px on cards, 16px on the panel |
| Surface | panel `surface` at 90% fill, top-lit; cards on `surface-raised` |
| Anchor | top, horizontally centered under the Clock module, with a beak at the clock; the clock lights `accent-primary` teal while open |
| Max height | screen height − bar height − 32px; the card column scrolls if it overflows |

Drawer rules apply unchanged: globally exclusive across screens, opens on the focused screen, one
`HyprlandFocusGrab`, re-summon toggles closed, an open drawer on a removed screen resets to closed.
The IPC target takes no screen argument.

## Motion

Open 320 ms (scrim opacity → 0.10 and content together, no stagger; content is opacity plus a 1%
scale settle about the clock anchor), close 240 ms opacity-only. Arriving from another open drawer
uses cross-drawer variant A: outgoing 140 ms, incoming 240 ms starting at +100 ms, scrim untouched.
Calendar month changes and card in-place updates are 140 ms. Fog ease
`cubic-bezier(0.22, 1, 0.36, 1)`; `reducedEffects` collapses everything to 140 ms opacity
crossfades. No entrance stagger on the card column.

## Card registry

Cards are registry-configurable exactly like bar modules — add, remove, and reorder from settings
or by hand-editing. `dashboard.cards` is an ordered array of card ids; unknown ids are ignored with
a log line and preserved on rewrite.

```json
"dashboard": { "cards": ["header", "calendar", "weather", "systemMonitor", "media"] }
```

| Id | Card |
|---|---|
| `header` | Date/time + profile |
| `calendar` | Month grid |
| `weather` | Open-Meteo current + 7-day |
| `systemMonitor` | CPU / RAM / disk / temp sparklines |
| `media` | Full MPRIS card |

Card components live in `Surfaces/Drawers/Dashboard/cards/<Id>Card.qml` and are registered in one
id → component map in that directory. A card that is not in the array is never instantiated, and
its backing sampling never starts.

## header — date/time + profile

- Clock in **Newsreader Light (300)**, `HH:mm`, the display serif's only appearance outside the
  lock screen. The design system's rule is that the serif is used once and never twice: no other
  text on the dashboard is serif.
- Date underneath in IBM Plex Sans 400, format `EEEE, d MMMM` (e.g. `Saturday, 1 August`).
- Profile block on the right: avatar from `~/.face`, falling back to a full-round `surface-raised`
  circle with the first letter of the username; `$USER@$HOSTNAME` in `text-secondary`; uptime from
  `/proc/uptime` rendered `up 3d 4h`.
- The clock ticks once per minute, aligned to the minute — seconds are never displayed here, so no
  second-resolution timer exists.

## calendar — month grid

Month grid only. **Event integration is out of v1** — no Google Calendar, no Notion, no local
`.ics`, no agenda list.

- 7×6 grid, cells 40×32px, weekday header row in caps labels (10.5px, +0.08em tracking).
- First day of week from `dashboard.calendarFirstDayOfWeek`, default `"monday"`.
- Today carries a 2px `accent-primary` ring; days outside the displayed month are `text-muted`.
- Chevrons step months; the month label click returns to today. Reopening the drawer always resets
  to the current month.
- Week numbers off by default (`dashboard.calendarShowWeekNumbers`, `false`).

## weather — Open-Meteo

Keyless and account-free. All requests are made with QML `XMLHttpRequest` — no `curl`, no
subprocess.

| Purpose | Endpoint |
|---|---|
| Forecast | `https://api.open-meteo.com/v1/forecast` |
| Geocoding a place name | `https://geocoding-api.open-meteo.com/v1/search?name=<place>&count=1` |
| IP-based auto location | `https://ipapi.co/json/` |

Forecast query parameters: `current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m`,
`daily=weather_code,temperature_2m_max,temperature_2m_min`, `timezone=auto`, plus
`temperature_unit=fahrenheit` and `wind_speed_unit=mph` when `weatherTime.units` is `"imperial"`.

**Location.** `weatherTime.location` is a place name string (default `""`), geocoded once and the
resulting lat/lon cached in state alongside the resolved display name. When
`weatherTime.locationAuto` is `true` (default `false`) the coordinates come from the IP lookup
instead and the configured place name is ignored. If both are unavailable the card renders a single
"Set a location in Settings › Weather & Time" line — it never guesses.

**Card contents.** Current temperature (large), condition text and Lucide icon mapped from the WMO
`weather_code`, feels-like, wind, and today's high/low; below that a 7-column daily strip of
weekday initial, icon, high/low. Day/night icon variants are chosen from `is_day`.

**Refresh policy.** One fetch in the deferred startup stage, then a fetch on dashboard open when
the cached response is older than `weatherTime.refreshMinutes` (default `15`). There is no periodic
timer — the shell must not wake up for weather while the dashboard is closed. Responses are cached
in the runtime state file under `Quickshell.stateDir`; the cached values render immediately on open
and are replaced in place at 140 ms when the new response lands. A failed request leaves the last
good data on screen with a `text-muted` "stale" timestamp.

## systemMonitor — sparkline row

Four sparklines in a row: CPU, RAM, disk, temp. Each is a 96×32px sparkline with the current value
as a numeral beside it. **Native sampling only — no `dgop`, no `btop`, no monitoring daemon.**

| Readout | Source | Computation |
|---|---|---|
| CPU | `/proc/stat` | `cpu` line; busy delta over total delta between consecutive samples |
| RAM | `/proc/meminfo` | `(MemTotal − MemAvailable) / MemTotal` |
| Temp | `/sys/class/hwmon/hwmon*/temp*_input` | the hwmon whose `name` is `coretemp`, `k10temp`, or `zenpower`; first `temp*_input` in millidegrees |
| Disk | `df -P -B1 /` via `Process` | used/size of the root filesystem |

`/proc` and `/sys` files are read with `FileView` and an explicit `reload()` per tick — file
watching does not fire on procfs. The `df` subprocess is the only external call; it runs on the
same tick.

**Sampling runs only while the dashboard is open.** Interval `dashboard.monitorIntervalMs`, default
`2000`; the ring buffer holds 60 samples (2 minutes) and is discarded when the drawer closes. This
is the shell's only sampling timer and it exists solely under the poll-only-while-visible rule that
keeps idle CPU ≤ 0.5% and idle wakeups < 5/s on the T480.

Sparklines are `accent-primary` at 60% opacity with a 1px line; they redraw once per sample, never
animate between frames, and there is no ambient motion of any kind.

## media — full MPRIS card

The full card, distinct from the control center's compact strip and the bar's MPRIS pill.

- Cover art 96px from `MprisPlayer.trackArtUrl`, radius 6px, with a `surface-raised` placeholder
  when absent.
- Title, artist, album — one line each, elided.
- Seek bar with elapsed/total, enabled only when `MprisPlayer.positionSupported`; the position is
  read only while the drawer is open and the player is playing.
- Transport: previous, play/pause, next, plus shuffle and loop when the player advertises them.
- When `Mpris.players` holds more than one player, a row of small source chips selects the active
  one; otherwise the chips are hidden.
- With no player at all the card renders a single `text-muted` "Nothing playing" line — it stays in
  the column so the layout does not jump.

## Out of v1

Tabs, to-do list, notepad, pomodoro, a full performance/process view, and calendar event
integration. Do not add them, and do not leave placeholders for them.

## Settings

Section `dashboard`:

| Key | Type | Default |
|---|---|---|
| `cards` | array | `["header", "calendar", "weather", "systemMonitor", "media"]` |
| `calendarFirstDayOfWeek` | string | `"monday"` |
| `calendarShowWeekNumbers` | bool | `false` |
| `monitorIntervalMs` | int | `2000` |
| `showUptime` | bool | `true` |

Section `weatherTime` (shared with the clock and the night-light schedule):

| Key | Type | Default |
|---|---|---|
| `location` | string | `""` |
| `locationAuto` | bool | `false` |
| `units` | string | `"metric"` |
| `refreshMinutes` | int | `15` |

Runtime state (`Quickshell.stateDir`): `weather.cache` (last response plus fetch timestamp),
`weather.coords` (resolved lat/lon and display name).

## IPC and shortcuts

```qml
IpcHandler {
  target: "dashboard"
  function toggle(): void
  function open(): void
  function close(): void
}
```

`GlobalShortcut` name: `forest-shell:dashboard`. Hyprland binds use the
`qs ipc call TEST_ALIVE || <fallback>` idiom.

## Performance

- All card content is unloaded while the drawer is closed; the shared drawer window is unmapped and
  contributes zero wakeups.
- The only timers are the sampling tick (open-only) and the minute-aligned clock.
- Weather never wakes the shell on its own.
- Zero idle animation: sparklines, the clock, and the media card have no ambient loops.
- The panel must hit zero dropped frames at 60 Hz on the T480 at 1.5× scale; the fog scrim animates
  opacity only and there is no QML-side full-screen blur.
