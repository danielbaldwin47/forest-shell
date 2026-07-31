#!/usr/bin/env python3
"""Measure the contrast numbers quoted in findings.md §3.

The question this answers is whether the compositor's blur is load-bearing for
legibility. It is not: a Gaussian redistributes detail but barely moves the mean
luminance, so the blur-on and blur-off columns come out identical, and the thing
that *does* move is the veil — in the wrong direction.

Backgrounds are sampled from the captures rather than computed, because the
scrim is the wallpaper plus a wash plus noise plus a god ray, and only the
rendered pixels know what that came to.

    ./tools/measure-contrast.py
"""

import subprocess
import sys

# Regions in the 1920x1080 captures. Both are chosen to hold no glyphs, so the
# sample is the background the text is drawn onto.
FOOTER_BG = "500x40+1000+1022"   # empty middle of the footer legend row
CARD_BG = "120x14+700+660"       # empty card interior below the last row

TEXT_MUTED = (0x7D, 0x8F, 0x86)
TEXT_SECONDARY = (0xA9, 0xB8, 0xB0)
LEGEND_ALPHA = 0.60              # what Clearing.qml draws the legend at


def srgb_to_linear(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = (srgb_to_linear(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def over(fg, bg, alpha):
    return tuple(round(alpha * fg[i] + (1 - alpha) * bg[i]) for i in range(3))


def sample(path, region):
    fmt = "%[fx:int(255*u.r+0.5)] %[fx:int(255*u.g+0.5)] %[fx:int(255*u.b+0.5)]"
    out = subprocess.run(
        ["magick", path, "-crop", region, "+repage",
         "-colorspace", "sRGB", "-resize", "1x1!", "-format", fmt, "info:"],
        capture_output=True, text=True, check=True).stdout
    return tuple(int(x) for x in out.split())


SCENES = [
    ("busy  blur on   veil 0.10", "shots/40-chosen-busy.jpg"),
    ("busy  blur off  veil 0.10", "shots/41-chosen-busy-blur-off.jpg"),
    ("busy  blur off  veil 0.18", "shots/42-chosen-busy-blur-off-veil18.jpg"),
    ("busy  blur off  veil 0.26", "shots/43-chosen-busy-blur-off-veil26.jpg"),
    ("ridge blur on   veil 0.10", "shots/38-chosen-query.jpg"),
    ("ridge blur off  veil 0.10", "shots/39-chosen-blur-off.jpg"),
]


def main():
    print(f"{'scene':27} {'card: muted':>12} {'footer: muted@.60':>18} "
          f"{'footer: secondary':>18}")
    for label, path in SCENES:
        try:
            card = sample(path, CARD_BG)
            footer = sample(path, FOOTER_BG)
        except (subprocess.CalledProcessError, FileNotFoundError):
            print(f"{label:27}  (missing {path})")
            continue
        print(f"{label:27} "
              f"{contrast(TEXT_MUTED, card):>11.2f}:1 "
              f"{contrast(over(TEXT_MUTED, footer, LEGEND_ALPHA), footer):>17.2f}:1 "
              f"{contrast(TEXT_SECONDARY, footer):>17.2f}:1")
    print("\n4.5:1 is the target for text this size. The card clears it and does not "
          "care about blur;\nthe footer legend fails in its current role and is fixed by "
          "the role, not by the scrim.")


if __name__ == "__main__":
    sys.exit(main())
