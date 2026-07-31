#!/usr/bin/env python3
"""Normalize the Lucide icons this prototype uses, per issue #19's resolution.

Two build-time rewrites, and only two:

    stroke-width="2"           -> stroke-width="1.5"   (design system spec, #8)
    stroke|fill="currentColor" -> "#ffffff"            (Qt never resolves
                                                        currentColor; white is
                                                        the neutral base that
                                                        MultiEffect colorizes)

    ./tools/normalize-icons.py <src-dir> <out-dir> <name> [<name> ...]
"""

import re
import sys
from pathlib import Path

CURRENT_COLOR = re.compile(r'(stroke|fill)="currentColor"')
STROKE_WIDTH = re.compile(r'stroke-width="[^"]*"')


def normalize(text: str) -> str:
    text = CURRENT_COLOR.sub(r'\1="#ffffff"', text)
    return STROKE_WIDTH.sub('stroke-width="1.5"', text)


def main():
    src, out, *names = sys.argv[1:]
    src, out = Path(src), Path(out)
    out.mkdir(parents=True, exist_ok=True)
    missing = []
    for name in names:
        f = src / f"{name}.svg"
        if not f.exists():
            missing.append(name)
            continue
        (out / f.name).write_text(normalize(f.read_text()))
    print(f"{len(names) - len(missing)} icons -> {out}")
    if missing:
        sys.exit(f"missing from the vendored set: {', '.join(missing)}")


if __name__ == "__main__":
    main()
