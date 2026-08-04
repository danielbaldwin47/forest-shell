#!/usr/bin/env python3
"""What the idle ladder did to a measured window (#176).

`tools/idle-budget.sh` measures 195 s while the machine is left strictly alone,
which is the same condition the idle ladder is waiting for: `system.idle.dim`
fires at 2.5 min (150 s) on battery and 5 min on mains, so the default window
straddles a rung on battery and does not on AC. #152 walked into exactly that —
45 frames against a budget of 10, 39 of them the screen dimming at 151.7 s and
the OSD announcing it (#175). Read as a count that is a repaint regression;
read with the ladder next to it, it is a state change the harness measured.

The ladder is not re-derived here. The shell logs it as it arms it
(`Services/System/IdlePolicy.ladderLine`), out of the same settings it obeys, so
the log is the authority for both the power state and each rung's timeout and
the harness cannot disagree with the shell about what was armed. The prediction
below says which rungs the window *could* reach; the `fired=` line says which
ones the shell says actually went off inside it, and that one is a witness
rather than a forecast.

    tools/idle-rungs.py LOG --window 195 --lead 14 --from-line 420

    power=battery
    armed=dim:150,lock:300,dpms:360,suspend:900
    off=
    before=
    crossed=dim:150
    beyond=lock:300,dpms:360,suspend:900
    fired=dim

Stdlib only, and the arithmetic is on this side of the line rather than in the
harness (`tests/tst_idle_rungs.py`) — the `tools/measure-blur.py` split, for the
same reason: only the window needs a real session, the decision does not.
"""

import argparse
import re
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*m")

# `ladder on battery: dim 150s, lock 300s, dpms 360s, suspend off (turned off)`
LADDER = re.compile(r"\bidle:\s+ladder on (battery|ac):\s*(.*)$")
ROW = re.compile(r"^(\w+)\s+(?:(\d+)s|off \((.*)\))$")
# `idle: dim — backlight 60 → 10%`, under the `idle` tag, hence the doubling.
FIRED = re.compile(r"\bidle:\s+idle:\s+(\w+)\b")


def _plain(line):
    return ANSI.sub("", line).rstrip()


def parse_ladder(lines):
    """`(power, armed, off)` from the last ladder line in the log.

    Last rather than first: plugging the mains in rearms the whole ladder and
    writes a new line, and the one in force at the end is the one the window
    was measured under. `armed` is `[(id, seconds)]` in the shell's own order;
    `off` is `[(id, reason)]`, which is worth carrying because "dim never fired"
    has four causes and #81 is what happens when a harness cannot tell them
    apart.

    Returns `(None, [], [])` when the log has no ladder line at all — an older
    shell, or a log that starts after startup. The caller decides what to do
    without one; this does not guess.
    """
    power, armed, off = None, [], []
    for raw in lines:
        match = LADDER.search(_plain(raw))
        if not match:
            continue
        power, armed, off = match.group(1), [], []
        for part in match.group(2).split(", "):
            row = ROW.match(part.strip())
            if not row:
                continue
            if row.group(2) is not None:
                armed.append((row.group(1), int(row.group(2))))
            else:
                off.append((row.group(1), row.group(3)))
    return power, armed, off


def fired(lines):
    """The rungs the log says actually went off, in the order they did.

    Deduplicated, because dim can fire, wake and fire again inside one window
    and the question being answered is which rungs were in it.
    """
    seen = []
    for raw in lines:
        match = FIRED.search(_plain(raw))
        if match and match.group(1) not in seen:
            seen.append(match.group(1))
    return seen


def classify(armed, lead, window):
    """Split the armed rungs by where their timeout falls in the idle clock.

    A rung fires `seconds` after the last input, so the comparison is against
    idle time and not against time inside the window: the window covers idle
    time `lead` to `lead + window`, `lead` being how long the harness had
    already been leaving the machine alone by the time it opened — launch plus
    settle.

    `lead` is measured from the harness's own start, which assumes the last
    input was someone running it. If the session was already idle before that,
    the real lead is larger and every rung sits earlier in the window than this
    says — so a `crossed` rung may in fact have fired before the window opened,
    and a `beyond` one may have fired inside it. That is the whole reason
    `fired()` exists: the prediction is what the run can say in advance, the log
    is what actually happened.
    """
    before, crossed, beyond = [], [], []
    for rung in armed:
        seconds = rung[1]
        if seconds < lead:
            before.append(rung)
        elif seconds <= lead + window:
            crossed.append(rung)
        else:
            beyond.append(rung)
    return before, crossed, beyond


def _rungs(rows):
    return ",".join(f"{name}:{value}" for name, value in rows)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="which idle rungs a measured window reached (#176)",
    )
    parser.add_argument("log", help="the shell log the window was measured from")
    parser.add_argument("--window", type=float, required=True,
                        help="window length in seconds")
    parser.add_argument("--lead", type=float, default=0.0,
                        help="seconds of idle time already spent when the window opened")
    parser.add_argument("--from-line", type=int, default=0,
                        help="only rungs firing after this line of the log count as fired")
    args = parser.parse_args(argv)

    try:
        with open(args.log, errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError as error:
        print(f"idle-rungs: cannot read {args.log}: {error}", file=sys.stderr)
        lines = []

    power, armed, off = parse_ladder(lines)
    before, crossed, beyond = classify(armed, args.lead, args.window)

    print(f"power={power or 'unknown'}")
    print(f"armed={_rungs(armed)}")
    print(f"off={_rungs(off)}")
    print(f"before={_rungs(before)}")
    print(f"crossed={_rungs(crossed)}")
    print(f"beyond={_rungs(beyond)}")
    print(f"fired={','.join(fired(lines[max(0, args.from_line):]))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
