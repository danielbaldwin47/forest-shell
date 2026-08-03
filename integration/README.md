# Integration — running forest-shell as the daily driver

Everything here is about the machine rather than the shell: which quickshell
binary runs it, how `shell-switch` finds it, and which keys reach it. The
repo-side half is scripted and tested; the half that needs `sudo` and a live
session is written out below and is deliberately not automated.

| Thing | Where |
| --- | --- |
| Registration values + applier | `tools/register-shell-switch.sh` |
| Hyprland keybinds | `integration/hyprland/forest-binds.conf` |
| Runtime resolution | `tools/qs-runtime.sh` (+ `tests/tst_qs_runtime.sh`) |
| Bind verification | `tools/binds-harness.sh` (seam 2) |
| The contract this follows | `.wayfinder/research/shell-switch-integration.md` |

The order below matters: the binds and the registration are inert until the
runtime swap has happened, and the runtime swap is the step that can take the
session down.

---

## 1. Swap the runtime

**This step removes packages that other shells depend on. Read it before
running it.**

forest-shell needs upstream Quickshell 0.3.0 or newer. Until #57 the machine
had two runtimes side by side: `/usr/bin/qs`, which is the `noctalia-qs` fork
(0.0.12) and cannot run this shell, and `~/.local/bin/qs-upstream`, a hand-built
prefix holding upstream 0.3.0 (#15). The swap makes plain `qs` the real thing
and retires the prefix.

The obstacle is that `noctalia-qs` declares `Provides: quickshell` and
`Conflicts: quickshell`, so pacman cannot hold both. Removing it cascades:

```
noctalia-qs
├─ dms-shell
│  └─ dms-shell-niri
└─ noctalia-shell-git
```

Those are two of the three shells `shell-switch` can currently switch to. After
the swap its menu still lists them, but `dms run` and `qs -c noctalia-shell`
will not start. **Ghibli is the uncertain one**: it is a Quickshell *config*,
launched with `qs -c ghibli`, so after the swap it runs against upstream 0.3.0
instead of the fork it was written for. It may work unchanged or it may not —
nothing here has tested that, and it is the reason to do this with a terminal
already open rather than over a fresh login.

```bash
# From a TTY or an already-open terminal, not from a fresh login.
sudo pacman -S extra/quickshell        # pacman will list noctalia-qs, dms-shell,
                                       # dms-shell-niri and noctalia-shell-git
                                       # for removal — that is expected
qs --version                           # must say: Quickshell 0.3.0 (or newer)
```

Then retire the prefix, once `qs` answers correctly:

```bash
rm ~/.local/bin/qs-upstream
rm -rf ~/.local/opt/quickshell-upstream
```

Nothing in the repo needs `qs-upstream` after this — `tools/qs-runtime.sh`
defaults to `qs` and accepts any binary that identifies as upstream Quickshell
at or above the floor, so `QS_BIN=qs-upstream` keeps working for exactly as long
as you leave the prefix on disk.

### Rolling back

`noctalia-qs` is still in the `cachyos` repo and a copy is in the local package
cache, so the swap is reversible:

```bash
sudo pacman -S cachyos/noctalia-qs                 # from the repo
# or, offline:
sudo pacman -U /var/cache/pacman/pkg/noctalia-qs-0.0.12-1.1-x86_64.pkg.tar.zst
sudo pacman -S dms-shell noctalia-shell-git        # the dependants, if wanted
```

---

## 2. Register with shell-switch

```bash
tools/register-shell-switch.sh --check   # say what would change, touch nothing
tools/register-shell-switch.sh           # apply
```

This writes three things: a `~/.config/quickshell/forest` symlink pointing at
the repo (so `qs -c forest` resolves), a `SHELL_DB` block and a `get_all_shells`
entry in `~/.config/shell-switch/lib/shell-manager.sh`, and a cosmetic entry in
that tool's `config.json`. It backs up each file it edits, once, before the
first edit, and it is idempotent — re-running it after the fork is updated or
reset restores the entry rather than stacking a second one.

It does **not** run shell-switch's `install.sh`, ever. That script is a
first-time bootstrap: `create_config()` rewrites `config.json` from scratch with
only `noctalia` and `dms` in it, which would drop both `ghibli` and `forest` and
reset the switch counter.

The registration values live in the script itself, near the top, because the
file they land in is an uncommitted local modification to somebody else's
checkout — the ghibli entry already there is the precedent. Keeping the values
in the repo is the only reason they survive a `git checkout` of the fork.

Then switch, and reload:

```bash
shell-switch          # pick "Forest Shell"
hyprctl reload        # shell-switch never does this itself
```

The reload is not optional and not cosmetic. `reload_compositor()` exists in
`lib/compositor.sh` and is called by nothing, so the regenerated
`bind = SUPER, Space, …` line sits in a sourced file the compositor has not
re-read. The switch changes the running process immediately and the keybind
lazily.

### If the switch rolls back immediately

`verify_shell_running` claims a 5-second budget but increments its counter by 1
per half-second sleep, so it really gives the new shell about 2.5 s to appear.
A cold QML compile can lose that race and get the switch declared failed and
rolled back. Start the shell once by hand first (`qs -c forest`, wait for it,
kill it) so the compile is warm, then switch.

---

## 3. Wire the keybinds

Add one line to `~/.config/hypr/hyprland.conf`:

```
source = ~/repos/forest-shell/integration/hyprland/forest-binds.conf
```

Do not put these in `~/.config/hypr/shell-switcher-binds.conf`. That file is
regenerated wholesale from a template on every switch, despite the comment in it
inviting custom binds below the managed section.

Every bind in the file is `qs -c forest ipc call <target> <fn> || <fallback>`.
`ipc call` exits 255 with no instance running, so `||` fires exactly when the
shell is down and the keys keep doing something while it is being fixed.
SUPER+Space is the one exception and is not in the file: shell-switch owns it,
and interpolates it through `sed -e "s|{{LAUNCHER_CMD}}|…|g"`, so a `|` anywhere
in that value breaks the substitution. It therefore cannot have a fallback.

`tools/binds-harness.sh` checks all of this against a live shell in a nested
compositor — that each bind has a fallback, that the target and function it
names are really on the IPC surface, that the call exits non-zero with the shell
down, and that it exits **zero** with the shell up. The last one is the
non-obvious half: `||` runs the fallback on any non-zero exit, so a live shell
that returned non-zero would fire both its own handler and the fallback.

---

## 4. Verify the swap landed

```bash
tests/run.sh                                    # seam 1, incl. the runtime check
tools/binds-harness.sh                          # seam 2, the binds
tools/settings-harness.sh                       # seam 2, a surface
tools/capture-harness.sh /tmp/bar.png --surface bar   # seam 3
tools/idle-budget.sh                            # the startup/idle budgets
```

All of them resolve the runtime through `tools/qs-runtime.sh`, so on a machine
where the swap has not happened they fail with what to do about it rather than
with a QML import error. `--help` still works on such a machine — resolution is
deliberately lazy.

## 5. What is still open

The first-frame ≤ 1.5 s / interactive ≤ 2 s budgets from #57 have **not** been
re-measured on the pacman runtime; they were last measured against the
`qs-upstream` prefix. Same binary version, different build and different library
paths, so the numbers are probably but not certainly unchanged. Re-run
`tools/idle-budget.sh` after step 1 and judge on `render` time — the swap blocks
on the Wayland frame callback — using the same method as #95 so the two tickets
do not measure differently.
