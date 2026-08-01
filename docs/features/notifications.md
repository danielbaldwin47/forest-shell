# Notifications

Sources: [#9](https://github.com/danielbaldwin47/forest-shell/issues/9), [#4](https://github.com/danielbaldwin47/forest-shell/issues/4), [#12](https://github.com/danielbaldwin47/forest-shell/issues/12), [#21](https://github.com/danielbaldwin47/forest-shell/issues/21), [#22](https://github.com/danielbaldwin47/forest-shell/issues/22), [#27](https://github.com/danielbaldwin47/forest-shell/issues/27), [#30](https://github.com/danielbaldwin47/forest-shell/issues/30), [.wayfinder/research/quickshell-capabilities.md](../../.wayfinder/research/quickshell-capabilities.md), [.wayfinder/prototypes/motion-choreo/findings.md](../../.wayfinder/prototypes/motion-choreo/findings.md)

## Shape

Three surfaces over one service:

| Surface | Window | Lives in |
|---|---|---|
| Popup toasts | own layer-shell window per screen, kept alive | `Surfaces/Notifications/` |
| Notification center | shared drawer window, right-anchored | `Surfaces/Drawers/Notifications/` |
| Bar indicator | bar module | `Surfaces/Bar/` (see [bar.md](bar.md)) |

State is cross-surface (toasts, center, bar indicator, lock surface), so the server and the history
store are one `pragma Singleton` in `Services/System/Notifications.qml`, force-touched by
`Core/ServiceInit.qml`.

## Backend

`Quickshell.Services.Notifications.NotificationServer` is the backend — a complete
`org.freedesktop.Notifications` implementation. No `dunst`, no `mako`, no helper process.

**Constraint:** a running dunst/mako silently owns the bus name and `NotificationServer` appears
dead with no error. Audit for a live notification daemon before first run.

Advertised capability flags mirror exactly what the shell renders — never advertise a capability
whose UI does not exist:

| Flag | Value |
|---|---|
| `bodySupported` | `true` |
| `bodyMarkupSupported` | `true` (body rendered with `textFormat: Text.StyledText`) |
| `bodyImagesSupported` | `true` |
| `imageSupported` | `true` |
| `actionsSupported` | `true` |
| `persistenceSupported` | `true` |
| `bodyHyperlinksSupported` | `false` |
| `actionIconsSupported` | `false` |
| `inlineReplySupported` | `false` |
| `keepOnReload` | `true` |

`keepOnReload: true` keeps the live list across hot reloads. Close animations hold the object with
`RetainableLock` so a client-side dismiss does not tear the card out mid-exit.

The shell raises its own notifications (screenshot saved, recorder fallback, bad config value)
through an internal `notify()` method on the singleton, not through the bus.

## Popup toasts

Top-right of the **focused screen only**. The window exists on every screen and stays alive with
unloaded content (`visible: false`); only the focused screen's instance loads the stack. A focus
change re-renders the stack on the newly focused screen — windows never move between outputs.

| Property | Value |
|---|---|
| Anchor | top + right |
| Top margin | bar height + 8px |
| Right margin | 12px |
| Toast width | 380px |
| Gap between toasts | 8px |
| Max visible | 3 (`maxVisiblePopups`); further notifications queue and surface as slots free |
| Radius | 16px, `surface` at 90% fill, top-lit |

Card contents: app icon (24px), app name, relative time, summary (`text-primary`, one line,
elided), body (`text-secondary`, clamped to 2 lines), image if present (48px, leading), action
buttons (max 3, overflow dropped). A close affordance appears on hover.

Interaction: click the body invokes the default action if one exists and dismisses, otherwise just
dismisses; hovering pauses the expiry timer and restarts it on exit; middle-click dismisses without
invoking. Dismissed toasts stay in history.

### Timeouts

Urgency drives the timeout. A client `expireTimeout` above zero wins, clamped to 2000–30000 ms.
`expireTimeout: 0` (never expire) is honored only for critical urgency; at low and normal it falls
back to the urgency default. `-1`/absent uses the urgency default.

| Urgency | Default timeout |
|---|---|
| Low | 4000 ms (`timeoutLow`) |
| Normal | 6000 ms (`timeoutNormal`) |
| Critical | never auto-dismisses (`timeoutCritical: 0`) |

Notifications with the `transient` hint show a toast and are **not** written to history.

### Suppression

A toast is suppressed — the notification still enters history and the center — when any of:

- Do Not Disturb is on.
- The focused Hyprland toplevel is fullscreen (`suppressOnFullscreen`, default `true`).
- The notification center is open (the notification is already visible there).
- The session is locked.

**Critical urgency breaks through DND and fullscreen** (`criticalBypassesDnd`, default `true`). It
does not break through the open center or the lock surface.

### Motion

Per the motion spec: **enter 240 ms, condense in place — no translation**; exit 140 ms, opacity
only; **stack-shift 140 ms, the only translate in the shell** (a closing gap cannot fade). Fog ease
`cubic-bezier(0.22, 1, 0.36, 1)` throughout. `reducedEffects` collapses enter/exit to 140 ms
opacity fades and makes the stack-shift an instant reposition.

## Notification center

A right-anchored panel in the shared drawer window, summoned from the bar's notification
indicator. The center is drawer content, not its own window: the shared drawer window per screen
hosts the launcher, control center, dashboard, session menu, **and** the notification center — one
window, one input mask, one focus grab. It obeys the drawer rules unchanged: globally exclusive
across all screens, opens on the focused screen, one `HyprlandFocusGrab`, re-summon toggles closed,
an open drawer on a removed screen resets to closed.

| Property | Value |
|---|---|
| Width | 420px |
| Max height | screen height − bar height − 32px |
| Anchor | top-right, under the notification indicator, with a beak at the icon; the icon lights teal while open |
| Surface | `surface` at 90%, radius 16px |

Layout:

- **Header** — "Notifications", unread count, a DND toggle, and Clear all.
- **Groups** — one group per app, ordered by most recent notification, newest first inside a group.
  A group header carries the app icon, app name, count, and a per-app clear. Groups collapse past
  3 entries behind a "Show N more" row.
- **Cards** — summary plus 2-line body clamp. Click expands to full body plus action buttons; one
  card is expanded at a time; expand/collapse is a 140 ms in-place animation.
- **Empty state** — a single centered `text-muted` line, no illustration.

Opening the center clears the unread state on the bar indicator. Restored-from-disk entries render
without action buttons: actions die with the client that posted them.

Motion: drawer enter 320 ms (scrim opacity → 0.10 plus content, no stagger, content gets the 1%
scale settle about the anchor icon), exit 240 ms. Arriving from another open drawer uses
cross-drawer variant A — outgoing 140 ms, incoming 240 ms starting at +100 ms, scrim untouched.
The bar renders above the fog scrim and stays clickable, so clicking the indicator while the
launcher is open performs that transition directly.

## Bar indicator

The `notificationIndicator` bar module, right cluster. Lucide `bell`, stroke 1.5. Three states:

| State | Rendering |
|---|---|
| Idle | `bell`, `text-secondary`, no badge |
| Unread | `bell` plus the unread count badged in `accent-warm` |
| DND | `bell-off`, `text-muted` |

Amber here is the shell's attention lamplight — the bar at rest carries no warm element, so amber
means something wants you. Click toggles the center; right-click toggles DND.

## History and persistence

History lives in the runtime state file under `Quickshell.stateDir`, never in `settings.json`.

- Writes are debounced 1000 ms and atomic (`FileView.atomicWrites` is `true` by default).
- Cap `historyLimit`, default 200 entries, oldest dropped first.
- Per entry: `id`, `appName`, `desktopEntry`, `summary`, `body`, `urgency`, `timestamp`,
  `imagePath`.
- Images that arrive as pixmaps rather than paths are written to
  `${Quickshell.cacheDir}/notifications/<id>.png` and referenced by path.
- Restore happens in the deferred startup stage, after `Config.ready`.

**Constraint:** Quickshell hot-reloads on any write inside the config directory, silently resetting
singleton state. History, caches, and image spool must never be written under the repo root.

## Do Not Disturb

DND is situational, not setup, so it lives in state — not `settings.json` — and is not portable
between machines. It is toggled from the control center's DND tile, the center header, the bar
indicator's right-click, and `qs ipc call notifications toggleDnd`. There is no DND schedule in v1.

## Per-app rules

Per-app behavior is configured in **Settings › Notifications**, never on the notification card.
Every app that has notified is listed (from the `knownApps` state list, keyed the same way) with a
three-way control:

| State | Toast | History | Bar indicator |
|---|---|---|---|
| `normal` (default) | yes | yes | yes |
| `silent` | no | yes | no |
| `blocked` | no | no | no |

Rules are stored in `notifications.appRules` as an object keyed by `desktopEntry`, falling back to
the lowercased `appName` when the client sends no desktop entry. An absent key means `normal`, so
the sparse-file rule keeps the config clean. `blocked` drops the notification at the server before
it reaches history.

## Lock screen

The lock surface shows a **count only** — never summary, body, app name, or image. Controlled by
`lockScreenShowCount`, default `true`; `false` hides the count entirely. No toasts render while
locked. See the lock and session spec for the surrounding lock layout.

## Settings

Section `notifications` in `~/.config/forest-shell/settings.json` (camelCase, sparse — only changed
keys are written):

| Key | Type | Default |
|---|---|---|
| `timeoutLow` | int ms | `4000` |
| `timeoutNormal` | int ms | `6000` |
| `timeoutCritical` | int ms | `0` (sticky) |
| `maxVisiblePopups` | int | `3` |
| `suppressOnFullscreen` | bool | `true` |
| `criticalBypassesDnd` | bool | `true` |
| `historyLimit` | int | `200` |
| `lockScreenShowCount` | bool | `true` |
| `appRules` | object | `{}` |

Runtime state (`Quickshell.stateDir`, spec-driven the same way):

| Key | Type | Default |
|---|---|---|
| `notifications.dnd` | bool | `false` |
| `notifications.history` | array | `[]` |
| `notifications.knownApps` | array | `[]` |

## IPC and shortcuts

Co-located with the surfaces, per the architecture's no-central-IPC rule.

```qml
IpcHandler {
  target: "notifications"
  function toggle(): void       // notification center
  function open(): void
  function close(): void
  function toggleDnd(): void
  function clearAll(): void
  function state(): string      // JSON: { unread, total, dnd }
}
```

`GlobalShortcut` names: `forest-shell:notificationCenter`, `forest-shell:dnd`. Hyprland binds use
the `qs ipc call TEST_ALIVE || <fallback>` idiom.

## Performance

- Nothing polls. `NotificationServer` is event-driven; the only timer in the feature is the toast
  expiry timer, which exists only while a toast is visible.
- With no toast up, every popup window holds unloaded content and contributes zero wakeups.
- The center's content is unloaded when the drawer closes.
- No ambient motion: nothing pulses, breathes, or marquees. The unread dot is static.
