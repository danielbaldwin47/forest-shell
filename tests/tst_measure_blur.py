#!/usr/bin/env python3
"""Unit tests for tools/measure-blur.py — the #97 measurement.

The tool answers "is this surface blurred" from two captures rather than by
eye, so what it must not do is say yes when nothing changed, or no when the
detail behind the surface has collapsed. Both are checkable without a
compositor: a box blur applied here produces exactly the picture the compositor
is supposed to produce, and an identical pair produces the picture a broken
blur produces.

    tests/tst_measure_blur.py      # part of tests/run.sh

Stdlib only, same rule as the tool: this runs inside a gate.
"""

import importlib.util
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TOOL = REPO / "tools" / "measure-blur.py"

_spec = importlib.util.spec_from_file_location("measure_blur", TOOL)
measure_blur = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(measure_blur)

failures = []


def check(name, condition, detail=""):
    if condition:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        failures.append(name)


def write_png(path, rows):
    """8-bit RGB, filter 0. rows are lists of (r, g, b)."""
    height, width = len(rows), len(rows[0])
    raw = b"".join(bytes([0]) + bytes(c for px in row for c in px) for row in rows)

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    Path(path).write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b""))


def noise_rows(width, height, seed=12345):
    """Deterministic high-frequency grey noise — the wallpaper this measures."""
    state = seed
    rows = []
    for _ in range(height):
        row = []
        for _ in range(width):
            state = (1103515245 * state + 12345) % (1 << 31)
            v = 40 + ((state >> 16) & 0xFF) * 3 // 4   # 40..231, well off both rails
            row.append((v, v, v))
        rows.append(row)
    return rows


def box_blur(rows, radius=6):
    """What the compositor is supposed to do: a low-pass, mean preserved.

    Separable, edges clamped — the point is not to match Hyprland's kernel but
    to be unambiguously a blur.
    """
    height, width = len(rows), len(rows[0])

    def pass_h(src):
        out = []
        for y in range(height):
            row = []
            for x in range(width):
                lo, hi = max(0, x - radius), min(width - 1, x + radius)
                n = hi - lo + 1
                row.append(tuple(sum(src[y][i][c] for i in range(lo, hi + 1)) // n
                                 for c in range(3)))
            out.append(row)
        return out

    def pass_v(src):
        out = []
        for y in range(height):
            lo, hi = max(0, y - radius), min(height - 1, y + radius)
            n = hi - lo + 1
            out.append([tuple(sum(src[j][x][c] for j in range(lo, hi + 1)) // n
                              for c in range(3)) for x in range(width)])
        return out

    return pass_v(pass_h(rows))


def composite(rows, y0, y1, fill=(30, 40, 36), alpha=0.85):
    """A bar-shaped fill over rows y0..y1 — what the shell puts on top."""
    out = [list(row) for row in rows]
    for y in range(y0, y1):
        for x in range(len(out[y])):
            out[y][x] = tuple(round(fill[c] * alpha + out[y][x][c] * (1 - alpha))
                              for c in range(3))
    return out


def run(*args):
    proc = subprocess.run([sys.executable, str(TOOL), *map(str, args)],
                          capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


def main():
    print("tst_measure_blur.py")
    tmp = Path(tempfile.mkdtemp(prefix="blurtest-"))

    W, H = 120, 60
    base = noise_rows(W, H)
    blurred = box_blur(base)

    # The pair the tool is built for, shaped the way a compositor makes it: a
    # layer rule blurs what is *behind that surface only*, so the wallpaper
    # under the bar is low-passed and the wallpaper below it is untouched. A
    # fixture that blurred the whole frame would be a picture no layer rule can
    # produce, and the untouched-region control below would have nothing to say.
    off = composite(base, 0, 20)
    on = composite([blurred[y] if y < 20 else base[y] for y in range(H)], 0, 20)
    write_png(tmp / "off.png", off)
    write_png(tmp / "on.png", on)
    # A blur that never happened: byte-identical captures.
    write_png(tmp / "same.png", off)

    # --- the metric itself -------------------------------------------------
    d_off = measure_blur.detail(off, (0, 0, W, 20))
    d_on = measure_blur.detail(on, (0, 0, W, 20))
    check("blurring collapses local detail",
          d_on < d_off * 0.25, f"off {d_off:.2f}, on {d_on:.2f}")
    check("unblurred detail is worth measuring at all",
          d_off > 2.0, f"off {d_off:.2f}")

    m_off = measure_blur.mean_grey(off, (0, 0, W, 20))
    m_on = measure_blur.mean_grey(on, (0, 0, W, 20))
    check("the fill's mean stays put under blur",
          abs(m_on - m_off) < 1.5, f"off {m_off:.2f}, on {m_on:.2f}")

    # A region the blur did not touch must not read as blurred. Here the strip
    # below the bar, taken from *both* captures of the pair: in a real capture
    # that is bare wallpaper, and it is the control that says the collapse above
    # came from the layer rule and not from the wallpaper having changed between
    # the two shots. Comparing one capture with itself would pass no matter what
    # the tool did, which is the mistake this comment exists to stop.
    d_below_off = measure_blur.detail(off, (0, 30, W, 25))
    d_below_on = measure_blur.detail(on, (0, 30, W, 25))
    check("an untouched region reads as unchanged across the pair",
          abs(d_below_on - d_below_off) < 1e-9,
          f"off {d_below_off:.3f}, on {d_below_on:.3f}")
    check("and the untouched region has detail to lose",
          d_below_off > 2.0, f"{d_below_off:.3f}")

    # --- the CLI -----------------------------------------------------------
    code, out = run(tmp / "off.png", tmp / "on.png", "--region", f"0,0,{W}x20")
    kept_line = [l for l in out.splitlines() if l.startswith("blur:")]
    check("a headline line is printed for the harness to grep",
          len(kept_line) == 1, out.strip()[:120])
    check("the run without a threshold exits 0", code == 0, out.strip()[:120])
    check("the headline states kept detail as a percentage",
          bool(kept_line) and "kept" in kept_line[0] and "%" in kept_line[0],
          kept_line[0] if kept_line else "")

    code, out = run(tmp / "off.png", tmp / "on.png",
                    "--region", f"0,0,{W}x20", "--max-kept", "25")
    check("a real blur passes --max-kept 25", code == 0, out.strip()[:160])

    code, out = run(tmp / "off.png", tmp / "same.png",
                    "--region", f"0,0,{W}x20", "--max-kept", "25")
    check("an unchanged capture fails --max-kept 25", code == 1, out.strip()[:160])
    check("the failure says what it measured",
          "kept" in out, out.strip()[:160])

    code, out = run(tmp / "off.png", tmp / "on.png",
                    "--region", f"0,0,{W}x20", "--max-mean-drift", "1.5")
    check("a blur that preserves the mean passes --max-mean-drift",
          code == 0, out.strip()[:160])

    # A pair whose mean moved is two different pictures, not a blur. Built by
    # brightening the fill in the second shot, which is what a wallpaper change
    # or a stray window between the captures would look like from here.
    write_png(tmp / "brighter.png", composite(blurred, 0, 20, fill=(90, 100, 96)))
    code, out = run(tmp / "off.png", tmp / "brighter.png",
                    "--region", f"0,0,{W}x20", "--max-mean-drift", "1.5")
    check("a pair whose mean moved fails --max-mean-drift", code == 1,
          out.strip()[:160])

    # --min-kept is the other direction: a region the run says was untouched.
    code, out = run(tmp / "off.png", tmp / "same.png",
                    "--region", f"0,30,{W}x25", "--min-kept", "90")
    check("an untouched region passes --min-kept 90", code == 0, out.strip()[:160])

    code, out = run(tmp / "off.png", tmp / "on.png",
                    "--region", f"0,0,{W}x20", "--min-kept", "90")
    check("a blurred region fails --min-kept 90", code == 1, out.strip()[:160])

    code, out = run(tmp / "off.png", tmp / "on.png", "--region", f"0,0,{W}x999")
    check("a region outside the capture is refused", code != 0, out.strip()[:120])

    for f in tmp.iterdir():
        f.unlink()
    tmp.rmdir()

    if failures:
        print(f"{len(failures)} check(s) failed")
        return 1
    print("measure-blur: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
