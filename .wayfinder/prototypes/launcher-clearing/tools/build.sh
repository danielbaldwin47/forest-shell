#!/usr/bin/env bash
# Regenerate everything this prototype commits: fixtures, normalized icons, the
# noise tile, all 33 scene captures, and the labelled contact sheets.
#
#   ./tools/build.sh
#
# Runs the capture on the real Wayland session — MultiEffect (both the fog blur
# and the icon colorization) renders *nothing at all* under
# QT_QPA_PLATFORM=offscreen, silently, so a headless run would produce plausible
# but wrong pictures. See findings.md.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONS=../../../assets/icons/lucide

# The XDG vars are set explicitly: a detached/background shell may have none,
# and without them Qt's icon-theme lookup silently returns no app icons.
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-$HOME/.local/share:/usr/local/share:/usr/share}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"

mkdir -p fixtures gen shots sheets

echo "== fixtures"
python3 tools/make-fixtures.py > fixtures/apps.json

echo "== icons"
python3 tools/normalize-icons.py "$ICONS" gen/icons \
  search calculator clipboard-list smile command sparkles corner-down-left arrow-up arrow-down \
  layout-grid equal clipboard settings-2 mountain-snow moon sun palette power lock monitor \
  circle-slash package folder-search terminal x

echo "== noise tile"
magick -size 220x220 xc:gray50 +noise Random -colorspace Gray -attenuate 1.0 gen/noise.png

echo "== capture"
rm -f shots/*.png shots/*.jpg
FS_SHOOT=1 QT_ASSUME_STDERR_HAS_CONSOLE=1 qs-upstream -p shell.qml 2>&1 | grep -aE "shot |ERROR" || true

echo "== pack"
for f in shots/*.png; do magick "$f" -quality 90 "${f%.png}.jpg"; done
rm -f shots/*.png

sheet() {
  local out="$1"; shift
  magick montage "$@" \
    -tile 2x -geometry 960x540+8+8 \
    -background '#0b100d' -fill '#e6ece8' -pointsize 22 \
    "sheets/$out.png"
  magick "sheets/$out.png" -quality 88 "sheets/$out.jpg"
  rm -f "sheets/$out.png"
  echo "sheets/$out.jpg"
}

echo "== sheets"
rm -f sheets/*.jpg

sheet 1-scrim \
  -label 'A  pale mist (the brief)'    shots/01-baseline.jpg \
  -label 'B  dusk mist (proposed)'     shots/25-scrim-dusk.jpg \
  -label 'C  dim to black'             shots/02-scrim-dim.jpg \
  -label 'D  pale mist, graded'        shots/03-scrim-fog-gradient.jpg

sheet 2-panel \
  -label 'A  no plate — rows on fog'   shots/08-panel-none.jpg \
  -label 'B  strata plate'             shots/01-baseline.jpg \
  -label 'C  card, radius 16'          shots/09-panel-card.jpg \
  -label 'D  dusk + no plate'          shots/32-apps-query-dusk-panel-none.jpg

sheet 3-legibility \
  -label 'A  pale mist + plate, busy wall'  shots/05-wall-busy.jpg \
  -label 'B  pale mist, no plate, busy'     shots/29-scrim-fog-panel-none-busy.jpg \
  -label 'C  dusk + plate, busy'            shots/26-scrim-dusk-busy.jpg \
  -label 'D  dusk, no plate, busy'          shots/33-baseline-dusk-busy-panel-none.jpg

sheet 4-providers \
  -label '= calculator'   shots/16-calculator.jpg \
  -label '; clipboard'    shots/17-clipboard.jpg \
  -label ': emoji'        shots/18-emoji.jpg \
  -label '/ actions'      shots/19-actions.jpg

sheet 5-ask-claude \
  -label 'A  pale mist + plate'  shots/20-ask-claude.jpg \
  -label 'B  dusk, no plate'     shots/31-ask-claude-dusk-panel-none.jpg

sheet 6-geometry \
  -label 'A  horizon at 22%'      shots/22-horizon-high.jpg \
  -label 'B  horizon at 32%'      shots/13-apps-query.jpg \
  -label 'C  horizon at 42%'      shots/23-horizon-low.jpg \
  -label 'D  boxed field'         shots/07-field-boxed.jpg

sheet 7-rows \
  -label 'A  haze on unselected rows'   shots/01-baseline.jpg \
  -label 'B  no haze'                   shots/10-rowhaze-off.jpg \
  -label 'C  category on selected only' shots/12-category-selected-only.jpg \
  -label 'D  no legend / key hints'     shots/24-legend-off.jpg

sheet 8-no-compositor-blur \
  -label 'A  pale mist, blur off'   shots/34-fog-no-compositor-blur.jpg \
  -label 'B  dusk, blur off'        shots/35-dusk-no-compositor-blur.jpg \
  -label 'C  dusk, blur off, busy'  shots/36-dusk-no-blur-busy.jpg \
  -label 'D  dusk, blur on, busy'   shots/33-baseline-dusk-busy-panel-none.jpg
