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
#   tools/capture-harness.sh out.png --bar-opacity 0.65     # #79's failing floor
#   tools/capture-harness.sh out.png --wallpaper ~/pins/pin11.jpg
#   tools/capture-harness.sh out.png --size 1920x1080
#   tools/capture-harness.sh out.png --contrast             # measure, report
#   tools/capture-harness.sh out.png --contrast --min-ratio 4.5   # and gate
#   tools/capture-harness.sh out.png --surface bar-full --session   # with modules
#   tools/capture-harness.sh out.png --surface lock --session --lock-state summoned
#   tools/capture-harness.sh out.png --surface settings --session --tab appearance
#   tools/capture-harness.sh out.png --reduced             # appearance.reducedEffects on
#
# --reduced renders with the degrade knob on (#22 §7, #69). Every rung of that
# ladder is either the compositor's (blur), a transition, or an effect no
# shipped surface draws yet, so a still frame of a surface at rest should be
# *byte-identical* to one taken without it — which is what makes this flag the
# check that reduced effects is a supported look and not a stripped one.
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
DELAY_MS=600
REDUCED=0

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
        --delay-ms)    DELAY_MS="$2"; shift 2 ;;
        --reduced)     REDUCED=1; shift ;;
        --help|-h)     sed -n '2,66p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
printf '{ "wallpaper": { "path": "%s" }, "appearance": { "reducedEffects": %s } }\n' \
    "$WALLPAPER" "$( ((REDUCED)) && echo true || echo false )" \
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
    CAPTURE_DELAY_MS="$DELAY_MS"
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
    if [[ "$SURFACE" != bar ]]; then
        # `bar-full` has a strip too, and text drawn into it — which is why it
        # is refused rather than measured: #79 is the contrast of the authored
        # text colour against the *fill it sits on*, so a region containing the
        # rendered glyphs would be measuring the text against itself.
        fail "--contrast measures the fill the bar's text sits on; --surface $SURFACE is not that picture (use bar)"
    elif [[ -z "$SCALE" ]]; then
        fail "--contrast needs a verified capture"
    elif [[ ! "$BAR_H" =~ ^[0-9]+$ ]]; then
        # Parsed out of the shell's own log line, so a change to that line must
        # not silently become a contrast failure — which is what an empty region
        # would look like.
        fail "--contrast could not read the bar height from: $SAVED"
    else
        # Skip the hairline row at the bottom edge of the strip: it is authored
        # `border-subtle`, not fill, and #79's numbers are about the fill. In
        # capture pixels, so scaled — the strip is a fixed number of *logical*
        # rows wherever it is rendered.
        read -r RX RY RW RH WIN < <(python3 -c '
import sys
s, w, bar = float(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
print(0, round(1 * s), round(w * s), round((bar - 2) * s), round(100 * s))' \
            "$SCALE" "$W" "$BAR_H")
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
