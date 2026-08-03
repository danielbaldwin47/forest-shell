#!/usr/bin/env python3
"""Turn a QSG_RENDER_TIMING log into the frame budget's four numbers (#22 §6).

    tools/measure-frame-timing.py run.log --budget-ms 8 --min-frames 100
    tail -n +900 run.log | tools/measure-frame-timing.py

Qt's scenegraph prints one `frame rendered in Nms, sync=, render=, swap=` line
per presented frame per window when QSG_RENDER_TIMING=1 is set, and one
`elapsed since last call` line per frame with the wall gap since the previous
one. Those are the only two facts here; everything below is arithmetic over
them.

**The gate reads `render`.** #73 measured a toast where 40 of 59 frames looked
like they blew the 8 ms budget and every millisecond of it was `swap` — the
render thread blocking on the Wayland frame callback at 16.7 ms, which is the
compositor pacing the shell rather than the shell being slow. Gating on total
would condemn a shell doing 0.5 ms of work. The report prints all three so the
split stays visible; only render decides.

Stdlib only: this runs inside a gate, on whatever machine has the session.
"""

import argparse
import math
import re
import sys

# The window and thread pointers vary per line and the log is ANSI-coloured
# (the harnesses set QT_ASSUME_STDERR_HAS_CONSOLE=1, or Qt prints nothing into
# a pipe at all), so both patterns anchor on the scenegraph's own wording and
# ignore everything to the left of it.
FRAME_RE = re.compile(
    r"frame rendered in (\d+)ms, sync=(\d+), render=(\d+), swap=(\d+)"
)
GAP_RE = re.compile(r"syncAndRender: start, elapsed since last call: (\d+) ms")

# A gap this long is a dropped frame at 60 Hz — 20 ms is #73's own threshold,
# one frame's slack over the 16.7 ms callback.
GAP_BUDGET_MS = 20


def percentile(values, fraction):
    """Nearest-rank, deliberately: with 120 frames at 0 ms and one at 12 ms,
    an interpolated p95 invents a number that no frame took."""
    if not values:
        return 0
    ordered = sorted(values)
    rank = max(1, math.ceil(fraction * len(ordered)))
    return ordered[rank - 1]


def series(name, values, budget_ms):
    over = sum(1 for v in values if v > budget_ms)
    mean = sum(values) / len(values) if values else 0.0
    return "%-7s max=%d mean=%.2f p95=%d over=%d/%d" % (
        name,
        max(values, default=0),
        mean,
        percentile(values, 0.95),
        over,
        len(values),
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", nargs="?", help="QSG_RENDER_TIMING log (default: stdin)")
    parser.add_argument("--budget-ms", type=int, default=8,
                        help="the #22 §6 GPU budget, read against render (default: 8)")
    parser.add_argument("--min-frames", type=int, default=0,
                        help="fail if the run collected fewer frames than this")
    parser.add_argument("--from-line", type=int, default=0,
                        help="skip this many leading lines (startup is not interaction)")
    parser.add_argument("--list-gaps", type=int, metavar="MS",
                        help="also list every gap at or over MS, in seconds — #22 §5 "
                             "is judged on when the repaints fell, not just how many")
    args = parser.parse_args()

    if args.log:
        with open(args.log, "r", errors="replace") as handle:
            lines = handle.readlines()
    else:
        lines = sys.stdin.read().splitlines()
    lines = lines[args.from_line:]

    totals, renders, swaps, gaps = [], [], [], []
    for line in lines:
        frame = FRAME_RE.search(line)
        if frame:
            total, _sync, render, swap = (int(g) for g in frame.groups())
            totals.append(total)
            renders.append(render)
            swaps.append(swap)
            continue
        gap = GAP_RE.search(line)
        if gap:
            gaps.append(int(gap.group(1)))

    print("frames  %d" % len(totals))
    if totals:
        print(series("total", totals, args.budget_ms))
        print(series("render", renders, args.budget_ms))
        print(series("swap", swaps, args.budget_ms))
    if gaps:
        # fps off the p50 gap, not the mean: a run that drives an interaction,
        # waits, and drives another has idle stretches between the animations.
        # They are not dropped frames, and a mean would read them as a frame
        # rate collapse. The dropped-frame question is answered by the
        # over-20ms count next to it instead. p50 rather than "median" because
        # this is nearest-rank on an even count too — no averaging of the two
        # middle samples, so every number printed is a gap that happened.
        p50 = percentile(gaps, 0.5)
        fps = 1000.0 / p50 if p50 else 0.0
        over = sum(1 for g in gaps if g > GAP_BUDGET_MS)
        print("pacing  fps=%.1f p50-gap=%dms max-gap=%dms over-%dms=%d/%d"
              % (fps, p50, max(gaps), GAP_BUDGET_MS, over, len(gaps)))
        if args.list_gaps is not None:
            # #22 §5 is "one repaint a minute, on the minute", and #73 proved it
            # with the list rather than the count: [59999, 59999, 60000, …] says
            # *the clock* in a way "6 frames" does not. Sub-threshold gaps are
            # the second window rendering alongside the first, not a repaint.
            listed = [g for g in gaps if g >= args.list_gaps]
            print("gaps    %s" % ", ".join("%.1fs" % (g / 1000.0) for g in listed))

    if not totals:
        print("no frames in the log — the shell rendered nothing, or "
              "QSG_RENDER_TIMING was not set", file=sys.stderr)
        return 1
    if len(totals) < args.min_frames:
        # Exit 2, not 1: this run did not measure the criterion, which is a
        # different thing from measuring it and finding it blown. Same third
        # verdict tools/idle-budget.sh uses for a window that was not idle.
        print("only %d frames, wanted %d — the interaction did not drive the "
              "shell, so the budget is unmeasured rather than met"
              % (len(totals), args.min_frames), file=sys.stderr)
        return 2
    worst_render = max(renders)
    if worst_render > args.budget_ms:
        print("render peaked at %dms, over the %dms budget"
              % (worst_render, args.budget_ms), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
