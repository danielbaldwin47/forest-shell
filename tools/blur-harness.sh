#!/usr/bin/env bash
# Push the bar's blur rule at a real compositor and assert it was taken (#78).
#
#   tools/blur-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/blur-harness.sh --keep   # leave the nested session up to poke at
#
# The bug this exists for was invisible for four PRs because the shell logged a
# success line next to a command that failed every time. Hyprland reworked rule
# syntax in the 0.5x line, `blur, forest-shell:bar` has been answered with
# `invalid field blur: missing a value` ever since, and nothing here read the
# reply. So the checks below are as much about the *reporting* as the rule:
#
#   1. the facade is talking to a compositor at all
#   2. the bar's own rule is accepted on startup, and the old syntax is not
#   3. a rule Hyprland refuses is logged as a warning, not as a success
#   4. changing `bar.surface.blur` pushes the opposing rule, live
#   5. two rules pushed at once are both applied, not one killing the other
#
# What it still cannot check is the picture: whether the bar looks blurred. That
# is the screenshot gap in the header of tools/nested-session.sh, and #78's "by
# eye" acceptance is the part of it a real session still owns — the more so
# after #78's own comment found that blur renders nowhere on the test machine,
# so even a real session there answered "is the rule taken", not "is it blurred".
# What is checked here is everything up to the compositor's own `ok`.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

ipc() { nested_ipc call "$@"; }

## Wait for a line to have been logged `want` times. The rule is pushed more
## than once over a run, so "is it in the log" stops being the question as soon
## as the same rule is expected back.
await_count() {
    local pattern="$1" want="$2" timeout="${3:-10}"
    for _ in $(seq 1 $((timeout * 10))); do
        [[ $(grep -ac "$pattern" "$NESTED_SHELL_LOG") -ge "$want" ]] && return 0
        sleep 0.1
    done
    return 1
}

NAMESPACE="forest-shell:bar"

nested_up || exit 1

# The shell gets its own config dir. `layerrule blur false` below is a real
# settings write, and the real one belongs to whoever is running this.
mkdir -p "$NESTED_WORK/config"
NESTED_SHELL_ENV=("XDG_CONFIG_HOME=$NESTED_WORK/config")

nested_shell blur-harness.qml 'harness: blur harness ready' || exit 1

echo
# 1 — a facade with no session degrades every call to a logged no-op, which
# would let every check below pass by never running. Assert it is live first.
if [[ "$(ipc layerrule available)" == "true" ]]; then
    nested_pass "the facade is attached to the nested compositor"
else
    nested_fail "the facade found no Hyprland session — every rule below is a no-op"
fi

# 2 — the bar's own rule, pushed at the deferred stage. The log line is now
# written from the compositor's reply rather than from the fact of asking.
if nested_await "$NESTED_SHELL_LOG" "compositor: layerrule blur 1 → $NAMESPACE" 15; then
    nested_pass "the bar's blur rule was accepted by Hyprland"
else
    nested_fail "the bar's blur rule was never accepted — $(grep -a 'layerrule' "$NESTED_SHELL_LOG" | tail -2)"
fi

# 2b — and the old syntax really is refused, so the check above is not passing
# on a compositor that would take anything. This is the measurement from the
# ticket, taken again on whatever machine is running the harness.
old=$(nested_hyprctl keyword layerrule "blur, $NAMESPACE")
if [[ "$old" == "ok" ]]; then
    nested_fail "this Hyprland still accepts the pre-0.5x syntax — the rule was spelled for nothing"
else
    nested_pass "the pre-0.5x syntax is refused here: $old"
fi

# 3 — the half that matters more. A rule the compositor refuses has to reach
# the log as a warning; a success line is what hid this for four PRs.
ipc layerrule push "notarule 1" "$NAMESPACE" > /dev/null
if nested_await "$NESTED_SHELL_LOG" 'hyprland refused layerrule "notarule 1"' 10; then
    refusal=$(grep -a 'hyprland refused' "$NESTED_SHELL_LOG" | tail -1)
    nested_pass "a refused rule is reported: ${refusal#*compositor: }"
else
    nested_fail "a rule Hyprland refused was not reported at all (#78)"
fi

if grep -qa "layerrule notarule 1 → $NAMESPACE" "$NESTED_SHELL_LOG"; then
    nested_fail "a refused rule was *also* logged as a success — the #78 line"
else
    nested_pass "the refusal was not dressed up as a success line"
fi

# 4 — the setting is live, and off is a rule of its own now that 0.5x has no
# clearing verb.
#
# Driven through `Config.set` rather than by editing settings.json, which is
# how #78 words it ("flipping `bar.surface.blur` in `settings.json` changes it
# live"), because a hand edit changes nothing in a running shell **at all**:
# measured here, the shell holds zero inotify descriptors, so no external edit
# to settings.json is ever noticed, while an independent Quickshell FileView
# watching the same file in the same nested session sees every one of them.
# That is a bug in Core/ and a separate ticket — Core/Paths.qml calls
# settings.json "hand-editable, hot-reloaded" — and not one this ticket can
# quietly fix under a blur rule. What is checked here is everything downstream
# of the config having changed: the key dispatch, the bar, the rule.
ipc layerrule blur false > /dev/null
if nested_await "$NESTED_SHELL_LOG" "compositor: layerrule blur 0 → $NAMESPACE" 10; then
    nested_pass "turning bar.surface.blur off pushed blur 0, accepted"
else
    nested_fail "turning blur off pushed nothing Hyprland took — $(grep -a 'layerrule' "$NESTED_SHELL_LOG" | tail -2)"
fi

was=$(grep -ac "layerrule blur 1 → $NAMESPACE" "$NESTED_SHELL_LOG")
ipc layerrule blur true > /dev/null
if await_count "layerrule blur 1 → $NAMESPACE" $((was + 1)) 10; then
    nested_pass "turning it back on pushed blur 1 again, accepted"
else
    nested_fail "turning blur back on did not re-push the rule"
fi

# 5 — two rules in the air at once. There is one hyprctl process, and handing
# it a second command while the first is running kills the first mid-run, which
# would drop a rule exactly as silently as the bug this ticket is about. Both
# replies have to come back.
ipc layerrule pushTwo "blur 0" "forest-shell:probe-a" "blur 1" "forest-shell:probe-b" > /dev/null
if await_count "layerrule blur 0 → forest-shell:probe-a" 1 10 \
   && await_count "layerrule blur 1 → forest-shell:probe-b" 1 10; then
    nested_pass "two rules pushed together were both applied and both reported"
else
    nested_fail "a rule pushed while another was in flight was lost — $(grep -a 'layerrule' "$NESTED_SHELL_LOG" | tail -3)"
fi

echo
if (( nested_fail_count )); then
    printf '\033[31m%d check(s) failed\033[0m\n' "$nested_fail_count"
    exit 1
fi
printf '\033[32mthe compositor is taking the bar'\''s rules\033[0m\n'
exit 0
