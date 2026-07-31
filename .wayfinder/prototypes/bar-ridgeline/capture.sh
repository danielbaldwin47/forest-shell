#!/usr/bin/env bash
# Drives the running prototype over IPC and assembles the comparison sheets in
# `shots/`. Start the prototype first:
#
#   qs-upstream -p shell.qml &
#   ./capture.sh
set -euo pipefail
cd "$(dirname "$0")"

QS=(qs-upstream -p shell.qml)

# Captures must NOT land inside the config directory: Quickshell watches it and
# hot-reloads on any file write, which silently resets every knob mid-run (the
# first version of this script produced sheets where half the variants were the
# defaults). Work outside the tree, copy the finished sheets back at the end.
WORK="${WORK:-${TMPDIR:-/tmp}/forest-bar-shots}"
OUT="$WORK"
FINAL=shots
mkdir -p "$OUT/raw" "$FINAL"

set_() { "${QS[@]}" ipc call proto set "$1" "$2" >/dev/null; }
wallpaper() { "${QS[@]}" ipc call proto wallpaper "$1" >/dev/null; }

# One frame: the bar plus enough wallpaper underneath to judge how it sits.
# The capture is 3x logical px (1.5 scale * 2 oversample).
shot() { # shot <name> <label>
  local name="$1" label="$2" band=340
  # grabToImage snapshots the frame at call time, so let the 240ms transitions
  # settle first — otherwise variants are captured mid-animation (the teal
  # variant came out half-way between teal and amber).
  sleep 0.6
  rm -f "$OUT/raw/$name.png"
  "${QS[@]}" ipc call proto capture "$OUT/raw/$name.png" >/dev/null
  # grabToImage + saveToFile is async; wait for the size to stop changing.
  local last=-1 cur=0 tries=0
  while [ "$cur" != "$last" ] || [ "$cur" -eq 0 ]; do
    last=$cur; sleep 0.4
    cur=$(stat -c %s "$OUT/raw/$name.png" 2>/dev/null || echo 0)
    tries=$((tries + 1)); [ $tries -gt 25 ] && break
  done
  magick "$OUT/raw/$name.png" -crop "3840x${band}+0+0" +repage -resize 1280x \
    -background '#0b100d' -fill '#a9b8b0' -font 'IBM-Plex-Sans' -pointsize 15 \
    label:"  $label" +swap -gravity west -append "$OUT/raw/$name-l.png"
}

sheet() { # sheet <out> <names...>
  local out="$1"; shift
  magick "${@/#/$OUT/raw/}" -append -bordercolor '#0b100d' -border 6 -quality 92 -sampling-factor 4:4:4 "$FINAL/${out%.png}.jpg"
  echo "  -> $FINAL/${out%.png}.jpg"
}

reset_() {
  set_ mock true
  set_ barHeight 32; set_ floating false; set_ barOpacity 1.0
  set_ topLight true; set_ grain true; set_ bottomHairline false
  set_ padH 12; set_ moduleGap 14
  set_ ridgeShape strata; set_ ridgeUnitWidth 14; set_ ridgeGap 4
  set_ ridgeActiveH 14; set_ ridgeOccupiedH 9; set_ ridgeEmptyH 3
  set_ ridgeFalloff 2; set_ ridgeOccupiedOpacity 0.62; set_ ridgeEmptyOpacity 0.22
  set_ ridgeOpacityFalloff 0.10; set_ ridgeAmberActive true
  set_ ridgeShowNumber false; set_ ridgeHorizon false
  set_ barBlur false; set_ fogWash 0.10; set_ barBlurAmount 0.55
  wallpaper 0
}

echo "sheet 1 — bar height"
reset_
for h in 26 30 32 36 40; do set_ barHeight "$h"; shot "h$h" "flush · height ${h}px"; done
sheet sheet-height.png h26-l.png h30-l.png h32-l.png h36-l.png h40-l.png

echo "sheet 2 — edge treatment"
reset_
shot e-flush "flush · opaque · top-light"
set_ bottomHairline true; shot e-hairline "flush · 1px bottom hairline"
reset_; set_ barOpacity 0.86; shot e-translucent "flush · 86% opacity (no blur)"
reset_; set_ floating true; shot e-float "floating island · margin 12/8 · radius 10"
reset_; set_ floating true; set_ floatMarginH 24; set_ floatMarginV 10; set_ barOpacity 0.9
shot e-float-wide "floating · margin 24/10 · 90% opacity"
reset_; set_ barBlur true; set_ barOpacity 0.45
shot e-fog "fog band · blurred wallpaper + 45% surface + mist wash"
reset_; set_ barBlur true; set_ barOpacity 0.2; set_ fogWash 0.16
shot e-fog-light "fog band · 20% surface · heavier mist"
reset_; set_ barBlur true; set_ barOpacity 0.45; set_ floating true
shot e-fog-float "fog band · floating island"
sheet sheet-edge.png e-flush-l.png e-hairline-l.png e-translucent-l.png e-float-l.png e-float-wide-l.png e-fog-l.png e-fog-light-l.png e-fog-float-l.png

echo "sheet 3 — ridgeline"
reset_
shot r-strata "strata · w14 gap4 · amber active"
set_ ridgeUnitWidth 9; set_ ridgeGap 3; shot r-strata-narrow "strata · w9 gap3"
set_ ridgeUnitWidth 6; set_ ridgeGap 2; set_ ridgeActiveH 16; shot r-strata-thin "strata · w6 gap2 · active 16"
reset_; set_ ridgeShape peaks; set_ ridgeUnitWidth 16; set_ ridgeGap 2; shot r-peaks "peaks · w16 gap2"
reset_; set_ ridgeShape pills; shot r-pills "pills (control — the usual idiom)"
reset_; set_ ridgeAmberActive false; shot r-teal "strata · teal active (no lamplight)"
reset_; set_ ridgeShowNumber true; shot r-number "strata · id under active"
reset_; set_ ridgeHorizon true; shot r-horizon "strata · horizon rule"
sheet sheet-ridge.png r-strata-l.png r-strata-narrow-l.png r-strata-thin-l.png r-peaks-l.png r-pills-l.png r-teal-l.png r-number-l.png r-horizon-l.png

echo "sheet 4 — the flushness claim, across wallpapers"
reset_
for i in 0 1 2 3 4 5; do
  wallpaper "$i"; sleep 0.5
  shot "w$i" "wallpaper $i"
done
sheet sheet-wallpaper.png w0-l.png w1-l.png w2-l.png w3-l.png w4-l.png w5-l.png

reset_
echo "done"
