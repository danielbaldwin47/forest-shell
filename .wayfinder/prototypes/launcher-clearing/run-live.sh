#!/usr/bin/env bash
# Run the launcher prototype live, over the real desktop.
#
#   ./run-live.sh          real desktop behind the scrim
#   ./run-live.sh --blur   same, but turn Hyprland's blur on for the session first
#
# Keys:  type to search · ↑/↓ move · Esc quit
#        F1 scrim (pale mist → dusk → dim → graded)   F5 stand-in wallpaper
#        F2 field (horizon ↔ boxed)                   F6 stand-in desktop on/off
#        F3 panel (card → strata → none)              F7 horizon height
#        F4 row haze on/off                           F8 veil 0.10 → 0.18 → 0.26
#
# For issue #11 question 4, run it twice — once plain, once with --blur — and
# use F8 to find the lowest veil that still reads in each case.
set -euo pipefail
cd "$(dirname "$0")"

NS="forest-shell:launcher-proto"

export XDG_DATA_DIRS="${XDG_DATA_DIRS:-$HOME/.local/share:/usr/local/share:/usr/share}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"

# The scrim's blur is the compositor's job — a layer surface cannot blur what is
# behind it from inside QML. And `layerrule = blur` is inert unless blur is on
# globally, which it is NOT on this machine (decoration:blur:enabled = 0).
hyprctl keyword layerrule "blur, $NS" >/dev/null
hyprctl keyword layerrule "ignorealpha 0.05, $NS" >/dev/null

restore=""
if [[ "${1:-}" == "--blur" ]]; then
  was=$(hyprctl getoption decoration:blur:enabled -j | jq -r .int)
  hyprctl keyword decoration:blur:enabled true >/dev/null
  hyprctl keyword decoration:blur:size 8 >/dev/null
  hyprctl keyword decoration:blur:passes 3 >/dev/null
  restore=$was
  echo "blur temporarily on (size 8, passes 3); was enabled=$was — restored on exit"
fi

cleanup() {
  [[ -n "$restore" ]] && hyprctl keyword decoration:blur:enabled "$restore" >/dev/null || true
}
trap cleanup EXIT

QT_ASSUME_STDERR_HAS_CONSOLE=1 qs-upstream -p shell.qml
