#!/usr/bin/env bash
# The region picker's lifecycle, in a nested Hyprland (#51).
#
#   tools/screenshot-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/screenshot-harness.sh --keep   # leave the nested session up to poke at
#
# Seam 2 (CLAUDE.md). The rectangle arithmetic — which rectangle a backwards
# drag means, which window a click lands on, whether an edge snapped, what the
# file is called — is seam 1 and lives in `tests/tst_screenshotpolicy.qml`,
# where a three-window desktop can be posed. What only exists once a compositor
# does, and is therefore here:
#
#   - grim actually freezing a real output, and the picker only coming up once
#     it has (a picker over no freeze is a transparent window);
#   - the layer surface mapping, taking the keyboard, and giving it back;
#   - a committed region becoming a *file*, at the output's native resolution —
#     the one number this shell got wrong twice, because `grabToImage`
#     multiplies its `targetSize` by the surface's device pixel ratio and a
#     400x300 region silently wrote a 900x675 file while the log said 600x450;
#   - the two optional tools being absent, which is this machine's real state
#     and the branch that therefore actually runs.
#
# What it cannot check, and why: grim itself. Inside the nested compositor grim
# does not fail — it **hangs**, because it asks for a screencopy frame and that
# compositor never presents one after its first commit (upstream, #85 /
# hyprwm/aquamarine#348). Measured here: the first `open` produced no log line
# at all and every later one answered "already open" forever. So the harness
# stands a canned PNG in for the capture via FOREST_SCREENSHOT_FREEZE, and
# every other step — the picker mapping, the keyboard grab, the crop, the file
# and its size, the two optional tools — is exactly the real one. That grim's
# own output holds the right pixels was measured on the live session instead,
# bit-identical to `grim -g` of the same region; see the PR.
#
# The hang is also why the shell now has a deadline on the freeze, and it is
# what check 1 would report if the stand-in were ever removed.
#
# A scratch XDG_CONFIG_HOME and a scratch Pictures directory, so a test that
# writes screenshots does not write them into the session running it.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

ipc() { nested_ipc call screenshot "$@"; }

# The log is append-only, so "did this call do anything" is always a question
# about what arrived *after* it. Every check marks the log first and reads only
# the tail.
log_lines() { wc -l < "$NESTED_SHELL_LOG" 2>/dev/null || echo 0; }
since()     { tail -n "+$(($1 + 1))" "$NESTED_SHELL_LOG" 2>/dev/null; }

## Wait for a line that arrived after `mark`, and report it as a check.
expect_since() {
    local mark="$1" pattern="$2" what="$3"
    for _ in $(seq 1 60); do
        if since "$mark" | grep -qaE "$pattern"; then
            nested_pass "$what"; return 0
        fi
        sleep 0.1
    done
    nested_fail "$what — nothing matching /$pattern/ since the call"
    return 1
}

## Assert a line did *not* arrive. Given a moment first, because a negative that
## races the thing it is denying passes for the wrong reason.
refute_since() {
    local mark="$1" pattern="$2" what="$3"
    sleep 1
    if since "$mark" | grep -qaE "$pattern"; then
        nested_fail "$what — found /$pattern/, which should not be there"
        return 1
    fi
    nested_pass "$what"
}

## Assert an IPC reply is exactly what was expected.
expect_reply() {
    if [[ "$1" == "$2" ]]; then nested_pass "$3"
    else nested_fail "$3 — expected '$2', got '$1'"; fi
}

## The pixel dimensions of a PNG, read from its IHDR — no image library, and no
## trusting the shell's own claim about what it wrote.
png_size() {
    python3 - "$1" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as fh:
    head = fh.read(33)
w, h = struct.unpack('>II', head[16:24])
print(f"{w}x{h}")
PY
}

nested_up || exit 1

SCRATCH="$NESTED_WORK/xdg"
SHOTS="$NESTED_WORK/pictures"
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state" "$SHOTS"
cat > "$SCRATCH/config/forest-shell/settings.json" <<EOF
{
  "system": {
    "screenshot": {
      "directory": "$SHOTS",
      "copyToClipboard": true,
      "editor": "swappy",
      "snapToWindows": true
    }
  }
}
EOF
# The stand-in freeze: a PNG the size of the nested output, written where grim
# would have written one. Generated rather than checked in, so it tracks
# whatever size nested-session.sh gives the output.
FIXTURE="$NESTED_WORK/freeze-fixture.png"
python3 - "$FIXTURE" <<'FIXTURE_EOF'
import struct, sys, zlib

W, H = 1280, 800
# A checkerboard, so a crop of the wrong region is visibly the wrong crop
# rather than a uniform block that always looks right.
rows = bytearray()
for y in range(H):
    rows.append(0)
    for x in range(W):
        rows += bytes((40, 90, 70) if (x // 64 + y // 64) % 2 else (140, 160, 120))

def chunk(tag, data):
    return (struct.pack('>I', len(data)) + tag + data
            + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))

png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(bytes(rows), 6))
       + chunk(b'IEND', b''))
open(sys.argv[1], 'wb').write(png)
FIXTURE_EOF
[[ -f "$FIXTURE" ]] || { echo "could not build the freeze fixture" >&2; exit 1; }

NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state"
            "FOREST_SCREENSHOT_FREEZE=cp $FIXTURE")

nested_shell shell.qml 'screenshot picker armed' || exit 1

# The nested output, which the picker's geometry is all relative to. 1280x800 at
# scale 1, per the config nested-session.sh writes — so logical and native are
# the same here and a region's file is its own size. That is *not* true on the
# 1.5-scale laptop panel, which is why check 5 asserts the number rather than
# assuming it.
SCALE=$(nested_hyprctl monitors -j | python3 -c \
    'import json,sys; print(json.load(sys.stdin)[0]["scale"])' 2>/dev/null || echo 1)
nested_note "nested output scale is $SCALE"

# --- 1. the picker opens, and only once the freeze has landed ----------------
mark=$(log_lines)
ipc open > /dev/null
expect_since "$mark" 'screenshot: froze the screen to ' \
    'ipc call screenshot open freezes the screen before showing anything'
expect_since "$mark" 'screenshot: picker opened on .* window' \
    'the picker opens after the freeze, and says how many windows it can snap to'

# --- 2. it says it is open ---------------------------------------------------
expect_reply "$(ipc isOpen)" 'true' 'isOpen answers true while the picker is up'

# --- 3. a second open is refused rather than restarting the freeze -----------
# A second press mid-selection must not throw the drag away.
mark=$(log_lines)
ipc open > /dev/null
expect_since "$mark" 'screenshot: picker already open — ignoring open' \
    'a second open while the picker is up is refused, with the reason'
refute_since "$mark" 'screenshot: froze the screen to ' \
    'the refused open does not re-freeze the screen'

# --- 4. escape puts it away, and the reason is in the line -------------------
mark=$(log_lines)
# `nested_key_focused`, not `nested_key`: the picker is a layer surface, and
# `activewindow` resolves only to toplevels — it answers "window not found" and
# drops the keystroke, which reads exactly like a surface ignoring the key.
nested_key_focused escape
expect_since "$mark" 'screenshot: picker cancelled \(escape\)' \
    'escape cancels the picker, and the log says it was escape and not something else'
expect_reply "$(ipc isOpen)" 'false' 'isOpen answers false once it is down'

# --- 5. a committed region becomes a file, at the right size -----------------
mark=$(log_lines)
ipc region 100 80 400 300 > /dev/null
expect_since "$mark" 'screenshot: selected 400x300 at 100,80 \(ipc\)' \
    'ipc call screenshot region selects exactly the rectangle it was given'
expect_since "$mark" 'screenshot: saved [0-9]+x[0-9]+ to ' \
    'the region is written to a file'

SHOT=$(ipc last)
if [[ -f "$SHOT" ]]; then
    nested_pass "the file the shell named actually exists ($(basename "$SHOT"))"

    want="$(python3 -c "print(f'{round(400*$SCALE)}x{round(300*$SCALE)}')")"
    got="$(png_size "$SHOT")"
    # The check the #51 build got wrong twice. The log's claim and the file's
    # IHDR are two different sources, and only the second one is the picture.
    if [[ "$got" == "$want" ]]; then
        nested_pass "the file is $got — the region at the output's own scale, not a multiple of it"
    else
        nested_fail "the saved file is $got, expected $want (region 400x300 at scale $SCALE)"
    fi

    claimed=$(since "$mark" | grep -aoE 'saved [0-9]+x[0-9]+' | head -1 | cut -d' ' -f2)
    if [[ "$claimed" == "$got" ]]; then
        nested_pass "the log's size and the file's size agree ($got)"
    else
        nested_fail "the log claims $claimed but the file is $got"
    fi
else
    nested_fail "the shell reported a save but there is no file at '$SHOT'"
fi

# --- 6. the picker is down again once the shot is taken ----------------------
expect_reply "$(ipc isOpen)" 'false' 'the picker comes down once the shot is written'

# --- 6b. a cancel during the freeze stays cancelled --------------------------
# The bug this exists for: `cancel()` used to stop only the settle timer, so
# grim kept running and its `onExited` set the picker back to open and logged
# "picker opened" — an Escape that raced the freeze reopened what it dismissed.
mark=$(log_lines)
ipc open > /dev/null
ipc cancel > /dev/null
expect_since "$mark" 'screenshot: picker cancelled \(ipc\)' \
    'a cancel issued around the freeze is taken'

# Ordering, not presence. The stand-in freeze is a `cp` and each `ipc` call is
# its own process spawn, so the open usually *completes* before the cancel
# arrives — "picker opened" after the mark is therefore expected. The invariant
# that actually distinguishes the bug is that nothing reopens the picker
# *after* the cancel line.
sleep 1
if since "$mark" | awk '
        /screenshot: picker cancelled \(ipc\)/ { seen = 1; next }
        seen && /screenshot: picker opened on / { found = 1 }
        END { exit !found }
    '; then
    nested_fail 'the picker reopened after being cancelled — a freeze that outlived its cancel'
else
    nested_pass 'nothing reopens the picker after a cancel, however the freeze finishes'
fi
expect_reply "$(ipc isOpen)" 'false' 'the picker stays down after a cancel that raced the freeze'

# --- 7. a region under the floor is refused, and says so ---------------------
# Without this a stray click writes a 3x2 PNG and the window snapping looks
# broken (ScreenshotPolicy.minSide).
mark=$(log_lines)
ipc region 100 80 3 2 > /dev/null
expect_since "$mark" 'screenshot: selection .* is under 8px' \
    'a selection under the floor is refused rather than written'
refute_since "$mark" 'screenshot: saved ' \
    'nothing is written for a refused selection'

# --- 8. the two optional tools are absent, and each says which ---------------
# The branch that actually runs on this machine, and the one most likely to be
# silent: a person who pressed the key and then pressed paste has to be told
# they have a path and not a picture.
# Which branch is *expected* is decided by PATH here rather than by accepting
# whichever one the log happens to show: a check that passes on either branch
# asserts "the log said something about the clipboard", not the criterion. On a
# machine with neither tool this is the degraded path, and the degraded path is
# the one that has to be loud.
if command -v wl-copy > /dev/null; then
    expect_since 0 'screenshot: copied the image to the clipboard' \
        'wl-copy is installed, so the image itself went on the clipboard'
    refute_since 0 'screenshot: wl-copy is not installed' \
        'the shell did not claim wl-copy was missing when it is on PATH'
else
    expect_since 0 'screenshot: wl-copy is not installed — put the path on the clipboard' \
        'wl-copy is absent, so the path went on the clipboard and the log says which'
    refute_since 0 'screenshot: copied the image to the clipboard' \
        'the shell did not claim an image copy it could not have made'
fi

EDITOR_TOOL=swappy
if command -v "$EDITOR_TOOL" > /dev/null; then
    expect_since 0 "screenshot: handed .* to $EDITOR_TOOL" \
        "$EDITOR_TOOL is installed, so the shot was handed to it"
else
    expect_since 0 "screenshot: $EDITOR_TOOL is not installed — skipping the edit handoff" \
        "$EDITOR_TOOL is absent, so the handoff was skipped and the log names the tool"
fi

# --- 9. the target advertises nothing the CLI eats ---------------------------
# #77: `qs ipc call screenshot show` would be parsed as the client's own `show`
# subcommand, print the target listing and exit 0 without calling anything.
functions=$(nested_ipc show screenshot 2>&1 || true)
if grep -qaE '^\s*(function\s+)?(show|list|call)\s*\(' <<< "$functions"; then
    nested_fail "the screenshot target advertises a name the CLI eats: $(grep -aE '(show|list|call)\(' <<< "$functions" | head -1)"
else
    nested_pass 'the screenshot target has no show/list/call function (#77)'
fi

# --- 10. nothing is fighting itself ------------------------------------------
if grep -qa 'Binding loop' "$NESTED_SHELL_LOG"; then
    nested_fail "a binding loop was reported: $(grep -a 'Binding loop' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_pass 'no binding loops while opening, cancelling and taking a shot'
fi

printf '\n'
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all screenshot checks passed\n'
exit 0
