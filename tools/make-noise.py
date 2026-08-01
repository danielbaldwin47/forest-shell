#!/usr/bin/env python3
"""Generate the tiling grain texture the bar surface is dusted with (#8 §3.5, #35).

The brief asks for 2-4% monochrome noise over flat fills, and it is not
decoration: the bar's top-edge lightening is a very small luminance change
spread over 32 logical px, which is exactly the shape that bands visibly on an
8-bit panel. Noise breaks the bands into dither.

Why a checked-in PNG rather than a shader: Qt 6 compiles shaders ahead of time
with `qsb`, so a procedural grain would put a build step between cloning the
repo and running the shell — which #12 §1 rules out for the whole project. A
64x64 tile costs 4 KB and one small texture for a bar of any width.

Deterministic: same seed, same bytes, on any machine and any Python. So the
asset is checkable rather than merely regenerable, and a diff on it means
someone changed the recipe.

    tools/make-noise.py            (re)generate assets/noise.png
    tools/make-noise.py --check    verify the checked-in file, write nothing

The PNG is written by hand — 8-bit greyscale, one IDAT, no filtering — because
the alternative is a Pillow dependency for 40 lines of struct packing.
"""

import argparse
import struct
import sys
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_OUT = REPO / "assets" / "noise.png"

SIZE = 64
SEED = 0x5EED_F0E5  # "seed forest", near enough

# Linear congruential generator, glibc's constants. Written out rather than
# taken from `random` so the bytes do not depend on a Python version's idea of
# what Mersenne Twister seeding means.
LCG_A = 1103515245
LCG_C = 12345
LCG_M = 1 << 31


def noise_rows(size: int, seed: int) -> list[bytes]:
    """One row per scanline, each already carrying its PNG filter byte."""
    state = seed % LCG_M
    rows = []
    for _ in range(size):
        row = bytearray([0])  # filter type 0: none
        for _ in range(size):
            state = (LCG_A * state + LCG_C) % LCG_M
            # Bits 16-23: the low bits of an LCG are notoriously non-random,
            # and this is the one place that would show.
            row.append((state >> 16) & 0xFF)
        rows.append(bytes(row))
    return rows


def chunk(tag: bytes, payload: bytes) -> bytes:
    return (struct.pack(">I", len(payload)) + tag + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))


def png(size: int, seed: int) -> bytes:
    raw = b"".join(noise_rows(size, seed))
    header = struct.pack(">IIBBBBB", size, size, 8, 0, 0, 0, 0)  # 8-bit greyscale
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def pixels_of(data: bytes) -> bytes:
    """The filtered scanlines back out of a PNG we wrote ourselves.

    The check compares *pixels* and not file bytes on purpose: the pixels are
    the thing the recipe defines, while the exact deflate stream is whatever the
    local zlib felt like emitting. Comparing bytes would fail on a machine whose
    zlib packs differently, which is a false alarm about nothing.
    """
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("not a PNG")
    payloads = []
    offset = 8
    while offset < len(data):
        length, tag = struct.unpack(">I4s", data[offset:offset + 8])
        if tag == b"IDAT":
            payloads.append(data[offset + 8:offset + 8 + length])
        offset += 12 + length
    return zlib.decompress(b"".join(payloads))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--check", action="store_true",
                        help="verify the file matches the recipe; exit 1 if not")
    args = parser.parse_args()

    expected = png(SIZE, SEED)

    if args.check:
        if not args.output.exists():
            print(f"{args.output} is missing", file=sys.stderr)
            return 1
        try:
            found = pixels_of(args.output.read_bytes())
        except (ValueError, struct.error, zlib.error) as error:
            print(f"{args.output} is not readable as a PNG: {error}", file=sys.stderr)
            return 1
        if found != pixels_of(expected):
            print(f"{args.output} is not what tools/make-noise.py generates",
                  file=sys.stderr)
            return 1
        print(f"grain texture {SIZE}x{SIZE} verified")
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(expected)
    print(f"wrote {args.output} ({SIZE}x{SIZE}, {len(expected)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
