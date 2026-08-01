#!/usr/bin/env bash
# Capture a real shell surface to a PNG, client-side (#85, extended for #73).
#
# This is the visual half of the second seam, taken client-side: the nested
# compositor cannot produce pixels on the current Hyprland/aquamarine stack
# (see the header of tools/nested-session.sh for the diagnosis), but the
# shell's own rendering is unaffected — so the capture is a real Qt render of
# the real components, grabbed where the pixels are produced. Deterministic:
# fixed capture geometry, a scratch XDG_CONFIG_HOME, and (by default) a
# generated wallpaper, so a run does not depend on the session or the user's
# files.
#
#   tools/capture-harness.sh out.png                        # defaults
#   tools/capture-harness.sh out.png --bar-opacity 0.65     # #79's failing floor
#   tools/capture-harness.sh out.png --wallpaper ~/pins/pin11.jpg
#   tools/capture-harness.sh out.png --size 1920x1080
#   tools/capture-harness.sh out.png --contrast             # measure, report
#   tools/capture-harness.sh out.png --contrast --min-ratio 4.5   # and gate
#   tools/capture-harness.sh out.png --surface bar-full --session   # with modules
#   tools/capture-harness.sh out.png --surface lock --session --lock-state summoned
#   tools/capture-harness.sh out.png --surface settings --session --tab appearance
#
# --surface picks what is rendered: `bar` is the fill over the wallpaper (the
# composite #79 measures), `bar-full` is the whole bar including its module
# clusters, `lock` is the lock surface (`--lock-state summoned` reveals the
# field), `settings` is the settings window at the tab `--tab` names.
#
# --contrast runs tools/measure-contrast.py over the strip the bar occupies
# (skipping the 1px hairline row) against Theme.textSecondary #a9b8b0 — the
# #79 measurement, bar surface only. Without compositor blur the composite here
# is the *stricter* floor: blur only averages the wallpaper locally, so a
# window that passes unblurred passes blurred.
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

set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

QS_BIN="${QS_BIN:-qs-upstream}" # #14/#15: upstream prefix until the swap (#57)

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

while (( $# )); do
    case "$1" in
        --wallpaper)   WALLPAPER="$2"; shift 2 ;;
        --bar-opacity) BAR_OPACITY="$2"; shift 2 ;;
        --size)        SIZE="$2"; shift 2 ;;
        --contrast)    CONTRAST=1; shift ;;
        --min-ratio)   MIN_RATIO="$2"; shift 2 ;;
        --surface)     SURFACE="$2"; shift 2 ;;
        --session)     SESSION=1; shift ;;
        --lock-state)  LOCK_STATE="$2"; shift 2 ;;
        --tab)         SETTINGS_TAB="$2"; shift 2 ;;
        --help|-h)     sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)            echo "unknown option: $1" >&2; exit 2 ;;
        *)             OUT="$1"; shift ;;
    esac
done
[[ -n "$OUT" ]] || { echo "usage: tools/capture-harness.sh out.png [options]" >&2; exit 2; }

case "$SURFACE" in
    bar|bar-full|lock|settings) ;;
    *) echo "unknown surface: $SURFACE (bar, bar-full, lock, settings)" >&2; exit 2 ;;
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
# shape, not a friendly average. PPM because Qt reads it and three lines of
# python write it.
if [[ -z "$WALLPAPER" ]]; then
    WALLPAPER="$SCRATCH/wallpaper.ppm"
    python3 - "$WALLPAPER" "$W" "$H" <<'EOF'
import sys
path, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
rows = []
for y in range(h):
    t = y / (h - 1)
    r, g, b = int(216 - 150 * t), int(232 - 160 * t), int(240 - 150 * t)
    rows.append(bytes((r, g, b)) * w)
with open(path, "wb") as f:
    f.write(f"P6\n{w} {h}\n255\n".encode())
    f.writelines(rows)
EOF
fi
[[ -f "$WALLPAPER" ]] || { echo "no such wallpaper: $WALLPAPER" >&2; exit 2; }

mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state"
printf '{ "wallpaper": { "path": "%s" } }\n' "$WALLPAPER" \
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

CAPTURE_ENV=(
    XDG_CONFIG_HOME="$SCRATCH/config" XDG_STATE_HOME="$SCRATCH/state"
    CAPTURE_OUT="$OUT" CAPTURE_BAR_OPACITY="$BAR_OPACITY"
    CAPTURE_SURFACE="$SURFACE" CAPTURE_W="$W" CAPTURE_H="$H"
    CAPTURE_LOCK_STATE="$LOCK_STATE" CAPTURE_SETTINGS_TAB="$SETTINGS_TAB"
)
if (( SESSION )); then
    # Nothing unset: the session's own Wayland socket is the point.
    note "rendering on $WAYLAND_DISPLAY — MultiEffect included, window will flash"
else
    CAPTURE_ENV=(-u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE
                 QT_QPA_PLATFORM="offscreen:configfile=$SCRATCH/offscreen.json"
                 "${CAPTURE_ENV[@]}")
fi

LOG="$SCRATCH/shell.log"
env "${CAPTURE_ENV[@]}" timeout 30 "$QS_BIN" -p capture-harness.qml > "$LOG" 2>&1
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

# The render scale, taken from the file rather than from anything that claims
# to know it: offscreen renders 1:1, a session renders at the output's scale
# (1280x800 comes back 1920x1200 at 1.5). Both are native renders — the check
# is that the scene came back whole and uniformly scaled, not that it came back
# at one particular size. It is printed because every region below is in
# capture pixels, so a reader of a measurement needs it.
SCALE=$(python3 - "$OUT" "$W" "$H" <<'EOF'
import sys
import importlib.util
spec = importlib.util.spec_from_file_location("mc", "tools/measure-contrast.py")
mc = importlib.util.module_from_spec(spec); spec.loader.exec_module(mc)
w, h, rows = mc.decode_png(sys.argv[1])
want_w, want_h = int(sys.argv[2]), int(sys.argv[3])
sx, sy = w / want_w, h / want_h
assert abs(sx - sy) < 1e-6, f"non-uniform scale: {w}x{h} for {want_w}x{want_h}"
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
    if [[ "$SURFACE" != bar ]]; then
        fail "--contrast is the #79 bar measurement; --surface $SURFACE has no bar strip"
    elif [[ -z "$SCALE" ]]; then
        fail "--contrast needs a verified capture"
    else
        # Skip the hairline row at the bottom edge of the strip: it is authored
        # `border-subtle`, not fill, and #79's numbers are about the fill. In
        # capture pixels, so scaled — the strip is a fixed number of *logical*
        # rows wherever it is rendered.
        read -r RX RY RW RH WIN < <(python3 -c "
s, w, bar = float('$SCALE'), $W, $BAR_H
print(0, round(1 * s), round(w * s), round((bar - 2) * s), round(100 * s))")
        REGION="${RX},${RY},${RW}x${RH}"
        # The sliding window is a run of text, so it is 100 *logical* px wide
        # whatever the capture was rendered at.
        ARGS=(--text-color a9b8b0 --region "$REGION" --window "$WIN")
        [[ -n "$MIN_RATIO" ]] && ARGS+=(--min-ratio "$MIN_RATIO")
        if python3 tools/measure-contrast.py "$OUT" "${ARGS[@]}"; then
            pass "contrast measured over the bar strip"
        else
            fail "contrast below --min-ratio over the bar strip"
        fi
    fi
fi

(( fail_count == 0 )) || { printf '\n%d failed\n' "$fail_count"; exit 1; }
