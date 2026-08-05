#!/usr/bin/env bash
# Open, drive and dismiss the shared drawer window inside a nested Hyprland (#38).
#
#   tools/drawer-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/drawer-harness.sh --keep   # leave the nested session up to poke at
#
# The drawer is a lifecycle, which is the class of thing `tests/` cannot see at
# all: whether the window actually maps, whether the focus grab dismisses it,
# whether the state resets, whether the IPC door is callable at all. The
# decisions behind it — which drawer is open, which screen, what a hotplug does
# — are unit-checked in tests/tst_drawerpolicy.qml; this is the half that needs
# a compositor.
#
# What it asserts:
#
#   1. the drawer registers on the surface bus and on IPC as `session`
#   2. `ipc call session toggle` opens it, naming the screen
#   3. the fog is laid out *below* the bar, so the bar is above it
#   4. `ipc call session isOpen` agrees while it is open
#   5. a second toggle closes it, and says why
#   6. `ipc call session close` closes an open drawer, and says why
#   7. `show` is not on the target, because the CLI cannot call it (#77)
#   8. a toggle for a drawer nobody has built leaves the open one alone
#   8b-8d. the launcher, the notification centre and the control centre are
#      real tenants: each registers, opens, agrees it is open, and *swaps* with
#      another rather than taking the fog down between them
#   8i. the dashboard is the fifth (#49): it registers, opens, stacks the cards
#      the config named, builds its media card from the player on the bus, and
#      seeks it to a point in the track. Since #50 it also carries the two data
#      cards, and the sampler behind one of them is a *lifecycle*: nothing
#      samples the machine at startup, the system-monitor card starts the
#      sampler when it appears, and closing the dashboard stops it again
#   8e. the four service facades #44 added come up and say so
#   8f. every control-centre toggle is wired: each press logs what it asked for
#      and the facade answers — working or refusing
#   8g. the sliders route, without touching the caller's own sound card
#   8h. the five drill-in detail views (#45) open, close, replace each other,
#      release the radio they held, and refuse a row that does not exist
#   9. the compositor took the fog's blur layerrule
#  10. reducedEffects still opens and closes the drawer — the ladder collapses
#      the motion, it does not remove the surface
#  11. nothing is fighting itself (no binding loops)
#  12. a wallpaper pick survives a restart — the one check that restarts the
#      shell, and so the last one
#
# The shell under test runs against a scratch XDG_CONFIG_HOME and
# XDG_STATE_HOME: check 10 rewrites `appearance.reducedEffects`, and a harness
# that edits the settings of the session running it is one nobody will run twice.
#
# **Checks 8f do touch the caller's hardware, briefly.** There is no scratch
# copy of a radio: the nested session shares the host's NetworkManager, BlueZ
# and power-profiles-daemon, so a press that proves a toggle is wired is a press
# that really flips it. Every one is flipped back — booleans by pressing twice,
# the power profile and the wifi radio by name from an `EXIT` trap, so an
# interrupted run still puts them back. The sliders are *not* driven for the
# same reason turned up one notch further (8g): a sound card left at 40% is a
# change the user notices and cannot undo.
#
# **Escape is driven by hand, not here.** Hyprland's `sendshortcut` takes a
# *toplevel* — `, escape, activewindow`, and inside this session `hyprctl
# activewindow` answers `Invalid` because the shell is layer surfaces all the
# way down. There is no key-injection tool this repo may assume (no wtype, no
# ydotool), so the keyboard path is a `--keep` step:
#
#   tools/drawer-harness.sh --keep
#   qs -p shell.qml ipc call session open   # in the nested session
#   ...press Escape in it, and look for `drawers: session closed (escape)`
#
# tools/settings-harness.sh can press keys only because the settings window is
# an ordinary toplevel; tools/lock-harness.sh works around the same wall with a
# harness-only IPC that types for it, which tests the handler and not the key.
#
# What this seam also cannot answer, and #38's acceptance says so: whether the
# transitions hold 60 Hz. That is frame pacing — the nested session never
# presents (see the header of nested-session.sh) and a client-side grab never
# counts frames.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

ipc() { nested_ipc call session "$@"; }

# The log is append-only and the drawer is opened several times over, so "did
# this call do anything" is always a question about what arrived *after* it.
log_lines() { wc -l < "$NESTED_SHELL_LOG" 2>/dev/null || echo 0; }

since() { tail -n "+$(($1 + 1))" "$NESTED_SHELL_LOG" 2>/dev/null; }

expect_since() {
    local mark="$1" pattern="$2" what="$3"
    for _ in $(seq 1 50); do
        if since "$mark" | grep -qaE "$pattern"; then
            nested_pass "$what"
            return 0
        fi
        sleep 0.1
    done
    nested_fail "$what — nothing matching /$pattern/ since the call"
    return 1
}

## A file that has to come to hold something. Polled rather than read once: a
## config write is debounced (Core/SpecFile.qml, 250 ms) so that a slider being
## dragged does not rewrite settings.json on every frame, which means "the shell
## decided to write it" and "it is on disk" are two moments and not one.
expect_file_contains() {
    local file="$1" needle="$2" what="$3"
    for _ in $(seq 1 50); do
        if grep -qaF "$needle" "$file" 2>/dev/null; then
            nested_pass "$what"
            return 0
        fi
        sleep 0.1
    done
    nested_fail "$what — $file never came to hold it: $(cat "$file" 2>/dev/null)"
    return 1
}

## Nothing matching arrived, and waiting longer would not change that. Used for
## the checks whose evidence is an absence.
expect_quiet_since() {
    local mark="$1" pattern="$2" what="$3"
    sleep 0.5
    if since "$mark" | grep -qaE "$pattern"; then
        nested_fail "$what — /$pattern/ arrived and should not have"
        return 1
    fi
    nested_pass "$what"
}

nested_up || exit 1

SCRATCH="$NESTED_WORK/xdg"
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state"
SETTINGS_FILE="$SCRATCH/config/forest-shell/settings.json"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state")

# A player on the session bus, for the dashboard's media card (#49): a card that
# is absent with nothing playing — which is the shipped behaviour and the right
# one — cannot be checked on a machine that is not playing anything. The fixture
# carries a length, a cover and `CanSeek`, which is what makes "cover art,
# transport, seek if the player allows" a thing this seam can ask about at all.
#
# Started before the shell, so the facade sees it at construction rather than as
# a player arriving mid-run, and guarded on the bindings being installed — the
# rest of this harness has to run on a machine without them.
FAKE_CLIENTS_PID=""
if python3 -c 'import dbus, gi' 2>/dev/null; then
    python3 "$(dirname "${BASH_SOURCE[0]}")/fake-dbus-clients.py" mpris \
        > "$NESTED_WORK/fake-clients.log" 2>&1 &
    FAKE_CLIENTS_PID=$!
    nested_await "$NESTED_WORK/fake-clients.log" 'mpris org.mpris' 5 || true
    nested_note 'a fake media player is on the session bus'
    # Chained onto the teardown the nested session installed, not over it: a
    # trap that replaced it would leave a nested Hyprland running.
    trap 'kill "$FAKE_CLIENTS_PID" 2>/dev/null; nested_down' EXIT
else
    nested_note 'no python dbus bindings — the dashboard checks read the empty case'
fi

nested_shell shell.qml 'drawers armed' || exit 1

echo

# --- 1. the doors are open ---------------------------------------------------
#
# Two of them, and they are announced together on purpose: the surface bus
# registration is what makes a bar button reach this, and the IPC target is what
# makes a keybind reach it. A drawer that registers neither is #81 — a surface
# that does nothing, quietly.

if grep -qa 'surfaces: session registered (qs ipc call session toggle)' "$NESTED_SHELL_LOG"; then
    nested_pass 'the session drawer registered on the surface bus'
else
    nested_fail 'the session drawer never registered on the surface bus'
fi

if nested_ipc show | grep -qa '^target session$'; then
    nested_pass 'the session drawer owns the `session` ipc target'
else
    nested_fail 'there is no `session` ipc target'
fi

# The launcher's door is named by the shell-switch contract (#7) rather than
# chosen here: lowercase `launcher`, verb `toggle`. A rename is a broken
# integration in somebody else's repo, so it is asserted literally.

if grep -qa 'surfaces: launcher registered (qs ipc call launcher toggle)' "$NESTED_SHELL_LOG"; then
    nested_pass 'the launcher registered on the surface bus'
else
    nested_fail 'the launcher never registered on the surface bus'
fi

if nested_ipc show | grep -qa '^target launcher$'; then
    nested_pass 'the launcher owns the `launcher` ipc target'
else
    nested_fail 'there is no `launcher` ipc target'
fi

if nested_ipc show | sed -n '/^target launcher$/,/^target /p' | grep -qa 'function show('; then
    nested_fail 'the launcher target advertises show(), which the CLI cannot call'
else
    nested_pass 'the launcher target does not advertise an uncallable show()'
fi

# Super+Space (#39). The shell registers the shortcut over
# hyprland-global-shortcuts-v1 rather than shelling out per keypress, so the
# evidence is the compositor's own list — the binding in hyprland.conf is the
# user's half and is not something this seam can write for them.

if nested_hyprctl globalshortcuts | grep -qa 'forest-shell:launcher'; then
    nested_pass 'the compositor has the launcher global shortcut'
else
    nested_fail 'hyprland was never offered a launcher global shortcut'
fi

# --- 2. it opens, on a named screen ------------------------------------------

mark=$(log_lines)
ipc toggle > /dev/null
expect_since "$mark" 'drawers: session opened on ' 'ipc call session toggle opens the drawer'

# --- 3. the fog is laid out below the bar ------------------------------------
#
# #38's "the bar renders above the fog and stays clickable", measured rather
# than asserted. The drawer window reserves nothing and respects what does
# (`ExclusionMode.Normal`, zero zone), so the compositor lays it out *under* the
# bar's exclusive strip — the fog never covers the bar and stacking order within
# `WlrLayer.Top` never has to be argued with. `hyprctl layers` reports the
# geometry the compositor actually gave each surface, which is the evidence.
#
# Clickability used to have a second half — a focus grab, and a registry of the
# windows it must not eat clicks on. Both are gone (#187): the grab took pointer
# focus off the bar the moment it activated and never gave it back, so the
# geometry above is now the whole guarantee. What a click on the bar actually
# does while a drawer is open is measured next door, in bar-click-harness.sh,
# which drives a real pointer.

layers=$(nested_hyprctl layers)
bar_height=$(sed -n 's/.*xywh: [0-9-]* [0-9-]* [0-9-]* \([0-9]*\),.*forest-shell:bar.*/\1/p' <<< "$layers" | head -1)
fog_top=$(sed -n 's/.*xywh: [0-9-]* \([0-9-]*\) [0-9-]* [0-9]*,.*forest-shell:drawers.*/\1/p' <<< "$layers" | head -1)

if [[ -z "$fog_top" ]]; then
    nested_fail 'the drawer window never mapped a layer surface'
elif [[ -z "$bar_height" ]]; then
    nested_fail 'the bar has no layer surface to be above'
elif [[ "$fog_top" == "$bar_height" ]]; then
    nested_pass "the fog starts below the bar (bar ${bar_height}px, fog top ${fog_top}px)"
else
    nested_fail "the fog starts at ${fog_top}px under a ${bar_height}px bar — it is covering it"
fi

# --- 4. ...and says so ---------------------------------------------------------

reply=$(ipc isOpen)
if grep -qa 'true' <<< "$reply"; then
    nested_pass 'isOpen agrees while the drawer is open'
else
    nested_fail "isOpen said \"$reply\" with the drawer open"
fi

# --- 5. a second toggle closes it, and the reason travels --------------------
#
# A drawer that was dismissed and one that was toggled shut look identical
# afterwards. The reason in the line is what tells them apart, here and in a bug
# report.

mark=$(log_lines)
ipc toggle > /dev/null
expect_since "$mark" 'drawers: session closed \(toggle\)' 'a second toggle closes it, saying toggle'

reply=$(ipc isOpen)
if grep -qa 'false' <<< "$reply"; then
    nested_pass 'isOpen agrees once it is closed'
else
    nested_fail "isOpen said \"$reply\" with the drawer closed"
fi

# --- 6. the explicit close ---------------------------------------------------

ipc open > /dev/null
mark=$(log_lines)
ipc close > /dev/null
expect_since "$mark" 'drawers: session closed \(ipc\)' 'ipc call session close closes it, saying ipc'

# --- 7. `show` is not on the surface -----------------------------------------
#
# `qs ipc call session show` is parsed as the `ipc show` subcommand and prints
# the target listing, exit 0, without calling anything (#77). A `show` on the
# handler would put that name in front of everybody in the listing they read it
# from.

if nested_ipc show | sed -n '/^target session$/,/^target /p' | grep -qa 'function show('; then
    nested_fail 'the session target advertises show(), which the CLI cannot call'
else
    nested_pass 'the session target does not advertise an uncallable show()'
fi

# --- 8. a drawer nobody built leaves the open one alone ----------------------
#
# Reaching for a drawer that does not exist has to be a no-op — what must not
# happen is the open drawer closing because someone reached for a surface that
# is not there.
#
# This was `launcher` until #39 landed and made it a real drawer, then
# `controlcenter` until #44 did the same, then `dashboard` until #49 did, which
# is the hazard the check has to be written against: the unbuilt name has to be
# one that is *still* unbuilt, or the assertion quietly becomes "a toggle for a
# drawer that exists does nothing", which is the opposite claim and passes for
# the wrong reason.
#
# #49 was the last tenant the build plan names, so the name below is an invented
# one rather than the next ticket's. If a sixth drawer is ever called `notepad`,
# move this again rather than deleting it.

ipc open > /dev/null
mark=$(log_lines)
nested_ipc call notepad toggle > /dev/null 2>&1
expect_quiet_since "$mark" 'drawers: session closed' \
    'a toggle for an unbuilt drawer leaves the open one alone'
ipc close > /dev/null

# --- 8b. the launcher is a drawer, and swapping does not close the fog -------
#
# #39's tenant, checked here rather than in tools/launcher-harness.sh because
# what is being asserted is the *window's* behaviour: one drawer replacing
# another is a transition inside one surface, and the evidence that it was not
# two windows fighting is that no `closed` line appears between them.

ipc open > /dev/null
mark=$(log_lines)
nested_ipc call launcher toggle > /dev/null
expect_since "$mark" 'drawers: session → launcher' \
    'the launcher swaps with the session menu rather than stacking'
expect_quiet_since "$mark" 'drawers: session closed' \
    'the swap does not take the fog down on its way'

mark=$(log_lines)
nested_ipc call launcher toggle > /dev/null
expect_since "$mark" 'drawers: launcher closed \(toggle\)' 'the launcher toggles shut'

# --- 8c. the notification centre is the third tenant -------------------------
#
# #43. The door is `notificationcenter` and not `notifications`, and that is the
# part worth asserting literally: the notification *service* already owns the
# `notifications` IPC target for DND, and two IpcHandlers on one name is one of
# them silently not answering. A rename here is a keybind that stops working.

if grep -qa 'surfaces: notificationcenter registered (qs ipc call notificationcenter toggle)' \
        "$NESTED_SHELL_LOG"; then
    nested_pass 'the notification centre registered on the surface bus'
else
    nested_fail 'the notification centre never registered on the surface bus'
fi

if nested_ipc show | grep -qa '^target notificationcenter$'; then
    nested_pass 'the notification centre owns the `notificationcenter` ipc target'
else
    nested_fail 'there is no `notificationcenter` ipc target'
fi

# Both targets exist, separately — the evidence that the two names did not
# collide into one handler.
if nested_ipc show | grep -qa '^target notifications$'; then
    nested_pass 'the notification service still owns its own `notifications` target'
else
    nested_fail 'the `notifications` ipc target went away when the centre took a name'
fi

mark=$(log_lines)
nested_ipc call notificationcenter toggle > /dev/null
expect_since "$mark" 'drawers: notificationcenter opened on ' \
    'ipc call notificationcenter toggle opens the centre'

reply=$(nested_ipc call notificationcenter isOpen)
if grep -qa 'true' <<< "$reply"; then
    nested_pass 'the centre agrees it is open'
else
    nested_fail "notificationcenter isOpen said \"$reply\" with the centre open"
fi

# Opening the centre is what "read" means in this shell (#43): the surface sets
# `centerOpen`, the service stamps `seenAt` and the bar's count empties. The
# stamp is the log line; the count is asked for over IPC below.
expect_since "$mark" 'notifications: seen \(unread ' \
    'opening the centre marks history seen'

mark=$(log_lines)
nested_ipc call notificationcenter toggle > /dev/null
expect_since "$mark" 'drawers: notificationcenter closed \(toggle\)' 'the centre toggles shut'

if nested_ipc show | sed -n '/^target notificationcenter$/,/^target /p' \
        | grep -qa 'function show('; then
    nested_fail 'the notificationcenter target advertises show(), which the CLI cannot call'
else
    nested_pass 'the notificationcenter target does not advertise an uncallable show()'
fi

# --- 8d. the control centre is the fourth tenant -----------------------------
#
# #44. `controlcenter`, lowercase and one word — the spelling
# Core/SurfaceBusPolicy.qml wrote down for the bar button that has been
# dispatching to it since #37. The surface had to land against the name the bar
# was already using; a rename here is a bar button that stops working.

if grep -qa 'surfaces: controlcenter registered (qs ipc call controlcenter toggle)' \
        "$NESTED_SHELL_LOG"; then
    nested_pass 'the control centre registered on the surface bus'
else
    nested_fail 'the control centre never registered on the surface bus'
fi

if nested_ipc show | grep -qa '^target controlcenter$'; then
    nested_pass 'the control centre owns the `controlcenter` ipc target'
else
    nested_fail 'there is no `controlcenter` ipc target'
fi

mark=$(log_lines)
nested_ipc call controlcenter toggle > /dev/null
expect_since "$mark" 'drawers: controlcenter opened on ' \
    'ipc call controlcenter toggle opens the control centre'

# The panel's own line, and the reason it exists: it is the evidence that the
# grid was assembled from the *real* services rather than drawn empty. The
# counts are not asserted — this nested session has no battery, may have no
# bluetooth radio and certainly has no VPN, and ControlCenterPolicy drops a tile
# per absence on purpose. What is asserted is that it counted something at all.
expect_since "$mark" 'control-centre: [0-9]+ tile\(s\), [0-9]+ slider\(s\)' \
    'the control centre assembled its grid from the live services'

reply=$(nested_ipc call controlcenter isOpen)
if grep -qa 'true' <<< "$reply"; then
    nested_pass 'the control centre agrees it is open'
else
    nested_fail "controlcenter isOpen said \"$reply\" with the panel open"
fi

# Cross-drawer, the other way round from 8b: the control centre is anchored to
# the top-right corner and the notification centre to the same one, so these two
# are the pair most likely to be mistaken for one window if the swap ever became
# a close and an open.
mark=$(log_lines)
nested_ipc call notificationcenter toggle > /dev/null
expect_since "$mark" 'drawers: controlcenter → notificationcenter' \
    'the two right-hand panels swap rather than stacking'
expect_quiet_since "$mark" 'drawers: controlcenter closed' \
    'the swap does not take the fog down on its way'

mark=$(log_lines)
nested_ipc call notificationcenter toggle > /dev/null
expect_since "$mark" 'drawers: notificationcenter closed \(toggle\)' 'and it toggles shut'

if nested_ipc show | sed -n '/^target controlcenter$/,/^target /p' \
        | grep -qa 'function show('; then
    nested_fail 'the controlcenter target advertises show(), which the CLI cannot call'
else
    nested_pass 'the controlcenter target does not advertise an uncallable show()'
fi

# --- 8i. the dashboard is the fifth tenant -----------------------------------
#
# #49, and the last drawer the build plan names. `dashboard`, lowercase and one
# word, which is the spelling Core/SurfaceBusPolicy.qml wrote down for the bar's
# *clock* — the module that opens it. A rename here is a clock that stops
# opening anything.

if grep -qa 'surfaces: dashboard registered (qs ipc call dashboard toggle)' \
        "$NESTED_SHELL_LOG"; then
    nested_pass 'the dashboard registered on the surface bus'
else
    nested_fail 'the dashboard never registered on the surface bus'
fi

if nested_ipc show | grep -qa '^target dashboard$'; then
    nested_pass 'the dashboard owns the `dashboard` ipc target'
else
    nested_fail 'there is no `dashboard` ipc target'
fi

# #50's first acceptance criterion, checked *before* the panel is ever opened:
# no sampling and no network at startup. The weather service is on the deferred
# list and the sampler is deliberately not (Core/ServiceInit.qml) — so at this
# point in the session the weather has read its cache and said so, and nothing
# has read /proc even once.
if grep -qa 'sysmon: sampling every' "$NESTED_SHELL_LOG"; then
    nested_fail 'the system monitor was sampling before anything opened the dashboard'
else
    nested_pass 'nothing sampled the machine at startup'
fi

if grep -qa 'weather: no place configured' "$NESTED_SHELL_LOG"; then
    nested_pass 'the weather service came up at the deferred stage without fetching'
else
    nested_fail 'the weather service never announced itself at the deferred stage'
fi

mark=$(log_lines)
nested_ipc call dashboard toggle > /dev/null
expect_since "$mark" 'drawers: dashboard opened on ' \
    'ipc call dashboard toggle opens the dashboard'

# The panel's own line, and the reason it exists: it is the evidence that the
# stack was assembled from `dashboard.cards` rather than drawn from a hardcoded
# list. The four names are asserted, because unlike the control centre's tiles
# they do not depend on this machine's hardware — the shipped default is #9's
# inventory in its order.
expect_since "$mark" 'dashboard: 4 card\(s\): calendar, weather, systemMonitor, media' \
    'the dashboard stacked the cards the config named, in the config order'

# The weather card with nowhere configured, which is the state a fresh install
# is in and the one the nested session runs in: it says so rather than sitting
# blank, and — the point — it puts nothing on the wire. The auto mode is opt-in
# (Core/SettingsSchema.qml at `weatherTime.weather.place`), so a shell nobody has
# configured never asks a geolocation service anything.
expect_since "$mark" 'dashboard: weather unset' \
    'the weather card says it has not been told where it is'

# The sampler, and the whole reason it is a subscription: it starts when the
# card that needs it appears, and #50's acceptance criterion is that it stops
# again. This is the first half.
expect_since "$mark" 'sysmon: sampling every [0-9]+ms for 1 watcher\(s\)' \
    'the system monitor card started the sampler when it appeared'

# What the machine answered. The row count is not asserted: a machine with no
# thermal sensor gets three rows and one with a sensor gets four, and both are
# real answers (Services/System/SystemStatsPolicy.qml drops the row rather than
# dashing it).
expect_since "$mark" 'dashboard: system monitor [0-9]+ row\(s\)' \
    'the system monitor card built its rows from the sampler'

# The calendar's line names a real month rather than a placeholder. Which month
# is not asserted — the nested session runs on today's date, whatever today is —
# only that the grid was built from one, with the six rows a fixed-height grid
# always has.
expect_since "$mark" 'dashboard: calendar [0-9]+/[0-9]{4} \(6 rows' \
    'the calendar built a month grid from the clock'

reply=$(nested_ipc call dashboard isOpen)
if grep -qa 'true' <<< "$reply"; then
    nested_pass 'the dashboard agrees it is open'
else
    nested_fail "dashboard isOpen said \"$reply\" with the panel open"
fi

# The media card, which is the one card made of something outside the shell.
# With the fixture on the bus it names the track; without the python bindings
# there is nothing playing, and the card's *absence* is the shipped behaviour
# rather than a failure — so the two cases are asserted separately and both are
# real answers.
if [[ -n "$FAKE_CLIENTS_PID" ]]; then
    expect_since "$mark" 'dashboard: media Test Track' \
        'the media card was built from the player on the bus'

    # The seek. A drag on the progress bar is not reachable from here, so the
    # gesture is driven through the door the media service owns (#49) — without
    # it the ticket's "seek if the player allows" would have no seam under it at
    # all. Both halves are checked: the shell's arithmetic, and the player
    # receiving the position it computed.
    #
    # `media` and not `dashboard`, because the player is the service's and not
    # the drawer's — a verb on the drawer would answer with the drawer shut.
    if nested_ipc show | grep -qa '^target media$'; then
        nested_pass 'the media facade owns the `media` ipc target'
    else
        nested_fail 'there is no `media` ipc target for the card to be driven through'
    fi

    seek_mark=$(log_lines)
    nested_ipc call media seek 50 > /dev/null
    expect_since "$seek_mark" 'media: seek to 1:30' \
        'the dashboard seeks the player to half way through a 3:00 track'
    if nested_await "$NESTED_WORK/fake-clients.log" 'seeked to 90' 5; then
        nested_pass 'the player was asked for that position and took it'
    else
        nested_fail "the player never saw the seek: $(cat "$NESTED_WORK/fake-clients.log")"
    fi
else
    expect_since "$mark" 'dashboard: media no player' \
        'the media card is absent with nothing playing'
fi

# The cards survive a settings write that is not about them (#75). This is the
# check for a failure with no visible symptom until you meet it: Core/SpecFile.qml
# replaces `Config.values` whole on every reload, so a dashboard that *bound* its
# card list would hand the Repeater a new array on any key changing — and every
# card would be destroyed and rebuilt, losing the month you had paged to and
# remounting the media card mid-track. The evidence is an absence: no card
# announces itself a second time.
cards_mark=$(log_lines)
printf '{ "notifications": { "maxVisible": 4 } }\n' > "$SETTINGS_FILE"
expect_since "$cards_mark" 'config: reloaded ' 'an unrelated settings write reaches the shell'
expect_quiet_since "$cards_mark" 'dashboard: calendar [0-9]' \
    'the cards are not rebuilt by a settings write that is not about them'

# Cross-drawer, from the middle of the bar to its right-hand corner: the
# dashboard hangs off the clock in the centre cluster and the control centre off
# a button at the edge, so these two are anchored to different places and the
# swap is the one most likely to be built as a close and an open.
mark=$(log_lines)
nested_ipc call controlcenter toggle > /dev/null
expect_since "$mark" 'drawers: dashboard → controlcenter' \
    'the dashboard and the control centre swap rather than stacking'
expect_quiet_since "$mark" 'drawers: dashboard closed' \
    'the swap does not take the fog down on its way'

# The second half of #50's subscription criterion, and the one that is a *cost*
# rather than a feature: the dashboard going away destroys the card, the card
# releases its subscription, and four file reads a second stop. A drawer swap is
# the harder case than a plain close — the panel is replaced rather than
# dismissed — so it is the one asserted.
expect_since "$mark" 'sysmon: sampling stopped — nothing is watching' \
    'the sampler stopped when the dashboard was replaced'

mark=$(log_lines)
nested_ipc call controlcenter toggle > /dev/null
expect_since "$mark" 'drawers: controlcenter closed \(toggle\)' 'and it toggles shut'

if nested_ipc show | sed -n '/^target dashboard$/,/^target /p' \
        | grep -qa 'function show('; then
    nested_fail 'the dashboard target advertises show(), which the CLI cannot call'
else
    nested_pass 'the dashboard target does not advertise an uncallable show()'
fi

# --- 8e. the services the grid is made of came up ----------------------------
#
# #44 added four, and three of them are named in Core/ServiceInit.qml's deferred
# list precisely so they are constructed before the drawer is first opened — a
# tile absent for the first frames of every first open reads as a machine that
# has no such hardware. Each announces itself either way, working or inert, and
# that line is the whole of the evidence that the singleton was constructed at
# all. What the machine actually has is not asserted: a nested session has no
# battery and no tunnel, and both of those are legitimate answers.

for service in 'power-profile' 'vpn' 'night-light' 'keep-awake'; do
    if grep -qaE "^.* $service: " "$NESTED_SHELL_LOG"; then
        nested_pass "the $service facade came up"
    else
        nested_fail "the $service facade never logged — was it constructed?"
    fi
done

# --- 8f. the control centre's controls actually do something -----------------
#
# The ticket's "Wi-Fi, BT, DND, Night Light, Keep Awake, Dark/Light, Power
# Profile, VPN toggles functional", which is a seam-2 claim: it is about
# services talking to a real NetworkManager, a real BlueZ and a real
# `powerprofilesctl`. Driven over `press` rather than by clicking, because a
# tile is a `TapHandler` and there is no injection tool here — the panel calls
# the same function (Surfaces/Drawers/ControlCenterActions.qml), so this drives
# what a finger drives.
#
# Each press is asserted twice, and the pair is the point:
#
#   1. `control-centre: <id> on|off` — the shell asked for something. This is
#      the line that says the control is *wired*, and it is the only evidence
#      for three of them: DND and Keep Awake write state and the theme mode
#      writes a config key, none of which logs on success. Without it a press
#      on any of the three is indistinguishable from a tile wired to nothing.
#   2. the facade's own line — the hardware answered. **Not asserted as
#      success**: this session has no VPN, no battery and may have no bluetooth
#      adapter, and "no adapter — unchanged" is the correct answer to a press
#      rather than a failure. What would be a failure is silence.
#
# So the first pattern is exact and the second accepts the service's own
# vocabulary, working or refusing.

# **This section touches the caller's own machine, and puts it back.**
#
# There is no scratch copy of a radio. The nested session shares the host's
# NetworkManager, BlueZ, power-profiles-daemon and PipeWire, so a press that
# reaches a facade reaches the real hardware — which is exactly what makes this
# a seam-2 check and exactly what makes it dangerous. Every boolean below is
# therefore pressed an even number of times, and the three that cannot be
# restored that way are recorded here and set back at the end regardless of how
# the run finishes.
#
# The alternative was to press nothing and assert only the routing, which is
# what 8g does for the sliders. It is the right answer there — a sound card left
# at 40% is a change the user notices and cannot undo — and the wrong one here:
# "the eight toggles are functional" is the ticket's acceptance, and a radio
# that never moved is not evidence of it.
# Recorded by *name* and set back by name, rather than by pressing twice. A
# second press is not a reliable undo: the facades toggle off their own bound
# property, and BlueZ takes long enough to propagate the first change that the
# second press can read the stale value and ask for the same thing again —
# measured, and it left this laptop's bluetooth radio off.
HOST_PROFILE=$(powerprofilesctl get 2>/dev/null | tr -d '[:space:]' || true)
# `nmcli radio wifi` *prints* enabled/disabled and *takes* on/off. Passing back
# what it printed is silently rejected, which is how an earlier version of this
# left the laptop's wifi off after every run.
case "$(nmcli radio wifi 2>/dev/null | tr -d '[:space:]')" in
    enabled)  HOST_WIFI=on ;;
    disabled) HOST_WIFI=off ;;
    *)        HOST_WIFI="" ;;
esac
HOST_BT=$(bluetoothctl show 2>/dev/null | sed -n 's/.*Powered: \(yes\|no\).*/\1/p' | head -1)

restore_host() {
    [[ -n "$HOST_PROFILE" ]] && powerprofilesctl set "$HOST_PROFILE" 2>/dev/null
    [[ -n "$HOST_WIFI" ]] && nmcli radio wifi "$HOST_WIFI" 2>/dev/null
    [[ "$HOST_BT" == yes ]] && bluetoothctl power on > /dev/null 2>&1
    [[ "$HOST_BT" == no ]] && bluetoothctl power off > /dev/null 2>&1
    return 0
}

# Called explicitly at the end of this section rather than from a `trap`.
# `trap restore_host EXIT` was the obvious spelling and it is wrong here:
# nested-session.sh installs its own EXIT trap to tear the compositor down, and
# a second `trap ... EXIT` *replaces* it rather than chaining — which took the
# nested session's cleanup with it and failed ten checks that had nothing to do
# with radios. An interrupted run is the accepted cost; `--keep` exists for the
# case where someone wants to stop in the middle anyway.

press() { nested_ipc call controlcenter press "$1" > /dev/null 2>&1; }

check_press() {
    local control="$1" pattern="$2" what="$3"
    local mark
    mark=$(log_lines)
    press "$control"
    expect_since "$mark" "$pattern" "$what"
}

# The three with no hardware to be missing: state and a config key, so both
# halves are exact.
check_press dnd 'control-centre: dnd on' 'pressing Do Not Disturb asks for it on'
check_press dnd 'control-centre: dnd off' 'and pressing it again asks for it off'

check_press keepawake 'control-centre: keepawake on' 'pressing Keep Awake asks for it on'
expect_since "$(( $(log_lines) - 40 ))" 'keep-awake: on — inhibiting idle' \
    'and the facade took the idle inhibitor'
check_press keepawake 'control-centre: keepawake off' 'and pressing it again releases it'

check_press mode 'control-centre: mode on' 'pressing Theme asks for light'
check_press mode 'control-centre: mode off' 'and pressing it again asks for dark'

# The five that depend on hardware this session may not have. The first line is
# exact; the second only has to be *something* from the right facade.
check_press wifi 'control-centre: wifi (on|off)' 'pressing Wi-Fi asks the network facade'
expect_since "$(( $(log_lines) - 40 ))" 'network: ' 'and the network facade answered'
# Restored by name in `restore_host`, for the reason bluetooth is.

check_press bluetooth 'control-centre: bluetooth (on|off)' \
    'pressing Bluetooth asks the bluez facade'
expect_since "$(( $(log_lines) - 40 ))" 'bluetooth: ' 'and the bluez facade answered'
# Not pressed again: see `restore_host`. BlueZ has not propagated the first
# change yet, so a second press reads the stale value and asks for the same
# thing twice — which is how this check used to leave the radio off.

# The one that cannot be undone by pressing it again — it cycles, and the cycle
# length is whatever the daemon offers. `restore_host` sets it back by name.
check_press powerprofile 'control-centre: powerprofile pressed' \
    'pressing Power Profile asks power-profiles-daemon'
expect_since "$(( $(log_lines) - 40 ))" 'power-profile: ' \
    'and power-profiles-daemon answered'

check_press vpn 'control-centre: vpn (on|off)' 'pressing VPN asks networkmanager'
expect_since "$(( $(log_lines) - 40 ))" 'vpn: ' 'and networkmanager answered'
press vpn   # back down, on a machine that actually had one to bring up

check_press nightlight 'control-centre: nightlight (on|off)' \
    'pressing Night Light asks the configured command'
expect_since "$(( $(log_lines) - 40 ))" 'night-light: ' 'and the command answered'
press nightlight

# The one tile that is a door rather than a switch. It said "the picker is not
# built yet" until #45; now the press opens the picker, and both halves are
# asserted — the tile logging the press it shares with its eight neighbours, and
# the navigation opening the panel behind it. Closed again immediately, because
# every check after this one expects the grid.
check_press wallpaper 'control-centre: wallpaper pressed' \
    'the wallpaper tile logs its press like every other tile'
expect_since "$(( $(log_lines) - 40 ))" 'control-centre: wallpaper panel opened' \
    'and the press opens the picker behind it'
nested_ipc call controlcenter back > /dev/null 2>&1

# A name no tile has. Over IPC this is something a person typed into a keybind,
# and a keybind that does nothing deserves the one line saying why.
check_press nonesuch 'control-centre: nonesuch unchanged — no such control' \
    'a press for a control that does not exist explains itself'

restore_host

# --- 8g. the sliders route to the right service ------------------------------
#
# Only the routing, and deliberately only the routing. The three sliders drive
# **the caller's own hardware**: this nested session shares the host's PipeWire
# and its backlight, so `slide volume 40` sets the volume of the machine running
# the harness and `mute mic` mutes its microphone. A harness that edits the
# settings of the session running it is one nobody runs twice (this file's own
# header says so about XDG_CONFIG_HOME) — and a sound card is worse than a
# config file, because there is no scratch copy of it to point at.
#
# So what is asserted is the line the shell logs *before* it calls the facade,
# and the two ids that reach no hardware at all. That the facades themselves
# work is Services/Media/AudioPolicy.qml and Services/Hardware/BacklightPolicy
# .qml at seam 1, and tools/services-harness.sh at this one.

mark=$(log_lines)
nested_ipc call controlcenter slide nonesuch 40 > /dev/null 2>&1
expect_since "$mark" 'control-centre: nonesuch unchanged — no such slider' \
    'a slide for a slider that does not exist explains itself'

mark=$(log_lines)
nested_ipc call controlcenter mute brightness > /dev/null 2>&1
expect_since "$mark" 'control-centre: brightness unchanged — does not mute' \
    'the brightness slider refuses to mute rather than silently ignoring it'

# --- 8h. the control centre's drill-in detail views (#45) --------------------
#
# Five panels behind the grid: a Wi-Fi list, a bluetooth device list, an output
# picker and per-application mixer, a VPN list, and a wallpaper picker. Driven
# over `drill`/`back` rather than by pressing a chevron, for the reason 8f gives
# about tiles: a chevron is a `TapHandler` inside a drawer and there is no
# injection tool here, so the IPC door is what a finger drives and this is what
# drives it.
#
# **Nothing below joins, pairs, switches or disconnects anything.** That is a
# harder line than 8f draws, and deliberately: a press that flips a radio is
# undoable by pressing again, but joining a different access point drops the
# caller's connection and unpairing a device destroys a bond that has to be
# recreated by hand at the device. So what is asserted here is:
#
#   - the navigation — every panel opens, closes, replaces another and refuses
#     a name nothing has;
#   - the scanner handoff, which *is* a real radio and is the one thing here
#     that touches hardware. A scan changes no connection and is released again
#     by `back`; the check that it is released is the point, since a scanner
#     left running is a wakeup every few seconds that nothing on screen shows
#     (#22 §5);
#   - the refusal path of every row action, which is reachable with names that
#     exist nowhere and so cannot act on anything real.
#
# Joining a protected network, pairing a device, switching the output and
# connecting a tunnel are the four acceptance criteria no seam in this repo
# reaches. They are a manual real-session pass and the PR says so.

drill() { nested_ipc call controlcenter drill "$1" > /dev/null 2>&1; }
cc_back() { nested_ipc call controlcenter back > /dev/null 2>&1; }

nested_ipc call controlcenter toggle > /dev/null

for view in wifi bluetooth audio vpn wallpaper; do
    mark=$(log_lines)
    drill "$view"
    expect_since "$mark" "control-centre: $view panel opened" \
        "drill $view opens the $view panel"

    reply=$(nested_ipc call controlcenter panel)
    if grep -qa "$view" <<< "$reply"; then
        nested_pass "the centre agrees the $view panel is open"
    else
        nested_fail "panel said \"$reply\" with the $view panel open"
    fi

    mark=$(log_lines)
    cc_back
    expect_since "$mark" "control-centre: $view panel closed \(ipc\)" \
        "and back leaves it, saying ipc"
done

# The two that hold a radio. This is the check the whole scanner design exists
# for: the hold is counted and released by whatever closes the panel, and a
# release that never happened is invisible on screen and expensive forever.
#
# Neither pattern is asserted as success, for the reason 8f gives: this machine
# may have no wifi device and may have no bluetooth adapter, and "cannot scan"
# is the correct answer to a panel opening rather than a failure. Silence is
# what would be one.
mark=$(log_lines)
drill wifi
expect_since "$mark" 'network: (scanning|no wifi device — cannot scan)' \
    'opening the Wi-Fi panel asks the radio to scan'
mark=$(log_lines)
cc_back
expect_since "$mark" 'control-centre: wifi panel closed' \
    'and closing it releases the scan'
expect_quiet_since "$mark" 'network: scanning$' \
    'the scanner is not started again on the way out'

mark=$(log_lines)
drill bluetooth
expect_since "$mark" \
    'bluetooth: (scanning for devices|no adapter — cannot scan|radio off — scan deferred)' \
    'opening the Bluetooth panel asks the adapter to discover'
mark=$(log_lines)
cc_back
expect_since "$mark" 'control-centre: bluetooth panel closed' \
    'and closing it releases the discovery'

# Depth of exactly one: a second panel replaces the first rather than stacking
# under it, and pressing the door you are already behind takes you back out.
mark=$(log_lines)
drill wifi
drill bluetooth
expect_since "$mark" 'control-centre: wifi panel closed \(toggle\)' \
    'a second panel replaces the first'
expect_since "$mark" 'control-centre: bluetooth panel opened' \
    'and the second one opens'

mark=$(log_lines)
drill bluetooth
expect_since "$mark" 'control-centre: bluetooth panel closed \(toggle\)' \
    'pressing the door you are behind takes you back out'

# A panel nobody built. Over IPC this is a name someone typed into a keybind.
mark=$(log_lines)
drill nonesuch
expect_since "$mark" 'control-centre: no nonesuch panel — no such panel' \
    'a drill-in for a panel that does not exist explains itself'

# The one that would otherwise leak a radio: the drawer being dismissed out from
# under an open panel. The panel has to close itself, which is what releases the
# scanner — and the reason ControlCenter.qml has a `Component.onDestruction` at
# all.
drill wifi
mark=$(log_lines)
nested_ipc call controlcenter toggle > /dev/null
expect_since "$mark" 'control-centre: wifi panel closed \(drawer\)' \
    'closing the drawer closes the panel under it'

nested_ipc call controlcenter toggle > /dev/null

# Every row action, on a name that exists nowhere — the refusal path, which is
# the half of each verb that can be driven without touching real hardware. Each
# answers from its own facade, which is the evidence the door is wired to the
# service and not to nothing.
mark=$(log_lines)
nested_ipc call controlcenter network nonesuch > /dev/null 2>&1
expect_since "$mark" 'control-centre: nonesuch unchanged — no such network' \
    'pressing a Wi-Fi row that does not exist explains itself'

mark=$(log_lines)
nested_ipc call controlcenter passphrase nonesuch abcdefghij > /dev/null 2>&1
expect_since "$mark" 'network: wifi nonesuch unchanged — no such network' \
    'a passphrase for a network that does not exist reaches the network facade'

mark=$(log_lines)
nested_ipc call controlcenter device 00:00:00:00:00:00 > /dev/null 2>&1
expect_since "$mark" 'bluetooth: device 00:00:00:00:00:00 unchanged — no such device' \
    'pressing a bluetooth row that does not exist reaches the bluez facade'

mark=$(log_lines)
nested_ipc call controlcenter output 999999 > /dev/null 2>&1
expect_since "$mark" 'audio: stream 999999 unchanged — no such output' \
    'choosing an output that does not exist reaches the pipewire facade'

mark=$(log_lines)
nested_ipc call controlcenter stream 999999 40 > /dev/null 2>&1
expect_since "$mark" 'audio: stream 999999 unchanged — no such stream' \
    'moving a mixer row that does not exist explains itself'

mark=$(log_lines)
nested_ipc call controlcenter tunnel nonesuch > /dev/null 2>&1
expect_since "$mark" 'vpn: no connection called nonesuch' \
    'connecting a tunnel that does not exist reaches the vpn facade'

mark=$(log_lines)
nested_ipc call controlcenter wallpaper /nowhere/notes.txt > /dev/null 2>&1
expect_since "$mark" 'wallpaper: wallpaper unchanged — not an image' \
    'a wallpaper that is not an image is refused rather than written'

nested_ipc call controlcenter close > /dev/null

# --- 9. the fog asked the compositor for its blur ----------------------------
#
# The 10% wash does nothing on its own — what makes it fog is the compositor
# blurring what is behind it. #78: hyprctl exits 0 when it *refuses* a rule, so
# the reply text is the only evidence there is, and the shell logs the two cases
# differently for exactly that reason.

if grep -qa 'layerrule blur 1 → forest-shell:drawers' "$NESTED_SHELL_LOG"; then
    nested_pass 'hyprland took the fog blur layerrule'
elif grep -qa 'refused layerrule .* forest-shell:drawers' "$NESTED_SHELL_LOG"; then
    nested_fail "hyprland refused the fog blur: $(grep -a 'refused layerrule' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_fail 'the fog blur layerrule was never pushed'
fi

# --- 10. reduced effects still has a drawer -----------------------------------
#
# #22 §7 asks for "a fully supported look, not a broken mode". Rung 3 collapses
# every transition to a 140 ms fade; what it must not do is leave the surface
# unopenable. The durations themselves are unit-checked
# (tests/tst_effectspolicy.qml) — what is checked here is that the lifecycle
# still runs with the knob on.

reduced_mark=$(log_lines)
printf '{ "appearance": { "reducedEffects": true } }\n' > "$SETTINGS_FILE"
expect_since "$reduced_mark" 'config: reloaded ' 'the knob reaches the running shell'

mark=$(log_lines)
ipc toggle > /dev/null
expect_since "$mark" 'drawers: session opened on ' 'the drawer still opens with reducedEffects on'

mark=$(log_lines)
ipc toggle > /dev/null
expect_since "$mark" 'drawers: session closed \(toggle\)' 'the drawer still closes with reducedEffects on'

# Rung 1 of the ladder, and the one rung with a subprocess in it — so this is a
# wait rather than a look: `hyprctl` is a `Process` the shell queues, and the
# reply lands some frames after the key that asked for it.
expect_since "$reduced_mark" 'layerrule blur 0 → forest-shell:drawers' \
    'reducedEffects took the fog blur away (rung 1)'

# --- 11. nothing is fighting itself ------------------------------------------
#
# A binding loop is a warning, not a failure, so it would otherwise pass
# unnoticed until the drawer visibly flickered. The window's `visible` is bound
# to an animated opacity and its slot list is rewritten from a signal on it,
# which is exactly the shape one comes from.

if grep -qa 'Binding loop' "$NESTED_SHELL_LOG"; then
    nested_fail "a binding loop was reported: $(grep -a 'Binding loop' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_pass 'no binding loops while the drawer was open'
fi

# --- 12. the wallpaper pick survives a restart -------------------------------
#
# #45's one acceptance criterion that is about *persistence* rather than about a
# radio, and the only check in this file that restarts the shell — which is why
# it is last. `nested_shell` truncates the log it writes, so every whole-log
# grep above (the registrations, the blur layerrule, the binding loops) would be
# looking at a log that only holds the second shell's output if this ran earlier.
#
# The claim being checked is exactly the one the picker makes: pressing a
# thumbnail writes `wallpaper.path` into settings.json, and settings.json is what
# Core/Config.qml reads synchronously at stage one — so the wallpaper after a
# restart is the wallpaper before it because both are that one string. There is
# no cache and no second store, and this is what says so.

WALLS="$NESTED_WORK/walls"
mkdir -p "$WALLS"

# Two, so "it picked the one that was pressed" is a distinguishable claim from
# "it picked whatever was in the folder". Written the way
# tools/capture-harness.sh writes its own, for the same reason: the picker takes
# the raster formats a person keeps wallpapers in, and a PPM is not one.
python3 - "$WALLS" <<'PYEOF'
import struct
import sys
import zlib


def chunk(tag, payload):
    return (struct.pack(">I", len(payload)) + tag + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))


def write(path, shade):
    raw = bytearray()
    for _ in range(8):
        raw.append(0)
        raw += bytes((shade, shade, shade)) * 8
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 6)))
        f.write(chunk(b"IEND", b""))


write(sys.argv[1] + "/alder.png", 40)
write(sys.argv[1] + "/birch.png", 200)
PYEOF

CHOSEN="$WALLS/birch.png"

folder_mark=$(log_lines)
printf '{ "wallpaper": { "folder": "%s" } }\n' "$WALLS" > "$SETTINGS_FILE"
expect_since "$folder_mark" 'config: reloaded ' 'the picker folder reaches the running shell'

# The drawer is opened first, and it has to be: the panel is a `Loader` inside
# the control centre, and the folder is listed by a singleton nothing constructs
# until something looks at it. Drilling in with the drawer shut sets the
# navigation state and draws nothing — which is a real thing to be able to do
# (the state is what the surface binds to), and the wrong thing to check a
# *picker* with. This check wants the panel that a person would see.
nested_ipc call controlcenter toggle > /dev/null

nested_ipc call controlcenter drill wallpaper > /dev/null

# Asserted since the *folder* was written, not since the drill: the listing
# follows `wallpaper.folder`, so it is re-read the moment the config reload
# lands and not when somebody next looks at it. Measured the hard way — this
# check was written against the drill's own mark and failed on a run where
# everything worked, because the line it wanted had already gone past.
expect_since "$folder_mark" 'wallpaper: 2 wallpaper\(s\) in ' \
    'the picker found both wallpapers in the folder'

mark=$(log_lines)
nested_ipc call controlcenter wallpaper "$CHOSEN" > /dev/null
expect_since "$mark" "wallpaper: wallpaper set to $CHOSEN" \
    'pressing a thumbnail sets the wallpaper'

# The intent, on disk. Not the same claim as the line above — that one says the
# shell decided to write it, this one says it landed somewhere a restart will
# find it, and the two are 250 ms apart on purpose (Core/SpecFile.qml debounces,
# so a dragged slider does not rewrite the file every frame).
expect_file_contains "$SETTINGS_FILE" "$CHOSEN" \
    'the pick was written to settings.json'

# Pressing it again is not a second write: every write is a file rewritten and a
# reload pushed to every surface bound to it, and the row with the tick on it is
# the most likely press in the panel.
mark=$(log_lines)
nested_ipc call controlcenter wallpaper "$CHOSEN" > /dev/null
expect_since "$mark" 'wallpaper: wallpaper unchanged — already set' \
    'pressing the wallpaper already set writes nothing'

# And the restart. A new shell, the same scratch XDG_CONFIG_HOME, and the
# question is what the background loads with no help from the old process.
nested_kill_shell
if nested_shell shell.qml 'drawers armed'; then
    # Awaited rather than read once. The wallpaper is decoded synchronously
    # before the first frame (Surfaces/Background/Wallpaper.qml explains why it
    # has to be), but "the shell announced its drawers" and "the image reported
    # itself ready" are still two events, and which lands first is not something
    # this check should be asserting.
    if nested_await "$NESTED_SHELL_LOG" 'background: wallpaper .*birch\.png' 10; then
        nested_pass 'the pick survived a restart — the new shell loaded it'
    else
        nested_fail 'the restarted shell did not load the chosen wallpaper'
    fi
else
    nested_fail 'the shell did not come back up after the restart'
fi

printf '\n'
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all drawer checks passed\n'
exit 0
