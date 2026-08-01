// Adaptive bar opacity (#35): the optional, off-by-default knob that spends
// spare contrast on translucency. The floor that keeps the bar legible is in
// the schema, not here — this may only ever make the bar *more* solid.
import QtQuick
import QtTest
import "../Surfaces/Bar"

TestCase {
    name: "SurfaceOpacity"

    SurfaceOpacity { id: surface }

    function test_luminance_matches_the_wcag_definition() {
        // The same function #10's contrast measurements used, so a number here
        // and a number in findings.md mean the same thing.
        fuzzyCompare(surface.relativeLuminance(Qt.color("#000000")), 0.0, 0.0001);
        fuzzyCompare(surface.relativeLuminance(Qt.color("#ffffff")), 1.0, 0.0001);
        // The bar's own fill — 0.017, as measured on the captured frames.
        fuzzyCompare(surface.relativeLuminance(Qt.color("#141b17")), 0.0088, 0.002);
        // Green carries most of the weight, blue almost none.
        verify(surface.relativeLuminance(Qt.color("#00ff00"))
               > surface.relativeLuminance(Qt.color("#0000ff")));
    }

    function test_a_dark_wallpaper_leaves_the_setting_alone() {
        compare(surface.opacityFor(0.86, 0), 0.86);
    }

    function test_a_white_wallpaper_goes_fully_opaque() {
        compare(surface.opacityFor(0.86, 1), 1.0);
    }

    function test_it_can_only_ever_add_opacity() {
        // The knob spends spare contrast; it may never eat into the floor the
        // schema clamps at.
        for (const luminance of [0, 0.1, 0.35, 0.8, 1]) {
            const value = surface.opacityFor(0.65, luminance);
            verify(value >= 0.65, value + " went below the setting");
            verify(value <= 1.0, value + " went past opaque");
        }
    }

    function test_an_out_of_range_reading_cannot_push_it_out_of_range() {
        compare(surface.opacityFor(0.86, -3), 0.86);
        compare(surface.opacityFor(0.86, 12), 1.0);
    }

    function test_no_reading_yet_means_the_plain_setting() {
        // The bar paints before the quantizer has answered, and it must paint
        // at the configured opacity rather than at NaN.
        compare(surface.opacityFor(0.86, NaN), 0.86);
        compare(surface.meanLuminance([]), NaN);
        compare(surface.meanLuminance(null), NaN);
        compare(surface.opacityFor(0.86, surface.meanLuminance([])), 0.86);
    }

    function test_mean_luminance_averages_the_palette() {
        const mid = surface.meanLuminance([Qt.color("#000000"), Qt.color("#ffffff")]);
        fuzzyCompare(mid, 0.5, 0.0001);
        compare(surface.meanLuminance([Qt.color("#ffffff")]), 1.0);
    }
}
