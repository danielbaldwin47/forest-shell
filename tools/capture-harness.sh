#!/usr/bin/env bash
# Capture a real shell surface to a PNG, client-side (#85, extended for #73).
#
# This is the visual half of the second seam, taken client-side: the nested
# compositor cannot produce pixels on the current Hyprland/aquamarine stack
# (see the header of tools/nested-session.sh for the diagnosis), but the
# shell's own rendering is unaffected — so the capture is a real Qt render of
# the real components, grabbed where the pixels are produced. A run does not
# depend on the session or the user's files: the capture geometry is fixed in
# logical pixels, and the config it renders from is a scratch XDG_CONFIG_HOME
# with (by default) a generated wallpaper. The one thing the caller's machine
# does set is the scale the file comes back at — see the two modes below.
#
#   tools/capture-harness.sh out.png                        # defaults
#   tools/capture-harness.sh out.png --bar-opacity 0.65     # the setting, clamped
#   tools/capture-harness.sh out.png --bar-opacity 0.65 --unclamped  # #79's failure
#   tools/capture-harness.sh out.png --wallpaper ~/pins/pin11.jpg
#   tools/capture-harness.sh out.png --size 1920x1080
#   tools/capture-harness.sh out.png --contrast             # measure, report
#   tools/capture-harness.sh out.png --contrast --min-ratio 4.5   # and gate
#   tools/capture-harness.sh out.png --surface bar-full --session   # with modules
#   tools/capture-harness.sh out.png --surface lock --session --lock-state summoned
#   tools/capture-harness.sh out.png --surface settings --session --tab appearance
#   tools/capture-harness.sh out.png --surface settings --tab system --scroll 900
#   tools/capture-harness.sh out.png --surface drawer --session   # the fog scrim
#   tools/capture-harness.sh out.png --surface launcher --session # the clearing
#   tools/capture-harness.sh out.png --surface center --session   # the notification centre
#   tools/capture-harness.sh out.png --surface dashboard --session # the dashboard
#   tools/capture-harness.sh out.png --surface osd --session      # the OSD pill
#   tools/capture-harness.sh out.png --surface osd --session --osd mic:60:muted
#   tools/capture-harness.sh out.png --surface screenshot           # the region picker
#   tools/capture-harness.sh out.png --surface screenshot --pick window
#   tools/capture-harness.sh out.png --surface launcher --session --query '?' \
#       --transcript 'you|why is the sky blue~claude|Rayleigh scattering.'  # Ask Claude
#   tools/capture-harness.sh out.png --surface launcher --contrast --min-ratio 4.5
#   tools/capture-harness.sh out.png --reduced             # appearance.reducedEffects on
#   tools/capture-harness.sh out.png --contrast --palette generated.json  # a #59 palette
#
# --palette wears a role → colour map a theming mode produced, from a file, with
# `appearance.mode` set to dynamic (#59). It is how a *generated* palette gets
# measured as a picture rather than as arithmetic: the seventeen roles a
# wallpaper earned are the ones the bar is drawn out of, and whether they still
# hold the contrast floor over a photograph is not a number any table predicts.
# `tools/matugen-harness.sh` passes the palette the running shell wrote.
#
# --reduced renders with the degrade knob on (#22 §7, #69). Every rung of that
# ladder is either the compositor's (blur), a transition, or an effect no
# shipped surface draws yet, so a still frame of a surface at rest is
# *byte-identical* either way, and that is the check reduced effects is a
# supported look rather than a stripped one — two runs and a `cmp`:
#
#   tools/capture-harness.sh a.png --surface lock
#   tools/capture-harness.sh b.png --surface lock --reduced
#   cmp a.png b.png
#
# (The Appearance tab is the one exception, and only because the switch this
# knob now has draws its own state.)
#
# --lock-state poses the lock: `quiet`, or any comma-separated combination of
# `summoned` (the field revealed), `caps` (the caps-lock warning) and
# `notify:N`. Every item in the status strip is gated on something about the
# machine, so a capture that does not pose them photographs whatever the laptop
# happened to be doing — the battery item is the one that cannot be posed, and
# the saved line reports what it was instead. --delay-ms buys settle time on a
# loaded machine.
#
# --surface picks what is rendered: `bar` is the fill over the wallpaper (the
# composite #79 measures), `bar-full` is the whole bar including its module
# clusters, `lock` is the lock surface (`--lock-state summoned` reveals the
# field), `settings` is the settings window at the tab `--tab` names — scrolled
# down `--scroll <px>` first, because the System tab is several windows tall and
# a capture of its first screen is not a capture of the tab — and
# `drawer` is #38's fog scrim with the session menu in it, laid out below the
# bar the way the compositor lays it out — the picture that answers "scrim at
# 0.10, bar above the fog". Its icons need `--session`. `osd` is #46's pill,
# placed where the settings' position key puts it and posed with `--osd
# channel[:percent[:muted]]`; its glyph needs `--session` too. `dashboard` is
# #49's panel under the clock, posed with a fixed day and a fixed player so the
# same picture is taken twice — its glyphs need `--session` as well.
# `screenshot` is #51's region picker over a frozen screen, posed with `--pick
# region` (a drawn selection and its readout) or `--pick window` (the highlight
# a click would take). It is the one surface with no glyph in it at all, so the
# default offscreen mode judges it completely and `--session` buys nothing.
#
# --contrast runs tools/measure-contrast.py over the strip the bar occupies
# (skipping the 1px hairline row) against Theme.textSecondary #a9b8b0 — the
# #79 measurement, bar surface only. Without compositor blur the composite here
# is the *stricter* floor: blur only averages the wallpaper locally, so a
# window that passes unblurred passes blurred.
#
# --bar-opacity sets the *setting*. What gets painted is that setting raised to
# whatever the wallpaper behind it demands (#79) — the bar reads the strip under
# itself and clamps up to hold 4.5:1 — so `--bar-opacity 0.65 --contrast
# --min-ratio 4.5` is the gate on the clamp, and the `painted=` field in the
# saved line is what the clamp chose. --unclamped turns that off and renders the
# setting raw, which is how the failure #79 reported is reproduced and how the
# numbers in the Bar tab's copy are checked (#94). The full picture,
# `--surface bar-full`, always clamps: it is the real BarContent.
#
# Two rendering modes, and the difference between them is MultiEffect:
#
#   (default)  QT_QPA_PLATFORM=offscreen. Needs no session, so CI can run it,
#              and the screen list comes from a config file so the geometry is
#              fixed. But MultiEffect draws *nothing* on the offscreen
#              scenegraph, silently (Widgets/Icon.qml): every Lucide glyph is
#              missing from the capture. Layout, colour and opacity
#              compositing are exact, which is what #79 and #80 need.
#   --session  renders on the caller's Wayland session, where MultiEffect
#              works — the only way to judge the icons (#73). The scene is a
#              fixed-size item inside an ordinary toplevel and the grab takes
#              the whole item, so the window manager's sizing does not reach
#              the capture; a window does flash on the session for ~1s.
#
# What neither mode judges: compositor composition — blur behind the bar, layer
# stacking, frame pacing (#78). Those are the compositor's pixels, not the
# client's.
#
# --clock writes `weatherTime.clock.format` into the scratch config: `auto`,
# `12h` or `24h`. #93 was the bar and the lock reading the same minute two ways,
# and the check that it is one decision now is two captures side by side — a
# default pair agrees because both follow the locale, so the pair that proves
# the *key* reaches both surfaces is the one taken with it set:
#
#   tools/capture-harness.sh bar.png  --surface bar-full --clock 24h
#   tools/capture-harness.sh lock.png --surface lock     --clock 24h

set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=qs-runtime.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qs-runtime.sh"

OUT=""
WALLPAPER=""
BAR_OPACITY=""
SIZE=""
CONTRAST=0
MIN_RATIO=""
SURFACE="bar"
SESSION=0
LOCK_STATE="quiet"
SETTINGS_TAB=""
SETTINGS_SCROLL="0"
LAUNCHER_QUERY=""
CLAUDE_TRANSCRIPT=""
DRILL=""
OSD_STATE="volume:45"
OSD_SET=0
PICK=""
WALLPAPER_FOLDER=""
DELAY_MS=600
REDUCED=0
LIGHT=0
UNCLAMPED=0
CLOCK=""
PALETTE=""

while (( $# )); do
    case "$1" in
        --wallpaper)   WALLPAPER="$2"; shift 2 ;;
        --bar-opacity) BAR_OPACITY="$2"; shift 2 ;;
        --size)        SIZE="$2"; shift 2 ;;
        --contrast)    CONTRAST=1; shift ;;
        --min-ratio)   MIN_RATIO="$2"; shift 2 ;;
        --surface)     SURFACE="$2"; shift 2 ;;
        --light)       LIGHT=1; shift ;;
        --session)     SESSION=1; shift ;;
        --lock-state)  LOCK_STATE="$2"; shift 2 ;;
        --tab)         SETTINGS_TAB="$2"; shift 2 ;;
        --scroll)      SETTINGS_SCROLL="$2"; shift 2 ;;
        --query)       LAUNCHER_QUERY="$2"; shift 2 ;;
        --transcript)  CLAUDE_TRANSCRIPT="$2"; shift 2 ;;
        --drill)       DRILL="$2"; shift 2 ;;
        --pick)
            PICK="${2:-}"; shift 2 ;;
        --osd)         OSD_STATE="$2"; OSD_SET=1; shift 2 ;;
        --wallpaper-folder) WALLPAPER_FOLDER="$2"; shift 2 ;;
        --delay-ms)    DELAY_MS="$2"; shift 2 ;;
        --clock)       CLOCK="$2"; shift 2 ;;
        --palette)     PALETTE="$2"; shift 2 ;;
        --reduced)     REDUCED=1; shift ;;
        --unclamped)   UNCLAMPED=1; shift ;;
        --help|-h)     sed -n '2,117p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)            echo "unknown option: $1" >&2; exit 2 ;;
        *)             OUT="$1"; shift ;;
    esac
done
[[ -n "$OUT" ]] || { echo "usage: tools/capture-harness.sh out.png [options]" >&2; exit 2; }

# The launcher is the one surface whose content arrives after the scene does:
# `DesktopEntries.applications` streams in over roughly a second and a half
# (measured — tools/launcher-harness.sh), and a capture taken at the usual 600 ms
# is a picture of an empty card. Only raised when the caller did not say
# otherwise, so `--delay-ms` still means what it says.
if [[ "$SURFACE" == launcher && "$DELAY_MS" == 600 ]]; then
    DELAY_MS=2200
fi

# `--drill` only means anything on the panel that has drill-ins in it, and a
# silently ignored flag is a capture of the wrong thing that looks right.
if [[ -n "$DRILL" ]]; then
    [[ "$SURFACE" == controlcenter ]] || {
        echo "--drill only applies to --surface controlcenter" >&2; exit 2; }
    case "$DRILL" in
        wifi|bluetooth|audio|vpn|wallpaper) ;;
        *) echo "unknown drill-in: $DRILL (wifi, bluetooth, audio, vpn, wallpaper)" \
               >&2; exit 2 ;;
    esac
fi

# `--osd` only means anything on the pill, and it names a channel the policy
# knows: a silently ignored flag is a capture of the wrong thing that looks
# right, and an unknown channel draws a pill with no glyph in it.
if (( OSD_SET )); then
    [[ "$SURFACE" == osd ]] || {
        echo "--osd only applies to --surface osd" >&2; exit 2; }
fi
case "${OSD_STATE%%:*}" in
    volume|mic|brightness) ;;
    *) echo "unknown OSD channel: ${OSD_STATE%%:*} (volume, mic, brightness)" >&2; exit 2 ;;
esac

# `--pick` only means anything on the picker, and it names a state the overlay
# can actually be in: a silently ignored flag is a capture of the wrong thing
# that looks right.
if [[ -n "$PICK" ]]; then
    [[ "$SURFACE" == screenshot ]] || {
        echo "--pick only applies to --surface screenshot" >&2; exit 2; }
    case "$PICK" in
        region|window) ;;
        *) echo "unknown pick state: $PICK (region, window)" >&2; exit 2 ;;
    esac
fi

# The three words Core/SettingsSchema.qml's `clockFormats` accepts. Checked here
# rather than left to the shell because `--clock 12` would otherwise be coerced
# back to the default and photographed as if it were the thing asked for.
if [[ -n "$CLOCK" ]]; then
    case "$CLOCK" in
        auto|12h|24h) ;;
        *) echo "unknown clock format: $CLOCK (auto, 12h, 24h)" >&2; exit 2 ;;
    esac
fi

case "$SURFACE" in
    bar|bar-full|lock|settings|drawer|launcher|center|controlcenter|dashboard|osd|screenshot) ;;
    *) echo "unknown surface: $SURFACE (bar, bar-full, lock, settings, drawer, launcher, center, controlcenter, dashboard, osd, screenshot)" \
           >&2; exit 2 ;;
esac

# The settings window is 900x660 by its own declaration; capturing it at the
# bar's 1280x800 would be measuring a size the shell never opens.
if [[ -z "$SIZE" ]]; then
    [[ "$SURFACE" == settings ]] && SIZE="900x660" || SIZE="1280x800"
fi
W="${SIZE%x*}"; H="${SIZE#*x}"

if (( SESSION )) && [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "--session needs a Wayland session: WAYLAND_DISPLAY is unset" >&2
    exit 2
fi

fail_count=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail_count=$((fail_count + 1)); }
note() { printf '  ....  %s\n' "$1"; }

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/forest-capture.XXXXXX")
trap 'rm -rf "$SCRATCH"' EXIT

# A deterministic wallpaper unless one is supplied: bright sky into dark
# ground, brightest exactly in the strip the bar sits over — the #79 failure
# shape, not a friendly average.
#
# PNG and not the PPM this wrote until #45, which was the cheaper thing to
# generate and is not a wallpaper as far as the shell is concerned:
# Surfaces/Background/WallpaperPolicy.qml accepts the raster formats a person
# actually keeps wallpapers in, so `--drill wallpaper` against a folder of PPMs
# captured an empty picker that looked like a broken one. Written the way
# tools/make-noise.py writes assets/noise.png — struct and zlib, because the
# alternative is a Pillow dependency for fifteen lines of packing.
if [[ -z "$WALLPAPER" ]]; then
    WALLPAPER="$SCRATCH/wallpaper.png"
    python3 - "$WALLPAPER" "$W" "$H" <<'EOF'
import struct
import sys
import zlib

path, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])

raw = bytearray()
for y in range(h):
    t = y / (h - 1)
    r, g, b = int(216 - 150 * t), int(232 - 160 * t), int(240 - 150 * t)
    raw.append(0)                      # filter type: none
    raw += bytes((r, g, b)) * w


def chunk(tag, payload):
    return (struct.pack(">I", len(payload)) + tag + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))


with open(path, "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n")
    f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
    f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 6)))
    f.write(chunk(b"IEND", b""))
EOF
fi
[[ -f "$WALLPAPER" ]] || { echo "no such wallpaper: $WALLPAPER" >&2; exit 2; }

mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state" "$SCRATCH/cache"
# The wallpaper picker's folder (#45). Defaults to the one the deterministic
# wallpaper above was written into, so `--drill wallpaper` has exactly one
# thumbnail to draw and the picture is the same on every machine — the folder
# is a scratch directory, so this cannot pick up whatever the caller happens to
# keep in ~/Pictures.
: "${WALLPAPER_FOLDER:=$(dirname "$WALLPAPER")}"
# `weatherTime.clock.format` only when asked for, so an unset --clock renders
# the default (`auto`) rather than a value this harness chose (#93).
CLOCK_JSON=""
if [[ -n "$CLOCK" ]]; then
    CLOCK_JSON=$(printf ', "weatherTime": { "clock": { "format": "%s" } }' "$CLOCK")
fi
# A palette a mode produced, worn for the capture (#59). The generated palette
# is the least trustworthy input the contrast floor will ever see — nobody
# authored it and nobody looked at it — and the roles it replaces are the ones
# the bar is drawn out of, so "does this palette survive over a photograph"
# is a picture and not arithmetic. `tools/matugen-harness.sh` hands the palette
# the *shell* generated straight to this flag, so what is measured here is the
# real output of the real mode rather than a re-derivation of it.
PALETTE_JSON=""
if [[ -n "$PALETTE" ]]; then
    [[ -f "$PALETTE" ]] || { echo "no such palette: $PALETTE" >&2; exit 2; }
    PALETTE_JSON=$(printf ', "mode": "dynamic", "dynamic": %s' "$(tr -d '\n' < "$PALETTE")")
fi
printf '{ "wallpaper": { "path": "%s", "folder": "%s" }, "appearance": { "reducedEffects": %s, "darkMode": %s%s }%s }\n' \
    "$WALLPAPER" "$WALLPAPER_FOLDER" \
    "$( ((REDUCED)) && echo true || echo false )" \
    "$( ((LIGHT)) && echo false || echo true )" \
    "$PALETTE_JSON" \
    "$CLOCK_JSON" \
    > "$SCRATCH/config/forest-shell/settings.json"

# The offscreen platform takes its screen list from a config file; this is
# what makes the capture geometry deterministic rather than the 800x800 the
# platform defaults to. Unused under --session, where the scene's own fixed
# size is what the grab takes.
cat > "$SCRATCH/offscreen.json" <<EOF
{ "screens": [ { "name": "CAPTURE-1", "x": 0, "y": 0,
                 "width": $W, "height": $H,
                 "logicalDpi": 96, "logicalBaseDpi": 96, "dpr": 1 } ] }
EOF

# The clipboard list (#53), seeded so `--surface launcher --query ';'` draws the
# same rows on every machine — the argument the generated wallpaper above makes,
# and a sharper one: cliphist's store lives under `XDG_CACHE_HOME`, so a capture
# without the scratch cache in CAPTURE_ENV below would render the caller's own
# clipboard history into a PNG. Two entries, because the picture worth looking at
# is a text row and an image row in the same list.
if [[ "$SURFACE" == launcher && "$LAUNCHER_QUERY" == \;* ]]; then
    if command -v cliphist >/dev/null 2>&1; then
        printf 'git push --force-with-lease' \
            | XDG_CACHE_HOME="$SCRATCH/cache" cliphist store
        XDG_CACHE_HOME="$SCRATCH/cache" cliphist store < assets/noise.png
        note 'seeded a scratch clipboard history (one text entry, one image)'
    else
        note 'no cliphist — the clipboard rows will be the empty-history line'
    fi
fi

CAPTURE_ENV=(
    XDG_CONFIG_HOME="$SCRATCH/config" XDG_STATE_HOME="$SCRATCH/state"
    XDG_CACHE_HOME="$SCRATCH/cache"
    CAPTURE_OUT="$OUT" CAPTURE_BAR_OPACITY="$BAR_OPACITY"
    CAPTURE_BAR_CLAMP="$( ((UNCLAMPED)) && echo 0 || echo 1 )"
    CAPTURE_SURFACE="$SURFACE" CAPTURE_W="$W" CAPTURE_H="$H"
    CAPTURE_LOCK_STATE="$LOCK_STATE" CAPTURE_SETTINGS_TAB="$SETTINGS_TAB"
    CAPTURE_SETTINGS_SCROLL="$SETTINGS_SCROLL"
    CAPTURE_DELAY_MS="$DELAY_MS" CAPTURE_LAUNCHER_QUERY="$LAUNCHER_QUERY"
    CAPTURE_CLAUDE_TRANSCRIPT="$CLAUDE_TRANSCRIPT" CAPTURE_DRILL="$DRILL"
    CAPTURE_OSD="$OSD_STATE" CAPTURE_PICK="$PICK"
)
if (( SESSION )); then
    # Nothing unset: the session's own Wayland socket is the point.
    note "rendering on $WAYLAND_DISPLAY — MultiEffect included, window will flash"
else
    CAPTURE_ENV=(-u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE
                 QT_QPA_PLATFORM="offscreen:configfile=$SCRATCH/offscreen.json"
                 "${CAPTURE_ENV[@]}")
fi

QS_RUNTIME=$(qs_runtime_bin) || exit 1

LOG="$SCRATCH/shell.log"
env "${CAPTURE_ENV[@]}" timeout 30 "$QS_RUNTIME" -p capture-harness.qml > "$LOG" 2>&1
rc=$?

SAVED=$(grep -a 'capture: saved=' "$LOG" || true)
if [[ "$SAVED" == *"saved=true"* ]]; then
    pass "capture written: ${SAVED#*capture: }"
else
    fail "capture did not complete (exit $rc) — log follows"
    tail -20 "$LOG"
    exit 1
fi

# `bar=N` in the saved line is authoritative — it is what the QML actually
# rendered, not what this script asked for.
BAR_H=$(sed -n 's/.* bar=\([0-9]*\).*/\1/p' <<< "$SAVED")

# What scale the capture should have come back at. #85 asks for "pixel-for-pixel
# … no outer-display scaling applied", so this is an assertion and not an
# observation: offscreen renders 1:1 by construction, and a session renders at
# the output's own scale, which the compositor is asked for rather than
# inferred. (`Screen.devicePixelRatio` is not usable here — it reports 2 on this
# 1.5-scale display, the lie Widgets/Icon.qml documents.) Nothing is resampled
# in either case; the factor exists so a measurement region can be stated in
# logical pixels and applied to the file.
WANT_SCALE=1
if (( SESSION )); then
    WANT_SCALE=$(hyprctl -j monitors 2>/dev/null | python3 - <<'EOF' || true
import json, sys
try:
    monitors = json.load(sys.stdin)
except Exception:
    sys.exit()
focused = next((m for m in monitors if m.get("focused")), None) \
    or (monitors[0] if monitors else None)
if focused:
    print(format(focused["scale"], "g"))
EOF
)
    if [[ -z "$WANT_SCALE" ]]; then
        note "no compositor scale available — the capture's own scale is taken on trust"
        WANT_SCALE="any"
    fi
fi

SCALE=$(python3 - "$OUT" "$W" "$H" "$WANT_SCALE" <<'EOF'
import sys
import importlib.util
spec = importlib.util.spec_from_file_location("mc", "tools/measure-contrast.py")
mc = importlib.util.module_from_spec(spec); spec.loader.exec_module(mc)
w, h, rows = mc.decode_png(sys.argv[1])
want_w, want_h, want_scale = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
sx, sy = w / want_w, h / want_h
assert abs(sx - sy) < 1e-6, f"non-uniform scale: {w}x{h} for {want_w}x{want_h}"
if want_scale != "any":
    assert abs(sx - float(want_scale)) < 1e-6, \
        f"{w}x{h} is scale {sx:g}, expected {want_scale} — the scene was not captured whole"
sample = {rows[y][x] for y in range(0, h, 16) for x in range(0, w, 16)}
assert len(sample) > 8, f"only {len(sample)} distinct colours — nothing rendered"
print(f"{sx:g}")
EOF
)
if [[ -n "$SCALE" ]]; then
    pass "PNG is the whole ${W}x${H} scene at scale ${SCALE} and not blank"
else
    fail "PNG failed verification"
fi

if (( CONTRAST )); then
    ## Measure one region of the capture, stated in *logical* pixels, against
    ## the authored text colour that sits on it. The sliding window is a run of
    ## text, so it is 100 logical px wide whatever the file came back at.
    measure_region() {
        local what="$1" x="$2" y="$3" w="$4" h="$5" color="$6"
        local rx ry rw rh win
        read -r rx ry rw rh win < <(python3 -c '
import sys
s = float(sys.argv[1])
print(*(round(float(v) * s) for v in sys.argv[2:6]), round(100 * s))' \
            "$SCALE" "$x" "$y" "$w" "$h")

        if (( rw <= 0 || rh <= 0 )); then
            fail "--contrast: $what has no area (${w}x${h} logical) — the scene did not report it"
            return
        fi

        local args=(--text-color "$color" --region "${rx},${ry},${rw}x${rh}" --window "$win")
        [[ -n "$MIN_RATIO" ]] && args+=(--min-ratio "$MIN_RATIO")
        printf '\n  %s\n' "$what"
        if python3 tools/measure-contrast.py "$OUT" "${args[@]}"; then
            pass "contrast measured over $what"
        else
            fail "contrast below --min-ratio over $what"
        fi
    }

    if [[ -z "$SCALE" ]]; then
        fail "--contrast needs a verified capture"
    elif [[ "$SURFACE" == bar ]]; then
        if [[ ! "$BAR_H" =~ ^[0-9]+$ ]]; then
            # Parsed out of the shell's own log line, so a change to that line must
            # not silently become a contrast failure — which is what an empty region
            # would look like.
            fail "--contrast could not read the bar height from: $SAVED"
        else
            # Skip the hairline row at the bottom edge of the strip: it is authored
            # `border-subtle`, not fill, and #79's numbers are about the fill.
            measure_region "the bar strip" 0 1 "$W" "$(( BAR_H - 2 ))" a9b8b0
        fi
    elif [[ "$SURFACE" == launcher ]]; then
        # #39: "card >= 4.5:1, legend >= 4.5:1", in #79's metric — the worst
        # 100px window of the composited fill against the text colour that sits
        # on it. Both regions come out of the saved line rather than being
        # recomputed here, because the card's height depends on how many rows
        # the fold left in it.
        #
        # Unlike the bar, these regions *contain* rendered text, and that is
        # deliberate rather than overlooked. The measurement takes the mean
        # luminance of each column of the region: the shell is dark-first, so
        # every glyph in there is lighter than the fill behind it and can only
        # raise that mean, which can only lower the ratio against a light text
        # colour. Including the glyphs therefore makes the gate stricter than
        # the fill alone — a card that passes here passes on its fill, and the
        # reverse is not possible. (Offscreen, where the icons do not draw at
        # all, it is stricter still by less.)
        #
        # `textSecondary` and not `textPrimary`: after #39 moved subtitles,
        # category labels and the legend off `textMuted`, secondary is the
        # dimmest role anything on this card is drawn in, so it is the one the
        # floor has to hold for.
        CARD=$(sed -n 's/.* card=\([0-9]*\),\([0-9]*\),\([0-9]*\)x\([0-9]*\).*/\1 \2 \3 \4/p' <<< "$SAVED")
        LEGEND=$(sed -n 's/.* legend=\([0-9]*\),\([0-9]*\),\([0-9]*\)x\([0-9]*\).*/\1 \2 \3 \4/p' <<< "$SAVED")

        if [[ -z "$CARD" || -z "$LEGEND" ]]; then
            fail "--contrast could not read the card and legend regions from: $SAVED"
        else
            # Inset by the card's 1px border, which is authored `border-subtle`
            # rather than fill — the same argument the bar's hairline gets.
            read -r cx cy cw ch <<< "$CARD"
            measure_region "the launcher card" "$(( cx + 1 ))" "$(( cy + 1 ))" \
                "$(( cw - 2 ))" "$(( ch - 2 ))" a9b8b0
            # The legend is measured on the *fill beside its text*, not on the
            # band containing it, and the difference is not cosmetic: the
            # legend strip is 18px tall carrying 11.5px glyphs, so most of
            # every column in it is text and the measurement comes back 3.1:1
            # — the text against itself, which is the same objection this
            # script has always made about `bar-full`. The band immediately
            # below it is the card's own bottom padding: the same fill, over
            # the same part of the wallpaper, with nothing drawn on it. That is
            # what the legend's text actually sits on.
            #
            # It matters that this is the *bottom* of the card. #11's finding
            # was that the legend failed on bare scrim; the fix put it on the
            # card, and the card is one flat fill over a wallpaper that is
            # brightest at the top — so the card region above already measures
            # the harder end of the same surface.
            read -r lx ly lw lh <<< "$LEGEND"
            read -r cx cy cw ch <<< "$CARD"
            FILL_Y=$(( ly + lh ))
            FILL_H=$(( cy + ch - 1 - FILL_Y ))
            if (( FILL_H < 4 )); then
                fail "--contrast: only ${FILL_H}px of card below the legend — the footer is overflowing its card"
            else
                measure_region "the fill under the legend" \
                    "$(( cx + 1 ))" "$FILL_Y" "$(( cw - 2 ))" "$FILL_H" a9b8b0
            fi
        fi
    elif [[ "$SURFACE" == controlcenter ]]; then
        # Refused, and the refusal is the finding. #44 was written asking for a
        # `--contrast` gate over the light palette here, and that gate exists —
        # it is just not at this seam.
        #
        # What this script measures is a **composite**: an authored fill at some
        # opacity over a wallpaper, which is a number no palette table can
        # predict and only a render can produce. That is #79, on the bar. The
        # control centre has no such surface — the panel, the tiles and the
        # strip are all opaque tokens over an opaque panel, so every ratio in it
        # is arithmetic over two constants. Rendering them would photograph two
        # hex values and divide them, and the answer would be worse than the
        # arithmetic: a region containing text measures its own glyphs, which is
        # how the first attempt read 3.86:1 over a panel whose real pairings are
        # 6.4:1 and 4.6:1.
        #
        # So the palette gate is `tests/tst_tokens.qml`, where it covers both
        # modes, every text role and every surface rather than the handful a
        # posed capture puts on screen — and runs with no compositor at all.
        # What this surface is captured *for* is the picture: the #80-class
        # layout check, which needs no flag.
        fail "--contrast measures a fill composited over the wallpaper; the control centre is opaque throughout — its palette gate is tests/tst_tokens.qml. Capture it without --contrast for the layout."
    else
        # `bar-full` has a strip too, and text drawn into it — which is why it
        # is refused rather than measured: there is no authored fill under it
        # whose composite is the thing #79 is about.
        fail "--contrast measures a fill some authored text sits on; --surface $SURFACE is not that picture (use bar or launcher)"
    fi
fi

(( fail_count == 0 )) || { printf '\n%d failed\n' "$fail_count"; exit 1; }
