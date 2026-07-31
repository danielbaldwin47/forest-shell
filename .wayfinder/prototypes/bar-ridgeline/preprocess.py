#!/usr/bin/env python3
"""Normalize pristine Lucide SVGs for forest-shell (issue #19).

Two rewrites, and only two — they are separable and only one of them belongs
at build time:

  stroke-width="2"        -> stroke-width="1.5"   (design system spec, #8)
  stroke/fill="currentColor" -> "#ffffff"          (Qt's SVG renderer does not
                                                    resolve currentColor; white
                                                    is the neutral base that
                                                    MultiEffect colorizes)

The colour is NOT baked to a palette token: white + MultiEffect colorization is
pixel-identical to a baked-colour file, and stays dynamic.

  ./preprocess.py <src-dir> <out-dir> [--all]

Without --all, only the demo subset is written.
"""

import re
import sys
from pathlib import Path

DEMO = [
    "wifi", "wifi-off", "battery-medium", "battery-full", "volume-2", "volume-x",
    "bell", "bell-off", "settings", "search", "sun", "moon", "cloud-fog",
    "mountain-snow", "cpu", "bluetooth", "monitor", "keyboard", "calendar",
    "play", "pause", "skip-forward", "power", "lock", "tag", "palette",
]

CURRENT_COLOR = re.compile(r'(stroke|fill)="currentColor"')
STROKE_WIDTH = re.compile(r'stroke-width="[^"]*"')


def normalize(text: str) -> str:
    text = CURRENT_COLOR.sub(r'\1="#ffffff"', text)
    return STROKE_WIDTH.sub('stroke-width="1.5"', text)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    src = Path(args[0] if args else "assets/icons/lucide")
    out = Path(args[1] if len(args) > 1 else ".wayfinder/prototypes/icon-rendering/gen/normalized")
    every = "--all" in sys.argv

    out.mkdir(parents=True, exist_ok=True)
    names = sorted(p.stem for p in src.glob("*.svg")) if every else DEMO

    written = 0
    for name in names:
        path = src / f"{name}.svg"
        if not path.exists():
            print(f"missing: {path}", file=sys.stderr)
            continue
        (out / f"{name}.svg").write_text(normalize(path.read_text()))
        written += 1

    print(f"normalized {written} icons -> {out}")


if __name__ == "__main__":
    main()
