#!/usr/bin/env bash
# Capture the shell's bar-over-wallpaper composite to a PNG, offscreen (#85).
#
# This is the visual half of the second seam, taken client-side: the nested
# compositor cannot produce pixels on the current Hyprland/aquamarine stack
# (see the header of tools/nested-session.sh for the diagnosis), but the
# shell's own rendering is unaffected — so the capture is a real Qt render of
# the real components, grabbed where the pixels are produced. Deterministic:
# fixed screen geometry via the offscreen platform's config file, a scratch
# XDG_CONFIG_HOME, and (by default) a generated wallpaper, so a run does not
# depend on the session or the user's files.
#
#   tools/capture-harness.sh out.png                        # defaults
#   tools/capture-harness.sh out.png --bar-opacity 0.65     # #79's failing floor
#   tools/capture-harness.sh out.png --wallpaper ~/pins/pin11.jpg
#   tools/capture-harness.sh out.png --size 1920x1080
#   tools/capture-harness.sh out.png --contrast             # measure, report
#   tools/capture-harness.sh out.png --contrast --min-ratio 4.5   # and gate
#
# --contrast runs tools/measure-contrast.py over the strip the bar occupies
# (skipping the 1px hairline row) against Theme.textSecondary #a9b8b0 — the
# #79 measurement. Without compositor blur the composite here is the *stricter*
# floor: blur only averages the wallpaper locally, so a window that passes
# unblurred passes blurred.
#
# What this cannot judge: MultiEffect surfaces (blank on the offscreen
# scenegraph — Widgets/Icon.qml) and compositor composition. Real session.

set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

QS_BIN="${QS_BIN:-qs-upstream}" # #14/#15: upstream prefix until the swap (#57)

OUT=""
WALLPAPER=""
BAR_OPACITY=""
SIZE="1280x800"
CONTRAST=0
MIN_RATIO=""

while (( $# )); do
    case "$1" in
        --wallpaper)   WALLPAPER="$2"; shift 2 ;;
        --bar-opacity) BAR_OPACITY="$2"; shift 2 ;;
        --size)        SIZE="$2"; shift 2 ;;
        --contrast)    CONTRAST=1; shift ;;
        --min-ratio)   MIN_RATIO="$2"; shift 2 ;;
        --help|-h)     sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)            echo "unknown option: $1" >&2; exit 2 ;;
        *)             OUT="$1"; shift ;;
    esac
done
[[ -n "$OUT" ]] || { echo "usage: tools/capture-harness.sh out.png [options]" >&2; exit 2; }
W="${SIZE%x*}"; H="${SIZE#*x}"

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
# platform defaults to.
cat > "$SCRATCH/offscreen.json" <<EOF
{ "screens": [ { "name": "CAPTURE-1", "x": 0, "y": 0,
                 "width": $W, "height": $H,
                 "logicalDpi": 96, "logicalBaseDpi": 96, "dpr": 1 } ] }
EOF

LOG="$SCRATCH/shell.log"
env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    QT_QPA_PLATFORM="offscreen:configfile=$SCRATCH/offscreen.json" \
    XDG_CONFIG_HOME="$SCRATCH/config" XDG_STATE_HOME="$SCRATCH/state" \
    CAPTURE_OUT="$OUT" CAPTURE_BAR_OPACITY="$BAR_OPACITY" \
    timeout 30 "$QS_BIN" -p capture-harness.qml > "$LOG" 2>&1
rc=$?

SAVED=$(grep -a 'capture: saved=' "$LOG" || true)
if [[ "$SAVED" == *"saved=true"* ]]; then
    pass "capture written: ${SAVED#*capture: }"
else
    fail "capture did not complete (exit $rc) — log follows"
    tail -20 "$LOG"
    exit 1
fi

# `bar=N opacity=X` in the saved line is authoritative — it is what the QML
# actually rendered, not what this script asked for.
BAR_H=$(sed -n 's/.* bar=\([0-9]*\).*/\1/p' <<< "$SAVED")

python3 - "$OUT" "$W" "$H" <<'EOF' && pass "PNG is ${W}x${H} and not blank" || fail "PNG failed verification"
import sys
sys.path.insert(0, "tools")
import importlib.util
spec = importlib.util.spec_from_file_location("mc", "tools/measure-contrast.py")
mc = importlib.util.module_from_spec(spec); spec.loader.exec_module(mc)
w, h, rows = mc.decode_png(sys.argv[1])
assert (w, h) == (int(sys.argv[2]), int(sys.argv[3])), f"got {w}x{h}"
sample = {rows[y][x] for y in range(0, h, 16) for x in range(0, w, 16)}
assert len(sample) > 8, f"only {len(sample)} distinct colours — nothing rendered"
EOF

if (( CONTRAST )); then
    # Skip the hairline row at the bottom edge of the strip: it is authored
    # `border-subtle`, not fill, and #79's numbers are about the fill.
    REGION="0,1,${W}x$((BAR_H - 2))"
    ARGS=(--text-color a9b8b0 --region "$REGION" --window 100)
    [[ -n "$MIN_RATIO" ]] && ARGS+=(--min-ratio "$MIN_RATIO")
    if python3 tools/measure-contrast.py "$OUT" "${ARGS[@]}"; then
        pass "contrast measured over the bar strip"
    else
        fail "contrast below --min-ratio over the bar strip"
    fi
fi

(( fail_count == 0 )) || { printf '\n%d failed\n' "$fail_count"; exit 1; }
