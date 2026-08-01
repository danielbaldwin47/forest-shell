# Session, lock, and idle

Sources: [#30](https://github.com/danielbaldwin47/forest-shell/issues/30), [#9](https://github.com/danielbaldwin47/forest-shell/issues/9), [#12](https://github.com/danielbaldwin47/forest-shell/issues/12), [#22](https://github.com/danielbaldwin47/forest-shell/issues/22), [#27](https://github.com/danielbaldwin47/forest-shell/issues/27), [.wayfinder/research/quickshell-capabilities.md](../../.wayfinder/research/quickshell-capabilities.md)

This feature owns everything between "the user stopped touching the machine" and "the machine is
asleep or locked", plus the session/power menu that does those things on purpose.

## Files

| Path | Contents |
|---|---|
| `Services/System/Idle.qml` | Singleton. The four `IdleMonitor` stages, the caffeine `IdleInhibitor`, the PipeWire suspend gate. |
| `Services/System/Session.qml` | Singleton. Lock state, the logind bridge `Process`, the sleep-delay inhibitor child, the session commands. |
| `scripts/logind-bridge.sh` | Shipped helper. `busctl monitor` → one event per stdout line. |
| `Surfaces/Lock/` | `WlSessionLock` + `WlSessionLockSurface` content, PAM contexts, co-located `IpcHandler` / `GlobalShortcut`. |
| `Surfaces/Drawers/Session/` | The session/power menu, one of the five drawers in the shared drawer window. |

Brightness writes go through `Services/Hardware/Brightness.qml`; DPMS goes through
`Services/Compositor/` (`Hyprland.dispatch`). Neither is re-implemented here.

## Idle ladder

Four stages. Each is one native `IdleMonitor { enabled; timeout; respectInhibitors; isIdle }`
(`ext-idle-notify-v1`, seconds). No `hypridle`, no `swayidle`. Each stage is individually
toggleable with an editable timeout on the Settings **System** tab, and each has an independent
AC and battery timeout. AC vs battery comes from native `UPower.onBattery`; a rail change
re-parameterizes the live monitors, it does not restart them.

| Stage | Battery | AC | Action | Restore on activity |
|---|---|---|---|---|
| Dim | 2.5 min (150 s) | 5 min (300 s) | `brightnessctl -s set 10%` | `brightnessctl -r` |
| Lock | 5 min (300 s) | 10 min (600 s) | `loginctl lock-session` | — |
| DPMS off | 6 min (360 s) | 12 min (720 s) | `Hyprland.dispatch("dpms off")` | `Hyprland.dispatch("dpms on")` |
| Suspend | 15 min (900 s) | off | `system.session.suspendCommand` | — |

- **Suspend on AC is off by default.** A rail timeout of `0` means "this stage does not fire on
  this rail"; `system.idle.suspend.acSeconds` defaults to `0`.
- **While locked, DPMS tightens to 30 s** (`system.idle.dpms.lockedSeconds`) — the DPMS monitor's
  `timeout` is swapped while `WlSessionLock.locked` and swapped back on unlock. **The battery
  suspend timer keeps running while locked**; locking is not a reason to stay awake.
- The dim stage no-ops when `/sys/class/backlight` is empty (the desktop). The stage stays in the
  config but reports unavailable, and the GUI control is disabled.
- Stages are independent monitors, not a chain: a stage whose timeout is shorter than an earlier
  stage's still fires at its own time. The GUI does not reorder or validate across stages.

### Inhibitors

`respectInhibitors: true` on **all four** stages. Video players and browsers already take the
Wayland `idle-inhibit-unstable-v1` protocol themselves, so honouring it is the whole media policy —
the shell does not sniff MPRIS to decide whether to stay awake.

**The suspend stage only** carries one additional gate: active audio playback blocks idle-suspend.
Music keeps playing with the lid open and the screen dark; the screen still dims, locks, and blanks
on schedule. The gate is evaluated **only at the moment the suspend monitor reports idle**, never
continuously — a standing peak monitor would burn the idle wakeup budget (#22: < 5 wakeups/s):

1. Suspend `IdleMonitor.isIdle` goes true.
2. `Services/System/Idle.qml` collects every `PwNode` with `isStream && isSink && ready` and
   unmuted `audio`, binds them with a `PwObjectTracker`, and attaches a `PwNodePeakMonitor` to each.
3. Over a 3 s window, if any monitored node reports `peak > 0.001`, suspend is skipped and the
   monitor is re-armed for another full timeout. Otherwise suspend runs.
4. The peak monitors and the tracker are torn down at the end of the window either way.

A corked or paused stream produces no peaks and therefore does not block suspend. MPRIS is
deliberately not consulted — not every audio producer implements it.

### Caffeine ("Keep Awake")

One `IdleInhibitor { enabled }` in `Services/System/Idle.qml`. While enabled it suppresses the
**entire ladder** — all four stages — because every stage sets `respectInhibitors: true`. It is
surfaced as the **Keep Awake** toggle in the control center's 3×3 toggle grid and as a launcher
`/` action.

Its state lives in the **state file** (`Quickshell.stateDir`), not `settings.json`: like DND it is
situational rather than setup, and a caffeine toggle that synced between the T480 and the desktop
would leave both machines permanently awake. It survives a shell restart and never syncs.

## logind bridge

Quickshell has no generic DBus binding, so logind's session `Lock`/`Unlock` and the manager's
`PrepareForSleep` are reached through one shipped helper script run as a `Process` from
`Services/System/Session.qml`.

### `scripts/logind-bridge.sh`

Emits exactly one event token per line on stdout: `lock`, `unlock`, `sleep`, `resume`. Consumed
with `Process { stdout: SplitParser { splitMarker: "\n" } }`. Invoked as
`["sh", Quickshell.configDir + "/scripts/logind-bridge.sh"]` — the repo root is the Quickshell
config dir, so this resolves inside the shell tree.

```sh
#!/bin/sh
# forest-shell logind bridge: one event token per stdout line.
set -eu
trap 'kill 0' INT TERM

session=$(busctl --system call org.freedesktop.login1 /org/freedesktop/login1 \
            org.freedesktop.login1.Manager GetSession s "${XDG_SESSION_ID:-auto}" \
          | cut -d'"' -f2)

stdbuf -oL busctl --system monitor \
  --match "type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Session',path='$session'" \
  --match "type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" \
| awk '
  /Member=/     { m = $0; sub(/.*Member=/, "", m); sub(/[ \t].*/, "", m) }
  /^ *BOOLEAN / { b = $2 }
  /^};/         { if      (m == "Lock")            print "lock"
                  else if (m == "Unlock")          print "unlock"
                  else if (m == "PrepareForSleep") print (b ~ /true/) ? "sleep" : "resume"
                  fflush(); m = ""; b = "" }'
```

The helper is restarted with a 2 s backoff if it exits for any reason. A dead bridge degrades the
shell to idle-only behavior (the ladder still works); it never blocks startup.

### Sleep-delay inhibitor

From shell startup, `Services/System/Session.qml` holds a **delay** lock as a child `Process`:

```
systemd-inhibit --what=sleep --mode=delay --who=forest-shell --why="Lock screen before sleep" sleep infinity
```

Only `--what=sleep`. Lid-close policy stays logind's (`HandleLidSwitch=suspend`, the machine's
default) and arrives on this same path as `PrepareForSleep`.

Lifecycle:

1. `sleep` event → call the internal `lock()` directly.
2. Wait for `WlSessionLock.locked === true` — the compositor's own confirmation, not a timer.
3. Kill the inhibitor child. Only now may the system sleep.
4. `resume` event → re-spawn the inhibitor child, `Hyprland.dispatch("dpms on")`, restore
   brightness, reset every `IdleMonitor`.

**Constraint:** logind's `InhibitDelayMaxSec` defaults to **5 s**. If the lock surface is not
confirmed within that window logind sleeps anyway, unlocked. Nothing on the `sleep` → `lock()` path
may wait on disk, on a subprocess, or on a config reload; the lock surface renders from already-loaded
state and paints its clock before it paints anything wallpaper-derived.

### Lock paths

All lock paths converge on one internal `lock()` in `Services/System/Session.qml`, which raises
`WlSessionLock` and is idempotent while already locked. What differs is who calls it:

| Trigger | Path |
|---|---|
| Session-menu **Lock** action | runs `system.session.lockCommand` (`loginctl lock-session`) |
| `lock` `GlobalShortcut` / `IpcHandler` | runs `loginctl lock-session` |
| Idle **Lock** stage | runs `loginctl lock-session` |
| Bridge `lock` event | calls `lock()` |
| Bridge `sleep` event | calls `lock()` directly (5 s budget, no round trip) |

Every deliberate lock goes out through logind and comes back in as a `Lock` signal, so logind's
session state stays truthful and anything else watching it agrees with the screen. On successful
authentication the shell releases `WlSessionLock` **and** runs `loginctl unlock-session`; the
resulting `unlock` event is a no-op.

## Lock surface

`WlSessionLock { locked; secure: true }` — real `ext-session-lock-v1`. `secure` means the compositor
keeps the surface up if the shell process dies, so a crash while locked cannot expose the session.
`WlSessionLockSurface` instantiates per monitor automatically (#22 correctness tier).

The surface is **quiet at rest**. Over the wallpaper:

- The fog scrim and the bar's ridgeline motif, in design-system tokens.
- Clock and date in **Newsreader Light (300)** — the one serif touch in the shell, used here and on
  the dashboard and nowhere else.
- **Notification count only**, never contents (`system.lock.showNotificationCount`, default `true`).
  It is the same unseen count the bar's notification indicator badges. At zero, nothing renders.
- A battery pill, shown only while `UPower.onBattery` (`system.lock.showBatteryPill`, default `true`).
- A caps-lock warning, shown only while caps lock is on.

No password box, no user avatar, no buttons, no power controls.

### Type-to-summon

There is no visible auth field until the user types. The first printable keypress reveals the field
(240 ms enter, fog ease) and is inserted as the first character. Escape clears and hides it; 10 s
with no input hides it again (140 ms exit). Enter submits.

### PAM

- Password: one `PamContext { config: "login"; configDirectory: "/etc/pam.d" }`. The system `login`
  stack inherits faillock and all distro policy, and **nothing is written to `/etc`** to install
  forest-shell.
- Fingerprint is **latent and runtime-gated**. At lock time, if `system.lock.fingerprint` is
  `"auto"` (default) and `/etc/pam.d/fprintd-auth` is readable, a **second, parallel**
  `PamContext { config: "fprintd-auth" }` starts alongside the password one — hyprlock-style
  concurrent auth. Whichever completes first wins; the loser is deactivated (`active = false`).
  When the file is absent the fingerprint context is never created and the surface looks identical.
  `system.lock.fingerprint: "off"` suppresses the probe entirely.
- Installing and enrolling fprintd on the T480 (Synaptics `06cb:009a`, libfprint-supported) is an
  optional post-v1 machine task. **No enrollment UI ships in v1.**
- PAM prompt text is rendered verbatim under the field — including the fingerprint stack's "Place
  your finger on the fingerprint reader".

### Failure UX

- `completed(PamResult)` with failure: horizontal shake of the field, ±4 px, 140 ms, fog ease, two
  cycles; a brief fog pulse (scrim opacity only); the PAM message printed verbatim under the field,
  **including faillock lockout text**, in `accent-ember`.
  This shake is the only translate in the shell besides the notification stack-shift (#27), and it
  collapses to an opacity-only flash under `reducedEffects`.
- **The shell imposes no retry limit and no cooldown of its own.** faillock owns lockout policy
  entirely. On failure the password context restarts immediately and the field re-accepts input.
- While a context is waiting, the field is disabled and shows a static "Checking…" label. No
  spinner — the shell runs no unattended animation (#22).

### Shortcuts while locked

`GlobalShortcut`s stay registered while the session is locked. Every shell shortcut therefore
**hard no-ops while `WlSessionLock.locked`** except volume, mic, and brightness keys. Drawers,
launcher, dashboard, screenshot, and recorder cannot be summoned from the lock surface; the drawer
window is never mapped while locked. `IpcHandler` targets other than `lock` reject calls while
locked with an error string.

## Session / power menu

The session menu is one of the five drawers hosted in the **shared drawer window** per screen
(#12) — same window, same input mask, same single `HyprlandFocusGrab` as the launcher, control
center, and dashboard. It lives in `Surfaces/Drawers/Session/`.

- **Entry point:** the session/power button in the **control center's bottom strip** (beside the
  settings gear). Also `IpcHandler { target: "session" }` (`toggle()`, `open()`, `close()`) and the
  launcher's `/` actions provider.
- **Anchor:** top-right, under the control-center bar icon — the same anchor as the control center,
  so swapping between them reads as the contents changing inside one continuous fog surface.
- **Motion:** opening from closed is the standard drawer open (320 ms enter / 240 ms exit, scrim to
  0.10 opacity, content opacity + 1% scale settle, no stagger). Arriving from the control center is
  the cross-drawer transition — old content out at 140 ms, new content in at 240 ms starting
  +100 ms, **scrim untouched** (#27 variant A).
- **Contents:** five rows in fixed order, Lucide icons at stroke-width 1.5.

| Row | Icon | Setting key | Default command |
|---|---|---|---|
| Lock | `lock` | `system.session.lockCommand` | `loginctl lock-session` |
| Log out | `log-out` | `system.session.logoutCommand` | `hyprctl dispatch exit` |
| Suspend | `moon` | `system.session.suspendCommand` | `systemctl suspend` |
| Reboot | `rotate-ccw` | `system.session.rebootCommand` | `systemctl reboot` |
| Shut down | `power` | `system.session.shutdownCommand` | `systemctl poweroff` |

- All five commands are **editable strings on the Settings System tab**. They run via
  `Quickshell.execDetached` with `["sh", "-c", <command>]` so a user's command may contain a
  pipeline. An empty string disables that row (greyed, not hidden).
- **Keyboard:** Lock is focused on open; arrows and Tab move; Enter activates; Escape closes.
- **Confirmation:** Lock and Suspend run immediately. Log out, Reboot, and Shut down are two-step —
  the first activation swaps the row's label to "Confirm" in `accent-ember` for 3 s, and a second
  activation within that window runs the command. Moving focus away or letting the window lapse
  cancels. There is no modal dialog and no second window.
- The drawer closes before the command is dispatched.

## Settings

All keys live in the `system` section of `settings.json` and are edited on the Settings **System**
tab. Timeouts are **seconds** in JSON and are presented as minutes in the GUI. The file is sparse:
only keys changed from these defaults are written.

```json
{
  "system": {
    "idle": {
      "enabled": true,
      "respectInhibitors": true,
      "dim":     { "enabled": true, "batterySeconds": 150, "acSeconds": 300, "level": 10 },
      "lock":    { "enabled": true, "batterySeconds": 300, "acSeconds": 600 },
      "dpms":    { "enabled": true, "batterySeconds": 360, "acSeconds": 720, "lockedSeconds": 30 },
      "suspend": { "enabled": true, "batterySeconds": 900, "acSeconds": 0 }
    },
    "lock": {
      "showNotificationCount": true,
      "showBatteryPill": true,
      "fingerprint": "auto"
    },
    "session": {
      "lockCommand": "loginctl lock-session",
      "logoutCommand": "hyprctl dispatch exit",
      "suspendCommand": "systemctl suspend",
      "rebootCommand": "systemctl reboot",
      "shutdownCommand": "systemctl poweroff"
    }
  }
}
```

- `system.idle.enabled: false` disables the whole ladder without losing per-stage settings.
- `system.idle.respectInhibitors` is a single key applied to all four monitors. It defaults to
  `true` and exists as an escape hatch for a misbehaving application; the GUI marks it advanced.
- `system.lock.fingerprint` coerces to `"auto"` for any value other than `"off"`.
- Any timeout coerces to its default if non-numeric, and to `0` (disabled) if negative.

## Acceptance checks

1. `loginctl lock-session` from a terminal raises the lock surface within 300 ms.
2. `systemctl suspend` from a terminal shows the lock surface **before** the screen goes dark, and
   the machine is locked on resume. Same for a lid close.
3. Killing the shell process while locked leaves the compositor's lock surface up (`secure`).
4. Playing audio and idling past 15 min on battery: screen dims, locks, blanks; the machine does
   **not** suspend and the audio does not stutter. Pausing the audio and idling again suspends.
5. Keep Awake on: nothing dims, locks, blanks, or suspends. Off: the ladder resumes from zero.
6. Three wrong passwords produce three verbatim PAM messages and no shell-side lockout; faillock's
   own message appears verbatim when it triggers.
7. Idle at rest with the shell locked contributes < 5 wakeups/s and no animation.
