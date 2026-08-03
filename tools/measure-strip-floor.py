#!/usr/bin/env python3
"""#79's calibration: what fill opacity does each wallpaper actually demand?

This is the offline form of Surfaces/Bar/SurfaceOpacity.qml. It answers two
questions over a whole folder of wallpapers, which is what settled the design:

  truth      For each wallpaper, the lowest `bar.surface.opacity` at which
             text-secondary still clears 4.5:1 over the worst 100px window of
             the strip the bar covers. This is the metric of record —
             tools/measure-contrast.py reports the same figure from a capture.

  estimate   What the *runtime* clamp will pick, given only what
             ColorQuantizer can hand it: the strip rescaled to N cells,
             brightest cell wins. The runtime solves for a target above 4.5:1;
             this reports whether that margin is enough for the truth to clear
             4.5:1 everywhere, which is the only thing the margin is for.

    tools/measure-strip-floor.py ~/Pictures/wallpaper
    tools/measure-strip-floor.py ~/Pictures/wallpaper --sweep      # pick a margin
    tools/measure-strip-floor.py ~/Pictures/wallpaper --screen 3840x2160

Unlike tools/measure-contrast.py this needs Pillow and NumPy. That one is
stdlib-only on purpose because it runs inside the capture gate on any machine;
this one is a calibration that is run when the numbers are being *chosen*, over
a folder of arbitrary JPEGs, and hand-rolling a JPEG decoder to avoid a
dependency for that would be a poor trade.

The band model below has to agree with what Qt Quick actually draws, and the
detail that is easy to get wrong is that item opacity is applied per node, not
to the subtree as a group: the top-light gradient is a child of the translucent
fill, so it composites *over* the wallpaper the fill let through and blocks some
of it. Modelled the other way (lightening the fill's colour before the blend)
the prediction is ~0.5 of a contrast point optimistic at the bottom of the
range. Checked against tools/capture-harness.sh --contrast over a black-to-white
ramp: 6.58/4.80/3.60/2.72:1 measured at 1.0/0.86/0.75/0.65, against
6.47/4.79/3.64/2.81 predicted.
"""

import argparse
import colorsys
import os
import sys

try:
    import numpy as np
    from PIL import Image
except ImportError:
    sys.exit("needs Pillow and NumPy: pip install --user pillow numpy")

# The shipped dark palette and the shipped bar.surface defaults.
TEXT = np.array([0xA9, 0xB8, 0xB0], float)      # textSecondary
SURFACE = np.array([0x14, 0x1B, 0x17], float)
FOG = np.array([0xBE, 0xCE, 0xD1], float)       # fogWash
BORDER = np.array([0x2A, 0x38, 0x30], float)    # borderSubtle
GRAIN_GREY = np.array([130.5] * 3)              # measured mean of assets/noise.png
MIST, GRAIN, TOP_LIGHT_AMOUNT, TOP_LIGHT_STOP = 0.10, 0.03, 0.05, 0.55

TARGET = 4.5        # the body-text floor (#10, #68)
WINDOW = 100        # px of screen a run of text sits on
CELLS = 64          # what the runtime quantizer resolves the strip to
MARGIN = 0.6        # what the runtime aims above TARGET; --sweep is how it was picked


def luminance(rgb):
    c = np.asarray(rgb, float) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return lin[..., 0] * 0.2126 + lin[..., 1] * 0.7152 + lin[..., 2] * 0.0722


TEXT_LUM = luminance(TEXT)


def contrast(lum):
    return (np.maximum(TEXT_LUM, lum) + 0.05) / (np.minimum(TEXT_LUM, lum) + 0.05)


def qt_lighter(rgb, factor):
    h, s, v = colorsys.rgb_to_hsv(*(np.asarray(rgb, float) / 255.0))
    return np.array(colorsys.hsv_to_rgb(h, s, min(1.0, v * factor))) * 255.0


LIT = qt_lighter(SURFACE, 1.0 + TOP_LIGHT_AMOUNT * 4)


def band(wallpaper, alpha, rows):
    """(N,3) wallpaper colours -> (rows,N,3) band colours, layer by layer."""
    wallpaper = np.asarray(wallpaper, float)
    out = np.empty((rows,) + wallpaper.shape)
    for y in range(rows):
        c = alpha * SURFACE + (1 - alpha) * wallpaper
        through = ((y + 0.5) / rows) / TOP_LIGHT_STOP
        if through < 1.0:
            a = alpha * (1 - through)
            c = a * LIT + (1 - a) * c
        c = MIST * FOG + (1 - MIST) * c
        c = GRAIN * GRAIN_GREY + (1 - GRAIN) * c
        if y == rows - 1:
            c = np.broadcast_to(BORDER, c.shape).copy()
        out[y] = c
    return out


def worst_window(strip, alpha, window=WINDOW):
    """Worst 100px-window contrast over a (rows, width, 3) strip of wallpaper."""
    rows, width, _ = strip.shape
    per_row = np.stack([luminance(band(strip[y], alpha, rows)[y]) for y in range(rows)])
    columns = per_row.mean(axis=0)
    w = min(window, width)
    smoothed = np.convolve(columns, np.ones(w) / w, mode="valid")
    return float(contrast(smoothed.max()))


def flat_contrast(colour, alpha, rows):
    """Contrast over one flat colour — what the runtime sees for one cell."""
    return float(contrast(luminance(band(np.asarray(colour).reshape(1, 3),
                                         alpha, rows)[:, 0, :]).mean()))


def lowest_passing(measure, target):
    """Least alpha in [0,1] with measure(alpha) >= target, bisected."""
    if measure(0.0) >= target:
        return 0.0
    if measure(1.0) < target:
        return 1.0
    low, high = 0.0, 1.0
    for _ in range(20):
        mid = (low + high) / 2
        if measure(mid) >= target:
            high = mid
        else:
            low = mid
    return high


def bar_strip(path, screen, bar_height):
    """The strip under the bar, at screen resolution, via PreserveAspectCrop."""
    screen_w, screen_h = screen
    image = Image.open(path).convert("RGB")
    iw, ih = image.size
    scale = max(screen_w / iw, screen_h / ih)
    visible_w, visible_h = screen_w / scale, screen_h / scale
    x0, y0 = (iw - visible_w) / 2, (ih - visible_h) / 2
    crop = image.crop((round(x0), round(y0),
                       round(x0 + visible_w), round(y0 + bar_height / scale)))
    return np.asarray(crop.resize((screen_w, bar_height), Image.LANCZOS), float)


def brightest_cell(strip, cells):
    """What ColorQuantizer(rescaleSize=cells, depth>=log2(cells)) reports."""
    small = Image.fromarray(strip.astype(np.uint8)).resize((cells, 1), Image.BOX)
    pixels = np.asarray(small, float)[0]
    return pixels[np.argmax(luminance(pixels))]


def wallpapers(folder):
    out = []
    for name in sorted(os.listdir(folder)):
        if name.lower().endswith((".jpg", ".jpeg", ".png", ".webp", ".bmp")):
            out.append(os.path.join(folder, name))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--screen", default="1920x1080", metavar="WxH")
    ap.add_argument("--bar-height", type=int, default=32)
    ap.add_argument("--cells", type=int, default=CELLS)
    ap.add_argument("--margin", type=float, default=MARGIN)
    ap.add_argument("--sweep", action="store_true",
                    help="try a range of cell counts and margins instead")
    args = ap.parse_args()

    screen = tuple(int(v) for v in args.screen.split("x"))
    rows = args.bar_height

    names, strips = [], []
    for path in wallpapers(args.folder):
        try:
            strips.append(bar_strip(path, screen, rows))
        except Exception as error:                      # noqa: BLE001 — report and skip
            print(f"skip {os.path.basename(path)}: {error}", file=sys.stderr)
            continue
        names.append(os.path.basename(path))
    if not strips:
        sys.exit(f"no readable wallpapers in {args.folder}")

    truth = np.array([lowest_passing(lambda a, s=s: worst_window(s, a), TARGET)
                      for s in strips])

    print(f"{len(strips)} wallpapers, {screen[0]}x{screen[1]}, {rows}px bar")
    print(f"\nopacity each wallpaper needs to hold {TARGET}:1 over the worst "
          f"{WINDOW}px window")
    for q in (100, 95, 75, 50, 25, 0):
        print(f"  p{q:<3d} {np.percentile(truth, q):.3f}")
    print(f"  fails at the 0.65 schema floor: {(truth > 0.65).sum()}/{len(truth)}")
    print(f"  fails at the 0.86 default:      {(truth > 0.86).sum()}/{len(truth)}")

    # What a fixed setting is worth over the worst wallpaper in the folder.
    # These are the numbers the settings copy quotes (#94 asks that the copy be
    # reproducible from a documented command, and the percentiles above are not
    # those numbers) — and they are the whole argument for the clamp: no setting
    # inside the slider's range is safe on its own.
    print("\nwhat a fixed setting leaves on the worst wallpaper here")
    for alpha in (1.0, 0.86, 0.75, 0.65):
        worst = min(worst_window(s, alpha) for s in strips)
        print(f"  opacity {alpha:.2f}: {worst:.2f}:1"
              f"{'' if worst >= TARGET else '   (under ' + str(TARGET) + ':1)'}")

    def run(cells, margin):
        picked = np.array([
            lowest_passing(lambda a, c=brightest_cell(s, cells): flat_contrast(c, a, rows),
                           TARGET + margin)
            for s in strips])
        actual = np.array([worst_window(s, a) for s, a in zip(strips, picked)])
        return picked, actual

    if args.sweep:
        print(f"\n{'cells':>6} {'margin':>7} {'worst true':>11} {'under 4.5':>10} "
              f"{'median opacity':>15}")
        for cells in (32, 48, 64, 96):
            for margin in (0.0, 0.2, 0.4, 0.6, 0.8):
                picked, actual = run(cells, margin)
                print(f"{cells:6d} {margin:7.2f} {actual.min():11.2f} "
                      f"{(actual < TARGET).sum():10d} {np.median(picked):15.3f}")
        return

    picked, actual = run(args.cells, args.margin)
    print(f"\nthe runtime clamp at cells={args.cells}, aiming "
          f"{TARGET + args.margin}:1")
    print(f"  worst true ratio it leaves:  {actual.min():.2f}:1")
    print(f"  wallpapers left under {TARGET}:1: {(actual < TARGET).sum()}/{len(actual)}")
    print(f"  opacity it picks: median {np.median(picked):.3f}  "
          f"p95 {np.percentile(picked, 95):.3f}  max {picked.max():.3f}")
    binds = picked > 0.65
    print(f"  raises a 0.65 setting on {binds.sum()}/{len(picked)} wallpapers")

    print("\n  the eight that demand the most:")
    for i in np.argsort(-truth)[:8]:
        print(f"    {names[i]:32s} needs {truth[i]:.3f}  clamp picks {picked[i]:.3f}"
              f"  leaves {actual[i]:.2f}:1")

    if (actual < TARGET).any():
        sys.exit(1)


if __name__ == "__main__":
    main()
