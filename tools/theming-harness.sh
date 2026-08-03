#!/usr/bin/env bash
# The constrained accent against a real shell (#58).
#
#   tools/theming-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/theming-harness.sh --keep   # leave the nested session up to poke at
#
# What is *not* here, on purpose: the colour space, the band, the shift cap, the
# concentration threshold and the contrast guarantee are decisions over numbers,
# and they are checked at the first seam in tests/tst_accentpolicy.qml — where
# the whole 25-image reference corpus costs 30ms rather than a compositor.
#
# What is here is everything that only exists once a shell is running: whether a
# *new wallpaper* actually retunes the accent, whether the mode switch takes
# effect live, and whether the answer reaches the settings file consumers read
# it from. Those are lifecycles, not arithmetic, and #81 is what happens when a
# lifecycle has no seam.
#
#   1. fixed forest samples nothing and writes nothing
#   2. selecting the constrained accent tunes it, live, with no restart
#   3. the tuned hue is inside the sage–lake band
#   4. a lake-blue wallpaper moves the accent lake-ward
#   5. ...and a pine-green one moves it sage-ward — the retune of criterion 1
#   6. an amber wallpaper is clamped rather than obeyed
#   7. a greyscale wallpaper keeps the shipped accent, and says so
#      (only the two teal roles are ever written, checked alongside 4)
#   8. going back to fixed forest deletes the key rather than freezing a sample
#
# The shell under test runs against a scratch XDG_CONFIG_HOME and
# XDG_STATE_HOME: every check here writes settings, and a harness that repainted
# the accent of the session running it is one nobody will run twice.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

command -v jq > /dev/null || { echo "jq is needed to read the files back" >&2; exit 1; }

log_lines() { wc -l < "$NESTED_SHELL_LOG" 2>/dev/null || echo 0; }
since() { tail -n "+$(($1 + 1))" "$NESTED_SHELL_LOG" 2>/dev/null; }

## Wait for a line that arrived after `mark`, and report it as a check.
expect_since() {
    local mark="$1" pattern="$2" what="$3"
    for _ in $(seq 1 60); do
        if since "$mark" | grep -qaE "$pattern"; then
            nested_pass "$what"
            return 0
        fi
        sleep 0.1
    done
    nested_fail "$what — nothing matching /$pattern/ since the change"
    nested_note "$(since "$mark" | grep -a theming | tail -3)"
    return 1
}

## The hue from the most recent "accent tuned to N°" line since `mark`, or "".
tuned_hue() {
    since "$1" | grep -aoE 'accent tuned to [0-9.]+' | tail -1 | grep -oE '[0-9.]+$'
}

await_json() {
    local file="$1" filter="$2" what="$3"
    for _ in $(seq 1 80); do
        if [[ -f "$file" ]] && jq -e "$filter" "$file" > /dev/null 2>&1; then
            nested_pass "$what"
            return 0
        fi
        sleep 0.1
    done
    nested_fail "$what — $filter never held for $file"
    [[ -f "$file" ]] && nested_note "$(tr -d '\n' < "$file")"
    return 1
}

refute_json() {
    local file="$1" filter="$2" what="$3"
    if [[ -f "$file" ]] && jq -e "$filter" "$file" > /dev/null 2>&1; then
        nested_fail "$what — $filter holds for $file"
        nested_note "$(tr -d '\n' < "$file")"
        return 1
    fi
    nested_pass "$what"
}

## Whether an awk expression over two numbers holds, as a check.
expect_math() {
    local expression="$1" what="$2"
    if awk "BEGIN { exit !($expression) }"; then
        nested_pass "$what"
    else
        nested_fail "$what — $expression is false"
    fi
}

nested_up || exit 1

SCRATCH="$NESTED_WORK/xdg"
CONFIG="$SCRATCH/config/forest-shell"
PAPERS="$NESTED_WORK/wallpapers"
mkdir -p "$CONFIG" "$SCRATCH/state" "$PAPERS"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state")

SETTINGS="$CONFIG/settings.json"

# The shipped accent, so the checks below can say "it moved" without hard-coding
# the answer they expect it to have moved to — that number is seam 1's business.
SHIPPED_HUE=201.9

# Four wallpapers with a hue each, written the way tools/capture-harness.sh
# writes its own: struct and zlib, because the alternative is a Pillow
# dependency for fifteen lines of packing.
#
# A vertical ramp from a quarter brightness to full rather than a flat fill, so
# the quantizer has clusters to split and the near-black end exercises the
# lightness filter that drops a photograph's shadows.
paper() {
    python3 - "$PAPERS/$1.png" "$2" "$3" "$4" <<'EOF'
import struct
import sys
import zlib

path, r, g, b = sys.argv[1], *(int(v) for v in sys.argv[2:5])
w = h = 128

raw = bytearray()
for y in range(h):
    t = 0.25 + 0.75 * y / (h - 1)
    raw.append(0)                      # filter type: none
    raw += bytes((int(r * t), int(g * t), int(b * t))) * w


def chunk(tag, payload):
    return (struct.pack(">I", len(payload)) + tag + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))


with open(path, "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n")
    f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
    f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 6)))
    f.write(chunk(b"IEND", b""))
EOF
}

# Three hues far enough apart that consecutive checks cannot be satisfied by a
# stale answer: each one has to produce a different accent from the one before
# it, so a service that stopped recomputing would be caught rather than pass by
# standing still.
paper lake  31 79 143      # deep water at 256° — clamped lake-ward
paper pine   0 143 131     # 184° — inside the shift cap, so it passes through
paper amber 211 105 31     # the research's pin24 at 50° — clamped sage-ward
paper grey  128 128 128    # no hue at all

## Change a settings key and let the shell's watcher pick it up. The mode, the
## wallpaper and the dark/light flip are all settings keys, so this is the whole
## control surface — no IPC verb exists for any of them, and driving them
## through the file is also how a user with an editor drives them.
##
## An *edit* of the file rather than a rewrite of it, because the shell writes
## the sampled accent into the same file: a harness that replaced the whole
## document would delete `appearance.dynamic` itself and then check the shell
## for having deleted it. That is a check that passes whatever the shell does.
settings() {
    local filter="$1"
    jq "$filter" "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
}

mode() { settings ".appearance.mode = \"$1\""; }
wallpaper() { settings ".wallpaper.path = \"$PAPERS/$1.png\""; }

# --- 1. fixed forest samples nothing -----------------------------------------

cat > "$SETTINGS" <<EOF
{
  "settingsVersion": 2,
  "appearance": { "mode": "forest", "darkMode": true },
  "wallpaper": { "path": "$PAPERS/lake.png" }
}
EOF

nested_shell shell.qml 'theming ready' || exit 1

expect_since 0 'stage theming ready \(mode forest\)' \
    'the theming service comes up and says which mode it is in'
sleep 1
refute_json "$SETTINGS" '.appearance.dynamic' \
    'fixed forest writes no sampled accent — the shipped palette is untouched'

# --- 2. selecting the constrained accent tunes it, live ----------------------

mark=$(log_lines)
mode accent
expect_since "$mark" 'theming: accent tuned to' \
    'switching to the constrained accent tunes it with no restart'
await_json "$SETTINGS" '.appearance.dynamic.accentPrimary' \
    'the tuned accent reaches the settings file consumers read'

# --- 3. ...inside the band ---------------------------------------------------

lake_hue=$(tuned_hue "$mark")
if [[ -z "$lake_hue" ]]; then
    nested_fail 'no tuned hue was logged, so the band cannot be checked'
else
    expect_math "$lake_hue >= 118 && $lake_hue <= 240" \
        "the tuned hue ${lake_hue}° is inside the sage–lake band"
fi

# --- 4. a lake-blue wallpaper moves the accent lake-ward ---------------------

expect_math "$lake_hue > $SHIPPED_HUE" \
    "a lake-blue wallpaper moved the accent lake-ward (${lake_hue}° > ${SHIPPED_HUE}°)"

lake_accent=$(jq -r '.appearance.dynamic.accentPrimary' "$SETTINGS")

await_json "$SETTINGS" \
    '(.appearance.dynamic | keys) == ["accentDeep", "accentPrimary"]' \
    'a sampled accent is two roles and no more — nothing else is generated'

# --- 5. ...and a pine-green one moves it sage-ward ---------------------------
#
# The ticket's first acceptance criterion: switching wallpaper retunes the
# accent, and it does so without the mode being touched or the shell restarted.

mark=$(log_lines)
wallpaper pine
expect_since "$mark" 'theming: accent tuned to' \
    'a new wallpaper retunes the accent on its own'
pine_hue=$(tuned_hue "$mark")
if [[ -z "$pine_hue" ]]; then
    nested_fail 'the wallpaper change logged no hue'
else
    expect_math "$pine_hue < $SHIPPED_HUE && $pine_hue >= 118" \
        "a pine-green wallpaper moved the accent sage-ward (${pine_hue}°)"
fi
await_json "$SETTINGS" \
    ".appearance.dynamic.accentPrimary != \"$lake_accent\"" \
    'the two wallpapers produced two different accents'

# --- 6. an amber wallpaper is clamped rather than obeyed ---------------------
#
# 50° is lamplight, 150° from the shipped teal and far outside the band. The
# whole point of a constrained mode is that this wallpaper does not turn the
# shell orange.

mark=$(log_lines)
wallpaper amber
expect_since "$mark" 'theming: accent tuned to' 'the amber wallpaper is sampled'
amber_hue=$(tuned_hue "$mark")
if [[ -z "$amber_hue" ]]; then
    nested_fail 'the amber wallpaper logged no hue'
else
    expect_math "$amber_hue >= 118 && $amber_hue <= 240" \
        "an amber wallpaper is clamped into the band (${amber_hue}°), not obeyed"
fi

# --- 7. a greyscale wallpaper keeps the shipped accent -----------------------
#
# Failing closed, and saying which of the two silences it is: "the mode declined"
# and "the service never ran" look identical from outside.

mark=$(log_lines)
wallpaper grey
expect_since "$mark" 'theming: accent kept: no dominant hue' \
    'a wallpaper with no dominant hue keeps the shipped accent, and says so'
await_json "$SETTINGS" '(.appearance | has("dynamic")) == false' \
    'keeping the shipped accent deletes the sample rather than freezing it'

# --- 8. going back to fixed forest deletes the sample ------------------------
#
# The ticket's fourth acceptance criterion. A mode that left its last sample
# behind would make fixed forest mean "whatever wallpaper you had when you
# turned it off".

mark=$(log_lines)
wallpaper lake
expect_since "$mark" 'theming: accent tuned to' 'the accent is sampled again'
await_json "$SETTINGS" '.appearance.dynamic.accentPrimary' \
    'there is a sample to clear'

mark=$(log_lines)
mode forest
expect_since "$mark" 'theming: accent cleared \(mode forest\)' \
    'leaving the mode says so, distinctly from declining to sample'
await_json "$SETTINGS" '(.appearance | has("dynamic")) == false' \
    'fixed forest is the shipped row again, with no sample left behind'

printf '\n'
if (( nested_fail_count )); then
    printf '%d check(s) failed\n' "$nested_fail_count"
    exit 1
fi
printf 'all checks passed\n'
