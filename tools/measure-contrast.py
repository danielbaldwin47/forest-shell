#!/usr/bin/env python3
"""Contrast of a text colour against a rendered region of a PNG capture.

This is the #79 measurement, made repeatable: sample the strip the bar
occupies out of a capture, and report the worst-case WCAG contrast ratio of
the authored text colour against what was actually composited there — both
the single worst pixel and the worst N-px-wide window, which is what a run of
text actually sits on.

    tools/measure-contrast.py shot.png --text-color a9b8b0 \
        --region 0,1,1280x30 --window 100 [--min-ratio 4.5]

Exit 0 normally; with --min-ratio, exit 1 if the worst window fails it.

Pure stdlib, including the PNG decode (8-bit RGB/RGBA, all five scanline
filters) — same reasoning as tools/make-noise.py: the alternative is a Pillow
dependency for a page of struct unpacking.
"""

import argparse
import struct
import sys
import zlib


def decode_png(path):
    """-> (width, height, rows) with rows as flat RGB tuples per pixel."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"not a PNG: {path}")
    width = height = bitdepth = colortype = None
    idat = b""
    off = 8
    while off < len(data):
        length, ctype = struct.unpack(">I4s", data[off:off + 8])
        chunk = data[off + 8:off + 8 + length]
        if ctype == b"IHDR":
            width, height, bitdepth, colortype = struct.unpack(">IIBB", chunk[:10])
            if chunk[10] != 0 or chunk[12] != 0:
                sys.exit("unsupported PNG: non-default compression/interlace")
        elif ctype == b"IDAT":
            idat += chunk
        off += 12 + length
    if bitdepth != 8 or colortype not in (2, 6):
        sys.exit(f"unsupported PNG: bit depth {bitdepth}, colour type {colortype} "
                 "(need 8-bit RGB or RGBA)")
    bpp = 3 if colortype == 2 else 4
    raw = zlib.decompress(idat)
    stride = width * bpp
    rows = []
    prev = bytearray(stride)
    pos = 0
    for _ in range(height):
        filt = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if filt == 1:    # Sub
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif filt == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif filt == 3:  # Average
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif filt == 4:  # Paeth
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif filt != 0:
            sys.exit(f"unsupported PNG filter {filt}")
        prev = line
        rows.append([tuple(line[x * bpp:x * bpp + 3]) for x in range(width)])
    return width, height, rows


def linearize(channel):
    c = channel / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = (linearize(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(l1, l2):
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def parse_region(spec, width, height):
    try:
        pos, size = spec.split(" ") if " " in spec else spec.rsplit(",", 1)
        x, y = (int(v) for v in pos.split(",")[:2])
        w, h = (int(v) for v in size.split("x"))
    except ValueError:
        sys.exit(f"bad --region {spec!r}: want X,Y,WxH")
    if x < 0 or y < 0 or x + w > width or y + h > height:
        sys.exit(f"--region {spec!r} outside the {width}x{height} capture")
    return x, y, w, h


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("png")
    ap.add_argument("--text-color", required=True, metavar="RRGGBB")
    ap.add_argument("--region", required=True, metavar="X,Y,WxH")
    ap.add_argument("--window", type=int, default=100,
                    help="width in px of the sliding worst-window (default 100)")
    ap.add_argument("--min-ratio", type=float, default=None,
                    help="fail (exit 1) if the worst window is below this")
    args = ap.parse_args()

    text = tuple(int(args.text_color.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
    text_lum = luminance(text)

    width, height, rows = decode_png(args.png)
    x0, y0, w, h = parse_region(args.region, width, height)

    # Per-column mean luminance in linear space — the window average is a
    # window over these, so the whole scan is one pass.
    col_lum = []
    worst_px = None
    for x in range(x0, x0 + w):
        total = 0.0
        for y in range(y0, y0 + h):
            lum = luminance(rows[y][x])
            total += lum
            ratio = contrast(text_lum, lum)
            if worst_px is None or ratio < worst_px:
                worst_px = ratio
        col_lum.append(total / h)

    win = min(args.window, w)
    running = sum(col_lum[:win])
    worst_win = contrast(text_lum, running / win)
    for i in range(win, w):
        running += col_lum[i] - col_lum[i - win]
        worst_win = min(worst_win, contrast(text_lum, running / win))

    print(f"region {x0},{y0} {w}x{h} vs #{args.text_color.lstrip('#')}: "
          f"worst pixel {worst_px:.2f}:1, worst {win}px window {worst_win:.2f}:1")

    if args.min_ratio is not None and worst_win < args.min_ratio:
        print(f"FAIL: worst window {worst_win:.2f}:1 is below {args.min_ratio}:1")
        sys.exit(1)


if __name__ == "__main__":
    main()
