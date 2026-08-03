#!/usr/bin/env bash
# Photograph the bar blurred and unblurred on a real session, and measure the
# difference (#97).
#
#   tools/blur-measure.sh                       # run it, print the numbers
#   tools/blur-measure.sh --out DIR             # put the captures somewhere named
#   tools/blur-measure.sh --size 8 --passes 3   # a stronger blur than configured
#   tools/blur-measure.sh --keep                # leave the shell up afterwards
#   tools/blur-measure.sh --text-color RRGGBB   # what the contrast is measured against
#   tools/blur-measure.sh --max-kept PCT        # how much detail a blur may leave
#
# ## What this is for
#
# #78 settled that Hyprland accepts the bar's layer rule and logs a refusal as a
# refusal. It could not settle that the bar is *blurred*, and neither can any
# other seam in this repo:
#
#   * tools/blur-harness.sh reads the compositor's reply, not its output;
#   * tools/capture-harness.sh is client-side by construction — it renders the
#     shell's own surfaces and never sees what was composited behind them;
#   * the nested session cannot present at all (#85);
#   * the one real session #78 tried had blur rendering nowhere, for any window,
#     so a corrected rule producing no visible change proved nothing.
#
# That last one is the shape of the problem: "the rule did nothing" and "this
# machine draws no blur" look identical from inside the shell. So the first
# thing this script does is take the ambiguity away — an ordinary translucent
# toplevel over the same wallpaper, blur on and off, with no layer rule anywhere
# near it. If that pair shows no blur, the run stops there and says so, rather
# than blaming the bar for the compositor.
#
# ## Why it takes over the session for ten seconds
#
# There is nothing to photograph without a compositor that presents, so this
# runs on the caller's own Wayland session — the seam CLAUDE.md names as the one
# nothing covers. It borrows the session and gives it back:
#
#   * it switches to an empty named workspace, so nobody's windows are in the
#     shot, and switches back at the end;
#   * it turns compositor blur on with `hyprctl keyword`, which is runtime-only,
#     and finishes with `hyprctl reload` — every keyword set here is gone;
#   * the shell it launches gets its own XDG_CONFIG_HOME, because flipping
#     `bar.surface.blur` is a real settings write.
#
# ## What it measures
#
# tools/measure-blur.py, whose arithmetic is unit-tested in
# tests/tst_measure_blur.py. A blur is a low-pass filter, so the high-frequency
# detail behind the surface collapses while the mean stays put; `kept` is the
# blurred capture's detail as a percentage of the unblurred one's. The mean is
# the control — a pair that lost its detail *and* moved its mean is not a blur,
# it is a different picture.
#
# Then tools/measure-contrast.py over both captures, which is the #79 number:
# the capture seam measures the unblurred worst case because that bounds the
# blurred one from below, and this says by how much.
set -uo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source tools/qs-runtime.sh

OUT_DIR=""
KEEP=0
BLUR_SIZE=""
BLUR_PASSES=""
TEXT_COLOR=a9b8b0
# How much detail the blurred capture may keep before the pair stops showing a
# blur. Not a tight bound, deliberately: the bar dusts client-side grain over
# its own fill (BarSurface.qml §6), and no compositor blur can remove that — it
# is in front of the effect, not behind it. So `kept` has a floor the wallpaper
# never reaches, and the threshold only has to separate "blurred" from "the rule
# did nothing", where kept is ~100%.
MAX_KEPT=60
# The fill is opaque enough (0.86 by default) that the blur can only move the
# composited mean a little. A larger move means the two shots are not the same
# picture — something else changed between them.
MAX_MEAN_DRIFT=6

while (( $# )); do
    case "$1" in
        --out) OUT_DIR="${2:?--out needs a directory}"; shift 2 ;;
        --keep) KEEP=1; shift ;;
        --size) BLUR_SIZE="${2:?--size needs a number}"; shift 2 ;;
        --passes) BLUR_PASSES="${2:?--passes needs a number}"; shift 2 ;;
        --text-color) TEXT_COLOR="${2:?--text-color needs RRGGBB}"; shift 2 ;;
        --max-kept) MAX_KEPT="${2:?--max-kept needs a percentage}"; shift 2 ;;
        -h|--help) sed -n '2,56p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
note()  { printf '  \033[2m%s\033[0m\n' "$1"; }
fail_count=0
pass() { green "  PASS  $1"; }
fail() { red   "  FAIL  $1"; fail_count=$((fail_count + 1)); }

# --- the session ------------------------------------------------------------

command -v grim >/dev/null || { echo "grim not found — this seam is screenshots" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 1; }
[[ -n "${WAYLAND_DISPLAY:-}" ]] || { echo "no WAYLAND_DISPLAY — run this from the session you want photographed" >&2; exit 1; }

## Find the Hyprland this session is actually talking to.
##
## HYPRLAND_INSTANCE_SIGNATURE is inherited, and a long-lived terminal (or a
## background agent) can be carrying one from an instance that died days ago —
## measured: 300+ stale socket directories under /run/user/$UID/hypr, exactly
## one of them live. Probing beats trusting the environment.
resolve_hypr() {
    if hyprctl version >/dev/null 2>&1; then return 0; fi
    local dir sig
    for dir in /run/user/"$(id -u)"/hypr/*/; do
        sig="$(basename "$dir")"
        if HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl version >/dev/null 2>&1; then
            export HYPRLAND_INSTANCE_SIGNATURE="$sig"
            note "stale HYPRLAND_INSTANCE_SIGNATURE in the environment; using the live one"
            return 0
        fi
    done
    return 1
}

resolve_hypr || { echo "no live Hyprland found — this measurement needs one" >&2; exit 1; }

QS_BIN=$(qs_runtime_resolve) || exit 1

# `grim -o` grabs one output, while every coordinate hyprctl reports — layer
# surfaces, window positions — is in the global layout. On a second monitor
# those differ by the output's origin, so it is subtracted from everything
# before a region is cut out of the capture. Getting this wrong does not look
# like a bug: it looks like a blur that did nothing.
read -r MONITOR MON_W MON_H SCALE MON_X MON_Y < <(hyprctl -j monitors | python3 -c '
import json, sys
mons = json.load(sys.stdin)
m = next((m for m in mons if m["focused"]), mons[0])
print(m["name"], m["width"], m["height"], format(m["scale"], "g"), m["x"], m["y"])')
[[ -n "$MONITOR" ]] || { echo "no monitor reported by hyprctl" >&2; exit 1; }

getopt_int() { hyprctl -j getoption "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["int"])'; }

WAS_ENABLED=$(getopt_int decoration:blur:enabled)
[[ -n "$BLUR_SIZE" ]]   || BLUR_SIZE=$(getopt_int decoration:blur:size)
[[ -n "$BLUR_PASSES" ]] || BLUR_PASSES=$(getopt_int decoration:blur:passes)
PREV_WS=$(hyprctl -j activeworkspace | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')

WORK=$(mktemp -d /tmp/blur-measure.XXXXXX)
[[ -n "$OUT_DIR" ]] || OUT_DIR="$WORK/shots"
mkdir -p "$OUT_DIR" "$WORK/config"
SHELL_LOG="$WORK/shell.log"
SHELL_PID=""
FOREIGN_BARS=""

cleanup() {
    if (( KEEP )) && [[ -n "$SHELL_PID" ]]; then
        note "--keep: the shell is still running as pid $SHELL_PID"
    elif [[ -n "$SHELL_PID" ]]; then
        kill -- "-$SHELL_PID" 2>/dev/null || kill "$SHELL_PID" 2>/dev/null
        wait "$SHELL_PID" 2>/dev/null
    fi
    # Everything set with `hyprctl keyword` is runtime-only; a reload puts the
    # session back on its own config file, blur included. It also drops every
    # runtime layer rule — see the warning about a shell that was already
    # running when this started.
    hyprctl reload >/dev/null 2>&1
    hyprctl dispatch workspace "$PREV_WS" >/dev/null 2>&1
    # The captures are the point of the run and outlive it; the scratch config,
    # state and cache are not. `--keep` holds on to the lot, log included.
    (( KEEP )) || rm -rf "$WORK/config" "$WORK/state" "$WORK/cache"
    printf '\ncaptures: %s\n' "$OUT_DIR"
    [[ -z "$FOREIGN_BARS" ]] || note "the reload dropped every runtime layer rule, including the blur of the forest-shell that was already running — restart it to get that back"
}
trap cleanup EXIT
# A signal must become an exit, or the EXIT trap never runs and the caller's
# compositor keeps this run's keywords.
trap 'exit 130' INT
trap 'exit 143' TERM

echo
echo "blur measurement (#97) — $MONITOR ${MON_W}x${MON_H} at scale $SCALE"
note "captures in $OUT_DIR"
note "blur size $BLUR_SIZE, passes $BLUR_PASSES (config had enabled=$WAS_ENABLED)"

# An empty workspace: nobody's windows in the shot, and nothing else moving
# between the two captures of a pair.
hyprctl dispatch workspace name:blur-measure >/dev/null
hyprctl keyword decoration:blur:enabled true >/dev/null
hyprctl keyword decoration:blur:size "$BLUR_SIZE" >/dev/null
hyprctl keyword decoration:blur:passes "$BLUR_PASSES" >/dev/null

## Every forest-shell:bar surface currently mapped, one "x,y,w,h" per line.
bar_surfaces() { hyprctl -j layers | python3 -c '
import json, sys
want = sys.argv[1]
for name, out in json.load(sys.stdin).items():
    if name != want:
        continue
    for level in out.get("levels", {}).values():
        for s in level:
            if s.get("namespace") == "forest-shell:bar":
                print("%d,%d,%d,%d" % (s["x"], s["y"], s["w"], s["h"]))' "$MONITOR"; }

# Taken before the shell under test exists, so its own bar can be told from
# anyone else's afterwards. A forest-shell the caller is already running puts a
# second surface under the same namespace, and since a layer rule is matched by
# namespace it reaches both — so "which strip is mine" cannot be answered by
# looking at the picture, only by knowing what was there first.
FOREIGN_BARS=$(bar_surfaces)
[[ -z "$FOREIGN_BARS" ]] || note "another forest-shell is already running ($(wc -l <<<"$FOREIGN_BARS") bar surface(s)); its bar shares the namespace and will follow the same rules"

# The bar is given no modules. The contrast figure at the end is only
# comparable to the capture seam's if it is taken over the same thing, and
# tools/capture-harness.sh's `--surface bar` is the fill over the wallpaper with
# no content on it (its header: "the composite #79 measures"). A strip with
# glyphs on it measures the text against the text colour and reports 1:1, which
# is a fact about drawing letters rather than about blur.
mkdir -p "$WORK/config/forest-shell"
cat > "$WORK/config/forest-shell/settings.json" <<'JSON'
{
  "bar": {
    "modules": { "left": [], "center": [], "right": [] }
  }
}
JSON

# The shell's own config dir: flipping bar.surface.blur below is a real write.
# `setsid` because Quickshell forks — the process started here is not the one
# holding the Wayland connection and the IPC socket, so killing it by pid leaves
# an instance behind, orphaned and still answering (measured in #71).
SHELL_ENV=(XDG_CONFIG_HOME="$WORK/config"
           XDG_STATE_HOME="$WORK/state"
           XDG_CACHE_HOME="$WORK/cache"
           QT_ASSUME_STDERR_HAS_CONSOLE=1)
setsid env "${SHELL_ENV[@]}" "$QS_BIN" -p blur-measure.qml >"$SHELL_LOG" 2>&1 &
SHELL_PID=$!

await() {   # await <pattern> [timeout]
    local pattern="$1" timeout="${2:-15}"
    for _ in $(seq 1 $((timeout * 10))); do
        grep -qa "$pattern" "$SHELL_LOG" && return 0
        kill -0 "$SHELL_PID" 2>/dev/null || return 1
        sleep 0.1
    done
    return 1
}

# The IPC client has to see the same config root and the same XDG dirs as the
# instance it is addressing, or it looks for a socket the shell never opened.
ipc() { env "${SHELL_ENV[@]}" "$QS_BIN" -p blur-measure.qml ipc call "$@" 2>/dev/null; }

if ! await 'harness: blur measure harness ready'; then
    fail "the shell never came up — $(tail -3 "$SHELL_LOG")"
    exit 1
fi
# The wallpaper and the bar have to have been presented at least once before
# anything is photographed.
sleep 1.5

shoot() { grim -o "$MONITOR" "$1"; }

## A region in the compositor's *logical layout* coordinates -> the capture's
## own pixels: shifted to this output's origin, then scaled.
region() { python3 -c '
import sys
s, ox, oy = (float(v) for v in sys.argv[1:4])
x, y, w, h = (float(v) for v in sys.argv[4:8])
print("%d,%d,%dx%d" % (round((x - ox) * s), round((y - oy) * s),
                       round(w * s), round(h * s)))' \
    "$SCALE" "$MON_X" "$MON_Y" "$@"; }

measure() {  # measure <label> <off.png> <on.png> <region> [extra args...]
    local label="$1" off="$2" on="$3" reg="$4"; shift 4
    python3 tools/measure-blur.py "$off" "$on" --region "$reg" --label "$label" "$@"
}

# --- 1. does blur render on this machine at all -----------------------------
#
# The check #78 did not have. An ordinary toplevel, translucent, over the same
# wallpaper — no layer rule involved. If this shows nothing, every number below
# would be about the compositor rather than about the bar, and the run stops.
echo
echo "1. an ordinary window, so 'no blur' cannot mean 'no blur support'"

# Hard stop, not a note: every number below is about a rule this shell would
# never have pushed, and reporting them anyway is how #78's ambiguity got in.
if [[ "$(ipc measure available)" != "true" ]]; then
    fail "the shell's compositor facade is inert — it is not talking to this Hyprland"
    exit 1
fi

ipc measure probeWindow true >/dev/null
sleep 1.2
read -r PX PY PW PH < <(hyprctl -j clients | python3 -c '
import json, sys
want = sys.argv[1]
for c in json.load(sys.stdin):
    if c.get("title") == "forest-shell blur probe" and c.get("monitor") is not None:
        if c.get("workspace", {}).get("name") and c["at"] and c["size"]:
            print(*c["at"], *c["size"]); break' "$MONITOR")

if [[ -z "${PH:-}" ]]; then
    fail "the control window never mapped — cannot tell blur-off from blur-unsupported"
    exit 1
else
    # Inset well inside the frame: borders, rounding and the shadow are not the
    # window's own content and are not what is being measured.
    PROBE_REGION=$(region $((PX + 20)) $((PY + 20)) $((PW - 40)) $((PH - 40)))
    shoot "$OUT_DIR/window-blur-on.png"
    hyprctl keyword decoration:blur:enabled false >/dev/null
    sleep 0.7
    shoot "$OUT_DIR/window-blur-off.png"
    hyprctl keyword decoration:blur:enabled true >/dev/null
    sleep 0.7

    echo
    if measure "ordinary window" "$OUT_DIR/window-blur-off.png" \
               "$OUT_DIR/window-blur-on.png" "$PROBE_REGION" --max-kept "$MAX_KEPT"; then
        pass "Hyprland blur renders on this machine — the control is blurred"
    else
        fail "blur does not render for an ordinary window here; nothing below would mean anything"
        red "  this is #78's situation: check decoration:blur:enabled and the GPU, not the bar"
        exit 1
    fi
fi
ipc measure probeWindow false >/dev/null
sleep 0.7

# --- 2. the bar itself ------------------------------------------------------
echo
echo "2. the bar, with bar.surface.blur on and off"

if ! await "compositor: layerrule blur 1 → forest-shell:bar"; then
    fail "the bar's rule was never accepted — $(grep -a layerrule "$SHELL_LOG" | tail -2)"
fi

# Ours is the surface that was not there a moment ago. Picking "the one at the
# top of the screen" instead would photograph the caller's own bar half the
# time, and a bar photographed over the wrong config is a number about nothing.
read -r BX BY BW BH < <(comm -13 <(sort <<<"$FOREIGN_BARS") <(bar_surfaces | sort) \
    | head -1 | tr ',' ' ')

if [[ -z "${BH:-}" ]]; then
    fail "the bar under test never mapped as a layer surface"
    exit 1
fi
note "bar layer surface ${BW}x${BH} at ${BX},${BY} (logical)"
# Inset by 2 logical px: the bar's own top-edge lightening and its bottom
# boundary are authored gradients, not wallpaper, and a Laplacian reads a hard
# edge as detail.
BAR_REGION=$(region $((BX + 2)) $((BY + 2)) $((BW - 4)) $((BH - 4)))

shoot "$OUT_DIR/bar-blur-on.png"

was=$(grep -ac "layerrule blur 0 → forest-shell:bar" "$SHELL_LOG")
ipc measure blur false >/dev/null
for _ in $(seq 1 100); do
    [[ $(grep -ac "layerrule blur 0 → forest-shell:bar" "$SHELL_LOG") -gt "$was" ]] && break
    sleep 0.1
done
if [[ $(grep -ac "layerrule blur 0 → forest-shell:bar" "$SHELL_LOG") -le "$was" ]]; then
    fail "turning bar.surface.blur off pushed no rule Hyprland took"
fi
sleep 0.9
shoot "$OUT_DIR/bar-blur-off.png"

echo
if measure "bar strip" "$OUT_DIR/bar-blur-off.png" "$OUT_DIR/bar-blur-on.png" \
           "$BAR_REGION" --max-kept "$MAX_KEPT" --max-mean-drift "$MAX_MEAN_DRIFT"; then
    pass "the bar is blurred with bar.surface.blur on, and is not with it off"
else
    fail "the bar's picture does not change when its blur rule does"
fi

# The wallpaper *outside* the bar is the control for the pair: it is the same
# noise in both shots, and if its detail moved too, something other than the
# layer rule changed between them.
CTRL_Y=$(( BY + BH + 40 ))
CTRL_REGION=$(region "$((BX + 2))" "$CTRL_Y" "$((BW - 4))" 120)
echo
if measure "bare wallpaper below the bar" "$OUT_DIR/bar-blur-off.png" \
           "$OUT_DIR/bar-blur-on.png" "$CTRL_REGION" --min-kept 90; then
    pass "the wallpaper outside the bar is untouched — the collapse is the bar's rule"
else
    fail "the wallpaper outside the bar changed too — the pair is not a clean A/B"
fi

# --- 3. what the blur is worth to #79 ---------------------------------------
#
# The capture seam measures contrast over the *unblurred* bar because that
# bounds the blurred case from below. This is the other end of that bound,
# taken over the same strip on the same wallpaper.
echo
echo "3. contrast over the strip, blurred next to unblurred (#79)"
# Inset by one logical px on every side: the strip is the bar, and a region
# that starts inside it but keeps the full width runs off the right of the
# capture once the monitor scale is applied.
CONTRAST_REGION=$(region $((BX + 1)) $((BY + 1)) $((BW - 2)) $((BH - 2)))
WINDOW=$(python3 -c "print(round(100 * $SCALE))")
for shot in bar-blur-off bar-blur-on; do
    printf '  %s\n' "${shot#bar-}"
    python3 tools/measure-contrast.py "$OUT_DIR/$shot.png" \
        --text-color "$TEXT_COLOR" --region "$CONTRAST_REGION" --window "$WINDOW" \
        | sed 's/^/    /'
done

echo
note "bar.surface.opacity setting: $(ipc measure fillOpacity) — the legibility clamp (#79) can raise what was actually painted above it"
if (( fail_count )); then
    red "$fail_count check(s) failed"
    exit 1
fi
green "the bar is blurred, and by this much"
exit 0
