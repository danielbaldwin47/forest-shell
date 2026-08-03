// Where the bar's legibility floor lives (#79).
//
// The rule this file implements: **4.5:1 is a floor on the rendered band, not
// on the opacity setting.** #68 put it on the setting — "opacity clamps at 0.65,
// 0.60 measured 4.44:1" — and #79 measured what that actually ships: 2.73:1 on
// a real session, 2.82:1 at the capture seam. The clamp was calibrated against
// an averaged wallpaper luminance, and a wallpaper is not an average.
//
// The measurement that replaced it, over all 173 wallpapers on this machine
// (tools/measure-strip-floor.py, which is the offline form of the arithmetic
// below): the opacity a wallpaper needs in order to hold 4.5:1 across the worst
// 100px window of the strip the bar covers runs from 0 to 0.84, median 0.66.
// No single number is both safe and useful — 0.84 would leave a slider two
// notches wide, and anything lower fails on more than half the board. So the
// setting keeps its range and stays where the user put it, and the *rendered*
// fill is clamped up to whatever the wallpaper in front of it demands.
//
// Two halves, both here so they can be tested without a compositor:
//
//   `stripRect` — which pixels of the wallpaper file end up under the bar,
//   given PreserveAspectCrop. Handed to ColorQuantizer.imageRect.
//
//   `bandLuminance` / `minimumOpacity` — what those pixels become once the bar
//   is drawn over them, and the least opacity that keeps the text above the
//   floor.
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    /// Where the top-light gradient reaches transparent, as a fraction of the
    /// bar's height, and the factor the 0-0.4 `topLightAmount` setting is scaled
    /// by to become a `Qt.lighter` factor.
    ///
    /// These are the gradient Surfaces/Bar/BarSurface.qml draws, and it reads
    /// them from here rather than repeating them: this file predicts that
    /// gradient in order to decide the legibility floor, so a value the two
    /// disagree on yields a floor calculated for a bar nobody draws — a wrong
    /// answer that arrives looking like a right one.
    readonly property real topLightStop: 0.55
    readonly property real topLightScale: 4

    /// The mean colour of assets/noise.png (measured: 130.5/255 on every
    /// channel). The grain is a tiled monochrome texture, so as far as the
    /// band's average luminance is concerned it is a flat grey at the grain
    /// setting's opacity.
    readonly property color grainColor: Qt.rgba(130.5 / 255, 130.5 / 255, 130.5 / 255, 1)

    /// WCAG relative luminance of one colour.
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

    /// WCAG contrast ratio between two relative luminances.
    function contrast(a: real, b: real): real {
        return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
    }

    /// `over` at `alpha` composited onto `under`, in sRGB — which is the space
    /// Qt Quick blends in.
    function blend(over: color, alpha: real, under: color): color {
        return Qt.rgba(alpha * over.r + (1 - alpha) * under.r,
                       alpha * over.g + (1 - alpha) * under.g,
                       alpha * over.b + (1 - alpha) * under.b,
                       1);
    }

    /// The colour one row of the band ends up, over a wallpaper of the given
    /// colour.
    ///
    /// `look` carries the whole surface configuration — the theme colours plus
    /// `bar.surface` — because every layer in it costs contrast and a floor
    /// that ignored, say, the mist wash would under-protect whenever the user
    /// raised it.
    ///
    /// The layers are composited one at a time rather than pre-mixed, because
    /// that is what Qt Quick does: item opacity multiplies down the tree and
    /// each node blends against what is already on the target. So the
    /// top-light, a child of the translucent fill, does not lighten the fill's
    /// colour — it lands over the wallpaper the fill let through and blocks
    /// some of it. Over a bright wallpaper that makes the top of the bar
    /// *darker* than its middle, which is visible in any capture and is the
    /// detail an earlier model of this got wrong.
    function bandColor(look: var, fillOpacity: real, wallpaper: color, row: int): color {
        const rows = look.rows || 32;

        let c = blend(look.surface, fillOpacity, wallpaper);

        if (look.topLight) {
            const through = ((row + 0.5) / rows) / topLightStop;
            if (through < 1) {
                // Qt.lighter takes a factor rather than a delta — the same
                // arithmetic, from the same constant, as the gradient in
                // BarSurface.qml.
                const lit = Qt.lighter(look.surface,
                                       1.0 + look.topLightAmount * topLightScale);
                c = blend(lit, fillOpacity * (1 - through), c);
            }
        }

        c = blend(look.fogWash, look.mistWash, c);
        c = blend(grainColor, look.grain, c);

        // The hairline is the bar's outer edge at full strength, so it owns its
        // row outright — the bottom row on a top-anchored bar and the top row on
        // a bottom-anchored one, which is what `hairlineAtBottom` decides in
        // Surfaces/Bar/BarSurface.qml. One row in thirty-two, so it moves the
        // mean by well under a tenth of a ratio point; it is here because a
        // model that is right for one bar position and quietly wrong for the
        // other is the kind of thing that gets believed.
        if (look.hairline && row === (look.hairlineAtBottom === false ? 0 : rows - 1))
            c = look.hairlineColor;

        return c;
    }

    /// Mean relative luminance of the whole band — the figure
    /// tools/measure-contrast.py reports for one column of a capture, and so
    /// the figure a floor derived from it has to be built on.
    function bandLuminance(look: var, fillOpacity: real, wallpaper: color): real {
        const rows = look.rows || 32;
        let total = 0;
        for (let row = 0; row < rows; row++)
            total += relativeLuminance(bandColor(look, fillOpacity, wallpaper, row));
        return total / rows;
    }

    /// The least fill opacity that holds `target`:1 between `text` and the band
    /// over `wallpaper`. 0 when the wallpaper needs no help, 1 when even an
    /// opaque bar cannot get there.
    ///
    /// Bisected rather than solved: the band is a stack of sRGB blends behind a
    /// luminance curve, and there is no closed form worth the algebra for
    /// something that runs once per wallpaper.
    function minimumOpacity(look: var, wallpaper: color, text: color, target: real): real {
        const textLum = relativeLuminance(text);
        const passes = o => contrast(textLum, bandLuminance(look, o, wallpaper)) >= target;

        // The common case by a wide margin: on a dark wallpaper the band never
        // leaves the fill's own range and the setting stands untouched.
        if (passes(0))
            return 0;
        if (!passes(1))
            return 1;

        let low = 0;
        let high = 1;
        // 12 halvings put the answer inside 1/4096, well under the precision
        // the slider offers.
        for (let i = 0; i < 12; i++) {
            const mid = (low + high) / 2;
            if (passes(mid))
                high = mid;
            else
                low = mid;
        }
        return high;
    }

    /// The brightest colour in a quantized palette, or `null` for an empty one.
    ///
    /// Brightest rather than mean: the palette is read from the strip under the
    /// bar at roughly one entry per 40px of screen, so its brightest entry is
    /// the brightest run of wallpaper a line of text can land on. A mean over
    /// the strip is the measurement #68 calibrated against, and averaging away
    /// the bright part of the strip is exactly how it came to ship a floor that
    /// measures 2.8:1.
    function brightest(colors: var): var {
        if (!colors || colors.length === 0)
            return null;
        let best = null;
        let bestLum = -1;
        for (const color of colors) {
            const lum = relativeLuminance(color);
            if (lum > bestLum) {
                bestLum = lum;
                best = color;
            }
        }
        return best;
    }

    /// What to actually paint: the user's setting, raised to the legibility
    /// floor if the wallpaper demands it. A floor of `NaN` — nothing read yet —
    /// leaves the setting alone.
    function effectiveOpacity(setting: real, floor: real): real {
        if (floor === undefined || floor === null || !isFinite(floor))
            return setting;
        return Math.min(1, Math.max(setting, floor));
    }

    /// The rectangle of the wallpaper *file* that ends up under the bar, in the
    /// file's own pixels — which is the space ColorQuantizer.imageRect works
    /// in. `null` when the image's intrinsic size is not known yet.
    ///
    /// The wallpaper is drawn with PreserveAspectCrop (Surfaces/Background/
    /// Wallpaper.qml), so the file is scaled until it covers the screen and the
    /// overhang is trimmed evenly off both sides of whichever axis is long.
    ///
    /// `marginH` and `marginV` are the bar's inset from the screen edge, in
    /// screen pixels — zero for a flush bar, `floatMarginH`/`floatMarginV` for a
    /// floating one (Surfaces/Bar/Bar.qml). They are not cosmetic here: a
    /// floating bar reading the flush strip would read eight rows of wallpaper
    /// it does not cover and miss eight rows it does, and the rows it misses are
    /// the ones nothing else protects.
    ///
    /// `screenWidth`/`screenHeight` are the area the *wallpaper* is drawn into,
    /// which is the screen in the shell and the scene in the capture harness —
    /// PreserveAspectCrop is resolved against that item, so a caller that
    /// passes the wrong one gets a rect from a different crop of the file.
    ///
    /// Every rect this returns has to sit inside the file. An imageRect that
    /// overhangs is padded with black rather than clamped (measured), and black
    /// reads as "dark wallpaper, no clamp needed" — so an off-by-one here does
    /// not produce a slightly wrong floor, it produces no floor at all.
    function stripRect(imageWidth: int, imageHeight: int,
                       screenWidth: int, screenHeight: int,
                       barHeight: int, position: string,
                       marginH: int, marginV: int): var {
        if (!(imageWidth > 0) || !(imageHeight > 0)
                || !(screenWidth > 0) || !(screenHeight > 0))
            return null;

        // A margin wider than the screen it insets is a config that cannot be
        // drawn; clamped rather than rejected, because the answer still has to
        // be a rect inside the file.
        const insetH = Math.max(0, Math.min(marginH || 0, (screenWidth - 1) / 2));
        const insetV = Math.max(0, Math.min(marginV || 0, screenHeight - 1));

        const scale = Math.max(screenWidth / imageWidth, screenHeight / imageHeight);
        const visibleWidth = Math.min(imageWidth, screenWidth / scale);
        const visibleHeight = Math.min(imageHeight, screenHeight / scale);
        const stripHeight = Math.max(1, Math.min(Math.floor(visibleHeight),
                                                 Math.round(barHeight / scale)));

        const left = Math.max(0, (imageWidth - visibleWidth) / 2);
        const top = Math.max(0, (imageHeight - visibleHeight) / 2);

        const x = Math.max(0, Math.min(imageWidth - 1,
                                       Math.round(left + insetH / scale)));
        const width = Math.max(1, Math.min(Math.round(visibleWidth - 2 * insetH / scale),
                                           imageWidth - x));
        const down = position === "bottom"
            ? visibleHeight - insetV / scale - stripHeight
            : insetV / scale;
        const y = Math.max(0, Math.min(imageHeight - stripHeight,
                                       Math.round(top + down)));

        return Qt.rect(x, y, width, stripHeight);
    }
}
