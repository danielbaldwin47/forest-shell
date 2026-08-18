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
    ///
    /// **The sidebar's width is arithmetic, not taste.** It was 248, which does
    /// not divide by seven, so the mini-month — the widest block in the column
    /// and the thing every other left edge is squared against — was centred on
    /// a 5px remainder and started 3px right of the labels hung from the same
    /// inset. Three left edges in one column, which is what a reader counts
    /// before they can say why the column looks slipped.
    ///
    /// So the column is sized to hold the map exactly: seven `miniDayW` cells,
    /// one `sidebarPad` either side, and the hairline that closes the panel.
    /// Every left edge in the sidebar is then `sidebarPad` by construction and
    /// the map's two facing margins are equal without anything being centred.
    readonly property int miniDayW: 30
    readonly property int sidebarPad: 19
    readonly property int sidebarW: 7 * tokens.miniDayW + tokens.sidebarPad * 2 + 1
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

    // --- the two planes -------------------------------------------------------

    /// The chrome: the sidebar down the left and the toolbar across the top,
    /// one L-shaped plane around `Theme.bgBase`, which is the canvas the grid
    /// is drawn on.
    ///
    /// **This is the window's structure, and for four rounds hairlines were
    /// carrying all of it.** The sidebar was `Theme.surface` (`#141b17`) beside
    /// a `bgBase` canvas (`#0b100d`) under a `bgBase` toolbar — measured off
    /// the capture, three zones inside 4% of each other, so the only thing
    /// saying *panel here, page there* was a 1px rule. A window whose zones can
    /// only be told apart by their borders does not read as a sidebar next to a
    /// canvas; it reads as one flat plane with lines ruled on it.
    ///
    /// So the chrome takes a step the eye can measure without a side-by-side:
    /// `surfaceRaised` is 8 points of L* over the canvas where `surface` was 4,
    /// and the direction is the one every dark interface uses — the document is
    /// the deepest thing on screen and the furniture floats over it. In light
    /// the direction inverts, because paper is already near the ceiling: the
    /// chrome sinks past `bgSunken` toward `borderStrong`'s slate, which is the
    /// same 8-10 points measured downward.
    ///
    /// The canvas itself is deliberately untouched by this. Every chip fill in
    /// the table below is solved for ≥2.2:1 against `bgBase`, so moving the
    /// page would move forty-eight colours with it; moving the furniture moves
    /// two rectangles.
    readonly property color chromeGround: Theme.dark
        ? Theme.surfaceRaised
        : Qt.tint(Theme.bgSunken, Qt.alpha(Theme.borderStrong, 0.20))

    /// A row or a button under the pointer *on that plane*.
    ///
    /// `Theme.surfaceOverlay` is the shell's hover and it stops working here
    /// the moment the chrome lifts: overlay is one step above `surfaceRaised`,
    /// which the chrome now is, so every hover in the sidebar and the toolbar
    /// became a wash nobody can see. A hover is a difference from its own
    /// ground, so it is stated as one rather than borrowed from a ladder whose
    /// rungs this plane has already climbed.
    readonly property color chromeHover: Theme.dark
        ? Qt.tint(Theme.surfaceOverlay, Qt.alpha(Theme.textPrimary, 0.07))
        : Qt.darker(tokens.chromeGround, 1.06)

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

    /// The wash a modal puts over the grid behind it — the command menu and the
    /// shortcuts sheet.
    ///
    /// **Not** `Theme.fogWash` at `fogWashOpacity`, which is the shell's scrim
    /// for a *desktop*: 10% of a pale mist, which reads as haze over a
    /// photograph and, measured on this surface, as nothing at all over a dark
    /// grid — the first capture of the command menu had a card apparently
    /// floating on an undimmed calendar. A modal over a document has to push
    /// the document back, and the only ink that does that in both themes is
    /// black. Light needs less of it because its page has further to fall.
    readonly property color scrimWash: Qt.rgba(0, 0, 0, Theme.dark ? 0.46 : 0.28)

    // --- the column washes ----------------------------------------------------

    /// The weekend column's wash, and **the one place this file departs from
    /// DESIGN-SPEC.md's literal value.**
    ///
    /// The spec says `Theme.bgSunken` at 0.5, and in light mode that is exactly
    /// right: `bgSunken` sits a 1.12:1 step under paper, so half of it is a
    /// wash you can see without looking at it.
    ///
    /// In dark mode you cannot sink below a canvas that is already `#0b100d`,
    /// so the dark wash *lifts* — but only barely, and that limit is the
    /// correction this pass makes. Four rounds of measurement chased visibility
    /// upward (`surface` 0.45 → `surfaceOverlay` 0.55 → 0.8) and each step
    /// bought the weekend legibility by making the *canvas* lighter than the
    /// `Theme.surface` sidebar beside it. That inverts the surface hierarchy of
    /// the whole shell: a panel is raised above a canvas, and a grid whose
    /// quietest columns outrank the panel reads as two windows, not one.
    ///
    /// So the ceiling is the chrome: **no wash on this grid may be lighter than
    /// `chromeGround`.** That ceiling used to be `Theme.surface` and it sat 4
    /// points of L* over the canvas, which left the washes fighting for two of
    /// them; now that the chrome has stepped up to 13.6 there are eight points
    /// of room under it, and the weekend can take a share of them. `surface` at
    /// 0.55 composites to L* 7.7 against a weekday's 5.3 — a lift you can see
    /// without hunting for it and still plainly below the panel beside it, with
    /// the header's second cue (a weekend numeral is `textSecondary` where a
    /// weekday's is `textPrimary`) agreeing with it.
    readonly property color weekendWash: Theme.dark
        ? Qt.alpha(Theme.surface, 0.55)
        : Qt.alpha(Theme.bgSunken, 0.5)

    /// Today's column. A hue against a neutral rather than a lightness against
    /// a lightness, so one alpha works in both modes.
    ///
    /// **0.10, which is the number the room allows rather than the number the
    /// weekend forced.** Each earlier rise (0.11 → 0.17 → 0.24 → 0.30) was
    /// answering a weekend wash that was itself too loud, and 0.30 of teal
    /// landed at rgb(41,68,68) — lighter than the sidebar and saturated enough
    /// to compete with the chips over it. The retreat to the spec's 0.05 fixed
    /// the order and cost the column its visibility, because the ceiling then
    /// was `Theme.surface`, four points of L* over the page.
    ///
    /// With the chrome lifted to `chromeGround` the ladder has somewhere to
    /// stand: today composites to L* 11.5 over a weekend's 7.7 and a weekday's
    /// 5.3, all three under the chrome's 13.6. Today keeps the hue, which is
    /// what makes it findable at a glance; the *marker* for today is the filled
    /// disc in the column header, and a wash's job is to point at that rather
    /// than to replace it.
    readonly property color todayWash: Qt.alpha(Theme.accentPrimary, 0.10)

    /// The mini-month's band — the run of days the grid beside it is showing.
    ///
    /// The spec said `surfaceOverlay`, and measured on the sidebar's own ground
    /// that is #243029 on #1c2621: a step of about 1.14:1, which at arm's length
    /// disappears entirely and leaves "which week am I in" carried by the 20px
    /// today dot alone. It is the same mistake the today column wash made
    /// before it moved to `todayWash`, and it takes the same fix — tint the
    /// ground toward the accent rather than lifting it toward grey, so the band
    /// gains hue as well as value and survives a desaturated read.
    ///
    /// **One value, not a fill plus a stroke of nearly the same value.** The
    /// band carried both for a round, on the argument that an edge is what
    /// stops a wash reading as a smudge. At 0.45 fill under a 0.90 hairline of
    /// the *same* hue the edge was a sixteenth of the capsule's area doing a
    /// job the fill could do by being one step louder — visible only as
    /// fussiness, a stadium drawn twice. So the stroke is gone and the fill
    /// carries it at 0.55, which is the same total ink with one edge instead of
    /// two.
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
        Qt.alpha(Theme.borderStrong, Theme.dark ? 0.55 : 0.28)

    // --- the toolbar's three ranks ---------------------------------------------

    /// The selected segment of the view switcher.
    ///
    /// The switcher is the one control in this bar that answers a *question*
    /// (which scale am I in) rather than offering an action, and it answers it
    /// by lifting one tile. That only works if the tile is plainly the lightest
    /// thing in the bar: at `surfaceOverlay` it was two steps over the resting
    /// buttons beside it, close enough that a glance read the whole switcher as
    /// unselected — three labels in a box.
    ///
    /// So the thumb is taken past every other surface in the window rather than
    /// borrowed from the ladder: `surfaceOverlay` carried 14% of the way to
    /// `textPrimary` lands at about #3f4a43 in dark, five steps clear of the
    /// `bgSunken` track under it and two clear of `chromeGround`, which is the
    /// plane the whole bar rests on. In light the roles are already the right
    /// way round, so the thumb is simply `surfaceRaised` (white) in a sunken
    /// track.
    readonly property color switcherThumb: Theme.dark
        ? Qt.tint(Theme.surfaceOverlay, Qt.alpha(Theme.textPrimary, 0.14))
        : Theme.surfaceRaised

    /// The create button's field and the glyph on it — the one coloured fill
    /// in the chrome.
    ///
    /// It was `accentPrimary`, and measured off the capture that made it the
    /// loudest object in the window: 900px² of `#6fbec4` in a bar that holds
    /// nothing else saturated, while the chevrons beside it — pressed ten times
    /// as often and undone by each other — had no drawn box at all. Weight
    /// should follow how often a hand reaches for a thing, and that ordering
    /// was upside down at both ends.
    ///
    /// `accentDeep` is the same teal at the bottom of its range: still the only
    /// coloured field in the chrome and still the only control here that
    /// *makes* something, no longer brighter than the day it points at. Light
    /// mode reaches the same ink from the other side — its `accentPrimary` is
    /// that deep teal, and its `accentDeep` is a pale wash no glyph survives.
    readonly property color createFill: Theme.dark ? Theme.accentDeep : Theme.accentPrimary
    readonly property color createInk: Theme.dark ? Theme.textPrimary : Theme.bgBase

    /// Hover for that field: brighter than its rest state, which is a direction
    /// rather than a value — the deep teal sits on opposite sides of its ground
    /// in the two modes.
    readonly property color accentHover: Theme.dark
        ? Qt.lighter(tokens.createFill, 1.25)
        : Qt.darker(tokens.createFill, 1.12)

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

    /// The point size for initials inside a disc `d` across.
    ///
    /// Two glyphs, so the type has to clear roughly 0.42 of the disc before the
    /// pair reads as letters rather than as texture — measured on the chip,
    /// where 8.5pt inside 18px came back unreadable and 9.5 did not. Hence the
    /// floor: below about 20px the ratio would ask for less type than any disc
    /// can carry, so the floor wins and the disc simply gets fuller.
    ///
    /// Half-point steps, because `Theme.pt` scales whatever it is handed and a
    /// third of a point of difference between two avatar sizes is noise nobody
    /// asked for.
    function monogramPt(d: real): real {
        return Math.max(9.5, Math.round(d * 0.42 * 2) / 2);
    }

    /// A chip under the pointer, lifted 12% toward the overlay — the same
    /// gesture every other hoverable surface in the shell makes, done in the
    /// chip's own hue rather than replacing it.
    function fillHover(index: int): color {
        return Qt.tint(tokens.fill(index), Qt.alpha(Theme.surfaceOverlay, 0.12));
    }
}
