# Registering a new shell in `shell-switch`

Research date: 2026-07-31. All findings from reading the live install at
`/home/daniel/.config/shell-switch/` (read-only). Nothing was modified.

Upstream: `https://gitlab.com/theblackdon/shell-switch.git`. The local checkout has
**one uncommitted local modification** — `lib/shell-manager.sh`, which is where the user
hand-added the `ghibli` shell. That is the precedent to follow for `forest-shell`.

---

## 1. Mechanism, end to end

### 1.1 Entry point

- `~/.local/bin/shell-switch` is a symlink to `~/.config/shell-switch/shell-switch`.
- The script resolves the symlink (`readlink -f`) to find `SCRIPT_DIR`, then sources
  `lib/common.sh`, `lib/compositor.sh`, `lib/shell-manager.sh`.

**Important: there is no `shell-switch <name>` CLI form.** `main "$@"` is called but `main()`
ignores all positional arguments. The tool is *always* the interactive fzf picker. Any
"switch to forest non-interactively" workflow does not exist today and would have to be added
(see §4, ambiguity A5).

### 1.2 What actually happens on a run

`shell-switch` (`/home/daniel/.config/shell-switch/shell-switch`, `main()` at line 260):

1. **Dependency gate** — `require_dependencies fzf jq pgrep pkill`.
2. **Compositor detection** (`detect_compositor`, compositor.sh:19) — lowercased
   `$XDG_CURRENT_DESKTOP` matched against `niri`/`hyprland`; falls back to
   `pgrep -x niri` / `pgrep -x Hyprland`. Failure aborts. (The log shows a real failure
   at 2026-07-31 09:20:11 where neither matched — likely run from outside the session.)
3. **Current shell** — `jq -r '.current_shell' config.json`. This is the *only* field of
   `config.json` that the running tool ever reads.
4. **fzf menu** — `build_fzf_menu` iterates `get_all_shells` (a **hardcoded string** in
   shell-manager.sh, currently `"noctalia dms ghibli"`), renders
   `<icon> <name>|<id>`, displays field 1, returns field 2 as the shell id.
5. **Config regeneration BEFORE the switch** (`update_compositor_configs`, shell-switch:141):
   - backs up the existing startup + binds files into `~/.config/shell-switch/backups/`
     (timestamped `.bak`, last 5 kept per basename),
   - regenerates both files from `templates/<compositor>/` for the *new* shell.
6. **`switch_shell`** (shell-manager.sh:299):
   - `stop_shell` old: `pkill -f "$process_pattern"`, poll up to 3 s, then `pkill -9 -f`.
   - `start_shell` new: `eval "$launch_cmd" &>/dev/null &` (backgrounded, inherits the
     terminal's environment), `sleep 0.5`.
   - `verify_shell_running` new, 5 s budget: loops `pgrep -f "$process_pattern"`.
     **Note the timeout loop is buggy** — it increments `elapsed` by 1 while sleeping 0.5,
     so the "5 second" verify is really ~2.5 s of wall clock. A slow-starting shell can
     be falsely declared dead.
   - On start/verify failure: kills the new shell, restarts the old one, `notify-send`,
     returns 1.
7. **Rollback of configs** — if `switch_shell` fails, `shell-switch` calls
   `restore_backup` on the startup + binds files (newest `.bak` wins).
8. **State write** — `jq` sets `.current_shell`, `.last_switch`, `.switch_count += 1`.

**The compositor is never reloaded.** `reload_compositor()` exists in `lib/compositor.sh`
but is called by *nothing* (verified by grep). The README claims a reload step; it is not
implemented. Consequence: the new `bind = SUPER, Space, ...` line does not take effect
until `hyprctl reload` is run manually or Hyprland restarts. The `exec-once` line only
matters at next login. So a switch changes the *running process* immediately but the
*keybind* lazily.

Also unused at runtime: `validate_compositor_config`, `is_shell_installed`,
`get_installed_package`, `detect_running_shell` — these are only used by `install.sh`.

### 1.3 Where things live

| Thing | Path |
| --- | --- |
| Shell definitions (authoritative) | `/home/daniel/.config/shell-switch/lib/shell-manager.sh` |
| State (`current_shell` only field read) | `/home/daniel/.config/shell-switch/config.json` |
| Hyprland templates | `/home/daniel/.config/shell-switch/templates/hyprland/{shell-start.conf,shell-binds.conf}.template` |
| Generated Hyprland startup | `/home/daniel/.config/hypr/shell-switcher-startup.conf` |
| Generated Hyprland binds | `/home/daniel/.config/hypr/shell-switcher-binds.conf` |
| Sourced from | `/home/daniel/.config/hypr/hyprland.conf` lines 319-323 |
| Log | `/home/daniel/.config/shell-switch/shell-switch.log` |
| Backups | `/home/daniel/.config/shell-switch/backups/` |

---

## 2. The registration contract

### 2.1 The real registry is `lib/shell-manager.sh`, not `config.json`

`config.json`'s `shells` object (`name`, `installed`, `package`) is **write-only metadata**.
Grepping the whole tool confirms nothing ever reads `.shells`, `.installed`, `.package`, or
`.config_paths`. It is produced once by `install.sh:create_config()` and thereafter only
`.current_shell` / `.last_switch` / `.switch_count` are touched. Keeping it in sync is
cosmetic/documentary — but worth doing so the file doesn't lie.

The functional registry is two edits in `lib/shell-manager.sh`:

```bash
# inside init_shell_db()
SHELL_DB[<id>.name]="<Display Name>"            # fzf label, template {{SHELL_NAME}}
SHELL_DB[<id>.launch_cmd]="<command>"           # eval'd to start; template {{LAUNCH_CMD}}
SHELL_DB[<id>.launcher_cmd]="<command>"         # Super+Space; template {{LAUNCHER_CMD}}
SHELL_DB[<id>.process_pattern]="<pgrep -f re>"  # detect / pkill / verify
SHELL_DB[<id>.packages]="<pkg> [pkg...]"        # pacman -Q probe, install.sh only
SHELL_DB[<id>.id]="<id>"                        # set by convention; never read

# and
get_all_shells() { echo "noctalia dms ghibli <id>"; }   # menu order + detection order
```

All five `SHELL_DB` properties except `.id` are load-bearing. Omitting one makes
`get_shell_info` log an ERROR and return 1; under `set -euo pipefail` in the caller that
usually aborts the switch.

### 2.2 Property semantics and constraints

**`name`** — free text. Appears in the fzf row, in the generated file headers, and in
`hotkey-overlay-title` for niri.

**`launch_cmd`** — run via `eval "$launch_cmd" &>/dev/null &`. Must be a foreground,
non-daemonizing command (the switcher backgrounds it itself and `pgrep`s for it).
Do **not** add `&`, `disown`, or `--daemonize` — `verify_shell_running` needs the process
to be findable by `process_pattern` and a daemonized `qs` would change the cmdline.
Constraint: the value is interpolated with `sed -e "s|{{LAUNCH_CMD}}|${launch_cmd}|g"`, so
it must not contain `|` (breaks the sed expression) or `&` (means "the whole match" in a sed
replacement). Absolute paths with `/` are fine.

**`launcher_cmd`** — same sed constraints. Emitted verbatim into
`bind = SUPER, Space, exec, <launcher_cmd>`. For a Quickshell shell this is the IPC toggle,
e.g. ghibli uses `qs -c ghibli ipc call launcher toggle`, which requires the shell to declare
a matching `IpcHandler { target: "launcher"; function toggle(): void {...} }`
(ghibli does, in `shell.qml:21`).

**`process_pattern`** — an ERE fed to `pgrep -f` and `pkill -f` (matches against the full
command line, unanchored substring semantics). Three requirements:
1. It must match the new shell's real cmdline (else verify fails and the switch rolls back).
2. It must not match any *other* registered shell's cmdline — `detect_running_shell` returns
   the first hit in `get_all_shells` order, and `stop_shell` would kill the wrong process.
   Watch prefixes: a pattern `qs -c forest` would also match a running `qs -c forest-shell`.
3. It must not match the switcher's own process or a stray editor. Existing patterns:
   `qs.*noctalia-shell`, `dms run`, `qs -c ghibli`.

**`packages`** — space-separated **pacman package names**, probed with `pacman -Q "$pkg"`.
Only `is_shell_installed` / `get_installed_package` use it, and only `install.sh` calls those.
It cannot be a path or a command. For a config-directory shell there is no package, so the
existing convention is to name the *Quickshell runtime* package instead: ghibli declares
`noctalia-qs`, which is this machine's Quickshell build (`noctalia-qs 0.0.12-1.1`, and it
`provides` both `quickshell` and `quickshell-git`). That is a white lie that makes the probe
return true; it is harmless because nothing at switch time consults it.
`config.json`'s `"package": "noctalia-qs"` for ghibli mirrors that.

### 2.3 Template variables

Only five substitutions exist (shell-switch.sh:117-121):

| Variable | Value | Used by |
| --- | --- | --- |
| `{{SHELL_NAME}}` | `name` | both compositors, comments/titles |
| `{{LAUNCH_CMD}}` | `launch_cmd` verbatim | hyprland `shell-start.conf.template` |
| `{{LAUNCHER_CMD}}` | `launcher_cmd` verbatim | hyprland `shell-binds.conf.template` |
| `{{LAUNCH_CMD_ARGS}}` | `launch_cmd` word-split into `"a" "b" "c"` | niri `shell-start.kdl.template` |
| `{{LAUNCHER_CMD_ARGS}}` | `launcher_cmd` word-split | niri `shell-binds.kdl.template` |

The `_ARGS` forms come from `awk '{for(i=1;i<=NF;i++) printf "\"%s\" ", $i}'` — naive
whitespace splitting, so **no argument may contain a space** if niri support matters.

Full Hyprland templates (they are tiny — this is the entire per-shell surface):

```
# templates/hyprland/shell-start.conf.template
exec-once = {{LAUNCH_CMD}}

# templates/hyprland/shell-binds.conf.template
bind = SUPER, Space, exec, {{LAUNCHER_CMD}}
```

Templates are **shell-agnostic** — there is no per-shell template. Registering a new shell
requires **no template changes**. If forest-shell needs extra Hyprland settings (borders,
animations, rounding — the way ghibli has `~/.config/hypr/ghibli-theme.conf` sourced at
hyprland.conf:331), that is *outside* shell-switch: the theme conf is hand-sourced and is
**not** swapped on switch. See ambiguity A3.

Only one keybind is managed: `SUPER, Space` → launcher. `~/.config/hypr/keybinds.conf`
has no competing Space bind, so no conflict. Everything below
`# === END MANAGED SECTION ===` in the generated binds file is *also* overwritten (the file
is regenerated wholesale from the template), despite the comment inviting custom binds there
— that comment is misleading; custom binds must live in `keybinds.conf`.

### 2.4 Install-side requirements

`install.sh` is a **first-time bootstrap only** and is hostile to re-running:

- `create_config()` **overwrites `config.json` from scratch** with only `noctalia` and `dms`
  entries — re-running it would drop `ghibli` and any new shell, and reset `switch_count`.
- `check_shells()` hardcodes noctalia/dms and can `exit 1` if neither is installed.
- `integrate_with_compositor()` has a **bug for hyprland**: it passes the *niri* filenames
  (`shell-switcher-startup.kdl` / `.kdl`) to `add_include_statement` regardless of
  compositor, so it would append `source = ~/.config/hypr/shell-switcher-startup.kdl`.
  The live `hyprland.conf` has the corrected `.conf` lines (319-323), i.e. someone fixed
  this by hand already.

**Conclusion: do not run `install.sh` to register forest-shell.** Everything needed is
already installed (fzf, jq, the symlink, the `source =` lines in `hyprland.conf`). No pacman
package needs to exist for forest-shell.

---

## 3. Step-by-step: register `forest-shell`

Assumes forest-shell ships as a Quickshell config (it has no `shell.qml` yet — the repo is
currently only `.wayfinder/` + `.gitignore`).

**Step 0 — decide how the config is reachable.** Quickshell resolves `-c <name>` to
`$XDG_CONFIG_HOME/quickshell/<name>/shell.qml`, or takes `-p <path>` to a directory
containing `shell.qml`. Two options:

- **(a) symlink** `~/.config/quickshell/forest -> /home/daniel/repos/forest-shell`,
  launch with `qs -c forest`. Matches the ghibli precedent (ghibli lives as a real directory
  at `~/.config/quickshell/ghibli`, not a git repo — the repo-based variant is new).
- **(b) path launch** `qs -p /home/daniel/repos/forest-shell`, no symlink. Works, but the
  cmdline (and therefore `process_pattern`) contains an absolute path, and the IPC form
  becomes `qs -p /home/daniel/repos/forest-shell ipc call launcher toggle`. Longer but has
  no `|`/`&` and no spaces, so it is still template-safe.

(a) is recommended: shorter patterns, matches existing convention, and keeps the repo
git-clean.

**Step 1 — make the shell launchable.** `/home/daniel/repos/forest-shell/shell.qml` must
exist and `qs -c forest` must start and stay up for >3 s. Verify manually:
`qs -c forest` in a terminal, then `pgrep -af "qs -c forest"`.

**Step 2 — add an IPC launcher handler** in `shell.qml`:

```qml
IpcHandler {
    target: "launcher"
    function toggle(): void { /* ... */ }
}
```

Verify with `qs -c forest ipc call launcher toggle` while it runs. If forest-shell has no
launcher, `launcher_cmd` still must be set to *something* non-empty (see A4).

**Step 3 — edit `~/.config/shell-switch/lib/shell-manager.sh`** (the only functional edit),
inside `init_shell_db()`:

```bash
# Forest Shell (local quickshell config, repo at ~/repos/forest-shell)
SHELL_DB[forest.name]="Forest Shell"
SHELL_DB[forest.launch_cmd]="qs -c forest"
SHELL_DB[forest.launcher_cmd]="qs -c forest ipc call launcher toggle"
SHELL_DB[forest.process_pattern]="qs -c forest"
SHELL_DB[forest.packages]="noctalia-qs"
SHELL_DB[forest.id]="forest"
```

and extend the menu list:

```bash
get_all_shells() { echo "noctalia dms ghibli forest"; }
```

Pattern-collision check: `qs -c forest` does not match `qs -c ghibli` or
`qs.*noctalia-shell`; conversely nothing existing matches it. Safe as long as the config
directory is literally named `forest` and no other config name starts with `forest`.

**Step 4 — update `~/.config/shell-switch/config.json`** (cosmetic but keeps it honest):

```json
"forest": { "name": "Forest Shell", "installed": true, "package": "noctalia-qs" }
```

Do **not** hand-edit `current_shell` — let a real switch set it.

**Step 5 — switch.** Run `shell-switch`, pick "Forest Shell". Expect:
backups written, `~/.config/hypr/shell-switcher-startup.conf` → `exec-once = qs -c forest`,
`~/.config/hypr/shell-switcher-binds.conf` → `bind = SUPER, Space, exec, qs -c forest ipc call launcher toggle`,
old shell killed, new one verified within ~2.5 s.

**Step 6 — reload Hyprland manually**: `hyprctl reload` (the tool does not do this).
Then test Super+Space.

**Step 7 — sanity-check rollback** before relying on it: confirm `shell-switch` can switch
*away* from forest back to ghibli/noctalia.

**Step 8 (optional) — Hyprland theming.** If forest-shell wants its own borders/animations,
mirror `ghibli-theme.conf`: write `~/.config/hypr/forest-theme.conf` and source it at the end
of `hyprland.conf`. Note this is manual and *not* switched automatically — see A3.

---

## 4. Ambiguities needing a human decision

- **A1 — Where does forest-shell's config live?** Symlink `~/.config/quickshell/forest` →
  repo (`qs -c forest`) vs. `qs -p /home/daniel/repos/forest-shell`. Affects `launch_cmd`,
  `launcher_cmd`, and `process_pattern`. Recommendation: symlink.
- **A2 — Upstreaming vs. local drift.** `lib/shell-manager.sh` is already dirty with the
  ghibli patch against a GitLab remote. Adding forest deepens the local fork; a future
  `git pull` will conflict. Decide: keep patching locally, or fork/vendor shell-switch (e.g.
  into this repo's `scripts/`) so the registration is version-controlled.
- **A3 — Per-shell Hyprland theming is out of scope for shell-switch.** `ghibli-theme.conf`
  stays sourced even when DMS is active. If forest-shell wants its own look, someone must
  decide whether to (i) accept the same leak, (ii) hand-swap the source line, or (iii) extend
  shell-switch/the templates with a per-shell theme include. The templates would need a new
  variable for (iii).
- **A4 — Does forest-shell have a launcher?** `launcher_cmd` is mandatory and is bound to
  Super+Space unconditionally. If there is no launcher at registration time, pick a
  placeholder (e.g. point Super+Space at an existing launcher) and revisit — an empty value
  would emit a dangling `bind = SUPER, Space, exec,` line.
- **A5 — Non-interactive switching.** There is no `shell-switch forest`. If the forest-shell
  workflow (or a dev script) wants scripted switching, someone must add argv handling to
  `main()` — a ~10-line change, but another local patch (see A2).
- **A6 — Startup ownership.** `exec-once` in `shell-switcher-startup.conf` is the only
  autostart. Confirm nothing else in `hyprland.conf` / `hyprland-gui.conf` also starts a
  shell, or two will race at login.
- **A7 — Known defects to work around, not fix silently:** the ~2.5 s effective verify
  timeout (slow first QML compile can trip a false rollback — consider warming the shell once
  before the first switch), the never-called `reload_compositor`, and the
  "add custom binds below" comment in a file that is fully regenerated.
