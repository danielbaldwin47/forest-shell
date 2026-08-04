#!/usr/bin/env python3
"""Unit tests for tools/idle-rungs.py — the #176 decision.

The tool answers "did this window measure the idle shell, or did it measure the
idle ladder" from a log and two numbers. What it must not do is miss a rung the
window walked into — that is #152's 45 frames read as a repaint regression — or
invent one the window never reached, which would void a run that was fine.
Both are checkable without a session: the input is text the shell writes and
the output is arithmetic on it.

    tests/tst_idle_rungs.py        # part of tests/run.sh

Stdlib only, same rule as the tool: this runs inside a gate.
"""

import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TOOL = REPO / "tools" / "idle-rungs.py"

_spec = importlib.util.spec_from_file_location("idle_rungs", TOOL)
idle_rungs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(idle_rungs)

failures = []


def check(name, condition, detail=""):
    if condition:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        failures.append(name)


# A log the way the shell writes one: an elapsed stamp, the tag, the message,
# and colour on the stamp because a terminal was attached when it was kept.
BATTERY = "\x1b[90m  +212ms\x1b[0m idle: ladder on battery: dim 150s, lock 300s, dpms 360s, suspend 900s"
MAINS = "  +9412ms idle: ladder on ac: dim 300s, lock 600s, dpms 720s, suspend off (no timeout on ac)"


def test_parse_ladder():
    power, armed, off = idle_rungs.parse_ladder([
        "  +180ms startup: stage services",
        BATTERY,
    ])
    check("ladder line names the power state", power == "battery", repr(power))
    check("ladder line carries every armed rung",
          armed == [("dim", 150), ("lock", 300), ("dpms", 360), ("suspend", 900)],
          repr(armed))
    check("nothing is off on battery", off == [], repr(off))


def test_parse_ladder_off_rungs():
    _, armed, off = idle_rungs.parse_ladder([MAINS])
    check("a rung that is off is not armed",
          [name for name, _ in armed] == ["dim", "lock", "dpms"], repr(armed))
    check("a rung that is off keeps its reason",
          off == [("suspend", "no timeout on ac")], repr(off))


def test_last_ladder_line_wins():
    # Plugging the mains in rearms the whole ladder; the window was measured
    # under the one in force at the end.
    power, armed, _ = idle_rungs.parse_ladder([BATTERY, "  +900ms idle: dim disarmed (keep awake)", MAINS])
    check("the last ladder line is the one in force", power == "ac", repr(power))
    check("the last ladder line's timeouts are the ones used",
          armed[0] == ("dim", 300), repr(armed[:1]))


def test_no_ladder_line():
    power, armed, off = idle_rungs.parse_ladder(["  +180ms bar: content ready on eDP-1"])
    check("a log without a ladder line guesses nothing",
          (power, armed, off) == (None, [], []), repr((power, armed, off)))


def test_classify_default_window_on_battery():
    _, armed, _ = idle_rungs.parse_ladder([BATTERY])
    before, crossed, beyond = idle_rungs.classify(armed, lead=14, window=195)
    check("the default window on battery reaches dim",
          crossed == [("dim", 150)], repr(crossed))
    check("and reaches nothing above it",
          [name for name, _ in beyond] == ["lock", "dpms", "suspend"], repr(beyond))
    check("and nothing fired before it opened", before == [], repr(before))


def test_classify_default_window_on_mains():
    _, armed, _ = idle_rungs.parse_ladder([MAINS])
    _, crossed, _ = idle_rungs.classify(armed, lead=14, window=195)
    check("the same window on mains reaches no rung at all", crossed == [], repr(crossed))


def test_classify_longer_window_reaches_further():
    _, armed, _ = idle_rungs.parse_ladder([BATTERY])
    _, crossed, _ = idle_rungs.classify(armed, lead=14, window=360)
    check("a 360s window on battery reaches lock and dpms",
          [name for name, _ in crossed] == ["dim", "lock", "dpms"], repr(crossed))


def test_classify_counts_idle_time_not_window_time():
    # The rung fires on the idle clock, which was already running when the
    # window opened: dim at 150s is behind a 160s lead, not 10s into the window.
    _, armed, _ = idle_rungs.parse_ladder([BATTERY])
    before, crossed, _ = idle_rungs.classify(armed, lead=160, window=195)
    check("a rung behind the lead fired before the window", before == [("dim", 150)], repr(before))
    # 160 + 195 = 355, so lock at 300 is in and dpms at 360 misses by five
    # seconds — the same window that reaches only dim from a cold start.
    check("and the window reaches the one the lead pushed into it",
          [name for name, _ in crossed] == ["lock"], repr(crossed))


def test_classify_boundaries():
    armed = [("dim", 150), ("lock", 300)]
    _, crossed, _ = idle_rungs.classify(armed, lead=150, window=150)
    check("a rung at the window's first instant is in it",
          ("dim", 150) in crossed, repr(crossed))
    check("a rung at its last instant is in it too",
          ("lock", 300) in crossed, repr(crossed))


def test_fired_reads_the_witness():
    got = idle_rungs.fired([
        "  +212ms idle: dim armed at 150s",
        "\x1b[90m+151.7s\x1b[0m idle: idle: dim — backlight 60 → 10%",
        "+165.2s idle: activity: dim — backlight back to 60%",
    ])
    check("a rung that fired is read off the log", got == ["dim"], repr(got))


def test_fired_ignores_arming_and_waking():
    got = idle_rungs.fired([
        "  +212ms idle: lock armed at 300s",
        "  +900ms idle: dpms disarmed (keep awake)",
        "+165.2s idle: activity: dpms — screen on (input)",
        "  +920ms idle: suspend held off — audio is playing",
    ])
    check("arming, disarming, waking and blocking are not firing", got == [], repr(got))


def test_fired_deduplicates():
    got = idle_rungs.fired([
        "+151.7s idle: idle: dim — backlight 60 → 10%",
        "+165.2s idle: activity: dim — backlight back to 60%",
        "+320.9s idle: idle: dim — backlight 60 → 10%",
        "+361.0s idle: idle: dpms — screen off",
    ])
    check("a rung that fired twice is named once", got == ["dim", "dpms"], repr(got))


def run_tool(lines, *args):
    with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as handle:
        handle.write("\n".join(lines) + "\n")
        path = handle.name
    try:
        result = subprocess.run([sys.executable, str(TOOL), path, *args],
                                capture_output=True, text=True, check=False)
        fields = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
        return result, fields
    finally:
        Path(path).unlink(missing_ok=True)


def test_cli_reports_every_field():
    result, fields = run_tool(
        [BATTERY, "+151.7s idle: idle: dim — backlight 60 → 10%"],
        "--window", "195", "--lead", "14")
    check("the tool exits 0", result.returncode == 0, result.stderr.strip())
    check("the tool reports the power state", fields.get("power") == "battery", repr(fields))
    check("the tool reports the crossed rung", fields.get("crossed") == "dim:150", repr(fields))
    check("the tool reports the fired rung", fields.get("fired") == "dim", repr(fields))


def test_cli_from_line_excludes_earlier_firings():
    lines = [
        BATTERY,
        "+151.7s idle: idle: dim — backlight 60 → 10%",
        "+160.0s idle: activity: dim — backlight back to 60%",
        "+161.0s bar: content ready on eDP-1",
    ]
    _, fields = run_tool(lines, "--window", "195", "--lead", "14", "--from-line", "3")
    check("a rung that fired before the window is not counted as fired in it",
          fields.get("fired") == "", repr(fields))
    check("but it is still predicted as reachable",
          fields.get("crossed") == "dim:150", repr(fields))


def test_cli_survives_a_missing_log():
    result = subprocess.run(
        [sys.executable, str(TOOL), "/nonexistent/forest-idle.log", "--window", "195"],
        capture_output=True, text=True, check=False)
    fields = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    check("a missing log is unknown rather than fatal",
          result.returncode == 0 and fields.get("power") == "unknown", result.stdout)


def main():
    for name, test in sorted(globals().items()):
        if name.startswith("test_") and callable(test):
            test()
    if failures:
        print(f"{len(failures)} check(s) failed")
        return 1
    print("idle-rungs: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
