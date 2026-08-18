// The calendar's derived values: the numbers and the eight event hues that
// `Core/Theme.qml` does not have a name for.
//
// Read the shell's own tokens through `Theme`, never through `Core/Tokens.qml`
// directly: `Tokens` is a plain `QtObject` that `Theme` instantiates and
// re-exports, so `Tokens.pt(12)` in a surface resolves to the *type* and fails
// at runtime with "Property 'pt' of object Tokens is not a function" — a
// warning that costs a font and a size and still draws something.
//
// **This is the only file under Surfaces/Calendar allowed to write a hex
// colour.** Everything else asks here, so "what colour is a lake chip in light
// mode" has one answer and changing it is one edit. The rule matters more than
// usual on this surface: eight hues times three roles times two modes is
// forty-eight literals, and forty-eight literals scattered across five files is
// a palette nobody can audit against `tools/measure-contrast.py`.
//
// The numbers are here for a different reason. `hourRow: 56` is not a taste
// call — it is chosen so a 15-minute snap is 14px, above the 12px minimum drag
// target that 48 or 52 would miss — and a number carrying an argument like that
// belongs somewhere the argument can be written next to it rather than inlined
// at its one call site.
pragma Singleton
import QtQuick
import Quickshell
import qs.Core

Singleton {
    id: tokens

    // --- the grid -------------------------------------------------------------

    /// One hour of the day grid. 56 rather than Notion's ~52: the half-hour
    /// band is then 28 and a 15-minute snap is 14px, which is above the 12px
    /// floor for a drag target. 48 and 52 both land under it.
    readonly property int hourRow: 56

    /// The time gutter down the left of the grid, and the same width as an
    /// hour is tall — not for symmetry, but because `"12 PM"` at pt(11) with
    /// `space2` of right padding is 48px and 56 is the next step up that leaves
    /// the labels from crowding the first column's chips.
    readonly property int gutterW: 56

    /// The weekday/date row over the columns.
    readonly property int dayHeaderH: 48

    /// The all-day band's floor. It grows a lane at a time from here.
    readonly property int allDayMinH: 28

    /// One all-day bar and the gap under it.
    readonly property int allDayLaneH: 20
    readonly property int allDayLaneGap: 2

    /// The accent bar down a timed chip's left edge.
    readonly property int chipBar: 3

    /// The shortest a chip is ever drawn, whatever its duration says. A 15
    /// minute event is 14px of grid and 14px of chip is not a hit target.
    readonly property int chipMinH: 20

    /// The drag/resize snap, in minutes.
    readonly property int snapMin: 15

    readonly property int monthCellMinH: 108

    /// The sidebar, and the toolbar over the grid. Both are chrome rather than
    /// grid, and both are here so the one window that lays them out does not
    /// carry the only copy of the number.
    readonly property int sidebarW: 248
    readonly property int toolbarH: 52

    /// The chrome controls along the toolbar: chevrons, Today, and each
    /// segment of the view switcher all stand this tall.
    readonly property int controlH: 30

    // --- the column washes ----------------------------------------------------

    /// The weekend column's wash, and **the one place this file departs from
    /// DESIGN-SPEC.md's literal value.**
    ///
    /// The spec says `Theme.bgSunken` at 0.5. In light mode that is right and
    /// it is what is used: `bgSunken` sits a 1.12:1 step under `bgBase`, so
    /// half of it is a wash you can see without looking at it, which is the
    /// whole job — the week's shape has to be readable peripherally.
    ///
    /// In dark mode the same recipe is invisible, and measurably so: `bgBase`
    /// is `#0b100d` and `bgSunken` is `#070a08`, a 1.04:1 step, and half of it
    /// is 1.02:1. It was drawn, captured and could not be told from a weekday.
    /// You cannot sink below a canvas that is already nearly black, so the dark
    /// wash *lifts* instead — `Theme.surface`, the panel colour, at low alpha.
    /// Same intent, opposite direction, because the direction was never the
    /// point.
    readonly property color weekendWash: Theme.dark
        ? Qt.alpha(Theme.surface, 0.45)
        : Qt.alpha(Theme.bgSunken, 0.5)

    /// Today's column. 5% accent works in both modes because it is a hue
    /// against a neutral rather than a lightness against a lightness.
    readonly property color todayWash: Qt.alpha(Theme.accentPrimary, 0.05)

    // --- the hues -------------------------------------------------------------

    /// Which hue an event wears. The choice is pure and tested next door; this
    /// object only owns the colours it resolves to.
    readonly property HuePolicy hues: HuePolicy {}

    /// `bar` is the accent bar and the solid all-day fill; `fill` is the timed
    /// chip's background; `text` is what is legible on that fill. Every
    /// text/fill pair here is ≥4.5:1 in its own mode — the seam that verifies
    /// that is `tools/measure-contrast.py`, not an eyeball.
    ///
    /// The two tables are written out rather than computed with `Qt.tint`
    /// because a computed tint is only as good as the base it is computed
    /// against, and `Theme.surface` moves between themes while these have to
    /// hold their contrast ratio wherever they land.
    readonly property var barsDark: ["#6fbec4", "#8fbf6a", "#d8ac81", "#e07a5f",
                                     "#5b9dd9", "#afbd7a", "#b295cf", "#9d9e8d"]
    readonly property var fillsDark: ["#233533", "#283524", "#333228", "#352a22",
                                      "#1f3036", "#2d3527", "#2d2e34", "#2a302a"]
    readonly property var textsDark: ["#a5d3d3", "#b6d3a3", "#dec9af", "#e3ad9d",
                                      "#9ac1e0", "#c6d2ac", "#c9bcda", "#bec1b6"]

    readonly property var barsLight: ["#0c757b", "#4a7d35", "#8a5a2f", "#b0512f",
                                      "#23608f", "#59682c", "#6b4a8f", "#68695b"]
    readonly property var fillsLight: ["#dbe9e6", "#e2eade", "#eae6dd", "#eee5dd",
                                       "#dde7e9", "#e4e8dd", "#e6e4e9", "#e6e8e3"]

    /// Light mode's text is its bar — the same saturated ink on a pale wash,
    /// which is what keeps a light chip from needing a fourth column of hex.
    readonly property var textsLight: tokens.barsLight

    readonly property var bars: Theme.dark ? tokens.barsDark : tokens.barsLight
    readonly property var fills: Theme.dark ? tokens.fillsDark : tokens.fillsLight
    readonly property var texts: Theme.dark ? tokens.textsDark : tokens.textsLight

    /// An index that cannot miss. A delegate mid-rebuild asks with whatever it
    /// has, and a colour of `undefined` paints black on black.
    function wrap(index: int): int {
        const n = Math.round(index);
        if (!isFinite(n) || n < 0)
            return 0;
        return n % tokens.hues.count;
    }

    function bar(index: int): color { return tokens.bars[tokens.wrap(index)]; }
    function fill(index: int): color { return tokens.fills[tokens.wrap(index)]; }
    function text(index: int): color { return tokens.texts[tokens.wrap(index)]; }

    /// The hairline inside a dark chip, so two chips of the same hue side by
    /// side still read as two. In light mode the fill is already lighter than
    /// the surface and the border only muddies it, so there is none.
    function chipBorder(index: int): color {
        return Theme.dark ? Qt.alpha(tokens.bar(index), 0.18) : "transparent";
    }

    /// A chip under the pointer, lifted 12% toward the overlay — the same
    /// gesture every other hoverable surface in the shell makes, done in the
    /// chip's own hue rather than replacing it.
    function fillHover(index: int): color {
        return Qt.tint(tokens.fill(index), Qt.alpha(Theme.surfaceOverlay, 0.12));
    }
}
