# shell-switch registration

Sources: [#7](https://github.com/danielbaldwin47/forest-shell/issues/7), [#14](https://github.com/danielbaldwin47/forest-shell/issues/14), [#15](https://github.com/danielbaldwin47/forest-shell/issues/15), [.wayfinder/research/shell-switch-integration.md](../.wayfinder/research/shell-switch-integration.md)

`shell-switch` is Daniel's fzf shell picker at `~/.config/shell-switch/` (upstream
`https://gitlab.com/theblackdon/shell-switch.git`, local checkout carries an uncommitted patch that
added `ghibli`). It stops the running shell, starts the chosen one, and regenerates two Hyprland
include files. forest-shell registers into it as a fourth entry.

This document is the version-controlled copy of that registration. The local checkout is a dirty
fork; **re-apply the block in §3 after any `git pull` in `~/.config/shell-switch/`.**

## 1. What the tool actually reads

**The registry is `lib/shell-manager.sh`, not `config.json`.** Nothing in the running tool ever reads
`config.json`'s `.shells`, `.installed`, `.package` or `.config_paths` — those fields are write-only
metadata produced once by `install.sh`. The only fields the tool touches at runtime are
`.current_shell` (read), `.last_switch` and `.switch_count` (written).

Registering a shell is therefore exactly two edits in
`/home/daniel/.config/shell-switch/lib/shell-manager.sh`:

1. Six `SHELL_DB[<id>.*]` assignments inside `init_shell_db()`.
2. Appending the id to the hardcoded string in `get_all_shells()`.

That is precisely how `ghibli` was added, and it is the precedent forest-shell follows.

| Thing | Path |
| --- | --- |
| Shell definitions (authoritative) | `/home/daniel/.config/shell-switch/lib/shell-manager.sh` |
| State (`current_shell` only field read) | `/home/daniel/.config/shell-switch/config.json` |
| Hyprland templates | `/home/daniel/.config/shell-switch/templates/hyprland/{shell-start.conf,shell-binds.conf}.template` |
| Generated Hyprland startup | `/home/daniel/.config/hypr/shell-switcher-startup.conf` |
| Generated Hyprland binds | `/home/daniel/.config/hypr/shell-switcher-binds.conf` |
| Sourced from | `/home/daniel/.config/hypr/hyprland.conf` lines 319-323 |
| Log | `/home/daniel/.config/shell-switch/shell-switch.log` |

The templates are shell-agnostic and complete:

```
# templates/hyprland/shell-start.conf.template
exec-once = {{LAUNCH_CMD}}

# templates/hyprland/shell-binds.conf.template
bind = SUPER, Space, exec, {{LAUNCHER_CMD}}
```

**Registering forest-shell requires no template changes.**

## 2. Constraints the registration must respect

**Never run `install.sh`.** It is a first-time bootstrap and is hostile to re-running:
`create_config()` regenerates `config.json` from scratch with only `noctalia` and `dms` — dropping
`ghibli`, forest-shell, and the switch counter — and `integrate_with_compositor()` has a live bug
that feeds the niri `.kdl` filenames to the Hyprland branch. Everything forest-shell needs (fzf, jq,
the `~/.local/bin/shell-switch` symlink, the `source =` lines in `hyprland.conf`) is already
installed, and forest-shell needs no pacman package of its own.

**The local fork stays unpatched.** Do not fix the reload gap, the verify-timeout bug, or the
misleading "add custom binds below" comment. Work around them as documented below.

**Constraint — no `|` or `&` in commands.** `launch_cmd` and `launcher_cmd` are interpolated with
`sed -e "s|{{LAUNCH_CMD}}|${launch_cmd}|g"`: a `|` breaks the sed expression and a `&` means "the
whole match" in the replacement. Absolute paths and `/` are fine. This is why the Super+Space bind
cannot carry the `TEST_ALIVE || fallback` idiom that forest-shell's own binds use.

**Constraint — `launcher_cmd` is mandatory** and is bound to `SUPER, Space` unconditionally. The
launcher IPC entry point must exist from day one:

```qml
IpcHandler {
    target: "launcher"
    function toggle(): void { /* ... */ }
}
```

**Constraint — `launch_cmd` must be foreground and non-daemonizing.** The tool runs
`eval "$launch_cmd" &>/dev/null &` itself and then `pgrep`s for the process. Never add `&`,
`disown`, or `--daemonize`/`-d`; a daemonized Quickshell also changes the cmdline that
`process_pattern` matches.

**Constraint — `process_pattern` is an unanchored `pgrep -f` / `pkill -f` ERE** matched against full
command lines. It must (a) match forest-shell's real cmdline, (b) match no other registered shell —
`detect_running_shell` returns the first hit in `get_all_shells` order and `stop_shell` would kill
the wrong process — and (c) match no editor or stray tool. A bare `forest-shell` pattern would match
`nvim /home/daniel/repos/forest-shell/shell.qml` and `pkill` the editor, which is why the patterns
below include the binary name and the `-p` flag.

**Constraint — the running check is effectively ~2.5 s.** `verify_shell_running` increments its
counter by 1 while sleeping 0.5, so the nominal 5 s budget is about 2.5 s of wall clock. A slow first
QML compile can trigger a false "failed to start", which rolls back to the previous shell. Warm
forest-shell once by hand before the first switch (§4 step 1) so the QML cache is populated.

**Constraint — the compositor is never reloaded.** `reload_compositor()` exists in
`lib/compositor.sh` and is called by nothing. Run `hyprctl reload` by hand after every switch, or
Super+Space keeps invoking the previous shell's launcher until the next Hyprland restart. The
`exec-once` line only matters at next login.

There is no `shell-switch <name>` argv form — `main()` ignores positional arguments, and the tool is
always the interactive fzf picker. Do not script around it.

## 3. The registration block

Two profiles. **Development** is the one to register now: the pacman-managed `qs` is still the
archived `noctalia-qs` fork, and forest-shell must run under upstream 0.3.0 via the `qs-upstream`
wrapper (see [architecture.md](architecture.md) §1). The **post-swap** profile replaces it during the
build-plan phase that swaps pacman to upstream `quickshell` and retires the old stack.

forest-shell launches **by direct path**. The repo root is the Quickshell config dir with `shell.qml`
at top level, and shell-switch points straight at it — there is no `~/.config/quickshell/forest`
symlink and no `-c` config name.

### 3.1 Development profile (pre-swap) — register this

Inside `init_shell_db()` in `/home/daniel/.config/shell-switch/lib/shell-manager.sh`:

```bash
# Forest Shell (repo at ~/repos/forest-shell, upstream Quickshell via qs-upstream wrapper)
SHELL_DB[forest.name]="Forest Shell"
SHELL_DB[forest.launch_cmd]="qs-upstream -p /home/daniel/repos/forest-shell/shell.qml"
SHELL_DB[forest.launcher_cmd]="qs-upstream -p /home/daniel/repos/forest-shell/shell.qml ipc call launcher toggle"
SHELL_DB[forest.process_pattern]="quickshell -p /home/daniel/repos/forest-shell"
SHELL_DB[forest.packages]="noctalia-qs"
SHELL_DB[forest.id]="forest"
```

and extend the menu list:

```bash
get_all_shells() { echo "noctalia dms ghibli forest"; }
```

Why `process_pattern` names `quickshell`, not `qs-upstream`: the wrapper ends in
`exec "$PREFIX/usr/bin/quickshell" "$@"`, so the surviving process's command line is
`/home/daniel/.local/opt/quickshell-upstream/usr/bin/quickshell -p /home/daniel/repos/forest-shell/shell.qml`.
A pattern containing `qs-upstream` matches nothing and every switch rolls back.

Collision check, all four registered patterns: `qs.*noctalia-shell`, `dms run`, `qs -c ghibli`,
`quickshell -p /home/daniel/repos/forest-shell`. The forest cmdline contains no `qs` substring
(`quickshell` does not), so it cannot be claimed by the noctalia or ghibli patterns; no other shell's
cmdline contains the forest path.

`packages` is cosmetic — only `install.sh` reads it, and `install.sh` is never run. `noctalia-qs` is
this machine's installed Quickshell build and matches the ghibli precedent.

### 3.2 Post-swap profile — apply during the pacman-swap phase

After `dms-shell` and `noctalia-shell-git` are removed and `pacman -S quickshell` has replaced the
fork, `qs` *is* upstream 0.3.0 and the wrapper is no longer needed. Replace the block with:

```bash
# Forest Shell (repo at ~/repos/forest-shell)
SHELL_DB[forest.name]="Forest Shell"
SHELL_DB[forest.launch_cmd]="qs -p /home/daniel/repos/forest-shell/shell.qml"
SHELL_DB[forest.launcher_cmd]="qs -p /home/daniel/repos/forest-shell/shell.qml ipc call launcher toggle"
SHELL_DB[forest.process_pattern]="qs -p /home/daniel/repos/forest-shell"
SHELL_DB[forest.packages]="quickshell"
SHELL_DB[forest.id]="forest"
```

`get_all_shells()` loses the retired entries in the same phase.

## 4. Procedure

A build session performing the registration runs these steps in order.

**1. Warm the shell.** Confirm forest-shell starts and stays up under the exact launch command,
before shell-switch ever runs it:

```sh
qs-upstream -p /home/daniel/repos/forest-shell/shell.qml
```

Leave it running for more than 3 s, then in another terminal:

```sh
pgrep -af "quickshell -p /home/daniel/repos/forest-shell"
```

This both validates `process_pattern` against the real cmdline and populates the QML cache so the
~2.5 s verify window is not a coin flip on the first switch.

**2. Verify the launcher IPC entry point** while that instance runs:

```sh
qs-upstream -p /home/daniel/repos/forest-shell/shell.qml ipc call launcher toggle
```

The drawer must open. Then stop the manual instance before switching.

**3. Edit `lib/shell-manager.sh`** — add the §3.1 block inside `init_shell_db()` and append `forest`
to `get_all_shells()`. This is the only functional edit.

**4. Update `config.json`** — cosmetic, but keeps the file honest:

```json
"forest": { "name": "Forest Shell", "installed": true, "package": "noctalia-qs" }
```

Do **not** hand-edit `.current_shell`; a real switch sets it.

**5. Switch.** Run `shell-switch` and pick "Forest Shell". Expected results:

- backups of the two generated files written to `~/.config/shell-switch/backups/`,
- `~/.config/hypr/shell-switcher-startup.conf` →
  `exec-once = qs-upstream -p /home/daniel/repos/forest-shell/shell.qml`,
- `~/.config/hypr/shell-switcher-binds.conf` →
  `bind = SUPER, Space, exec, qs-upstream -p /home/daniel/repos/forest-shell/shell.qml ipc call launcher toggle`,
- the previous shell killed, forest-shell verified within ~2.5 s,
- `.current_shell` set to `forest`.

**6. Reload Hyprland by hand:**

```sh
hyprctl reload
```

Then test Super+Space. Skipping this leaves the previous shell's launcher bound.

**7. Sanity-check rollback** before relying on it: run `shell-switch` again and switch *away* from
forest back to ghibli or noctalia, then back. If a switch to forest fails, the tool kills the new
process, restarts the old shell, restores the newest `.bak` of both generated files, and
`notify-send`s — the failure mode is safe, but confirm it once.

**8. Confirm single autostart.** `exec-once` in `shell-switcher-startup.conf` must be the only shell
autostart; check `hyprland.conf` and `hyprland-gui.conf` for a competing line, or two shells race at
login.

## 5. Out of scope for shell-switch

Only one keybind is managed: `SUPER, Space` → launcher. All other forest-shell binds live in
`~/.config/hypr/keybinds.conf` and use the `TEST_ALIVE || fallback` idiom
([architecture.md](architecture.md) §8). Note that everything below the
`# === END MANAGED SECTION ===` comment in the generated binds file is overwritten too — the file is
regenerated wholesale from the template, so that comment's invitation to add custom binds is false.

Per-shell Hyprland theming is not switched. `~/.config/hypr/ghibli-theme.conf` stays sourced whatever
shell is active; any forest-shell compositor settings are a hand-sourced conf with the same leak, and
the switcher is not extended to manage them.
