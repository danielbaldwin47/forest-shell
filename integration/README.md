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
`Conflicts: quickshell`, so pacman cannot hold both.

What this file used to say next was that removing `noctalia-qs` cascades through
`dms-shell`, `dms-shell-niri` and `noctalia-shell-git`, and that a single
`pacman -S extra/quickshell` would list all four for removal. Both halves are
wrong, and the first attempt at the swap (2026-08-04, #152) stopped on the
second one:

    :: quickshell-0.3.0-2 and noctalia-qs-0.0.12-1.1 are in conflict. Remove noctalia-qs? [y/N] y
    error: failed to prepare transaction (could not satisfy dependencies)
    :: removing noctalia-qs breaks dependency 'noctalia-qs' required by noctalia-shell-git

`pacman -S` resolves a conflict by removing the conflicting package, but it will
not remove that package's *dependants* for you — it refuses the transaction
instead. And only one dependant is a real blocker. `dms-shell` depends on the
virtual name `quickshell`, which `noctalia-qs` merely provides, so the real
`extra/quickshell` satisfies it just as well; only `noctalia-shell-git` depends
on `noctalia-qs` by name. So the cascade is one package, and `dms-shell` and
`dms-shell-niri` survive the swap with their dependency still satisfied:

```bash
# From a TTY or an already-open terminal, not from a fresh login.
sudo pacman -R noctalia-shell-git      # the one hard dependant; nothing needs it
sudo pacman -S extra/quickshell        # now the conflict resolves — it will list
                                       # noctalia-qs for removal, which is expected
qs --version                           # must say: Quickshell 0.3.0 (or newer)
```

Plain `-R`, not `-Rs`: the recursive form would also take `imagemagick`,
`ffmpeg`, `wlr-randr` and whatever else it judged unneeded. Orphans are
harmless; `pacman -Qdtq` afterwards if you want them.

That leaves `qs -c noctalia-shell` dead — `noctalia-shell-git` is gone — while
`dms run`, `qs -c ghibli` and `dms-shell-niri` are all still *installed* but now
run against upstream 0.3.0 instead of the fork they were written for. Whether
any of them still works is untested, and that is the reason to do this with a
terminal already open rather than over a fresh login.

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
cache, so that half is a `pacman -S` away. **`noctalia-shell-git` is not**: it is
an AUR package, so `pacman -Si` finds nothing and `/var/cache/pacman/pkg` holds
no copy. What makes it recoverable without a rebuild is the AUR helper's own
cache, and that is worth confirming is still there *before* removing it:

```bash
ls ~/.cache/yay/noctalia-shell-git/*.pkg.tar.zst   # check first — this is the rollback
```

Order matters on the way back: `noctalia-shell-git` depends on `noctalia-qs` by
name, so `noctalia-qs` has to be in place first.

```bash
sudo pacman -S cachyos/noctalia-qs                 # from the repo
# or, offline:
sudo pacman -U /var/cache/pacman/pkg/noctalia-qs-0.0.12-1.1-x86_64.pkg.tar.zst
sudo pacman -U ~/.cache/yay/noctalia-shell-git/noctalia-shell-git-4.7.5.r59.g40dd5f54a-1-any.pkg.tar.zst
```

If that file is gone, rebuild it from the AUR — `yay -S noctalia-shell-git`.
`dms-shell` and `dms-shell-niri` are not removed by the swap and need nothing
here.

---

## 2. Register with shell-switch

```bash
tools/register-shell-switch.sh --check   # say what would change, touch nothing
tools/register-shell-switch.sh           # apply
```

This writes two things: a `SHELL_DB` block and a `get_all_shells` entry in
`~/.config/shell-switch/lib/shell-manager.sh`, and a cosmetic entry in that
tool's `config.json`. It backs up each file it edits, once, before the first
edit, and it is idempotent — re-running it after the fork is updated or reset
restores the entry rather than stacking a second one.

There is nothing to install for the shell itself. The launch is the direct path,
`qs -p <repo>/shell.qml`, with **no `~/.config/quickshell` symlink** — the
shell-switch research recommends the symlink, but #12 settled it the other way
and the [#13 assembly refinements](https://github.com/danielbaldwin47/forest-shell/issues/13)
closed the question: "direct-path launch … no config-dir symlink". Where the
research file and the decision disagree, the decision wins.

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

### Autostart

Autostart of *the shell* is what this is about; the clipboard watchers the
launcher needs are a separate line and are in §3 below.

There is nothing separate to wire. Autostart *is* the switch: `shell-switch`
regenerates `~/.config/hypr/shell-switcher-startup.conf` from its template
before it switches, so picking "Forest Shell" leaves that file holding

```
exec-once = qs -p /home/daniel/repos/forest-shell/shell.qml
```

and `hyprland.conf` already sources it (line 320). It takes effect at the next
login, not at the switch.

The thing worth checking once, per the contract's ambiguity A6, is that nothing
*else* starts a shell at login, or two race. Checked as of #57: every other
`exec-once` in `hyprland.conf` is commented out and `hyprland-gui.conf` has
none, so the generated file is the only autostart. Re-check if that changes.

### If the switch rolls back immediately

`verify_shell_running` claims a 5-second budget but increments its counter by 1
per half-second sleep, so it really gives the new shell about 2.5 s to appear.
A cold QML compile can lose that race and get the switch declared failed and
rolled back. Start the shell once by hand first (`qs -c forest`, wait for it,
kill it) so the compile is warm, then switch.

---

## 3. Wire the keybinds and the clipboard watchers

Add two lines to `~/.config/hypr/hyprland.conf`:

```
source = ~/repos/forest-shell/integration/hyprland/forest-binds.conf
source = ~/repos/forest-shell/integration/hyprland/forest-autostart.conf
```

The second one is not optional if you want the launcher's `;` page, and its
absence is invisible: `forest-autostart.conf` starts the two `wl-paste --watch`
processes that fill `cliphist`, and Wayland keeps no clipboard history without
them. With no watcher running the history is empty forever and looks exactly
like a history nobody has copied into yet — which is how #140 was found on the
T480, with the shell running and both binaries installed. It also needs

```bash
pacman -S cliphist wl-clipboard
```

The rest of this section is the binds.

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

Everything here needs step 1 to have happened, so none of it could be done from
the repo side. All three are #57 acceptance criteria that are **not** met yet.

**The seams have not been re-run on the pacman runtime.** Every result behind
this work was measured with `QS_BIN=qs-upstream`, against the prefix. The
maintenance pass on #57 is explicit that the swap "must update them and re-run
all three seams under the pacman runtime, or it lands blind". Same upstream
version, different build and different library paths. After step 1, re-run the
list in §4 with no `QS_BIN` set.

**The shell-switch round-trip has not been performed.** "shell-switch switches
to and from forest-shell; launcher entry point works" needs a live session:
switch to Forest Shell, confirm it comes up, press SUPER+Space after
`hyprctl reload`, then switch *back* to another shell and confirm that works
too. The rollback direction is the one worth doing deliberately — it is what
you need if the swap goes badly.

**The startup budgets have not been re-measured.** First frame ≤ 1.5 s /
interactive ≤ 2 s, last measured against the prefix. Re-run
`tools/idle-budget.sh` after step 1 and judge on `render` time — the swap blocks
on the Wayland frame callback — using the same method as #95 so the two tickets
do not measure differently.
