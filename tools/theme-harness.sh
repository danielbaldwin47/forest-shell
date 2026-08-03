#!/usr/bin/env bash
# Save, apply, undo and delete a theme preset against a real shell (#56).
#
#   tools/theme-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/theme-harness.sh --keep   # leave the nested session up to poke at
#
# What is *not* here, on purpose: which keys a theme carries, what apply plans,
# what "Forest (default)" means, name rules and the coercion floor are all
# decisions, and they are checked at the first seam in tests/tst_themepolicy.qml
# where they cost 70ms rather than a compositor.
#
# What is here is everything that only exists once files and the config engine
# are involved — a theme is a file written to one directory, read back from it,
# and applied by writing another file the shell is simultaneously watching:
#
#   1. `ipc call theme save <name>` writes themes/<name>.json
#   2. what it wrote is sparse — the skin, and not a whole config
#   3. applying a theme lands its keys in settings.json
#   4. applying does not touch layout keys, or keys the schema never knew
#   5. a theme carrying an out-of-range value is applied coerced, not raw (#79)
#   6. "Forest (default)" deletes the flagged keys rather than writing defaults
#   7. the undo slot restores the state from just before the apply
#   8. a hand-written theme with an old settingsVersion migrates on apply
#   9. delete removes the file and leaves the settings alone
#  10. a refused name is refused with a reason, and writes nothing
#
# The shell under test runs against a scratch XDG_CONFIG_HOME and
# XDG_STATE_HOME: every check here writes settings, and a harness that rewrote
# the settings of the session running it is one nobody will run twice.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

ipc() { nested_ipc call theme "$@"; }

log_lines() { wc -l < "$NESTED_SHELL_LOG" 2>/dev/null || echo 0; }
since() { tail -n "+$(($1 + 1))" "$NESTED_SHELL_LOG" 2>/dev/null; }

## Wait for a line that arrived after `mark`, and report it as a check.
expect_since() {
    local mark="$1" pattern="$2" what="$3"
    for _ in $(seq 1 50); do
        if since "$mark" | grep -qaE "$pattern"; then
            nested_pass "$what"
            return 0
        fi
        sleep 0.1
    done
    nested_fail "$what — nothing matching /$pattern/ since the call"
    return 1
}

## Wait for a file to satisfy a jq expression. Every settings write is debounced
## and atomic, so "has the shell written this yet" is a poll on the file rather
## than a sleep after the call.
await_json() {
    local file="$1" filter="$2" what="$3"
    for _ in $(seq 1 60); do
        if [[ -f "$file" ]] && jq -e "$filter" "$file" > /dev/null 2>&1; then
            nested_pass "$what"
            return 0
        fi
        sleep 0.1
    done
    nested_fail "$what — $filter never held for $file"
    [[ -f "$file" ]] && nested_note "$(cat "$file")"
    return 1
}

## The same, for something that must *not* become true — checked once the shell
## has been given the same window to do it in.
refute_json() {
    local file="$1" filter="$2" what="$3"
    if [[ -f "$file" ]] && jq -e "$filter" "$file" > /dev/null 2>&1; then
        nested_fail "$what — $filter holds for $file"
        nested_note "$(cat "$file")"
        return 1
    fi
    nested_pass "$what"
}

command -v jq > /dev/null || { echo "jq is needed to read the files back" >&2; exit 1; }

nested_up || exit 1

SCRATCH="$NESTED_WORK/xdg"
CONFIG="$SCRATCH/config/forest-shell"
STATE="$SCRATCH/state/quickshell/by-path"
mkdir -p "$CONFIG" "$SCRATCH/state"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state")

SETTINGS="$CONFIG/settings.json"
THEMES="$CONFIG/themes"

# A shell wearing a skin worth saving, plus two keys that must not travel with
# it: a layout key, and a key no schema has ever heard of. Seeded before the
# first read, so the shell comes up already wearing it.
cat > "$SETTINGS" <<'EOF'
{
  "settingsVersion": 2,
  "appearance": {
    "paletteOverrides": { "accentPrimary": "#8fbf9f" }
  },
  "bar": {
    "height": 40,
    "surface": { "opacity": 0.72, "blur": false }
  },
  "somethingTheSchemaHasNeverHeardOf": { "kept": true }
}
EOF

nested_shell shell.qml 'themes armed' || exit 1

# --- 1. save writes a file ---------------------------------------------------

mark=$(log_lines)
ipc save Moss > /dev/null
expect_since "$mark" 'theme: saved "Moss"' 'ipc call theme save writes a theme'
await_json "$THEMES/Moss.json" '.bar.surface.opacity == 0.72' \
    'the theme file holds the skin that was on screen'

# --- 2. ...and it holds the skin and nothing else ----------------------------

refute_json "$THEMES/Moss.json" '.bar.height' \
    'a saved theme carries no layout — bar.height stayed on the machine'
refute_json "$THEMES/Moss.json" '.somethingTheSchemaHasNeverHeardOf' \
    'a saved theme carries nothing outside the flagged keys'
await_json "$THEMES/Moss.json" '.settingsVersion == 2' \
    'a theme carries its own settingsVersion'
await_json "$THEMES/Moss.json" '(.bar.surface | has("grain")) == false' \
    'a saved theme is sparse — an untouched knob is not frozen into it'

# --- 3. a second theme, and applying it --------------------------------------

cat > "$THEMES/Ridge.json" <<'EOF'
{
  "settingsVersion": 2,
  "appearance": { "paletteOverrides": { "accentPrimary": "#c08a5a" } },
  "bar": { "ridgeline": { "unitWidth": 20 } }
}
EOF

mark=$(log_lines)
ipc apply Ridge > /dev/null
expect_since "$mark" 'theme: applied "Ridge"' 'ipc call theme apply applies a theme'
await_json "$SETTINGS" '.bar.ridgeline.unitWidth == 20' \
    'applying copies the theme keys into settings.json'
await_json "$SETTINGS" '.appearance.paletteOverrides.accentPrimary == "#c08a5a"' \
    'applying replaces a flagged group rather than merging into it'
await_json "$SETTINGS" '(.bar | has("surface")) == false' \
    'a key the theme is silent about is deleted, not left behind'

# --- 4. ...and touches nothing else ------------------------------------------

await_json "$SETTINGS" '.bar.height == 40' \
    'applying leaves layout alone'
await_json "$SETTINGS" '.somethingTheSchemaHasNeverHeardOf.kept == true' \
    'applying preserves keys the schema has never heard of'

# --- 5. the floor a theme cannot get under (#79) -----------------------------
#
# 0.2 measured 1.25:1 against the wallpaper. A theme travels between machines
# and settingsVersions and this one carries a value from under the floor: the
# config engine's coercer is what stands between it and the screen.

cat > "$THEMES/Faint.json" <<'EOF'
{ "settingsVersion": 2, "bar": { "surface": { "opacity": 0.2 } } }
EOF

mark=$(log_lines)
ipc apply Faint > /dev/null
expect_since "$mark" 'theme: applied "Faint"' 'a theme from under the floor still applies'
await_json "$SETTINGS" '.bar.surface.opacity == 0.65' \
    'an out-of-range opacity is applied at the floor, not raw'

# --- 6. the shipped look is the deletion of the flagged keys -----------------

mark=$(log_lines)
ipc reset > /dev/null
expect_since "$mark" 'theme: applied "Forest \(default\)"' \
    'ipc call theme reset applies the shipped look'
await_json "$SETTINGS" '(.bar | has("surface")) == false and (.bar | has("ridgeline")) == false' \
    'Forest (default) deletes the flagged keys rather than writing defaults'
await_json "$SETTINGS" '(.appearance | not) or (.appearance | has("paletteOverrides") | not)' \
    'the palette overrides go with them'
await_json "$SETTINGS" '.bar.height == 40' \
    'and the layout is still there afterwards'

# --- 7. undo puts back what was there just before ----------------------------

mark=$(log_lines)
ipc undo > /dev/null
expect_since "$mark" 'theme: applied "Previous settings"' 'ipc call theme undo applies the slot'
await_json "$SETTINGS" '.bar.surface.opacity == 0.65' \
    'undo restores the state from just before the apply'

# Twice, because undo is itself an apply: the slot is always the other state,
# rather than a stack that can be walked off the end of.
mark=$(log_lines)
ipc undo > /dev/null
await_json "$SETTINGS" '(.bar | has("surface")) == false' \
    'undoing the undo goes back again'

# --- 8. a theme from an older shell migrates on the way in -------------------

cat > "$THEMES/Ancient.json" <<'EOF'
{ "settingsVersion": 1, "bar": { "surface": { "opacity": 0.9 } } }
EOF

mark=$(log_lines)
ipc apply Ancient > /dev/null
expect_since "$mark" 'theme: migrated "Ancient" v1 to v2' \
    'a theme with an old settingsVersion is migrated on apply'
await_json "$SETTINGS" '.bar.surface.opacity == 0.9' \
    'and is applied once it has been'

# --- 9. delete takes the file and nothing else -------------------------------

mark=$(log_lines)
ipc remove Moss > /dev/null
expect_since "$mark" 'theme: deleted "Moss"' 'ipc call theme remove deletes the file'
for _ in $(seq 1 30); do [[ -f "$THEMES/Moss.json" ]] || break; sleep 0.1; done
if [[ -f "$THEMES/Moss.json" ]]; then
    nested_fail 'the theme file is still there after a delete'
else
    nested_pass 'the theme file is gone'
fi
await_json "$SETTINGS" '.bar.surface.opacity == 0.9' \
    'deleting a theme does not undress the shell'

# --- 10. a refused name is refused out loud ----------------------------------

mark=$(log_lines)
ipc save ../escape > /dev/null
expect_since "$mark" 'theme: refusing "\.\./escape": a name cannot contain a slash' \
    'a name that would escape the themes directory is refused, with a reason'
if [[ -e "$CONFIG/escape.json" ]]; then
    nested_fail 'a name with a slash in it wrote a file outside the themes directory'
else
    nested_pass 'a name with a slash in it wrote nothing outside the themes directory'
fi
if [[ -e "$CONFIG/escape.json" || -e "$THEMES/../escape.json" ]]; then
    nested_fail 'a refused name wrote a file anyway'
else
    nested_pass 'a refused name writes nothing'
fi

mark=$(log_lines)
ipc apply Nonesuch > /dev/null
expect_since "$mark" 'theme: refusing "Nonesuch": cannot read ' \
    'applying a theme that is not there is refused, with a reason'

# --- what the state file remembers -------------------------------------------

state_file=$(find "$SCRATCH/state" -name state.json 2>/dev/null | head -1)
if [[ -n "$state_file" ]] && jq -e '.theme.lastApplied == "Ancient"' "$state_file" > /dev/null 2>&1; then
    nested_pass 'the breadcrumb names the theme that was applied'
else
    nested_fail "the breadcrumb is not \"Ancient\": $(jq -c '.theme' "${state_file:-/dev/null}" 2>/dev/null)"
fi

printf '\n'
if (( nested_fail_count )); then
    printf '%d check(s) failed\n' "$nested_fail_count"
    exit 1
fi
printf 'all checks passed\n'
