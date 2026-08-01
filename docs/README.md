# forest-shell — build plan

A from-scratch [Quickshell](https://quickshell.org) (QML) desktop shell for Hyprland on CachyOS: DE-grade feature scope, native-first, pure QML + CLI helpers, dark forest design language. Primary hardware target is a ThinkPad T480 (Intel UHD 620) at 1.5× scale.

This directory is the **destination artifact** of the planning effort tracked in [wayfinder map #1](https://github.com/danielbaldwin47/forest-shell/issues/1). Every decision in these docs is closed; there are no open options. Provenance — research, prototypes, measurements, and the discussions that closed each decision — lives in `.wayfinder/` and the map's tickets.

## The documents

| Doc | What it specifies |
|---|---|
| [architecture.md](architecture.md) | Runtime + dev prefix, native capability map, repo layout, window topology, startup, config system, theming plumbing, IPC/keybinds, multi-monitor model, performance budgets |
| [design-system.md](design-system.md) | Color tokens, spacing, radii, typography, motifs, icon system |
| [motion.md](motion.md) | The step system, per-surface duration/easing table, drawer choreography, `reducedEffects` |
| [shell-switch.md](shell-switch.md) | Registration procedure for Daniel's shell-switch tool |
| [roadmap.md](roadmap.md) | The nine build phases, standing gates, and per-phase exit gates |
| [features/bar.md](features/bar.md) | Bar + ridgeline workspace indicator |
| [features/launcher.md](features/launcher.md) | Launcher, the six providers, the Ask Claude CLI contract |
| [features/notifications.md](features/notifications.md) | Popups, notification center, per-app rules |
| [features/control-center.md](features/control-center.md) | Sliders, toggle grid, drill-ins, bottom strip |
| [features/dashboard.md](features/dashboard.md) | The five dashboard cards |
| [features/session-lock.md](features/session-lock.md) | Lock, PAM, idle ladder, suspend hooks, session menu |
| [features/utilities.md](features/utilities.md) | Clipboard, screenshot, screen recording, OSD |
| [features/settings.md](features/settings.md) | Settings window, ten tabs, theme presets |
| [features/dynamic-theming.md](features/dynamic-theming.md) | Fixed / constrained-accent / full-dynamic palette modes |

## How build sessions use this

Build sessions are Claude Opus 5 agent sessions executing [roadmap.md](roadmap.md) phase by phase. A session reads this README, `architecture.md`, `design-system.md`, its phase entry, and the feature spec(s) that phase names — then builds one shippable increment. The shell must boot and daily-drive after every session.

Two rules above all:

1. **The docs are the source of truth.** If reality contradicts a spec, the session updates the spec in the same commit and says why — the docs must stay true, not just start true.
2. **The standing gates in roadmap.md are always in force** — startup, idle, and animation budgets; keep-alive windows; no QML full-screen blur; migrations with every schema change.

Development runs on the `qs-upstream` prefix (`architecture.md`) until Phase 7 swaps the system package. Upstream-vs-fork API gotchas are listed there — target upstream 0.3.0 API only.
