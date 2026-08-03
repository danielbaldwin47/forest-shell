#!/usr/bin/env bash
# The full-dynamic palette against a real shell (#59).
#
#   tools/matugen-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/matugen-harness.sh --keep   # leave the nested session up to poke at
#
# What is *not* here, on purpose: the mapping, the two output shapes, the strict
# exit status and the contrast floor are decisions over a JSON document, and
# they are checked at the first seam in tests/tst_matugenpolicy.qml against real
# matugen output — where a wallpaper costs a millisecond rather than a
# compositor.
#
# What is here is everything that only exists once a shell is running: a
# subprocess, its exit status, the binary being absent, and whether a wallpaper
# change actually reaches all seventeen roles of a palette consumers read from a
# file.
#
#   1. selecting full dynamic generates a palette, live, with no restart
#   2. it is the whole palette — seventeen roles, not the accent's two
#   3. a new wallpaper regenerates it
#   4. the dark/light flip regenerates it as the other row
#   5. templates are off: matugen renders nothing into the user's own config
#   6. ...and on, it does — the opt-in is real and not just documented
#   7. going back to fixed forest deletes the palette rather than freezing it
#   8. switching to the constrained accent drops the palette before it tunes
#   9. without matugen: the mode says so once, writes nothing, and throws nothing
#  10. the generated palette holds the contrast floor as a picture (seam 3)
#
# The shell under test runs against a scratch XDG_CONFIG_HOME and
# XDG_STATE_HOME — which is also what makes check 5 and 6 safe, since matugen
# reads its template config from there and a harness that rendered the caller's
# own templates would restyle the terminal it was launched from.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

command -v jq > /dev/null || { echo "jq is needed to read the files back" >&2; exit 1; }
MATUGEN_BIN=$(command -v matugen) || {
    echo "matugen is not installed — this harness tests the mode that needs it." >&2
    echo "Install it (pacman -S matugen, or cargo install matugen) and re-run." >&2
    exit 2
}

log_lines() { wc -l < "$NESTED_SHELL_LOG" 2>/dev/null || echo 0; }
since() { tail -n "+$(($1 + 1))" "$NESTED_SHELL_LOG" 2>/dev/null; }

expect_since() {
    local mark="$1" pattern="$2" what="$3"
    for _ in $(seq 1 80); do
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

refute_since() {
    local mark="$1" pattern="$2" what="$3"
    if since "$mark" | grep -qaE "$pattern"; then
        nested_fail "$what — /$pattern/ appeared"
        nested_note "$(since "$mark" | grep -aE "$pattern" | tail -3)"
        return 1
    fi
    nested_pass "$what"
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
    [[ -f "$file" ]] && nested_note "$(tr -d '\n' < "$file" | head -c 400)"
    return 1
}

refute_json() {
    local file="$1" filter="$2" what="$3"
    if [[ -f "$file" ]] && jq -e "$filter" "$file" > /dev/null 2>&1; then
        nested_fail "$what — $filter holds for $file"
        nested_note "$(tr -d '\n' < "$file" | head -c 400)"
        return 1
    fi
    nested_pass "$what"
}

nested_up || exit 1

SCRATCH="$NESTED_WORK/xdg"
CONFIG="$SCRATCH/config/forest-shell"
PAPERS="$NESTED_WORK/wallpapers"
mkdir -p "$CONFIG" "$SCRATCH/state" "$PAPERS"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state")

SETTINGS="$CONFIG/settings.json"

# Wallpapers, written the way tools/theming-harness.sh writes its own: struct
# and zlib rather than a Pillow dependency for fifteen lines of packing. A
# vertical ramp rather than a flat fill, because matugen refuses an image it
# cannot pick a source colour from and a single flat colour is the degenerate
# case — the mode has to work on pictures, and a picture has a range.
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

# Two hues far enough apart that a shell which stopped regenerating cannot pass
# check 3 by standing still.
paper lake  31 79 143
paper amber 211 105 31

settings() {
    local filter="$1"
    jq "$filter" "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
}

## Apply an edit and make sure it survives — the shell writes this same file,
## so an edit that lands between its read and its write is silently reverted.
## tools/theming-harness.sh makes the argument at length.
apply_setting() {
    local filter="$1" check="$2" what="$3"
    for _ in $(seq 1 10); do
        settings "$filter"
        sleep 0.4
        jq -e "$check" "$SETTINGS" > /dev/null 2>&1 && return 0
    done
    nested_fail "$what — the edit never survived the shell's own writes"
    return 1
}

mode() {
    apply_setting ".appearance.mode = \"$1\"" ".appearance.mode == \"$1\"" \
        "selecting the $1 mode"
}

wallpaper() {
    apply_setting ".wallpaper.path = \"$PAPERS/$1.png\"" \
        ".wallpaper.path == \"$PAPERS/$1.png\"" "hanging the $1 wallpaper"
}

# --- 1. selecting full dynamic generates a palette, live ---------------------

cat > "$SETTINGS" <<EOF
{
  "settingsVersion": 2,
  "appearance": { "mode": "forest", "darkMode": true },
  "wallpaper": { "path": "$PAPERS/lake.png" }
}
EOF

nested_shell shell.qml 'theming ready' || exit 1

expect_since 0 'theming: matugen found' \
    'the shell probes for matugen at startup and finds it'

mark=$(log_lines)
mode dynamic
expect_since "$mark" 'theming: palette generated \(dark\)' \
    'switching to full dynamic generates a palette with no restart'
await_json "$SETTINGS" '.appearance.dynamic.bgBase' \
    'the generated palette reaches the settings file consumers read'

# --- 2. it is the whole palette ----------------------------------------------
#
# The difference between this mode and #58's in one check: the constrained
# accent writes two roles and leaves every background and every text colour
# where the brief put them. This one replaces the design system.

await_json "$SETTINGS" '(.appearance.dynamic | keys | length) == 17' \
    "the generated palette is all seventeen roles, not the accent mode's two"
await_json "$SETTINGS" \
    '[.appearance.dynamic | to_entries[] | select(.value | test("^#[0-9a-f]{6}$") | not)] | length == 0' \
    'every generated role is a colour the settings file can parse'

lake_bg=$(jq -r '.appearance.dynamic.bgBase' "$SETTINGS")
lake_accent=$(jq -r '.appearance.dynamic.accentPrimary' "$SETTINGS")

# --- 3. a new wallpaper regenerates it ----------------------------------------
#
# The ticket's first acceptance criterion. matugen is a subprocess and notices
# nothing on its own, so this is the check that the *shell* noticed.

mark=$(log_lines)
wallpaper amber
expect_since "$mark" 'theming: palette generated' \
    'a new wallpaper regenerates the palette on its own'
await_json "$SETTINGS" ".appearance.dynamic.accentPrimary != \"$lake_accent\"" \
    'the two wallpapers produced two different palettes'
await_json "$SETTINGS" ".appearance.dynamic.bgBase != \"$lake_bg\"" \
    'the backgrounds moved too — this is the full palette and not an accent'

# --- 4. the dark/light flip regenerates it as the other row ------------------

mark=$(log_lines)
apply_setting '.appearance.darkMode = false' '.appearance.darkMode == false' \
    'switching to light mode'
expect_since "$mark" 'theming: palette generated \(light\)' \
    'the dark/light flip regenerates the palette as the other row'
# Lexicographic on two lowercase hex digits is numeric on a byte, which is the
# whole check: the light row's base has to be *pale*, and a mode that flipped
# the flag without re-reading matugen would leave a near-black one behind.
await_json "$SETTINGS" \
    '(.appearance.dynamic.bgBase[1:3] | ascii_downcase) > "c0"' \
    'the light row is a light row — its base is pale rather than near-black'

apply_setting '.appearance.darkMode = true' '.appearance.darkMode == true' \
    'switching back to dark mode'

# --- 5/6. external templates are opt-in --------------------------------------
#
# The ticket's third acceptance criterion, and the reason it is a check rather
# than a paragraph: "documented as opt-in" is only true if the default actually
# renders nothing. matugen reads its templates from XDG_CONFIG_HOME, which is
# the scratch one here, so this writes a template of its own and looks for the
# file it would produce.

mkdir -p "$SCRATCH/config/matugen/templates"
cat > "$SCRATCH/config/matugen/templates/proof.txt" <<'EOF'
{{colors.primary.default.hex}}
EOF
cat > "$SCRATCH/config/matugen/config.toml" <<EOF
[config]

[templates.proof]
input_path = "$SCRATCH/config/matugen/templates/proof.txt"
output_path = "$SCRATCH/rendered-by-matugen.txt"
EOF

mark=$(log_lines)
wallpaper lake
expect_since "$mark" 'theming: palette generated' 'the palette regenerates with a template configured'
sleep 0.5
if [[ -e "$SCRATCH/rendered-by-matugen.txt" ]]; then
    nested_fail 'templates are off by default — nothing outside the shell is written'
    nested_note "$SCRATCH/rendered-by-matugen.txt exists"
else
    nested_pass 'templates are off by default — nothing outside the shell is written'
fi

# The toggle on its own, with no wallpaper change behind it: turning the opt-in
# on is a request to restyle the external apps *now*, and a shell that waited
# for the next wallpaper change to honour it would look like a switch that did
# nothing.
mark=$(log_lines)
apply_setting '.appearance.matugenTemplates = true' \
    '.appearance.matugenTemplates == true' 'turning external templates on'
expect_since "$mark" 'theming: palette generated' \
    'turning the opt-in on regenerates on its own, with no wallpaper change'
rendered=0
for _ in $(seq 1 40); do
    [[ -e "$SCRATCH/rendered-by-matugen.txt" ]] && { rendered=1; break; }
    sleep 0.1
done
if (( rendered )); then
    nested_pass "turning the opt-in on renders the user's own templates"
else
    nested_fail "turning the opt-in on renders the user's own templates — nothing was written"
fi

apply_setting '.appearance.matugenTemplates = false' \
    '.appearance.matugenTemplates == false' 'turning external templates back off'

# The palette the *shell* generated, kept for the seam-3 measurement at the end
# — the real output of the real mode rather than a re-derivation of it.
GENERATED="$NESTED_WORK/generated-palette.json"
jq '.appearance.dynamic' "$SETTINGS" > "$GENERATED"

# --- 7. going back to fixed forest deletes the palette -----------------------
#
# The ticket's fourth acceptance criterion. "Restores instantly" is a file
# deletion and a repaint: a mode that left its last generated palette behind
# would make fixed forest mean "whatever wallpaper you had when you turned it
# off".

mark=$(log_lines)
mode forest
expect_since "$mark" 'theming: generated palette cleared \(mode forest\)' \
    'leaving the mode says so, and says it was the generated one'
await_json "$SETTINGS" '(.appearance | has("dynamic")) == false' \
    'fixed forest is the shipped row again, with no palette left behind'

# --- 8. the constrained accent replaces it rather than inheriting it ---------
#
# The second half of the ticket's fourth criterion, and the half a poll cannot
# see. The accent's own recompute is asynchronous — its quantizer only starts
# loading when the mode becomes "accent" — so a switch that waited for it would
# leave the shell wearing all seventeen generated roles, backgrounds included,
# until the quantize finished. What proves it did not is the *order* of the two
# lines: the generated palette is dropped, and only then is an accent tuned.

mark=$(log_lines)
mode dynamic
expect_since "$mark" 'theming: palette generated' 'the generated palette is back'
await_json "$SETTINGS" '(.appearance.dynamic | keys | length) == 17' \
    'there are seventeen roles to hand over'

mark=$(log_lines)
mode accent
expect_since "$mark" 'theming: accent tuned to' 'the constrained accent takes over'
order=$(since "$mark" | grep -aoE 'generated palette cleared|accent tuned to' | head -2 | tr '\n' ' ')
if [[ "$order" == 'generated palette cleared accent tuned to '* ]]; then
    nested_pass 'the generated palette is dropped before the accent is tuned, not after'
else
    nested_fail "the shell wore the generated palette while the quantizer ran — order was: $order"
fi
await_json "$SETTINGS" \
    '(.appearance.dynamic | keys) == ["accentDeep", "accentPrimary"]' \
    'the accent mode writes its own two roles over the seventeen'

nested_kill_shell

# --- 9. without matugen ------------------------------------------------------
#
# The ticket's second acceptance criterion: mode unavailable, a clean hint, no
# errors. The settings window greys the choice out — that is a binding on
# `Matugen.available` and a picture, so it belongs to seam 3 — and what is
# checkable here is the other half: a config that names the mode anyway must
# leave the shipped palette standing, say so once, and throw nothing.
#
# PATH is a mirror of the real one with matugen removed rather than an empty
# directory: the shell probes half a dozen optional binaries at startup and a
# session with none of them would be testing something else.

STUB="$NESTED_WORK/nomatugen"
mkdir -p "$STUB"
for dir in $(printf '%s\n' "${PATH//:/$'\n'}" | sort -u); do
    [[ -d "$dir" ]] || continue
    cp -as "$dir/." "$STUB/" 2>/dev/null
done
rm -f "$STUB/matugen"
if [[ -e "$STUB/matugen" ]] || [[ ! -e "$STUB/jq" ]]; then
    nested_fail 'could not build a PATH without matugen — skipping the absent-binary checks'
else
    cat > "$SETTINGS" <<EOF
{
  "settingsVersion": 2,
  "appearance": { "mode": "dynamic", "darkMode": true },
  "wallpaper": { "path": "$PAPERS/lake.png" }
}
EOF
    NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state"
                "PATH=$STUB")
    nested_shell shell.qml 'theming ready' || exit 1

    expect_since 0 'theming: matugen not installed — full dynamic mode unavailable' \
        'without matugen the shell says so, in the mode that needed it'
    sleep 1
    refute_json "$SETTINGS" '.appearance.dynamic' \
        'without matugen nothing is written — the shipped palette stands'
    refute_since 0 '(TypeError|ReferenceError|is not a function|Unable to assign)' \
        'without matugen nothing throws — it is a missing option, not a fault'

    mark=$(log_lines)
    wallpaper amber
    sleep 1
    absent_lines=$(since "$mark" | grep -ac 'matugen not installed' || true)
    if (( absent_lines <= 1 )); then
        nested_pass 'the hint is said once rather than on every wallpaper change'
    else
        nested_fail "the hint repeats — $absent_lines lines for one wallpaper change"
    fi

    nested_kill_shell
fi

# --- 10. the generated palette holds the floor as a picture (seam 3) ---------
#
# The palette that came out of the running shell above, worn by the real bar
# over a photographic wallpaper and measured pixel-exact. Seam 1 already proved
# the arithmetic — every role against every surface, opaque token against opaque
# token. This is the composite the arithmetic cannot predict: a translucent bar
# fill over a wallpaper, which is the measurement #79 exists for and the one a
# generated palette has the least claim to passing.

if [[ -s "$GENERATED" ]] && [[ "$(jq -r 'keys | length' "$GENERATED")" == "17" ]]; then
    shot="$NESTED_WORK/dynamic-bar.png"
    if tools/capture-harness.sh "$shot" --surface bar --contrast \
            --palette "$GENERATED" > "$NESTED_WORK/capture.log" 2>&1; then
        nested_pass 'the generated palette holds the contrast floor on a real bar'
    else
        nested_fail 'the generated palette fails the contrast floor on a real bar'
        nested_note "$(grep -aE 'ratio|FAIL|floor' "$NESTED_WORK/capture.log" | tail -3)"
    fi
else
    nested_fail 'no generated palette was captured to measure'
fi

printf '\n'
if (( nested_fail_count )); then
    printf '%d check(s) failed\n' "$nested_fail_count"
    exit 1
fi
printf 'all checks passed\n'
