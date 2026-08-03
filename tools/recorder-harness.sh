#!/usr/bin/env bash
# Seam 2 (CLAUDE.md) for screen recording (#52): the real Services/Recorder,
# inside a nested Hyprland, driven over IPC.
#
#   tools/recorder-harness.sh
#   tools/recorder-harness.sh --keep      # leave the scratch dir for a look
#
# WHAT STANDS IN FOR THE ENCODERS, AND WHY IT IS NOT A STUB
#
# Neither real encoder can run here. `gpu-screen-recorder` wants a VA-API device
# the nested compositor does not expose, and `wf-recorder` takes a wlr-screencopy
# frame — which is the exact thing this compositor never presents after its
# first commit (#85, hyprwm/aquamarine#348), so it would hang rather than fail,
# the way grim does for tools/screenshot-harness.sh.
#
# So the harness puts two *real programs* named `gpu-screen-recorder` and
# `wf-recorder` at the front of the shell's PATH. Nothing inside the shell knows
# about them: there is no override property, no test-only branch, no env var the
# service reads. It probes them with `--version`, spawns them with the argv the
# policy built, signals them to stop, and reads their exit — every step is the
# one a real machine takes, and the only difference is that these two write a
# growing file instead of an H.264 stream.
#
# That buys three things a stubbed service could not:
#
#   - The argv is asserted as the encoder *received* it, from the far side of
#     `Process`. tests/tst_recorderpolicy.qml checks what the policy builds;
#     this checks what actually arrived, which is the half that a wrong
#     `command` binding would break.
#   - The fallback is exercised for real. A fake `gpu-screen-recorder` that
#     exits 1 in 50ms is indistinguishable to the shell from a machine whose
#     VAAPI driver is missing — which is the failure this ticket exists for and
#     the one that cannot be reproduced on hardware that works.
#   - SIGINT is proved rather than assumed. The fake writes an end marker from
#     its INT trap and only from there, so a file with the marker is a file
#     whose muxer got to flush. If the shell ever switched to SIGTERM the marker
#     would vanish, which is precisely what a real unplayable mp4 looks like.
#
# WHAT IT STILL CANNOT SAY: whether VAAPI works on the T480. That is a fact
# about a machine, no seam covers it, and the ticket's fourth criterion is a
# hardware check.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

ipc() { nested_ipc call recorder "$@"; }

# The log is append-only, so "did this call do anything" is always a question
# about what arrived *after* it. Every check marks the log first and reads only
# the tail.
log_lines() { wc -l < "$NESTED_SHELL_LOG" 2>/dev/null || echo 0; }
since()     { tail -n "+$(($1 + 1))" "$NESTED_SHELL_LOG" 2>/dev/null; }

expect_since() {
    local mark="$1" pattern="$2" what="$3"
    for _ in $(seq 1 80); do
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

## Each run overwrites the shell log, so keep a copy per run — a failure in run
## 3 must not take the evidence for run 1 with it.
keep_log() {
    cp "$NESTED_SHELL_LOG" "$NESTED_WORK/shell-$1.log" 2>/dev/null || true
    nested_note "run $1 log kept at $NESTED_WORK/shell-$1.log"
}

expect_reply() {
    if [[ "$1" == "$2" ]]; then nested_pass "$3"
    else nested_fail "$3 — expected '$2', got '$1'"; fi
}

## Assert the encoder was invoked with something. Reads the argv log the fakes
## append to, which is the command line as it crossed the process boundary.
expect_argv() {
    local pattern="$1" what="$2"
    for _ in $(seq 1 40); do
        if grep -qaE "$pattern" "$ARGV_LOG" 2>/dev/null; then
            nested_pass "$what"; return 0
        fi
        sleep 0.1
    done
    nested_fail "$what — no argv matching /$pattern/ in $ARGV_LOG"
    return 1
}

## Stop, and wait for the encoder to actually be gone. `ipc stop` returns as
## soon as the signal is sent; the muxer then has the container index to write,
## and a start issued inside that window is refused — correctly, but it makes
## the *next* check look like the failure.
stop_and_settle() {
    local mark
    mark=$(log_lines)
    ipc stop > /dev/null
    for _ in $(seq 1 60); do
        since "$mark" | grep -qaE 'recorder: recorded [0-9]+:[0-9]{2} to ' && return 0
        sleep 0.1
    done
    nested_note "the recorder did not settle after stop"
    return 1
}

expect_file_grew() {
    local file="$1" what="$2"
    for _ in $(seq 1 60); do
        if [[ -s "$file" ]]; then nested_pass "$what"; return 0; fi
        sleep 0.1
    done
    nested_fail "$what — $file is missing or empty"
    return 1
}

nested_up || exit 1

SCRATCH="$NESTED_WORK/xdg"
CLIPS="$NESTED_WORK/videos"
FAKEBIN="$NESTED_WORK/bin"
ARGV_LOG="$NESTED_WORK/argv.log"
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state" "$CLIPS" "$FAKEBIN"
: > "$ARGV_LOG"

# The optional dot is off by default (a module that is off is one no cluster
# names), so the scratch config names it — otherwise nothing here would load it
# and check 0 below would be asserting on a module that was never asked for.
cat > "$SCRATCH/config/forest-shell/settings.json" <<EOF
{
  "bar": {
    "modules": {
      "right": ["recorder", "clock"]
    }
  },
  "system": {
    "recording": {
      "directory": "$CLIPS",
      "engine": "auto",
      "framerate": 30,
      "audio": "desktop",
      "quality": "high",
      "container": "mp4"
    }
  }
}
EOF

# The stand-in encoder. One program under two names — it reads its own basename,
# which is also how it knows whether the output file arrives after `-o` (the GPU
# encoder) or after `-f` (wf-recorder). Getting that pair backwards is the
# mistake the policy's header warns about, so the fake refuses to guess: an
# unknown name writes nothing and exits non-zero, and the harness sees a
# recording that produced no file.
#
# `FAKE_BROKEN` names an encoder that should exit 1 during init — the VAAPI
# failure, which is a program that is installed and cannot run.
cat > "$FAKEBIN/gpu-screen-recorder" <<'FAKE_EOF'
#!/usr/bin/env bash
# A stand-in encoder for tools/recorder-harness.sh. Not a stub inside the
# shell: this is a real program the real service probes, spawns and signals.
set -u
me=$(basename "$0")
printf '%s %s\n' "$me" "$*" >> "$FAKE_ARGV_LOG"

# The probe. Absence of `started` is how the shell detects a missing binary, so
# a fake that is *present* must start and exit cleanly here.
if [[ "${1:-}" == "--version" ]]; then
    echo "$me (harness stand-in)"
    exit 0
fi

# Installed and unable to initialise — the VAAPI case the fallback exists for.
if [[ "${FAKE_BROKEN:-}" == "$me" ]]; then
    echo "$me: failed to open device" >&2
    exit 1
fi

out=""
flag="-o"
[[ "$me" == "wf-recorder" ]] && flag="-f"
prev=""
for arg in "$@"; do
    [[ "$prev" == "$flag" ]] && out="$arg"
    prev="$arg"
done
[[ -n "$out" ]] || { echo "$me: no output file after $flag" >&2; exit 2; }

# The end marker, written from the INT trap and from nowhere else. A file that
# has it is a file whose muxer got to flush; a shell that switched to SIGTERM
# would leave one without it, which is what an unplayable mp4 is.
finish() { printf 'MOOV\n' >> "$out"; exit 0; }
trap finish INT

printf 'FRAME\n' > "$out"
while :; do
    printf 'FRAME\n' >> "$out"
    sleep 0.1
done
FAKE_EOF
chmod +x "$FAKEBIN/gpu-screen-recorder"
cp "$FAKEBIN/gpu-screen-recorder" "$FAKEBIN/wf-recorder"

# The picker's stand-in freeze. #52 takes its region from #51's picker, and that
# picker cannot run grim in here — grim does not fail inside this compositor, it
# *hangs*, waiting for a frame that is never presented (#85). Same escape hatch
# tools/screenshot-harness.sh uses, for the same reason: with a canned PNG in
# place, every other step of the handoff is the real one.
FIXTURE="$NESTED_WORK/freeze-fixture.png"
python3 - "$FIXTURE" <<'FIXTURE_EOF'
import struct, sys, zlib

W, H = 1280, 800
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

# --- run 1: both encoders present and healthy --------------------------------

NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state"
            "PATH=$FAKEBIN:$PATH" "FAKE_ARGV_LOG=$ARGV_LOG"
            "FOREST_SCREENSHOT_FREEZE=cp $FIXTURE")

nested_shell shell.qml 'recorder armed' || exit 1

expect_since 0 'recorder: gpu-screen-recorder is available' \
    'the GPU encoder is probed and found'
expect_since 0 'recorder: wf-recorder is available' \
    'the fallback encoder is probed and found'
expect_reply "$(ipc using)" 'gpu-screen-recorder' \
    'with both installed, auto picks the GPU encoder'
expect_reply "$(ipc isRecording)" 'false' 'nothing is recording at rest'
refute_since 0 'recorder: env --default-signal=INT is unavailable' \
    'this machine can hand the encoder a working SIGINT'

# The bar dot. It draws nothing until something records, so its one log line is
# the only proof it resolved its imports and loaded at all — #73's caveat, that
# a directory reached by file URL is not a QML module, fails silently otherwise.
# What it *looks* like is seam 3 and not reachable from here.
expect_since 0 'bar: recorder dot on the bar' \
    'the optional bar dot loads when a cluster names it'
refute_since 0 'bar: no such module: recorder' \
    'the registry knows the module name the config used'

# --- 1. a whole-screen recording starts, and says what it is doing -----------
mark=$(log_lines)
: > "$ARGV_LOG"
ipc start > /dev/null
expect_since "$mark" 'recorder: recording the whole screen with gpu-screen-recorder to ' \
    'start names the engine, the target and the file before spawning'
expect_since "$mark" 'recorder: gpu-screen-recorder started encoding' \
    'the encoder reports it started, which is a separate line from the intent'
expect_reply "$(ipc isRecording)" 'true' 'isRecording answers true while it runs'

# The argv as the encoder received it — the far side of `Process`, which is the
# half tests/tst_recorderpolicy.qml cannot see.
expect_argv 'gpu-screen-recorder .*-f 30' 'the framerate setting reaches the encoder'
expect_argv 'gpu-screen-recorder .*-q high' 'the quality setting reaches the encoder'
expect_argv 'gpu-screen-recorder .*-a default_output' 'desktop audio reaches the encoder'
expect_argv 'gpu-screen-recorder .*-c mp4' 'the container setting reaches the encoder'

CLIP=$(ipc last)
nested_note "recording to $CLIP"
expect_file_grew "$CLIP" 'the encoder is writing a file'

# --- 2. a second start is refused rather than starting a second encoder ------
mark=$(log_lines)
ipc start > /dev/null
expect_since "$mark" 'recorder: already recording — ignoring start' \
    'a second start while recording is refused, with the reason'
refute_since "$mark" 'recorder: recording the whole screen' \
    'the refused start does not spawn a second encoder over the first file'

# --- 3. stop, with the signal that keeps the file ----------------------------
sleep 1
mark=$(log_lines)
ipc stop > /dev/null
expect_since "$mark" 'recorder: stopping the recorder \(SIGINT' \
    'stop says which signal it used, and why'
expect_since "$mark" 'recorder: recorded [0-9]+:[0-9]{2} to ' \
    'the stop line carries the duration and the file'
expect_reply "$(ipc isRecording)" 'false' 'isRecording answers false once it is over'

# The end marker only the INT trap writes. This is the SIGTERM regression test:
# a container with no index is a file that exists, is the right size, and will
# not play.
if grep -qa 'MOOV' "$CLIP"; then
    nested_pass 'the encoder was signalled with SIGINT and finished its file'
else
    nested_fail 'the file has no end marker — the encoder was killed, not stopped'
fi

# --- 4. stopping nothing is refused, not silent ------------------------------
mark=$(log_lines)
ipc stop > /dev/null
expect_since "$mark" 'recorder: not recording — ignoring stop' \
    'a stop with nothing running is refused, with the reason'

# --- 5. a region reaches the encoder as a region -----------------------------
mark=$(log_lines)
: > "$ARGV_LOG"
ipc region 100 50 640 480 > /dev/null
expect_since "$mark" 'recorder: recording 640x480 region with gpu-screen-recorder' \
    'a region recording says the rectangle it was given'
# `-w region` is a literal word where a monitor name would go — see gsrArgv.
expect_argv 'gpu-screen-recorder .*-w region .*-region 640x480\+100\+50' \
    'the region reaches the encoder in its own geometry form'
stop_and_settle

# --- 6. an odd-sided region is trimmed rather than refused -------------------
mark=$(log_lines)
: > "$ARGV_LOG"
ipc region 10 10 641 481 > /dev/null
expect_since "$mark" 'recorder: trimmed the region from 641x481 to 640x480' \
    'odd sides are trimmed to even, and the trim is said out loud'
expect_argv 'gpu-screen-recorder .*-region 640x480\+10\+10' \
    'the encoder gets the trimmed rectangle, not the drawn one'
stop_and_settle

# --- 7. a region under the floor is refused ----------------------------------
mark=$(log_lines)
ipc region 0 0 4 4 > /dev/null
expect_since "$mark" 'recorder: region 4x4 is under 8px — not recording it' \
    'a click-sized region is refused with its measurements'

# --- 8. the control centre's tile starts and stops it ------------------------
#
# The ticket's third criterion. Pressed over the panel's own IPC door rather
# than by clicking, because a press has to work with no drawer open at all —
# which is also how a keybind reaches it.
mark=$(log_lines)
nested_ipc call controlcenter press recording > /dev/null
expect_since "$mark" 'control-centre: recording' \
    'the control centre logs the press before routing it'
expect_since "$mark" 'recorder: recording the whole screen with ' \
    'a control-centre press starts a recording'
expect_reply "$(ipc isRecording)" 'true' 'the tile reads as recording'

mark=$(log_lines)
nested_ipc call controlcenter press recording > /dev/null
expect_since "$mark" 'recorder: stopping the recorder \(SIGINT' \
    'a second press on the same tile stops it'
expect_since "$mark" 'recorder: recorded [0-9]+:[0-9]{2} to ' \
    'the tile-stopped recording is written like any other'

# --- 9. a region comes from the picker, not from a second selection UI -------
#
# The cross-service handoff (#51's picker, #52's consumer). `pick` opens the
# picker; committing a rectangle over the screenshot target is what a drag would
# do, and the recorder must be the thing that receives it.
mark=$(log_lines)
: > "$ARGV_LOG"
ipc pick > /dev/null
expect_since "$mark" 'screenshot: picker opened on ' \
    'asking to record a region puts the real picker up'
refute_since "$mark" 'recorder: recording ' \
    'nothing is recorded until a rectangle is actually chosen'

mark=$(log_lines)
nested_ipc call screenshot region 20 30 320 240 > /dev/null
expect_since "$mark" 'screenshot: handed 320x240 at 20,30 to the caller — no file written' \
    'the picker hands the rectangle over instead of saving a screenshot'
expect_since "$mark" 'recorder: recording 320x240 region with ' \
    'the recorder receives the picked rectangle and records it'
expect_argv 'gpu-screen-recorder .*-region 320x240\+20\+30' \
    'the picked rectangle reaches the encoder'
stop_and_settle

# --- 10. a cancelled pick records nothing, and says so -----------------------
mark=$(log_lines)
ipc pick > /dev/null
expect_since "$mark" 'screenshot: picker opened on ' 'the picker is up again'
mark=$(log_lines)
nested_ipc call screenshot cancel > /dev/null
expect_since "$mark" 'recorder: region picker cancelled — nothing to record' \
    'a cancelled pick tells the recorder, rather than leaving it armed'
refute_since "$mark" 'recorder: recording ' 'a cancelled pick records nothing'

keep_log 1
nested_kill_shell

# --- run 2: the GPU encoder is installed and broken --------------------------
#
# The ticket's second acceptance criterion, and the one that cannot be produced
# on a machine where VAAPI works.

: > "$ARGV_LOG"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state"
            "PATH=$FAKEBIN:$PATH" "FAKE_ARGV_LOG=$ARGV_LOG"
            "FAKE_BROKEN=gpu-screen-recorder")

nested_shell shell.qml 'recorder armed' || exit 1

# It probes fine — `--version` is answered before the init failure, exactly as a
# tool with a missing driver behaves.
expect_reply "$(ipc using)" 'gpu-screen-recorder' \
    'a broken encoder still probes as present, so it is still the first choice'

mark=$(log_lines)
ipc start > /dev/null
expect_since "$mark" 'recorder: gpu-screen-recorder failed to initialise \(exit 1\) — falling back to wf-recorder' \
    'a fast non-zero exit is read as a failed init and falls back'
expect_since "$mark" 'recorder: recording the whole screen with wf-recorder to ' \
    'the fallback engine records the same thing'
expect_since "$mark" 'recorder: wf-recorder started encoding' \
    'the fallback actually starts'
expect_reply "$(ipc using)" 'wf-recorder' 'using() reports the engine that is really running'
expect_reply "$(ipc isRecording)" 'true' 'the recording survived the fallback'

# `-f` is the *file* to this tool and the framerate to the other one. The one
# thing that would silently swap.
expect_argv 'wf-recorder .*-r 30' 'wf-recorder gets the framerate after -r'
expect_argv "wf-recorder .*-f $CLIPS/" 'wf-recorder gets the output file after -f'

CLIP2=$(ipc last)
expect_file_grew "$CLIP2" 'the fallback encoder is writing a file'

sleep 1
mark=$(log_lines)
ipc stop > /dev/null
expect_since "$mark" 'recorder: recorded [0-9]+:[0-9]{2} to ' \
    'the fallback recording stops and reports like any other'

keep_log 2
nested_kill_shell

# --- run 3: the GPU encoder is not installed at all --------------------------

# A directory with only the fallback in it, prepended to the *real* PATH rather
# than replacing it: the shell binary is on that path too, and a PATH trimmed to
# /usr/bin is a harness that fails because it cannot find Quickshell. This works
# because `gpu-screen-recorder` is genuinely not installed on the machines this
# runs on — if it ever is, run 3 measures nothing and should be skipped rather
# than trusted.
WFONLY="$NESTED_WORK/bin-wf"
mkdir -p "$WFONLY"
cp "$FAKEBIN/wf-recorder" "$WFONLY/wf-recorder"

if command -v gpu-screen-recorder > /dev/null; then
    nested_note "gpu-screen-recorder is installed here — skipping the absent-encoder run"
    nested_down
fi

: > "$ARGV_LOG"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state"
            "PATH=$WFONLY:$PATH" "FAKE_ARGV_LOG=$ARGV_LOG")

nested_shell shell.qml 'recorder armed' || exit 1

# The missing-binary case has no exit code to read at all (#40): the probe's
# `started` never fires and that is the whole signal.
expect_since 0 'recorder: gpu-screen-recorder is not installed' \
    'a missing encoder is detected without an exit code to read'
expect_reply "$(ipc using)" 'wf-recorder' \
    'auto picks the only encoder that is installed'

mark=$(log_lines)
ipc start > /dev/null
expect_since "$mark" 'recorder: recording the whole screen with wf-recorder to ' \
    'a machine with only the fallback records with it directly, no failed hop'
refute_since "$mark" 'recorder: gpu-screen-recorder' \
    'the absent encoder is not spawned just to watch it fail'
ipc stop > /dev/null

keep_log 3
nested_down
