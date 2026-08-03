#!/usr/bin/env python3
"""Whether a surface is actually blurred, from two captures rather than by eye (#97).

#78 settled that Hyprland *accepts* the bar's blur layer rule. It could not
settle that the bar is *blurred*: the compositor's `ok` is a reply, not a
picture, and every other seam in this repo is client-side by construction —
tools/capture-harness.sh renders the shell's own surfaces and never sees what
was composited behind them. This is the arithmetic for the one seam that can:
two screenshots off a real session, blur on and blur off.

The measurement follows from what a blur is. A Gaussian/box blur is a low-pass
filter, so the high-frequency energy of whatever is behind the surface collapses
while its mean survives. Over a high-frequency wallpaper that is a large,
unambiguous signal:

    detail(region) = mean |4·g(x,y) − g(x−1,y) − g(x+1,y) − g(x,y−1) − g(x,y+1)|

a discrete Laplacian on grey g = 0.2126R + 0.7152G + 0.0722B in 8-bit display
space — display space and not linear, because the question is what a viewer can
see rather than what a photon did. `kept` is the blurred capture's detail as a
percentage of the unblurred one's: 100% is a blur that did nothing, and a real
blur over noise lands in the low tens or below.

The mean is reported next to it as the control. A capture that lost its detail
*and* moved its mean is not a blur — it is a different picture (wallpaper
changed, wrong region, a window in the way), and the pair proves nothing.

    tools/measure-blur.py off.png on.png --region 0,0,1920x36 \
        [--max-kept 40] [--min-kept 90] [--max-mean-drift 4] [--label "bar strip"]

Exit 0 normally; 1 if a threshold given on the command line is missed.

Pure stdlib, including the PNG decode, which is borrowed from
tools/measure-contrast.py — same reasoning as tools/make-noise.py: the
alternative is a Pillow dependency for a page of struct unpacking. Anything
inside a gate stays stdlib-only (CLAUDE.md), and this one runs in a harness.
"""

import argparse
import importlib.util
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent


def _sibling(stem):
    """Import a sibling tool whose filename is not a Python identifier."""
    spec = importlib.util.spec_from_file_location(
        stem.replace("-", "_"), _HERE / f"{stem}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_contrast = _sibling("measure-contrast")
decode_png = _contrast.decode_png
parse_region = _contrast.parse_region


def grey(rgb):
    """Rec.709 luma in 8-bit display space."""
    r, g, b = rgb
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def _greyplane(rows, region):
    x, y, w, h = region
    return [[grey(rows[j][i]) for i in range(x, x + w)] for j in range(y, y + h)]


def detail(rows, region):
    """Mean absolute Laplacian over the region — its high-frequency energy.

    Neighbours are taken from the region's own grey plane, so the border ring
    is skipped rather than clamped: clamping invents an edge that reads as
    detail, and on a 36 px strip that ring is a tenth of the sample.
    """
    plane = _greyplane(rows, region)
    h, w = len(plane), len(plane[0])
    if h < 3 or w < 3:
        sys.exit(f"region {region} is too small to measure detail (need 3x3)")
    total = 0.0
    for j in range(1, h - 1):
        row, above, below = plane[j], plane[j - 1], plane[j + 1]
        for i in range(1, w - 1):
            total += abs(4 * row[i] - row[i - 1] - row[i + 1] - above[i] - below[i])
    return total / ((h - 2) * (w - 2))


def mean_grey(rows, region):
    plane = _greyplane(rows, region)
    return sum(sum(row) for row in plane) / (len(plane) * len(plane[0]))


def stddev_grey(rows, region):
    """Spread over the whole region — the coarse companion to `detail`.

    Reported but never gated on: a blur leaves a large-scale gradient alone, so
    stddev falls by much less than the Laplacian does, and how much less depends
    on the wallpaper rather than on whether the blur happened.
    """
    plane = _greyplane(rows, region)
    values = [v for row in plane for v in row]
    mean = sum(values) / len(values)
    return (sum((v - mean) ** 2 for v in values) / len(values)) ** 0.5


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("unblurred", help="capture with the blur off")
    ap.add_argument("blurred", help="capture with the blur on")
    ap.add_argument("--region", required=True, metavar="X,Y,WxH",
                    help="the strip to measure, in capture pixels")
    ap.add_argument("--max-kept", type=float, metavar="PCT",
                    help="fail if the blurred capture keeps this much detail or more")
    ap.add_argument("--min-kept", type=float, metavar="PCT",
                    help="fail if it keeps less than this — for a region that is "
                         "supposed to be untouched, which is what says a pair is a "
                         "clean A/B rather than two different pictures")
    ap.add_argument("--max-mean-drift", type=float, metavar="LEVELS",
                    help="fail if the region's mean grey moved further than this")
    ap.add_argument("--label", default="", help="what this region is, for the report")
    args = ap.parse_args()

    w_off, h_off, rows_off = decode_png(args.unblurred)
    w_on, h_on, rows_on = decode_png(args.blurred)
    if (w_off, h_off) != (w_on, h_on):
        sys.exit(f"captures differ in size: {w_off}x{h_off} vs {w_on}x{h_on} — "
                 "the pair has to be the same screen")

    region = parse_region(args.region, w_off, h_off)
    x, y, w, h = region

    d_off, d_on = detail(rows_off, region), detail(rows_on, region)
    m_off, m_on = mean_grey(rows_off, region), mean_grey(rows_on, region)
    s_off, s_on = stddev_grey(rows_off, region), stddev_grey(rows_on, region)

    kept = 100.0 * d_on / d_off if d_off else float("inf")
    drift = m_on - m_off
    label = f" [{args.label}]" if args.label else ""

    print(f"region {x},{y} {w}x{h}{label}")
    print(f"  detail  off {d_off:7.3f}  on {d_on:7.3f}   kept {kept:5.1f}%")
    print(f"  stddev  off {s_off:7.3f}  on {s_on:7.3f}")
    print(f"  mean    off {m_off:7.3f}  on {m_on:7.3f}   drift {drift:+.3f}")
    print(f"blur: detail kept {kept:.1f}%, mean drift {drift:+.2f}{label}")

    failed = False
    if args.max_kept is not None and kept >= args.max_kept:
        print(f"FAIL kept {kept:.1f}% of the detail, wanted under {args.max_kept:.1f}% "
              "— this pair does not show a blur")
        failed = True
    if args.min_kept is not None and kept < args.min_kept:
        print(f"FAIL kept only {kept:.1f}% of the detail, wanted at least "
              f"{args.min_kept:.1f}% — this region was supposed to be untouched")
        failed = True
    if args.max_mean_drift is not None and abs(drift) > args.max_mean_drift:
        print(f"FAIL the mean moved {drift:+.2f} levels, over {args.max_mean_drift:.2f} "
              "— the two captures are not the same picture")
        failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
