#!/usr/bin/env bash
# Register forest-shell with the local shell-switch fork (#57).
#
#   tools/register-shell-switch.sh --check   # say what would change, touch nothing
#   tools/register-shell-switch.sh           # apply, backing up what it edits
#
# ## Why this is a script and not a paragraph in a README
#
# shell-switch's real registry is a bash associative array inside
# ~/.config/shell-switch/lib/shell-manager.sh — an *uncommitted local
# modification* to a checkout of someone else's GitLab repo. The ghibli entry
# already living there is the precedent. That means the one edit that makes this
# shell switchable is, by construction, outside version control and one
# `git checkout` away from being gone with no trace of what it said.
#
# So the values live here, in this repo, and this script applies them. Re-running
# it after the fork is updated or reset restores the entry exactly. #57 resolved
# the alternative (vendor shell-switch wholesale) against: the fork stays
# otherwise unpatched, and this touches nothing but the registry block it owns.
#
# ## What it will not do
#
# It never runs shell-switch's install.sh. That script is a first-time bootstrap
# and is hostile to re-running: create_config() rewrites config.json from
# scratch with only noctalia and dms in it, which would drop both ghibli and
# forest and reset the switch counter.
#
# It never writes .current_shell. That is switch state; only a real switch
# should set it.
set -uo pipefail

# --- the registration, as data ----------------------------------------------
#
# Kept in a sourceable file rather than inline, because tools/binds-harness.sh
# needs the launcher command too — to check it is sed-safe, which is what makes
# SUPER+Space the one bind that cannot have a fallback. Two readers, so the
# values are data and neither has to scrape the other's source.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# The checkout the registered commands should point at. Resolved from the git
# common dir so running this from a worktree still registers the main checkout —
# a `-p` into .claude/worktrees/ would break the moment that worktree was
# removed, and it is the daily driver being registered, not a scratch copy.
COMMON=$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
FOREST_REPO="${COMMON:+$(dirname "$COMMON")}"
FOREST_REPO="${FOREST_REPO:-$HERE}"
export FOREST_REPO

# shellcheck source=../integration/shell-switch/registration.env
source "$HERE/integration/shell-switch/registration.env"

SWITCH_DIR="${SHELL_SWITCH_DIR:-$HOME/.config/shell-switch}"
MANAGER="$SWITCH_DIR/lib/shell-manager.sh"
CONFIG_JSON="$SWITCH_DIR/config.json"
CHECK=0
for arg in "$@"; do
    case "$arg" in
        --check) CHECK=1 ;;
        # Stop at the first line that is not a comment, so the header can grow
        # without the range drifting past it into the code.
        --help|-h) sed -n '2,/^[^#]/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

changes=0
note()   { printf '  ....  %s\n' "$1"; }
ok()     { printf '  \033[32m ok \033[0m  %s\n' "$1"; }
would()  { changes=$((changes + 1)); printf '  \033[33mTODO\033[0m  %s\n' "$1"; }
die()    { printf '  \033[31mFAIL\033[0m  %s\n' "$1" >&2; exit 1; }

[[ -f "$MANAGER" ]] || die "no shell-switch registry at $MANAGER (set SHELL_SWITCH_DIR?)"

# At most one backup per file per run, and it is taken before the *first* edit.
# Steps 2 and 3 both write shell-manager.sh, and a second backup would be a copy
# of the half-edited file — taken within the same second, so it would land on
# the same timestamped name and overwrite the only pre-edit copy there was.
BACKED_UP=()
backup() {
    local f="$1" stamp done_f
    for done_f in ${BACKED_UP+"${BACKED_UP[@]}"}; do
        [[ "$done_f" == "$f" ]] && return 0
    done
    stamp=$(date +%Y%m%d-%H%M%S)
    # Fatal, not best-effort. There is no `set -e` here, so an unchecked `cp`
    # would let the rewrite below overwrite an uncommitted, unversioned file
    # with no copy of it anywhere.
    cp -p "$f" "$f.forest-$stamp.bak" || die "could not back up $f — refusing to edit it"
    BACKED_UP+=("$f")
    note "backed up $(basename "$f") -> $(basename "$f").forest-$stamp.bak"
}

# --- 1. the entry point the registration will name ---------------------------
#
# Nothing to install: the launch is the direct path (`qs -p <repo>/shell.qml`),
# per the #13 assembly refinements closing A1 — see registration.env. So this
# step only checks the path it is about to hand shell-switch is real, because a
# SHELL_DB entry naming a file that is not there fails at switch time with
# shell-switch's own rollback rather than anything readable.

[[ -f "$FOREST_REPO/shell.qml" ]] \
    || die "no shell.qml at $FOREST_REPO — that is what the registration would launch"
ok "entry point: $FOREST_REPO/shell.qml"

# --- 2. the SHELL_DB block ---------------------------------------------------
#
# Written as one block ending at the closing brace of init_shell_db, matching
# how the three existing entries are laid out. Rewriting rather than appending
# keeps this idempotent: a re-run after a value changed here replaces the old
# block instead of stacking a second one.

block=$(cat <<EOF
    # forest-shell (registered by tools/register-shell-switch.sh — #57)
    SHELL_DB[$FOREST_ID.name]="$FOREST_NAME"
    SHELL_DB[$FOREST_ID.launch_cmd]="$FOREST_LAUNCH_CMD"
    SHELL_DB[$FOREST_ID.launcher_cmd]="$FOREST_LAUNCHER_CMD"
    SHELL_DB[$FOREST_ID.process_pattern]="$FOREST_PROCESS_PATTERN"
    SHELL_DB[$FOREST_ID.packages]="$FOREST_PACKAGES"
    SHELL_DB[$FOREST_ID.id]="$FOREST_ID"
EOF
)

existing=$(grep -c "SHELL_DB\[$FOREST_ID\." "$MANAGER" || true)
want_lines=6

if (( existing == want_lines )) && diff -q \
        <(grep "SHELL_DB\[$FOREST_ID\." "$MANAGER" | sed 's/^ *//') \
        <(grep "SHELL_DB\[$FOREST_ID\." <<< "$block" | sed 's/^ *//') > /dev/null 2>&1; then
    ok "the $FOREST_ID entry in shell-manager.sh is up to date"
else
    if (( existing )); then
        would "replace the existing $FOREST_ID entry in shell-manager.sh ($existing lines)"
    else
        would "add the $FOREST_ID entry to shell-manager.sh"
    fi
    if (( ! CHECK )); then
        backup "$MANAGER"
        tmp=$(mktemp)
        # Drop any previous entry (its lines and its comment), then insert the
        # block before the closing brace of init_shell_db.
        awk -v id="$FOREST_ID" -v block="$block" '
            /^init_shell_db\(\)/ { inside = 1 }
            inside && $0 ~ ("SHELL_DB\\[" id "\\.") { next }
            inside && /register-shell-switch\.sh/ { next }
            inside && /^\}/ {
                printf "\n%s\n", block
                inside = 0
            }
            { print }
        ' "$MANAGER" > "$tmp"

        got=$(grep -c "SHELL_DB\[$FOREST_ID\." "$tmp" || true)
        (( got == want_lines )) || { rm -f "$tmp"; die "rewrite produced $got $FOREST_ID lines, expected $want_lines — left $MANAGER alone"; }
        bash -n "$tmp" || { rm -f "$tmp"; die "rewrite would not parse as bash — left $MANAGER alone"; }

        cat "$tmp" > "$MANAGER"   # preserve the original inode, mode and any symlink
        rm -f "$tmp"
        ok "wrote the $FOREST_ID entry into shell-manager.sh"
    fi
fi

# --- 3. the menu list --------------------------------------------------------
#
# get_all_shells() is both the fzf menu order and the order detect_running_shell
# tries patterns in. Appended, so forest is matched last and cannot shadow an
# existing shell's pattern.

menu=$(sed -n 's/^ *echo "\(.*\)" *$/\1/p' <<< "$(sed -n '/^get_all_shells()/,/^}/p' "$MANAGER")")
if [[ " $menu " == *" $FOREST_ID "* ]]; then
    ok "get_all_shells() already lists $FOREST_ID (\"$menu\")"
elif [[ -z "$menu" ]]; then
    die "could not read the shell list out of get_all_shells() — refusing to guess"
else
    would "append $FOREST_ID to get_all_shells() (\"$menu\" -> \"$menu $FOREST_ID\")"
    if (( ! CHECK )); then
        backup "$MANAGER"
        tmp=$(mktemp)
        awk -v old="$menu" -v new="$menu $FOREST_ID" '
            /^get_all_shells\(\)/ { inside = 1 }
            inside && index($0, "\"" old "\"") { sub("\"" old "\"", "\"" new "\""); inside = 0 }
            { print }
        ' "$MANAGER" > "$tmp"
        bash -n "$tmp" || { rm -f "$tmp"; die "rewrite would not parse as bash — left $MANAGER alone"; }
        cat "$tmp" > "$MANAGER"
        rm -f "$tmp"
        ok "get_all_shells() now lists $FOREST_ID"
    fi
fi

# --- 4. config.json, which nothing reads -------------------------------------
#
# `.shells` is write-only metadata: grepping the tool confirms nothing reads
# .shells, .installed or .package at any point — install.sh produces it once and
# only .current_shell, .last_switch and .switch_count are touched afterwards.
# Updated anyway so the file does not lie about what is registered.

if [[ ! -f "$CONFIG_JSON" ]]; then
    note "no config.json at $CONFIG_JSON — skipping (it is cosmetic)"
elif ! command -v jq > /dev/null; then
    note "jq not found — skipping the cosmetic config.json update"
elif [[ "$(jq -r --arg id "$FOREST_ID" '.shells[$id].name // ""' "$CONFIG_JSON")" == "$FOREST_NAME" ]]; then
    ok "config.json already describes $FOREST_ID"
else
    would "add $FOREST_ID to config.json's .shells (cosmetic — nothing reads it)"
    if (( ! CHECK )); then
        backup "$CONFIG_JSON"
        tmp=$(mktemp)
        jq --arg id "$FOREST_ID" --arg name "$FOREST_NAME" --arg pkg "$FOREST_PACKAGES" \
           '.shells[$id] = {name: $name, installed: true, package: $pkg}' \
           "$CONFIG_JSON" > "$tmp" && cat "$tmp" > "$CONFIG_JSON"
        rm -f "$tmp"
        ok "config.json now describes $FOREST_ID"
    fi
fi

printf '\n'
if (( CHECK )); then
    if (( changes )); then
        printf '%d change(s) pending — re-run without --check to apply\n' "$changes"
        exit 1
    fi
    printf 'forest-shell is registered with shell-switch\n'
    exit 0
fi

printf 'registered. Two things this does not do:\n'
printf '  - switch to it. Run `shell-switch` and pick "%s".\n' "$FOREST_NAME"
printf '  - reload Hyprland. shell-switch never calls reload_compositor(), so the\n'
printf '    new SUPER+Space bind is inert until you run `hyprctl reload`.\n'
