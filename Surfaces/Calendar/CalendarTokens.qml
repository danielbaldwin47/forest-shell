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

    /// The accent bar down a chip's left edge — timed *and* all-day, since
    /// there is only one chip language now.
    readonly property int chipBar: 4

    /// The air between two chips packed side by side in one column, and at the
    /// column's own edges. 2px: one pixel reads as a rendering artefact of the
    /// day separator, three starts to look like a gap in the schedule.
    readonly property int chipGap: 2

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
    /// The measured value moved once more. `Theme.surface` at 0.45 over
    /// `bgBase` is 1.05:1 — captured, and still indistinguishable from a
    /// weekday at arm's length. The wash lifts to `surfaceOverlay` (`#243029`)
    /// at 0.55, which is 1.28:1: the same step light mode gets from `bgSunken`,
    /// and the first value at which Sat/Sun read as a pair without the columns
    /// looking disabled.
    readonly property color weekendWash: Theme.dark
        ? Qt.alpha(Theme.surfaceOverlay, 0.55)
        : Qt.alpha(Theme.bgSunken, 0.75)

    /// Today's column. A hue against a neutral rather than a lightness against
    /// a lightness, so one alpha works in both modes.
    /// 0.11 and not 0.05, because the weekend wash moved: measured off the
    /// capture, today at 0.05 was *dimmer* than a Saturday, which inverts the
    /// two signals. Today has to be at least as loud as the column it may
    /// itself be.
    readonly property color todayWash: Qt.alpha(Theme.accentPrimary, 0.11)

    // --- the hues -------------------------------------------------------------

    /// Which hue an event wears. The choice is pure and tested next door; this
    /// object only owns the colours it resolves to.
    readonly property HuePolicy hues: HuePolicy {}

    /// `bar` is the accent bar down every chip's left edge; `fill` is the chip
    /// body; `text` is what is legible on that fill.
    ///
    /// **Two ratios are gated here, not one, and the second is the one the
    /// first table missed.** Text-on-fill was ≥7:1 across the board and the
    /// chips were still hard to find, because the number nobody had measured
    /// was *fill against the page*: `#2d3527` on `#0b100d` is **1.51:1**, so
    /// the olive chip was a title floating on the grid with no body under it.
    /// A chip is an object; an object needs an edge. The dark fills are
    /// re-tinted (33–41% of the hue over `Theme.surface`) to land at **≥2.2:1
    /// against `bgBase`**, and the light ones at ≥1.28:1 against paper — the
    /// same step light mode's `bgSunken` gets, which is the lightest wash that
    /// still reads as a filled shape. Text is then re-solved against the new
    /// fills and holds ≥4.5:1 in both modes.
    ///
    /// The two tables are written out rather than computed with `Qt.tint`
    /// because a computed tint is only as good as the base it is computed
    /// against, and `Theme.surface` moves between themes while these have to
    /// hold their contrast ratio wherever they land.
    readonly property var barsDark: ["#6fbec4", "#8fbf6a", "#d8ac81", "#e07a5f",
                                     "#5b9dd9", "#afbd7a", "#b295cf", "#9d9e8d"]
    readonly property var fillsDark: ["#325150", "#3d5132", "#554b3a", "#684235",
                                      "#304f65", "#464f37", "#50495d", "#484d44"]
    readonly property var textsDark: ["#a5d3d3", "#b6d3a3", "#dec9af", "#e5b2a3",
                                      "#9ac1e0", "#c6d2ac", "#c9bcda", "#bec1b6"]

    readonly property var barsLight: ["#0c757b", "#4a7d35", "#8a5a2f", "#b0512f",
                                      "#23608f", "#59682c", "#6b4a8f", "#68695b"]
    readonly property var fillsLight: ["#bfd9d8", "#cad9c3", "#ded4c7", "#e6d1c5",
                                       "#c8d7df", "#d1d6c5", "#d8d2df", "#d5d6d0"]

    /// Light mode's text used to *be* its bar. It cannot be any more: the
    /// fills darkened to make a chip a shape, and the bar hues are now 3.3–4.7:1
    /// on them. These are the same inks stepped down until every one clears
    /// 4.6:1 — still recognisably the hue, which is what a colour-coded
    /// calendar is for.
    readonly property var textsLight: ["#0a6469", "#39612a", "#7c522b", "#8f4227",
                                       "#215b88", "#515e28", "#6b4a8f", "#595a4e"]

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

    /// The hairline inside a chip, so two chips of the same hue packed side by
    /// side still read as two — and, at the new fill strengths, so a chip has a
    /// crisp edge rather than fading into the grid rule it abuts. Both modes
    /// get one now: the light fills darkened far enough that an undrawn edge
    /// was the same problem there.
    function chipBorder(index: int): color {
        return Qt.alpha(tokens.bar(index), Theme.dark ? 0.28 : 0.22);
    }

    /// A chip under the pointer, lifted 12% toward the overlay — the same
    /// gesture every other hoverable surface in the shell makes, done in the
    /// chip's own hue rather than replacing it.
    function fillHover(index: int): color {
        return Qt.tint(tokens.fill(index), Qt.alpha(Theme.surfaceOverlay, 0.12));
    }
}
