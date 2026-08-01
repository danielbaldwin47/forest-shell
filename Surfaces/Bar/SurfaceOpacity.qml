// How bright the wallpaper is, and what the bar should do about it.
//
// The bar's fill opacity is a legibility budget: #10 measured text-secondary
// over the band at 86% fill as 7.12:1 against the brightest wallpaper on the
// board and 4.44:1 at 60%, which is why the schema clamps at 0.65. Adaptive
// opacity spends the rest of that budget the other way — on a dark-topped
// wallpaper there is contrast to spare, so the bar can stay as translucent as
// the user asked, and it firms up as the image behind it brightens.
//
// Off by default, and a taste feature rather than a safety net: the clamp is
// what keeps the bar legible, and it holds whether this is on or not.
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    /// WCAG relative luminance of one colour. The same function the contrast
    /// measurements in #10 were computed with, so a number from here and a
    /// number from the prototype's `measure.py` mean the same thing.
    function relativeLuminance(color: color): real {
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b);
    }

    /// sRGB → linear light. The kink near black is in the standard, not a
    /// fudge: sRGB is linear down there and only turns into a power curve
    /// above it.
    function linear(channel: real): real {
        return channel <= 0.03928
            ? channel / 12.92
            : Math.pow((channel + 0.055) / 1.055, 2.4);
    }

    /// Mean luminance over a quantized palette, or `NaN` for an empty one.
    ///
    /// Unweighted, because a quantizer hands back representative colours
    /// without telling you how much of the image each one covers. That makes
    /// this a reading of "how bright are the colours in this image", not "how
    /// bright is this image" — good enough to move a knob, and honest about
    /// why the answer is approximate. It is also the *whole* wallpaper rather
    /// than the strip under the bar, which is the brighter part of a board pin
    /// and the part that actually matters; a region-limited quantizer would fix
    /// both, and does not exist.
    function meanLuminance(colors: var): real {
        if (!colors || colors.length === 0)
            return NaN;
        let total = 0;
        for (const color of colors)
            total += relativeLuminance(color);
        return total / colors.length;
    }

    /// Fill opacity for a wallpaper of the given luminance.
    ///
    /// Straight line from the user's setting at black to fully opaque at white.
    /// No curve, because there is no measurement behind one — the honest shape
    /// for "a bit more solid as it gets brighter" is the simplest one, and it
    /// can never land below the setting, which is where the legibility floor
    /// lives.
    function opacityFor(base: real, luminance: real): real {
        if (!isFinite(luminance))
            return base;
        const clamped = Math.min(1, Math.max(0, luminance));
        return base + (1 - base) * clamped;
    }
}
