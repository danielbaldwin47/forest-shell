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

    /// The lead-in between a column's own day separator and the first chip in
    /// it. It was 1px — enough to clear the rule and nothing more, so a chip in
    /// Tuesday's last lane and one in Wednesday's first were `2 + rule + 1` = 4
    /// pixels apart and read as one block with a scratch down it. 2 makes the
    /// pair `2 + rule + 2` = 5, and the chip's left edge sits *off* the rule
    /// rather than on it, which is the whole complaint.
    ///
    /// 2 and not the 4 that would look tidier still, because the lead-in comes
    /// out of the track every lane divides: at three lanes in a 124px column
    /// each extra pixel of inset is a third of a pixel off a chip that has
    /// none to give.
    readonly property int chipInset: 2

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

    /// The line the chrome band's two display-face headings sit on, measured
    /// from the top of the band.
    ///
    /// The sidebar's wordmark and the toolbar's date title are set at different
    /// sizes on either side of a hairline, and vertical *centring* does not put
    /// two different sizes on one line — the larger face's box is taller, so its
    /// baseline drops. Measured on the first capture of this band: 3px apart,
    /// which is far enough to see and close enough to look like a mistake
    /// rather than a decision. Stating the baseline instead of the centre makes
    /// the two agree by construction at any size either of them is ever set in.
    readonly property int titleBaseline: 34

    /// Lining, tabular figures — `font.features` for every number on this
    /// surface that sits in a column with another number: the hour gutter, the
    /// day-header numerals, the now stamp, and every time printed on a chip.
    ///
    /// Proportional figures are the default and they are wrong here for a
    /// reason that only shows up in a grid: a `1` is narrower than a `0`, so
    /// `10:00` and `11:00` are different widths, and a column of times ragged
    /// by a pixel and a half per row reads as a column that is not aligned. It
    /// is also what makes a live stamp jitter as the minute rolls over.
    readonly property var tabularFigures: ({ "tnum": 1, "lnum": 1 })

    // --- elevation ------------------------------------------------------------
    //
    // Two plates, not a blur. `MultiEffect` draws nothing on the offscreen
    // scenegraph (measured in `Widgets/Icon.qml`), so a shadow built from one is
    // a shadow that vanishes from half the pictures this surface is judged in —
    // and an elevation nobody can capture is one nobody can argue about. Two
    // flat translucent rectangles behind the card, one tight and one wide, are
    // what a key light and an ambient one come to at this size, and they cost a
    // rectangle each.
    //
    // Both are darker in the dark theme, which is the opposite of the instinct
    // and the right way round: the light theme's page is already bright enough
    // that a 10% plate reads, while a dark page swallows anything under 28%.
    readonly property color shadowKey: Qt.rgba(0, 0, 0, Theme.dark ? 0.28 : 0.10)
    readonly property color shadowAmbient: Qt.rgba(0, 0, 0, Theme.dark ? 0.36 : 0.14)

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
    /// And once more, for the same reason and off the same measurement. 0.55
    /// is 1.28:1 and reads as a pair *when you look for it*; the note that came
    /// back off the picture was that Saturday and Sunday were indistinguishable
    /// from a weekday, which is what a wash you have to look for means. 0.8 is
    /// 1.44:1 — still under the 1.6:1 at which a column starts reading as
    /// disabled rather than as quiet, and the first value that lands without
    /// being hunted for.
    ///
    /// The header carries a second, independent cue at the same time: a weekend
    /// numeral is `textSecondary` where a weekday's is `textPrimary`. Two weak
    /// signals that agree beat one strong one, and neither has to shout.
    readonly property color weekendWash: Theme.dark
        ? Qt.alpha(Theme.surfaceOverlay, 0.8)
        : Qt.alpha(Theme.bgSunken, 0.9)

    /// Today's column. A hue against a neutral rather than a lightness against
    /// a lightness, so one alpha works in both modes.
    /// 0.11 and not 0.05, because the weekend wash moved: measured off the
    /// capture, today at 0.05 was *dimmer* than a Saturday, which inverts the
    /// two signals. Today has to be at least as loud as the column it may
    /// itself be.
    /// 0.17 now, and it moves whenever the weekend wash does, because the one
    /// thing that must stay true is the *order*: today is louder than a
    /// weekend, a weekend is louder than a weekday. Measured off the capture at
    /// 0.11 against the stronger weekend wash, today came out 1.19:1 where
    /// Saturday was 1.28 — today reading as the quietest column on the grid,
    /// which is the signal exactly backwards.
    /// 0.24 now, and this time the measurement is of the *pair* rather than of
    /// either wash against the page. At 0.17 today came out rgb(28,45,44) and a
    /// weekend rgb(31,41,36): two different hues at 1.05:1 of each other, which
    /// is two colours doing one job — today was being carried entirely by the
    /// teal pill in its header, and the wash under it was decoration. 0.24 puts
    /// today at 1.23:1 over a weekend and 1.59:1 over a weekday, so the order
    /// the two signals are supposed to state — today loudest, weekend next,
    /// weekday quietest — is now a step you can see rather than one you can
    /// only compute.
    /// 0.30 now, and the measurement that moved it is a *value* one rather than
    /// a colour one. At 0.24 today came out rgb(35,58,57) against a weekend's
    /// rgb(31,42,36) — 1.23:1, which two hues can carry and one greyscale cannot:
    /// desaturate the capture and today and Saturday are the same wash, so a
    /// value-blind reader is left with the header pill alone. 0.30 is 1.42:1 over
    /// a weekend and 1.83:1 over a weekday, which survives the desaturation. The
    /// light alpha stays lower because there both washes move the same direction
    /// — down, off paper — and 0.30 of a dark teal on paper is a selection, not a
    /// wash.
    readonly property color todayWash:
        Qt.alpha(Theme.accentPrimary, Theme.dark ? 0.30 : 0.20)

    /// The mini-month's band — the run of days the grid beside it is showing.
    ///
    /// The spec said `surfaceOverlay`, and measured on the sidebar's own ground
    /// that is #1E2B26 on #141B17: a step of about 1.2:1, which at arm's length
    /// disappears entirely and leaves "which week am I in" carried by the 20px
    /// today dot alone. It is the same mistake the today column wash made
    /// before it moved to `todayWash`, and it takes the same fix — tint the
    /// ground toward the accent rather than lifting it toward grey, so the band
    /// gains hue as well as value and survives a desaturated read.
    ///
    /// The hairline is what stops it reading as a lit *cell* row: a filled
    /// stadium with a defined edge is a selection, an undrawn one is a smudge.
    ///
    /// **The hue is `borderStrong`, not the accent, and that is the second
    /// correction.** Tinting toward `accentPrimary` fixed the visibility and
    /// broke the reading: today's disc is solid `accentPrimary`, so a teal
    /// capsule around a teal disc merged into one blob and the week stopped
    /// saying *this week, and today is the marker inside it*. `borderStrong` is
    /// the palette's desaturated slate — a step of about 1.4:1 over the
    /// sidebar's ground, so it survives the same desaturated read the accent
    /// wash was chosen for, while leaving saturation to mean exactly one thing
    /// in this grid: today.
    readonly property color bandFill:
        Qt.alpha(Theme.borderStrong, Theme.dark ? 0.45 : 0.22)
    readonly property color bandBorder:
        Qt.alpha(Theme.borderStrong, Theme.dark ? 0.90 : 0.55)

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
    /// Text on fill, at **6:1 and not 4.5**, and the extra 1.5 is not headroom
    /// for its own sake. 4.5:1 is a threshold on two flat colours; a chip prints
    /// pt(9)–pt(12.5) type, antialiased, so every glyph's edge pixels are blends
    /// of ink and fill and the *measured* ratio off a capture comes in below the
    /// computed one — 4.56 computed read 4.3 on the picture, and the second line
    /// read 3.9. Solving at 6.0 puts the whole set over AA once the renderer has
    /// had its say, and the hues are still the hues: each ink keeps its hue and
    /// saturation and only its lightness moved.
    readonly property var textsDark: ["#bbdede", "#c7ddb9", "#e6d6c2", "#efd0c7",
                                      "#c3daed", "#d2dbbd", "#ddd5e8", "#d6d7d0"]

    readonly property var barsLight: ["#0c757b", "#4a7d35", "#8a5a2f", "#b0512f",
                                      "#23608f", "#59682c", "#6b4a8f", "#68695b"]
    readonly property var fillsLight: ["#bfd9d8", "#cad9c3", "#ded4c7", "#e6d1c5",
                                       "#c8d7df", "#d1d6c5", "#d8d2df", "#d5d6d0"]

    /// Light mode's text used to *be* its bar. It cannot be any more: the
    /// fills darkened to make a chip a shape, and the bar hues are now 3.3–4.7:1
    /// on them. These are the same inks stepped down until every one clears
    /// 4.6:1 — still recognisably the hue, which is what a colour-coded
    /// calendar is for.
    readonly property var textsLight: ["#085256", "#305224", "#664323", "#783821",
                                       "#1c4d74", "#434e21", "#593d77", "#4b4b41"]

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

    /// The guest monogram, **inverted out of the chip's own two colours**.
    ///
    /// It was the bar ink at 0.30 behind initials in the text ink, which is a
    /// pale letter on a tint of the same hue on a tint of the same hue: three
    /// values within a few steps of each other, and the capture came back with
    /// `JA BO WS` on olive reading as texture rather than as letters. The chip
    /// already owns a pair guaranteed to clear 4.5:1 in both modes — `text` on
    /// `fill` — so the monogram simply swaps them: the disc is the text ink and
    /// the letters are the fill. Same contrast, read the other way round, and
    /// the discs now also separate from the chip they sit in.
    function monogramFill(index: int): color {
        return tokens.text(index);
    }

    function monogramInk(index: int): color {
        return tokens.fill(index);
    }

    /// A chip under the pointer, lifted 12% toward the overlay — the same
    /// gesture every other hoverable surface in the shell makes, done in the
    /// chip's own hue rather than replacing it.
    function fillHover(index: int): color {
        return Qt.tint(tokens.fill(index), Qt.alpha(Theme.surfaceOverlay, 0.12));
    }
}
