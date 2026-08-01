#!/usr/bin/env python3
"""Normalize the vendored Lucide set for forest-shell (#19, #34).

Two rewrites, and only two:

    stroke-width="2"            -> stroke-width="1.5"   (design system spec, #8)
    stroke|fill="currentColor"  -> "#ffffff"            (Qt's SVG renderer does
                                                         not resolve currentColor
                                                         — it draws opaque black)

The colour is **not** baked to a palette token. White plus
`MultiEffect { colorization: 1.0 }` is pixel-identical to a baked-colour file
(measured in `.wayfinder/prototypes/icon-rendering/findings.md`) and stays
dynamic, so one file per icon serves every role in every mode.

Both rewrites are idempotent, and the set is normalized **in place**: there is
no second directory, no generated sibling, and no transform step between
cloning the repo and running the shell. `tools/vendor-lucide.sh` re-derives the
set from the pinned upstream release, so the pristine originals stay
reproducible without being carried.

    tools/normalize-lucide.py            normalize the vendored set in place
    tools/normalize-lucide.py --check    verify it, touch nothing (exit 1 if not)
    tools/normalize-lucide.py DIR        work on some other directory

`LICENSE` sits in the icon directory and is not an SVG; it is never read,
rewritten or counted.
"""

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_DIR = REPO / "assets" / "icons" / "lucide"

STROKE_WIDTH = "1.5"
BASE_COLOR = "#ffffff"

CURRENT_COLOR = re.compile(r'(stroke|fill)="currentColor"')
STROKE_WIDTH_ATTR = re.compile(r'stroke-width="([^"]*)"')


def normalize(text: str) -> str:
    text = CURRENT_COLOR.sub(rf'\1="{BASE_COLOR}"', text)
    return STROKE_WIDTH_ATTR.sub(f'stroke-width="{STROKE_WIDTH}"', text)


def defects(name: str, text: str) -> list[str]:
    """What is still wrong with one already-normalized file."""
    found = []
    if "currentColor" in text:
        found.append(f"{name}: still carries currentColor")
    widths = set(STROKE_WIDTH_ATTR.findall(text))
    if widths != {STROKE_WIDTH}:
        found.append(f"{name}: stroke-width {sorted(widths) or 'absent'}")
    if f'stroke="{BASE_COLOR}"' not in text:
        found.append(f'{name}: no stroke="{BASE_COLOR}"')
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", type=Path, default=DEFAULT_DIR)
    parser.add_argument("--check", action="store_true",
                        help="verify without writing; exit 1 if the set is not normalized")
    args = parser.parse_args()

    svgs = sorted(args.directory.glob("*.svg"))
    if not svgs:
        print(f"no SVGs in {args.directory}", file=sys.stderr)
        return 1

    if args.check:
        found = []
        for path in svgs:
            found += defects(path.name, path.read_text(encoding="utf-8"))
        if not (args.directory / "LICENSE").exists():
            found.append("LICENSE is missing from the icon set")
        for line in found[:20]:
            print(line, file=sys.stderr)
        if len(found) > 20:
            print(f"... and {len(found) - 20} more", file=sys.stderr)
        if found:
            return 1
        print(f"{len(svgs)} icons normalized (stroke-width {STROKE_WIDTH}, "
              f"stroke {BASE_COLOR})")
        return 0

    changed = 0
    for path in svgs:
        before = path.read_text(encoding="utf-8")
        after = normalize(before)
        if after != before:
            path.write_text(after, encoding="utf-8", newline="\n")
            changed += 1
    print(f"normalized {changed} of {len(svgs)} icons in {args.directory}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
