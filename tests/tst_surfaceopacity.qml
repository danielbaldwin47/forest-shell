// The bar's legibility floor (#79).
//
// The decision under test: the 4.5:1 body-text floor is a floor on the
// *rendered band*, not on the opacity setting. So these tests are mostly about
// two things — that the band model composites the layers the way Qt Quick
// actually draws them, and that `minimumOpacity` is a real inverse of it.
//
// The band numbers are anchored to `tools/capture-harness.sh --contrast`
// measurements, quoted at each check, so a drift here is a drift from what the
// shell renders rather than from a number someone typed.
import QtQuick
import QtTest
import "../Surfaces/Bar"

TestCase {
    name: "SurfaceOpacity"

    SurfaceOpacity { id: surface }

    // The shipped dark palette and the shipped `bar.surface` defaults — the
    // configuration every quoted measurement was taken against.
    readonly property var look: ({
        surface: Qt.color("#141b17"),
        fogWash: Qt.color("#beced1"),
        hairlineColor: Qt.color("#2a3830"),
        mistWash: 0.10,
        grain: 0.03,
        topLight: true,
        topLightAmount: 0.05,
        hairline: true,
        rows: 32
    })

    readonly property color text: Qt.color("#a9b8b0")
    readonly property color white: Qt.color("#ffffff")
    readonly property color black: Qt.color("#000000")

    function test_luminance_matches_the_wcag_definition() {
        fuzzyCompare(surface.relativeLuminance(black), 0.0, 0.0001);
        fuzzyCompare(surface.relativeLuminance(white), 1.0, 0.0001);
        // The bar's own fill — 0.0088, as measured on the captured frames.
        fuzzyCompare(surface.relativeLuminance(Qt.color("#141b17")), 0.0088, 0.002);
        // Green carries most of the weight, blue almost none.
        verify(surface.relativeLuminance(Qt.color("#00ff00"))
               > surface.relativeLuminance(Qt.color("#0000ff")));
    }

    function test_contrast_is_the_wcag_ratio() {
        fuzzyCompare(surface.contrast(1.0, 0.0), 21.0, 0.0001);
        compare(surface.contrast(0.5, 0.5), 1.0);
        // Symmetric — the caller should not have to know which is lighter.
        compare(surface.contrast(0.2, 0.7), surface.contrast(0.7, 0.2));
    }

    // The band is the fill, the top-light, the mist wash and the grain, each
    // composited separately. Not a group: Qt Quick multiplies opacity down the
    // tree and blends every node against what is already there, so the
    // top-light — a child of the translucent fill — lands *on top of* the
    // wallpaper the fill let through, and blocks some of it.
    //
    // Measured on a capture of a white wallpaper at 0.65, the band's top row is
    // #454c49-ish and its middle row #707572: the top of the bar is darker than
    // the middle, which only happens if the top-light composites this way.
    function test_the_top_light_blocks_wallpaper_rather_than_lightening_the_fill() {
        const top = surface.bandColor(look, 0.65, white, 0);
        const middle = surface.bandColor(look, 0.65, white, 16);
        verify(surface.relativeLuminance(top) < surface.relativeLuminance(middle),
               "the top row should be darker than the middle over a bright wallpaper");
        // Captured: row 0 read 69/255 on red, row 16 read 112/255.
        fuzzyCompare(top.r * 255, 69, 4);
        fuzzyCompare(middle.r * 255, 112, 4);
    }

    function test_an_opaque_fill_does_not_admit_the_wallpaper() {
        const overWhite = surface.bandLuminance(look, 1.0, white);
        const overBlack = surface.bandLuminance(look, 1.0, black);
        fuzzyCompare(overWhite, overBlack, 0.0001);
    }

    // tools/capture-harness.sh --wallpaper <ramp> --bar-opacity … --contrast,
    // over the ramp's brightest 100px window (#f5f5f5): 6.58:1 at 1.0,
    // 4.80:1 at 0.86, 3.60:1 at 0.75, 2.72:1 at 0.65.
    function test_the_band_reproduces_the_captured_contrast() {
        const wallpaper = Qt.rgba(245.1 / 255, 245.1 / 255, 245.1 / 255, 1);
        const textLum = surface.relativeLuminance(text);
        const captured = { "1": 6.58, "0.86": 4.80, "0.75": 3.60, "0.65": 2.72 };
        for (const key in captured) {
            const ratio = surface.contrast(
                textLum, surface.bandLuminance(look, parseFloat(key), wallpaper));
            // Within 0.15 of the capture — the residual is the harness averaging
            // real pixels where this averages one colour.
            fuzzyCompare(ratio, captured[key], 0.15);
        }
    }

    function test_a_dark_wallpaper_needs_no_clamp_at_all() {
        // Over black the band never leaves the fill's own range: 7.07:1 even
        // wide open. Nothing to clamp, so the setting stands untouched.
        compare(surface.minimumOpacity(look, black, text, 4.5), 0);
    }

    function test_a_bright_wallpaper_clamps_to_something_that_actually_passes() {
        const floor = surface.minimumOpacity(look, white, text, 4.5);
        verify(floor > 0.8, "a white wallpaper should need most of the range, got " + floor);
        verify(floor <= 1.0, floor + " went past opaque");
        // The point of the whole exercise: at the returned floor, the band
        // measures at or above the target.
        const ratio = surface.contrast(surface.relativeLuminance(text),
                                       surface.bandLuminance(look, floor, white));
        verify(ratio >= 4.5, "the clamp returned " + floor + " but that measures " + ratio);
    }

    function test_the_clamp_is_the_lowest_opacity_that_passes() {
        const floor = surface.minimumOpacity(look, white, text, 4.5);
        const textLum = surface.relativeLuminance(text);
        // A hair below it must fail, or the clamp is costing translucency it
        // does not need to cost.
        const below = surface.contrast(
            textLum, surface.bandLuminance(look, floor - 0.01, white));
        verify(below < 4.5, "opacity " + (floor - 0.01) + " already passes at " + below);
    }

    function test_an_unreachable_target_clamps_to_opaque_rather_than_past_it() {
        // 21:1 is the whole WCAG range and no band can reach it. The answer is
        // "as far as this can go", not a number outside [0, 1].
        compare(surface.minimumOpacity(look, white, text, 21), 1.0);
    }

    function test_a_heavier_mist_wash_raises_the_floor() {
        // The wash sits above the fill, so it costs contrast the fill cannot
        // win back. A clamp that ignored the rest of the surface config would
        // under-protect exactly here.
        const heavy = Object.assign({}, look, { mistWash: 0.4 });
        verify(surface.minimumOpacity(heavy, white, text, 4.5)
               > surface.minimumOpacity(look, white, text, 4.5));
    }

    function test_light_mode_clamps_from_the_other_side() {
        // Dark text on a light surface: a *dark* wallpaper is the hazard, and a
        // bright one needs no help.
        const light = {
            surface: Qt.color("#f7f9f5"), fogWash: Qt.color("#4a5a5e"),
            hairlineColor: Qt.color("#dbe1da"), mistWash: 0.10, grain: 0.03,
            topLight: true, topLightAmount: 0.05, hairline: true, rows: 32
        };
        const lightText = Qt.color("#46564d");
        compare(surface.minimumOpacity(light, white, lightText, 4.5), 0);
        verify(surface.minimumOpacity(light, black, lightText, 4.5) > 0.5);
    }

    function test_the_brightest_palette_entry_is_the_one_that_matters() {
        const palette = [Qt.color("#101010"), Qt.color("#e0e0e0"), Qt.color("#404040")];
        compare(surface.brightest(palette), Qt.color("#e0e0e0"));
        // Nothing to read yet is not the same as "black" — a caller must be
        // able to tell "no answer" from "a dark answer".
        compare(surface.brightest([]), null);
        compare(surface.brightest(null), null);
    }

    // The bar paints before the wallpaper has been read, and it must paint at
    // the user's setting rather than at NaN or at a guess.
    function test_no_reading_yet_means_the_plain_setting() {
        compare(surface.effectiveOpacity(0.65, NaN), 0.65);
        compare(surface.effectiveOpacity(0.65, undefined), 0.65);
    }

    function test_the_clamp_can_only_ever_add_opacity() {
        // It is a legibility floor, not an opacity policy: if the user asked
        // for more than the floor, they get what they asked for.
        compare(surface.effectiveOpacity(0.95, 0.80), 0.95);
        compare(surface.effectiveOpacity(0.65, 0.80), 0.80);
        for (const floor of [0, 0.3, 0.8, 1]) {
            const value = surface.effectiveOpacity(0.65, floor);
            verify(value >= 0.65, value + " went below the setting");
            verify(value <= 1.0, value + " went past opaque");
        }
    }

    // The strip of the wallpaper the bar covers, in the source image's own
    // pixels — what ColorQuantizer.imageRect wants. An overhanging rect is
    // padded with black rather than clamped (measured), and black reads as
    // "dark wallpaper, no clamp needed", so a wrong rect fails *unsafely*.
    function test_the_strip_rect_is_the_part_of_the_image_under_the_bar() {
        // A 16:9 image on a 16:9 screen: no crop, the bar covers the top
        // 32/1080 of the image.
        const exact = surface.stripRect(1920, 1080, 1920, 1080, 32, "top");
        compare(exact.x, 0);
        compare(exact.y, 0);
        compare(exact.width, 1920);
        compare(exact.height, 32);

        // A wider-than-16:9 image is cropped left and right, so the strip is
        // narrower than the file and starts inside it.
        const wide = surface.stripRect(4000, 1000, 1920, 1080, 32, "top");
        verify(wide.width < 4000, "a 4:1 image should be cropped horizontally");
        compare(wide.y, 0);
        // Same shape as the bar, give or take the strip height rounding to a
        // whole source pixel.
        fuzzyCompare(wide.width / wide.height, 1920 / 32, 2);

        // A taller image is cropped top and bottom, so the strip starts below
        // the top of the file.
        const tall = surface.stripRect(1000, 4000, 1920, 1080, 32, "top");
        compare(tall.x, 0);
        compare(tall.width, 1000);
        verify(tall.y > 0, "a 1:4 image should be cropped vertically, got y=" + tall.y);
    }

    function test_the_strip_rect_follows_the_bar_to_the_bottom_edge() {
        const bottom = surface.stripRect(1920, 1080, 1920, 1080, 32, "bottom");
        compare(bottom.y, 1048);
        compare(bottom.height, 32);
    }

    function test_the_strip_rect_never_leaves_the_image() {
        // Every rect the shell can ask for has to sit inside the file, whatever
        // the aspect ratio, or the quantizer pads it with black.
        for (const size of [[800, 600], [3840, 1080], [1080, 3840], [1920, 1080]]) {
            for (const edge of ["top", "bottom"]) {
                const r = surface.stripRect(size[0], size[1], 1920, 1080, 32, edge);
                verify(r.x >= 0 && r.y >= 0, size + " " + edge + ": rect starts outside");
                verify(r.x + r.width <= size[0], size + " " + edge + ": rect overhangs width");
                verify(r.y + r.height <= size[1], size + " " + edge + ": rect overhangs height");
                verify(r.width >= 1 && r.height >= 1, size + " " + edge + ": empty rect");
            }
        }
    }

    function test_an_unreadable_image_has_no_strip() {
        // Size 0 means the intrinsic size has not arrived. There is no rect to
        // ask for, and guessing one would sample black.
        compare(surface.stripRect(0, 0, 1920, 1080, 32, "top"), null);
    }
}
