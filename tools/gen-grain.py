#!/usr/bin/env python3
"""Generate assets/textures/grain.png — the anti-banding noise tile (#8 §3.5, #35).

    tools/gen-grain.py            regenerate the tile
    tools/gen-grain.py --check    verify the checked-in tile is this tile

The bar surface is a flat fill under a vertical gradient compressed into 32px,
which is exactly the shape that bands on an 8-bit panel. The brief's fix is
2-4% monochrome noise over the top; `Core/Tokens.qml` picks 3%.

The tile is generated rather than vendored because it is a *function*, not
artwork: a fixed-seed uniform noise field, tileable by construction (it is a
plain tile — every edge meets a fresh sample either way, and at 3% opacity no
seam is visible). Keeping the generator means the size, seed and distribution
are readable instead of being a binary someone has to trust.

Pure standard library: zlib for the PNG stream, no Pillow, so the check runs
anywhere `tests/run.sh` does.
"""

from __future__ import annotations

import argparse
import pathlib
import struct
import sys
import zlib

# 64px tiles at 1.5x scale repeat every 96 device px — small enough to stay in
# cache, large enough that the repeat is not a visible weave.
SIZE = 64

# Any fixed value; this one is arbitrary. What matters is that the tile is
# reproducible, so `--check` can tell "regenerated" from "hand-edited".
SEED = 0x5EED_F0_1E5

TILE = pathlib.Path(__file__).resolve().parent.parent / "assets" / "textures" / "grain.png"


def samples(size: int, seed: int) -> bytes:
    """Uniform 8-bit noise, from a spelled-out LCG.

    Not `random`: the point of the checked-in tile is that anyone regenerating
    it gets the same bytes, and the standard library's generator is only
    promised to be stable for `random.random`, not for whatever `randbytes`
    does in a future version. Numerical Recipes' constants, high byte taken
    because the low bits of an LCG are the weak ones.
    """
    state = seed & 0xFFFF_FFFF
    out = bytearray(size * size)
    for i in range(size * size):
        state = (1664525 * state + 1013904223) & 0xFFFF_FFFF
        out[i] = (state >> 24) & 0xFF
    return bytes(out)


def encode(size: int, pixels: bytes) -> bytes:
    """An 8-bit greyscale PNG. Every row uses filter 0, which is what `decode`
    below relies on — a filtered row would need the full unfilter machinery for
    no gain on noise, which does not predict from its neighbours anyway."""
    raw = b"".join(b"\x00" + pixels[y * size:(y + 1) * size] for y in range(size))

    def chunk(tag: bytes, payload: bytes) -> bytes:
        body = tag + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 0, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def decode(data: bytes) -> tuple[int, bytes]:
    """(size, pixels) from a PNG this script wrote.

    Compares pixels rather than file bytes on purpose: zlib's exact output is
    not promised to be stable across versions, so a byte comparison would fail
    the check on a machine whose zlib merely compresses differently.
    """
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")

    offset, size, stream = 8, None, bytearray()
    while offset < len(data):
        length, tag = struct.unpack(">I", data[offset:offset + 4])[0], data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        offset += 12 + length
        if tag == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", payload[:10])
            if width != height or depth != 8 or color != 0:
                raise ValueError("not a square 8-bit greyscale tile")
            size = width
        elif tag == b"IDAT":
            stream += payload
        elif tag == b"IEND":
            break

    if size is None:
        raise ValueError("no IHDR")

    raw = zlib.decompress(bytes(stream))
    pixels = bytearray()
    for y in range(size):
        row = raw[y * (size + 1):(y + 1) * (size + 1)]
        if row[0] != 0:
            raise ValueError("unexpected PNG row filter")
        pixels += row[1:]
    return size, bytes(pixels)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="fail if the checked-in tile is not what this script generates")
    args = parser.parse_args()

    expected = samples(SIZE, SEED)

    if args.check:
        if not TILE.exists():
            print(f"{TILE} is missing — run tools/gen-grain.py", file=sys.stderr)
            return 1
        try:
            size, pixels = decode(TILE.read_bytes())
        except ValueError as error:
            print(f"{TILE}: {error}", file=sys.stderr)
            return 1
        if size != SIZE or pixels != expected:
            print(f"{TILE} is not the generated tile — run tools/gen-grain.py", file=sys.stderr)
            return 1
        print(f"grain tile ok ({SIZE}x{SIZE})")
        return 0

    TILE.parent.mkdir(parents=True, exist_ok=True)
    TILE.write_bytes(encode(SIZE, expected))
    print(f"wrote {TILE} ({SIZE}x{SIZE})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
