// What the wallpaper is allowed to do to the accent (#58, #6), as pure
// functions.
//
// The constrained mode's promise is that the accent *responds* to the wallpaper
// without ever leaving the forest: teal may slide toward sage or toward lake
// blue, and it may not become orange, and it may not become hard to read. All
// three halves of that are arithmetic, so all three live here where tests/ can
// reach them — Services/Theming/Theming.qml is the half that knows what a
// quantizer and a settings file are.
//
// ## Oklab, and why not the obvious thing
//
// The obvious QML path is `Qt.hsla()` and `color.hslHue`, and it is wrong.
// Holding HSL lightness and saturation fixed while sweeping hue moves WCAG
// contrast against `bgBase` from 4.38:1 to 10.26:1 — a 134% spread, measured in
// `.wayfinder/research/dynamic-theming.md`. Yellow and blue at the same nominal
// lightness are not the same brightness, and any hue rotation done in HSL
// silently breaks legibility for half the circle.
//
// Oklab is built to fix exactly that: its L is perceptually uniform, so
// **rotating H while holding L and C fixed leaves contrast almost untouched**.
// Measured over the band below, at the shipped accent's own L and C, contrast
// against `bgBase` moves between 8.82:1 and 9.03:1 — a 2.3% drift against a
// fixed-accent baseline of 8.99:1, and every hue in the band stays in sRGB
// gamut. That single property is the whole safety argument, and it is why the
// rotation is the *only* thing this file does to a colour.
//
// The conversion is Björn Ottosson's reference matrices, ~15 lines each way.
// The alternative with the same contrast guarantee is Material's HCT, which
// needs CAM16 — Noctalia's port of it is 1071 lines of Python, for a feature
// that needs one hue number.
//
// ## The band is the palette's own
//
// `[118°, 240°]` is not a taste: 118.2° is `accentLichen`, the sage the brief
// already ships, and 225.9° is the brief's deep lake blue. The band is the arc
// between two colours the design already contains, which is what makes the
// clamp structurally unable to collide with the warm accents — `accentWarm`
// sits at 65.6° and `accentEmber` at 35.8°, both outside it. "Never red or
// purple" is not a rule this file enforces by checking; it is a place those
// hues cannot be reached from.
//
// Light mode raises the floor to 140°. At 118° the light accent renders
// `#636d31`, a muddy olive — the same dark yellow-green Material's
// `DislikeAnalyzer` exists to catch.
//
// ## Failing closed
//
// A wallpaper does not always have an answer. A greyscale photograph has no
// saturated hue; a rainbow has every hue and therefore no dominant one. Both
// come back as *no reading*, and no reading means the shipped accent — never a
// guess. `concentration` is what tells them apart, and it is a real measurement
// (the resultant length of the chroma-weighted hue vectors) rather than a
// heuristic: 1.0 is total agreement, 0 is a hue wheel.
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    id: policy

    // --- the knobs ------------------------------------------------------------
    //
    // Every one of these was swept over the 25 board reference images in
    // `.wayfinder/research/dynamic-theming.md`; the tables there are what picked
    // the numbers, and the sensitivity around each is recorded beside it.

    /// Below this Oklab chroma a quantized colour is grey as far as hue goes,
    /// and its hue is noise. 0.025 and not the more obvious 0.04 because
    /// Quickshell's `ColorQuantizer` is a recursive *median cut* — it averages
    /// clusters together, which drags chroma down. At 0.04 eight of the 25
    /// reference images fell back; at 0.025, two.
    readonly property real chromaMin: 0.025

    /// Near-black and near-white clusters are excluded whatever their chroma:
    /// they are the wallpaper's shadows and its sky, they dominate the pixel
    /// count of most photographs, and their hue is not what the image is *about*.
    readonly property real lightnessFloor: 0.25
    readonly property real lightnessCeiling: 0.90

    /// How much the surviving hues have to agree before the reading counts.
    /// 0.55 is a little over half; below it the image has no dominant hue and
    /// the shipped accent stands.
    readonly property real minConcentration: 0.55

    /// The furthest the accent may travel from where the brief put it, in
    /// degrees. Under 25° the band clamp never fires and the mode is really just
    /// a shift cap; at 30° the clamp starts doing real work, which is what makes
    /// the response feel wallpaper-driven rather than binary. Over 40° the
    /// contrast spread starts to widen for no extra distinctness.
    readonly property real maxShift: 30

    /// The arc, in Oklab hue degrees. Sage → teal → lake blue.
    readonly property real bandFloorDark: 118
    readonly property real bandFloorLight: 140
    readonly property real bandCeiling: 240

    /// WCAG AA for body text. The band never threatens this in dark mode
    /// (worst case 8.82:1); light mode's accent has 4.76:1 at its tightest,
    /// which is 0.26 of headroom — thin enough to be worth checking rather than
    /// asserting.
    readonly property real minRatio: 4.5

    // --- sRGB ⇄ Oklab ---------------------------------------------------------

    /// sRGB → linear light, and back. The kink near black is in the standard,
    /// not a fudge. Note this is the *colour space* transfer function and is a
    /// hair different from the one `relativeLuminance` uses below (0.04045 vs
    /// WCAG's 0.03928) — the two specifications disagree in the fourth decimal
    /// and both are quoted verbatim rather than reconciled, because a shared
    /// constant here would be this file inventing a standard.
    function linearize(channel: real): real {
        return channel <= 0.04045
            ? channel / 12.92
            : Math.pow((channel + 0.055) / 1.055, 2.4);
    }

    function delinearize(channel: real): real {
        return channel <= 0.0031308
            ? channel * 12.92
            : 1.055 * Math.pow(channel, 1 / 2.4) - 0.055;
    }

    /// A colour in cylindrical Oklab: `{ L, C, H }`, hue in degrees 0–360.
    ///
    /// `L` is perceptual lightness, `C` is chroma (distance from grey), `H` is
    /// the hue angle. The rest of this file only ever changes `H`.
    function toOklch(value: color): var {
        const r = policy.linearize(value.r);
        const g = policy.linearize(value.g);
        const b = policy.linearize(value.b);

        const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
        const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
        const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);

        const okL = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
        const okA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
        const okB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;

        return {
            L: okL,
            C: Math.sqrt(okA * okA + okB * okB),
            H: (Math.atan2(okB, okA) * 180 / Math.PI + 360) % 360
        };
    }

    /// Back to sRGB: `{ r, g, b, inGamut }`, channels clamped to 0–1.
    ///
    /// `inGamut` is reported rather than acted on. Every hue in the band is in
    /// gamut at the shipped accents' chroma — measured — so a false here means
    /// something upstream changed the palette, and it is worth a line in a test
    /// rather than a silent clamp.
    function fromOklch(okL: real, chroma: real, hue: real): var {
        const rad = hue * Math.PI / 180;
        const okA = chroma * Math.cos(rad);
        const okB = chroma * Math.sin(rad);

        const l = Math.pow(okL + 0.3963377774 * okA + 0.2158037573 * okB, 3);
        const m = Math.pow(okL - 0.1055613458 * okA - 0.0638541728 * okB, 3);
        const s = Math.pow(okL - 0.0894841775 * okA - 1.2914855480 * okB, 3);

        const raw = [
            policy.delinearize(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            policy.delinearize(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            policy.delinearize(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        ];

        const inGamut = raw.every(channel => channel >= -0.001 && channel <= 1.001);
        const fit = raw.map(channel => Math.min(1, Math.max(0, channel)));
        return { r: fit[0], g: fit[1], b: fit[2], inGamut: inGamut };
    }

    /// `{ r, g, b }` → `#rrggbb`. Lower case and six digits, because this is
    /// written into the settings file beside `paletteOverrides`, which
    /// `Core/Tokens.qml` parses with a pattern that admits exactly this.
    function hexOf(rgb: var): string {
        const byte = channel => {
            const text = Math.round(Math.min(1, Math.max(0, channel)) * 255).toString(16);
            return text.length === 1 ? "0" + text : text;
        };
        return "#" + byte(rgb.r) + byte(rgb.g) + byte(rgb.b);
    }

    // --- reading the wallpaper -------------------------------------------------

    /// The wallpaper's dominant saturated hue: `{ ok, hue, concentration,
    /// sampled }`.
    ///
    /// A **chroma-weighted circular mean**, and both halves of that matter.
    /// Circular because hue is an angle: the arithmetic mean of 350° and 10° is
    /// 180°, the exact opposite of the right answer. Chroma-weighted because
    /// `ColorQuantizer` hands back representative colours with no population
    /// counts — there is no way to ask how much of the image each one covers —
    /// so the weight has to come from the colours themselves, and "how colourful
    /// it is" is a better proxy for "how much this image is about this hue" than
    /// counting clusters equally.
    ///
    /// `concentration` is the resultant length of those weighted vectors: 1.0
    /// when every surviving colour shares a hue, near 0 when they cancel out
    /// around the wheel. It is what separates "this wallpaper is blue" from
    /// "this wallpaper is a rainbow", and the whole fail-closed story rests on
    /// it.
    function dominantHue(colors: var): var {
        let x = 0;
        let y = 0;
        let weight = 0;
        let sampled = 0;

        for (const value of colors ?? []) {
            const lch = policy.toOklch(value);
            if (lch.C < policy.chromaMin)
                continue;
            if (lch.L <= policy.lightnessFloor || lch.L >= policy.lightnessCeiling)
                continue;

            const rad = lch.H * Math.PI / 180;
            x += lch.C * Math.cos(rad);
            y += lch.C * Math.sin(rad);
            weight += lch.C;
            sampled++;
        }

        if (sampled === 0 || weight === 0)
            return { ok: false, hue: NaN, concentration: 0, sampled: 0 };

        const concentration = Math.sqrt(x * x + y * y) / weight;
        return {
            ok: concentration >= policy.minConcentration,
            hue: (Math.atan2(y, x) * 180 / Math.PI + 360) % 360,
            concentration: concentration,
            sampled: sampled
        };
    }

    // --- the clamp -------------------------------------------------------------

    /// Signed degrees from one hue to another, the short way round: −180…180.
    /// Going from 350° to 10° is +20°, not −340°.
    function shortestArc(from: real, to: real): real {
        return ((to - from + 540) % 360) - 180;
    }

    function bandFloor(darkMode: bool): real {
        return darkMode ? policy.bandFloorDark : policy.bandFloorLight;
    }

    /// Where the accent actually lands, given what the wallpaper wants.
    ///
    /// Two guardrails in series, and they are not redundant. The shift cap
    /// bounds *movement* — the accent never travels far from where the brief put
    /// it, however emphatic the wallpaper. The band bounds *destination* — the
    /// accent is never outside the forest, however the base palette is later
    /// retuned. A wallpaper 138° away (the amber pin) is stopped by the first;
    /// a base accent someone dragged toward yellow would be stopped by the
    /// second.
    function targetHue(dominant: real, baseHue: real, darkMode: bool): real {
        const wanted = policy.shortestArc(baseHue, dominant);
        const capped = Math.max(-policy.maxShift, Math.min(policy.maxShift, wanted));
        const shifted = (baseHue + capped + 360) % 360;
        return Math.max(policy.bandFloor(darkMode),
                        Math.min(policy.bandCeiling, shifted));
    }

    // --- legibility ------------------------------------------------------------

    /// WCAG relative luminance and contrast ratio. The same arithmetic
    /// `Surfaces/Bar/SurfaceOpacity.qml` uses, so a number from here and a
    /// number from there mean the same thing.
    function relativeLuminance(rgb: var): real {
        const linear = channel => channel <= 0.03928
            ? channel / 12.92
            : Math.pow((channel + 0.055) / 1.055, 2.4);
        return 0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b);
    }

    function contrast(one: real, other: real): real {
        const lighter = Math.max(one, other);
        const darker = Math.min(one, other);
        return (lighter + 0.05) / (darker + 0.05);
    }

    /// The lightness the rotated accent should actually use.
    ///
    /// Almost always the one it came in with: rotating at fixed L is the whole
    /// contrast argument, so moving L is an admission that the argument did not
    /// quite hold — which happens only in light mode, where the accent starts
    /// with 0.26 of headroom over AA. When it does, L is bisected *away from the
    /// background* until the ratio clears, and by the smallest step that clears
    /// it: the accent gets no lighter or darker than it has to.
    ///
    /// Hue is never touched here. Rescuing contrast by rotating would undo the
    /// clamp the rest of this file exists to enforce.
    function fitLightness(okL: real, chroma: real, hue: real, background: real): real {
        const ratioAt = candidate => policy.contrast(
            policy.relativeLuminance(policy.fromOklch(candidate, chroma, hue)), background);

        if (ratioAt(okL) >= policy.minRatio)
            return okL;

        // The end of the L axis that moves away from the background. Black and
        // white are the extremes; whichever is further from the background is
        // the direction contrast increases in.
        const away = background > policy.relativeLuminance(
            policy.fromOklch(okL, chroma, hue)) ? 0 : 1;
        if (ratioAt(away) < policy.minRatio)
            return away;   // unreachable with the shipped palette; take the best there is

        let near = okL;
        let far = away;
        for (let i = 0; i < 24; i++) {
            const mid = (near + far) / 2;
            if (ratioAt(mid) >= policy.minRatio)
                far = mid;
            else
                near = mid;
        }
        return far;
    }

    // --- the whole computation --------------------------------------------------

    /// The accent this wallpaper earns, as a sparse role → colour map — or `{}`
    /// for "keep the shipped one".
    ///
    /// `palette` is the **base** row for the current mode, never the one
    /// currently on screen. Measuring the shift from the last result would make
    /// this a feedback loop: each wallpaper change would rotate from wherever
    /// the previous one landed and the accent would walk off across successive
    /// changes. The shift is always measured from where the brief put the
    /// accent, so the same wallpaper always produces the same colour whatever
    /// came before it.
    ///
    /// Two roles move, not one. `accentPrimary` and `accentDeep` are the same
    /// teal at two lightnesses — 201.9° and 201.3° — and they are used together:
    /// the deep one is the fill under a selected row whose outline is the light
    /// one. So they take the same *rotation* rather than the same destination,
    /// which keeps the half-degree between them and keeps the pair looking like
    /// one colour. Everything else in the palette — the warm accents, every
    /// background, every text role — is untouched, which is what makes this a
    /// constrained mode rather than a generated one.
    function accent(colors: var, palette: var, darkMode: bool): var {
        const reading = policy.dominantHue(colors);
        if (!reading.ok)
            return ({});

        const primary = policy.toOklch(palette.accentPrimary);
        const hue = policy.targetHue(reading.hue, primary.H, darkMode);
        const rotation = policy.shortestArc(primary.H, hue);

        const background = policy.relativeLuminance(policy.toRgb(palette.bgBase));
        const okL = policy.fitLightness(primary.L, primary.C, hue, background);

        const deep = policy.toOklch(palette.accentDeep);
        const deepHue = (deep.H + rotation + 360) % 360;

        return {
            accentPrimary: policy.hexOf(policy.fromOklch(okL, primary.C, hue)),
            accentDeep: policy.hexOf(policy.fromOklch(deep.L, deep.C, deepHue))
        };
    }

    /// A colour as plain channels, for the luminance functions above — which
    /// take `{ r, g, b }` because that is what `fromOklch` hands back, and a
    /// `color` is not one.
    function toRgb(value: color): var {
        return { r: value.r, g: value.g, b: value.b };
    }

    // --- the log (#81) ---------------------------------------------------------
    //
    // The accent changing is a state change with no other evidence: it is one
    // colour, on a bar the user may not be looking at, and "the theme did not
    // move" and "the service never ran" look identical from outside. So each
    // outcome says which it was, with the numbers that decided it.

    function tunedLine(hue: real, concentration: real, hex: string): string {
        return "accent tuned to " + hue.toFixed(1) + "° (agreement "
            + concentration.toFixed(2) + ") " + hex;
    }

    function keptLine(concentration: real, sampled: int): string {
        return "accent kept: no dominant hue (agreement " + concentration.toFixed(2)
            + " over " + sampled + " colour(s))";
    }

    function clearedLine(mode: string): string {
        return "accent cleared (mode " + mode + ")";
    }
}
