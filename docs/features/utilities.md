# Utilities — clipboard, screenshot, screen recording, OSD

Sources: [#9](https://github.com/danielbaldwin47/forest-shell/issues/9), [#4](https://github.com/danielbaldwin47/forest-shell/issues/4), [#10](https://github.com/danielbaldwin47/forest-shell/issues/10), [#12](https://github.com/danielbaldwin47/forest-shell/issues/12), [#21](https://github.com/danielbaldwin47/forest-shell/issues/21), [#22](https://github.com/danielbaldwin47/forest-shell/issues/22), [#27](https://github.com/danielbaldwin47/forest-shell/issues/27), [.wayfinder/research/quickshell-capabilities.md](../../.wayfinder/research/quickshell-capabilities.md), [.wayfinder/prototypes/motion-choreo/findings.md](../../.wayfinder/prototypes/motion-choreo/findings.md)

Four features that share one property: each is a thin QML surface over a capability Quickshell
either lacks outright or only half-covers. Each external tool is wrapped in exactly one service
singleton so the subprocess stays an implementation detail.

**Constraint:** Quickshell hot-reloads on any write inside the config directory, silently resetting
singleton state. Nothing in this document may write under the repo root — screenshots, recordings,
thumbnails, and spool files all live outside it.

---

## Clipboard history

Quickshell's `Quickshell.clipboardText` is empty unless a Quickshell window is focused — a Wayland
`wl_data_device` property, not a defect — so it cannot observe copies made in other applications.
Clipboard history is therefore fully external, and there is no clipboard write API either.

### Backend

`cliphist`, fed by `wl-paste --watch` from **Hyprland autostart**, not from the shell. The shipped
Hyprland snippet is exactly two lines:

```
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store
```

Running the watcher from Hyprland rather than the shell means history survives a shell restart or
hot reload, and a shell crash never loses a copy.

### Surface

**The launcher `;` provider only.** There is no clipboard panel, no bar module, no separate window.
See [launcher.md](launcher.md) for the provider dispatch; this section owns the backend contract.

`Services/System/Clipboard.qml` is the singleton:

| Operation | Command |
|---|---|
| List | `cliphist list` — one entry per line, `<id>\t<preview>` |
| Decode to clipboard | `sh -c "cliphist decode '<id>' \| wl-copy"` |
| Decode an image to a file | `sh -c "cliphist decode '<id>' > '<path>'"` |
| Delete one entry | `cliphist delete`, with the entry's raw list line written to stdin |
| Wipe all | `cliphist wipe` |

Text previews are read with the plain `["cliphist", "decode", "<id>"]` form through
`StdioCollector`. The `sh -c` pipeline is used for the **copy** path and for image decoding,
because binary data must not pass through `StdioCollector`. `cliphist list` runs once when the `;`
provider is entered and again after any delete — never on a timer.

### Image thumbnails

Entries whose preview matches cliphist's binary marker (`[[ binary data … ]]`, carrying the type)
are images. They are decoded into `${Quickshell.cacheDir}/clipboard/<id>.<ext>` on first display
and rendered as 40px thumbnails at the leading edge of the launcher row; text entries render a
single-line preview in their place. The cache directory is pruned to the entries still present in
`cliphist list` when the provider is entered.

### Keys inside the provider

`Enter` copies and closes the launcher. `Shift+Delete` deletes the highlighted entry and keeps the
launcher open. Rows show a relative timestamp only when cliphist reports one.

### Settings

Section `launcher` (the clipboard is a launcher provider, so its keys live with it):

| Key | Type | Default |
|---|---|---|
| `clipboardMaxEntries` | int | `100` (display cap; the store's own size is cliphist's `-max-items`, default 750) |
| `clipboardImageThumbnails` | bool | `true` |

The provider itself is enabled by the presence of `"clipboard"` in `launcher.providers`; there is
no second on/off key.

---

## Screenshot

In-shell and native. `grim`/`slurp` are not used.

### The picker

A full-screen `WlrLayershell` overlay per screen, `layer: WlrLayer.Overlay`,
`keyboardFocus: WlrKeyboardFocus.Exclusive`, created on invocation and destroyed on completion.
This is the one surface in the shell that is not kept alive: invocation is user-initiated and rare,
and holding a full-screen buffer per screen idle costs more than the create/destroy does.

**Freeze mode** (`system.screenshotFreeze`, default `true`): before the overlay is shown, a
`ScreencopyView { captureSource: <ShellScreen>, live: false }` calls `captureFrame()`, and the
picker draws its selection UI over that frozen frame. The desktop cannot change under the
selection.

**Window snapping.** `Hyprland.refreshToplevels()` runs immediately before the picker opens; window
rectangles come from `Hyprland.toplevels`. Hovering inside a window rectangle highlights it with a
1px `accent-primary` outline and dims the rest of the screen; clicking without dragging captures
that window. Dragging starts a free region and suppresses snapping; holding `Shift` disables
snapping entirely.

| Key | Action |
|---|---|
| drag | free region |
| click on a highlighted window | that window's rectangle |
| `Space` | toggle whole-screen selection for the screen under the cursor |
| `Shift` (held) | disable window snapping |
| `Esc` | cancel, capture nothing |

The selection rectangle shows live `W × H` in `text-secondary` on the frozen frame; crosshair
guides span the screen. The overlay covers every screen, so a region may cross monitors, but the
capture is taken from the screen containing the selection's origin.

### Capture and output

The selected rectangle is grabbed with `grabToImage()` on the `ScreencopyView` and written with
`result.saveToFile(path)`. The grab is requested at the item's **device-pixel** size, so a
1920×1080 screen at 1.5× scale produces a 2880×1620 PNG — never a downscaled logical-pixel image.

- Save path: `~/Pictures/Screenshots/Screenshot_yyyy-MM-dd_HH-mm-ss.png`, directory from
  `system.screenshotDirectory`, created if missing.
- Copy to clipboard: `sh -c "wl-copy --type image/png < '<path>'"`. Copy and save are both on by
  default; with save off the file is written to `${Quickshell.cacheDir}/screenshots/` so the copy
  still has a source, and is deleted when the shell exits.

After a capture the shell raises an internal notification (not via the bus) reading "Screenshot
saved" with the thumbnail as its image and actions **Open**, **Copy**, and **Edit**. **Edit** is
present only when `swappy` is on `PATH` and runs `swappy -f <path>`; the handoff is optional and
swappy is never a hard dependency.

### Triggers

| Trigger | Mode |
|---|---|
| `forest-shell:screenshotRegion` | picker, region mode (default) |
| `forest-shell:screenshotScreen` | whole focused screen, no picker |
| `forest-shell:screenshotWindow` | picker pre-armed on the focused window |

All three hard no-op while `WlSessionLock.locked`, and the `screenshot` IPC target rejects calls
with an error string while locked.

```qml
IpcHandler {
  target: "screenshot"
  function region(): void
  function screen(): void
  function window(): void
}
```

### Settings

Section `system`:

| Key | Type | Default |
|---|---|---|
| `screenshotDirectory` | string | `"~/Pictures/Screenshots"` |
| `screenshotFreeze` | bool | `true` |
| `screenshotCopy` | bool | `true` |
| `screenshotSave` | bool | `true` |
| `screenshotSnapToWindows` | bool | `true` |
| `screenshotEditor` | string | `"swappy"` (empty string disables the Edit action) |

---

## Screen recording

Nothing in Quickshell encodes video. `Services/System/Recorder.qml` owns the whole lifecycle; QML
owns only the control surface and the indicator.

### Primary backend — gpu-screen-recorder

```
gpu-screen-recorder -w <target> -f <fps> -q <quality> -k auto -ac opus -o <path>
```

- `<target>` is the Hyprland monitor name (`eDP-1`) for a full-screen capture, or `region` with an
  additional `-region <W>x<H>+<X>+<Y>` for a region capture.
- `-k auto` lets gpu-screen-recorder pick the encoder: **VAAPI on the T480's Intel UHD 620**
  (confirmed capable) and **NVENC/AMF on the desktop's discrete GPU**. The shell never passes an
  explicit encoder — hardware selection is the tool's job and the desktop is a zero-tuning tier.
- Audio comes from `system.recorderAudio`: `"none"` passes no `-a`, `"output"` passes
  `-a default_output`, `"output+mic"` passes `-a "default_output|default_input"` (one merged
  track).

### Fallback — wf-recorder

The fallback engages when `gpu-screen-recorder` is absent from `PATH`, or when it exits non-zero
within 2000 ms of start (failed to initialize the encoder). The shell then runs:

```
wf-recorder -o <monitor> -f <path>
```

with `-g "<x>,<y> <w>x<h>"` added for a region capture and `--audio` added when audio is enabled.
Falling back raises a notification naming the reason; it is never silent. If the fallback also
fails to start, recording is abandoned with an error notification and the indicator returns to
idle.

### Lifecycle

- Stop sends `SIGINT` (`Process.signal(2)`) — both tools finalize the container on SIGINT. `SIGKILL`
  is never used; it truncates the file.
- Output path: `~/Videos/Recordings/Recording_yyyy-MM-dd_HH-mm-ss.mp4`, directory from
  `system.recorderDirectory`, created if missing.
- Only one recording runs at a time; a second start request is ignored while active. Starting is a
  hard no-op while `WlSessionLock.locked`; a recording already running keeps running through a
  lock.
- On shell exit or hot reload with a recording active, the shell sends `SIGINT` and waits for the
  process before tearing down.

### Control surfaces

- **Control center** — the recorder row between the toggle grid and the bottom strip (see
  [control-center.md](control-center.md)). Idle: "Record screen" with a region/screen chooser.
  Active: elapsed time in IBM Plex Mono and a stop button.
- **Bar dot** — the optional `recorderDot` bar module, shipped in the registry and **off by
  default** (its id is absent from every placement list; enabling it means adding `recorderDot` to
  `bar.modulesRight`). A static filled dot in the ember accent role while recording, hidden
  otherwise. It does not blink: the zero-idle-animation rule has no exception for it.
- **Region selection** uses the screenshot picker in region-only mode — the same overlay, the same
  snapping, the same keys, but the selection is handed to the recorder instead of being captured.
  Freeze mode is forced off for recording, since the picker must show live content.

```qml
IpcHandler {
  target: "recorder"
  function start(mode: string): void   // screen | region
  function stop(): void
  function toggle(): void
  function state(): string             // JSON: { recording, backend, elapsedMs, path }
}
```

`GlobalShortcut` name: `forest-shell:recorderToggle`.

### Settings

Section `system`:

| Key | Type | Default |
|---|---|---|
| `recorderDirectory` | string | `"~/Videos/Recordings"` |
| `recorderFps` | int | `60` |
| `recorderQuality` | string | `"very_high"` |
| `recorderAudio` | string | `"output"` (`none` \| `output` \| `output+mic`) |

The bar dot has no key of its own — visibility is the bar registry's `recorderDot` id.

---

## OSD

Feedback popups for output volume, microphone mute, and brightness.

### Topology

Its **own layer-shell window per screen, kept alive** with content unloaded while hidden — never
created and destroyed per event. It renders on the **focused screen only**; the other screens'
windows stay mapped-but-empty and contribute zero wakeups. A focus change while the OSD is visible
re-renders it on the newly focused screen; the window itself never moves between outputs.

| Property | Value |
|---|---|
| Anchor | bottom, horizontally centered |
| Bottom margin | 64px |
| Size | 260×56px |
| Surface | `surface` at 90% fill, radius 16px, top-lit |
| Contents | Lucide icon (28px), 4px track with `accent-primary` fill, value as an integer percentage |

### Behavior

- Raised by external changes: hardware keys, `brightnessctl` run elsewhere (caught by the
  `FileView` watch), another app changing the default sink volume, `wpctl`.
- **Not** raised by changes made in a visible surface that already shows the value — moving a
  control center slider never raises the OSD.
- Mute and unmute swap the icon and render the track at the muted value in `text-muted`; brightness
  and volume share one window and one timer, so a second event of a different kind replaces the
  contents in place rather than stacking.
- Hides `system.osdTimeoutMs` after the last change, default `1500`; each new change restarts the
  timer. Hovering the OSD holds it open.
- `system.osdEnabled`, default `true`, disables the surface entirely.
- While `WlSessionLock.locked` the OSD is never raised. Volume, mic, and brightness keys keep
  working while locked, but the lock surface covers every output and layer-shell windows sit below
  it, so the OSD would be invisible; the shell does not waste a frame drawing it.

### Motion

Per the per-surface motion table: **enter 240 ms, exit 140 ms, in-place value updates 140 ms**, fog
ease `cubic-bezier(0.22, 1, 0.36, 1)`, opacity-only on exit. The OSD does not slide — it
materializes in place. `reducedEffects` collapses enter and exit to 140 ms opacity fades.

### Settings

Section `system`:

| Key | Type | Default |
|---|---|---|
| `osdEnabled` | bool | `true` |
| `osdTimeoutMs` | int | `1500` |
| `osdShowOnInternalChange` | bool | `false` |

---

## Performance

- No utility polls. The clipboard list runs on provider entry, `df` runs only on the dashboard's
  tick, and the OSD's single timer exists only while it is visible.
- The recorder subprocess is the only long-lived child process the shell owns; the `wl-paste`
  watchers belong to Hyprland, not to the shell.
- The screenshot picker is the shell's only create-on-demand surface, and it exists for the
  duration of one selection.
- Idle budget on the T480 stands: ≤ 0.5% CPU 60-second average, < 5 wakeups/s, zero idle animation.
