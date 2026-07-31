#!/usr/bin/env python3
"""Measure the two claims the eye can argue about, from the captured frames.

  1. "near-flush with the wallpaper" — luminance delta between the bar band and
     the wallpaper immediately below it, per wallpaper.
  2. fog-band legibility — WCAG contrast of text-secondary against whatever the
     blurred band actually resolves to under each module cluster.

    ./measure.py <raw-shot-dir>
"""

import sys
from pathlib import Path

from PIL import Image

SCALE = 3          # capture is 3x logical px (1.5 display scale * 2 oversample)
BAR_H = 32         # logical bar height in the captured frames
TEXT_SECONDARY = (0xa9, 0xb8, 0xb0)


def rel_luminance(rgb):
    def chan(c):
        c /= 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (chan(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = rel_luminance(a), rel_luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def mean_rgb(img, box):
    crop = img.crop(box).convert("RGB")
    px = list(crop.getdata())
    n = len(px)
    return tuple(sum(c[i] for c in px) // n for i in range(3))


def main():
    raw = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/forest-bar-shots/raw")

    print("## Flushness — bar vs the wallpaper directly below it\n")
    print("| frame | bar L | wallpaper L | ΔL | contrast |")
    print("|---|---|---|---|---|")
    for name in ["w0", "w1", "w2", "w3", "w4", "w5"]:
        p = raw / f"{name}.png"
        if not p.exists():
            continue
        img = Image.open(p)
        w = img.width
        bar = mean_rgb(img, (0, 0, w, BAR_H * SCALE))
        below = mean_rgb(img, (0, BAR_H * SCALE, w, (BAR_H + 60) * SCALE))
        lb, lw = rel_luminance(bar), rel_luminance(below)
        print(f"| {name} | {lb:.3f} | {lw:.3f} | {abs(lb - lw):.3f} | {contrast(bar, below):.2f}:1 |")

    print("\n## Fog-band legibility — text-secondary over the band it sits on\n")
    print("| frame | region | band RGB | contrast vs #a9b8b0 | AA body (4.5:1) |")
    print("|---|---|---|---|---|")
    # Sample bands under the three clusters, avoiding the glyphs themselves by
    # taking the 4 logical px strip along the bar's top edge.
    regions = {"left": (0.02, 0.18), "centre": (0.40, 0.56), "right": (0.72, 0.98)}
    for name in ["e-flush", "e-translucent", "e-fog", "e-fog-light"]:
        p = raw / f"{name}.png"
        if not p.exists():
            continue
        img = Image.open(p)
        w = img.width
        for label, (x0, x1) in regions.items():
            box = (int(w * x0), 2 * SCALE, int(w * x1), 6 * SCALE)
            band = mean_rgb(img, box)
            c = contrast(band, TEXT_SECONDARY)
            print(f"| {name} | {label} | #{band[0]:02x}{band[1]:02x}{band[2]:02x} | "
                  f"{c:.2f}:1 | {'yes' if c >= 4.5 else 'NO'} |")


if __name__ == "__main__":
    main()
