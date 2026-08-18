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

    // --- motion ---------------------------------------------------------------
    //
    // Four durations and one distance, stated once here so no surface picks its
    // own. Every one of them is handed to `Theme.duration()` at the point of
    // use, which is what makes `appearance.reducedEffects` collapse the whole
    // window for free — there is no second reduce-motion knob on this surface
    // and there must not be one. Transforms are additionally guarded by
    // `Theme.animateTransforms`, so the ladder's middle rung keeps the fades and
    // drops the slides.

    /// A view or period change: 140ms, and an 8px slide in the travel direction
    /// (`KeyNavPolicy.viewSign` / `periodSign` decide the sign, not the surface).
    /// The slide is small on purpose — it has to say *which way* without ever
    /// making the reader wait for the grid to arrive.
    readonly property int motionView: 140
    readonly property int motionSlide: 8

    /// A chip settling from where the pointer left it to where the store put it:
    /// 160ms, position and size together. It is longer than the view change
    /// because it is the one motion whose *endpoint* is the information — a
    /// snap that arrives instantly is indistinguishable from a drag that never
    /// moved.
    readonly property int motionSettle: 160

    /// A popover arriving: 120ms, scale 0.96 → 1 with the fade. The shortest of
    /// the four, because it is the only one the reader is waiting on before
    /// they can type.
    readonly property int motionPopover: 120
    readonly property real popoverScaleFrom: 0.96

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
    /// The canvas itself is deliberately untouched by this. Every chip fill is
    /// a tint of `Theme.surface` (`HuePolicy.tintAlpha`), so moving the page
    /// would move sixteen colours with it; moving the furniture moves two
    /// rectangles.
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
    ///
    /// 0.52 and not 0.46. A saturated event chip is the brightest thing on this
    /// grid, and at 0.46 the ones flanking the card still read at full strength
    /// — the scrim measured as working (every pixel behind fell to 0.54 of
    /// itself) and still looked like none, because what a scrim has to beat is
    /// the loudest ink behind it, not the average. 0.52 puts a lamplight chip
    /// below the card's own fill, which is the test: nothing behind the modal
    /// should out-shout it.
    readonly property color scrimWash: Qt.rgba(0, 0, 0, Theme.dark ? 0.52 : 0.34)

    // --- the command menu -----------------------------------------------------

    /// The band under the command menu's selected row.
    ///
    /// **One accent hue per component**, and the first draft had two. The band
    /// was `Qt.tint(surfaceOverlay, Qt.alpha(accentPrimary, 0.18))` — the accent
    /// mixed into a grey that carries this palette's olive cast, which dragged
    /// the result to hue 167° while the rail two pixels to its left stayed at
    /// the accent's own 184°. Seventeen degrees apart on one row reads as two
    /// decisions rather than one mark: a green-teal band with a cyan bar on it.
    ///
    /// So the band is the accent's *own* hue at a different lightness — darker
    /// than the card in dark, paler in light — and the rail is the accent
    /// itself. Same hue, two steps, one idea.
    ///
    /// Measured on `surfaceRaised`: 1.60:1 dark, 1.46:1 light, both clear of the
    /// 1.4 floor a band has to beat to read as a band at all; `textPrimary` on
    /// it is 8.1:1 dark and 12.9:1 light, so the label loses nothing.
    readonly property color menuSelectFill: Theme.dark ? "#2c484a" : "#b0dee1"

    /// How far a Lucide glyph's ink sits inside its own box, in px, at the 18px
    /// size this surface draws row icons at.
    ///
    /// The set is drawn on a 24-unit grid with the artwork inset 3 units, so an
    /// icon box anchored to a margin lands its *ink* ~2px right of a letter
    /// anchored to the same margin. A menu whose magnifier, row icons, section
    /// headings and footer caps were all anchored at `space4` therefore had four
    /// left edges instead of one — measured at 10 device px of scatter, which is
    /// exactly the "no single left rail" a reader feels without being able to
    /// name. The glyphs give the 2px back; text and caps keep the margin.
    ///
    /// This only works because the icons are chosen to *share* an inset — see
    /// `KeyNavPolicy.commands`, where the chevrons (9 units in, 6.75px) were the
    /// outlier that produced the scatter in the first place.
    readonly property int glyphInk: 2

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

    // --- the drag's three colours -----------------------------------------------
    //
    // A mid-drag grid has to say three different things at once, and the first
    // pass said all three in the same register: the lifted chip wore the same
    // `fill(hue)` as a resting one (measured 1.18:1 against the column it was
    // over — no surface at all, so it read as *selected* rather than as
    // *carried*), the vacated slot wore a 0.09 wash that measured 1.02:1 and
    // vanished under its neighbours, and the target column wore a wash two
    // levels off `todayWash`, which is one token doing two jobs.
    //
    // So the three separate by *kind* and not by alpha. The thing in the hand
    // is solid; the thing left behind is an outline; the place it will land is
    // a stroked slot. None of them can be mistaken for the others at a glance,
    // and none of them is a wash.

    /// **The lifted chip: the resting chip, raised.** A dragged event is off the
    /// paper, and the first answer here was to paint it in the hue at full
    /// strength — `bar(hue)`, no tint, ink flipped to the far end of the ramp.
    ///
    /// Measured against the grid it sits on, that is not the same chip lifted;
    /// it is a different *kind* of object. Every resting chip on the surface is
    /// a dark tint carrying a 3px rail and light text, and a solid light-blue
    /// block with near-black ink on it reads as pasted in from another
    /// application — which is what a blind read of the drag capture called it.
    /// Identity is the one thing a move must not change: the whole gesture is
    /// an argument about *when*, and a card that changes what it looks like on
    /// the way across makes the reader check whether it is still the same
    /// event.
    ///
    /// So the lift keeps the chip's grammar and changes only its *level*: the
    /// same tint mixed on `surfaceRaised` instead of `surface`, at roughly
    /// twice the hue. That is a step of about 1.9:1 against the resting fill —
    /// plainly picked up, unmistakably the same event.
    function liftFill(index: int): color {
        return Qt.tint(Theme.surfaceRaised,
                       Qt.alpha(tokens.bar(index), Theme.dark ? 0.34 : 0.24));
    }

    /// The rail every resting chip wears, kept on the lifted one — it is the
    /// mark the eye matches the travelling card to its own row of neighbours by.
    function liftRail(index: int): color {
        return tokens.bar(index);
    }

    /// And its ink: the chip's own text colour rather than an inversion. The
    /// fill is a tint again, so the ramp that carries a resting chip's title
    /// carries this one at the same contrast.
    function liftText(index: int): color {
        return tokens.textFor(index, false);
    }

    /// The edge of a card held above the page. The hue itself, which only reads
    /// now that the fill beneath it is a tint rather than that same hue solid.
    function liftEdge(index: int): color {
        return Qt.alpha(tokens.bar(index), 0.55);
    }

    /// **The lift shadow, as a falloff rather than a plate.**
    ///
    /// It was three hard rectangles inset −10/−4/−1, and it photographed as
    /// exactly that: a square black slab sitting behind a rounded card with its
    /// corners disagreeing with the corners it was under, offset far enough to
    /// read as misregistration rather than as depth.
    ///
    /// The scene graph has no blur that survives an offscreen grab —
    /// `Widgets/Icon.qml` measured `MultiEffect` drawing nothing there — so the
    /// blur is stacked instead: six rings, each wider and fainter than the last
    /// and each offset *down* by a share of its own spread, so the falloff is
    /// heavier under the card than above it the way a lit one is. Composited
    /// they integrate to about `0 8px 24px rgba(0,0,0,.45)` at the core, and no
    /// single ring carries enough alpha to show an edge of its own.
    readonly property var liftShadow: [
        { spread: 20, drop: 12, alpha: 0.05 },
        { spread: 15, drop: 10, alpha: 0.06 },
        { spread: 11, drop: 8, alpha: 0.07 },
        { spread: 7, drop: 6, alpha: 0.09 },
        { spread: 4, drop: 4, alpha: 0.11 },
        { spread: 2, drop: 2, alpha: 0.13 }
    ]

    function liftShadowInk(alpha: real): color {
        return Qt.rgba(0, 0, 0, alpha);
    }

    /// Ink for the gutter stamp, which *is* a solid plate of `bar(hue)` and so
    /// still needs the far end of the ramp: the page in dark mode and
    /// white in light. The same inversion the today-disc already makes.
    ///
    /// Not `bgBase` in both. Dark mode's bars are light and `bgBase` clears
    /// 6.5:1 on the worst of the eight (ember). Light mode's bars are dark and
    /// its `bgBase` is a warm paper rather than white, which leaves moss at
    /// **4.31:1** — under the bar, and the one hue that fails is the one a
    /// spot check would not have been looking at. White carries the same eight
    /// at 4.91 and up, so light mode spends the extra half-step of glare and
    /// keeps the floor.
    readonly property color liftInk: Theme.dark ? Theme.bgBase : "#ffffff"

    /// **The vacated slot: an outline, not a fill.** 12% of the hue behind a
    /// dashed hairline of it. The fill alone was invisible the moment a
    /// cascaded neighbour was drawn over it; a dash survives, because a broken
    /// line is a mark the eye reads as a *hole* rather than as a surface, and
    /// the view draws it above the chips for the same reason.
    function vacatedFill(index: int): color {
        return Qt.alpha(tokens.bar(index), 0.12);
    }

    function vacatedEdge(index: int): color {
        return Qt.alpha(tokens.bar(index), 0.85);
    }

    /// The pixel under each dash. `liftInk` is the one colour on the surface
    /// guaranteed to separate from a full-strength hue, which is exactly what
    /// the dashes have to survive during a resize.
    readonly property color vacatedHalo: Qt.alpha(tokens.liftInk, 0.7)

    /// The dash: 4 on, 4 off at 1px, so a 56px hour of outline carries seven
    /// marks — enough to read as dashed at chip scale without turning a 20px
    /// minimum chip into a dotted smudge.
    readonly property int vacatedDash: 4

    /// **The target slot: a rounded stroke on the chip's own footprint.**
    /// Two pixels of the hue around the minute the drop will take, inset to the
    /// same lane a chip takes so it is visibly the outline the card is about to
    /// fill, with barely any fill of its own — the slot's job is to say *here*,
    /// and a filled one competes with the chip being carried into it.
    function targetEdge(index: int): color {
        return Qt.alpha(tokens.bar(index), 0.9);
    }

    function targetFill(index: int): color {
        return Qt.alpha(tokens.bar(index), 0.10);
    }

    /// **And the day, as a wash on the destination.**
    ///
    /// This was a 2px rail down the target column's leading edge, and a
    /// column's leading edge is where the grid draws its day separator: the
    /// rail landed exactly on the Tue/Wed rule and a blind read put the
    /// destination on the *wrong side* of it. A mark on a boundary names
    /// neither of the two things the boundary divides.
    ///
    /// A wash cannot be ambiguous that way — it has an area, and the area is
    /// the answer. The earlier objection was that a hue wash at 0.09 was inside
    /// two levels of `todayWash` and so said "today" instead; that is a
    /// *strength* problem, and it is fixed by spending more of the hue here
    /// than `todayWash` spends of the accent (0.05) rather than by giving up
    /// the area. With the slot outline inside it there are two marks on the
    /// destination and none anywhere else.
    function targetWash(index: int): color {
        return Qt.alpha(tokens.bar(index), 0.13);
    }

    /// The hair that ties the gutter stamp to the slot four columns away. Same
    /// device, and same argument, as the now-line's own connector: a number on
    /// the ruler and a box in the grid are one fact, and without a line between
    /// them the reader has to guess that.
    function targetConnector(index: int): color {
        return Qt.alpha(tokens.bar(index), 0.4);
    }

    /// **The gap between the lifted card and its slot.** Five, and it is doing
    /// the work of both marks: without it the ghost covers the outline exactly
    /// (the ghost is pinned to the snapped minute, so the two rectangles are
    /// the same rectangle) and the drop target has no visible existence at all.
    ///
    /// Five and not three because the ghost is also scaled 1.02 about its own
    /// centre, which spends about 1.6px of the gap on the long edge and 0.8 on
    /// the short one. Three would leave a hairline that photographs as a
    /// rendering seam; five leaves a gap that reads as air.
    readonly property int dragInset: 5

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

    /// The selected segment of the view switcher — **accent-tinted, not grey**.
    ///
    /// The switcher is the one control in this bar that answers a *question*
    /// (which scale am I in) rather than offering an action, and it answers it
    /// by lifting one tile. Two passes lifted it by value alone: `surfaceOverlay`
    /// first, then `surfaceOverlay` carried 14% toward `textPrimary`. Both were
    /// grey, and a grey tile lifted a step or two out of a grey bar is the exact
    /// shape this shell draws *hover* with everywhere else — so the capture read
    /// "the pointer is over Week", not "you are in Week". A selected state that
    /// is indistinguishable from a hover state is not a selected state.
    ///
    /// Lightness alone cannot fix that, because hover is also lightness. Hue
    /// can: the thumb takes 40% of `accentPrimary` over `surfaceOverlay`,
    /// landing near `#436b69` — 3.4:1 over the sunken track, so it still lifts,
    /// and unmistakably teal, so nothing else in the chrome reads that way.
    /// It stays a *tint* rather than the solid accent because `createFill` two
    /// controls left is the bar's one saturated field and this must not tie
    /// with it; state is quieter than action.
    ///
    /// Light mode reaches the same idea from the other side — a wash of teal
    /// over white, edged in the accent, because two pale tiles a lightness step
    /// apart on paper is the same unreadable pair dark mode had.
    readonly property color switcherThumb: Theme.dark
        ? Qt.tint(Theme.surfaceOverlay, Qt.alpha(Theme.accentPrimary, 0.40))
        : Qt.tint(Theme.surfaceRaised, Qt.alpha(Theme.accentPrimary, 0.20))

    /// The hairline around that thumb. Dark gets none — the hue is the edge —
    /// and light gets the accent at 0.35, which is what makes a pale wash on
    /// paper a tile rather than a smudge.
    readonly property color switcherEdge: Qt.alpha(Theme.accentPrimary, Theme.dark ? 0 : 0.35)

    /// Ink on that thumb: `textPrimary` in both modes, measured at 4.9:1 dark
    /// and 12:1 light. The resting segments stay `textMuted`, so the control
    /// now differs in hue, value and weight at once.
    readonly property color switcherInk: Theme.textPrimary

    /// A menu that opens *inside* a panel — the guest picker's results list.
    ///
    /// It was `bgSunken`, which is the darkest plane in the window, and that is
    /// elevation pointing the wrong way: a list that opens over the panel it
    /// belongs to is *above* it, and drawing it below made the panel look like
    /// it had a hole cut in it. Every other menu in this shell lifts.
    ///
    /// Dark takes `surfaceOverlay`, one rung above the `surfaceRaised` panel it
    /// sits on. Light cannot go up from white, so it stays on the panel's own
    /// plane and lets the shadow do the whole job — which is the same way a
    /// white menu over a white card reads anywhere.
    readonly property color dropdownFill: Theme.dark ? Theme.surfaceOverlay : Theme.surfaceRaised

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
    readonly property var barsDark: ["#6fbec4", "#8fbf6a", "#d8ac81", "#e07a5f",
                                     "#5b9dd9", "#afbd7a", "#b295cf", "#9d9e8d"]

    /// **The fills are computed, not written out, and that is the correction.**
    /// An earlier pass hand-solved two eight-entry hex tables so a chip would
    /// clear 2.2:1 against the page — a chip is an object, an object needs an
    /// edge, and at the spec's tint the fill alone was 1.5:1. The edge was the
    /// right diagnosis and the fill was the wrong place to put it: eight
    /// hand-solved values are eight values that drift, and the week's tint and
    /// the month's had already stopped agreeing by the time anybody compared
    /// them side by side.
    ///
    /// So the edge moved to where an edge belongs — the 3px bar down the chip's
    /// left and the 1px hue hairline around it (`chipBorder`, 0.28 dark) — and
    /// the fill went back to being a tint: `HuePolicy.tintAlpha` over
    /// `Theme.surface`, one number, tested next door, read by the week band,
    /// the grid chip, the month chip and the drag ghost alike. At 0.16 dark and
    /// 0.12 light the eight land on the design spec's fill table exactly, and
    /// every ink below clears 7:1 on its fill rather than the 6 they were
    /// solved at, because a weaker fill only ever helps the text on it.
    readonly property real tintAlpha: tokens.hues.tintAlpha(Theme.dark)

    function tintOf(hue: string): color {
        return tokens.hues.tint(hue, String(Theme.surface), tokens.tintAlpha);
    }

    /// Text on fill, at **6:1 and not 4.5**, and the extra 1.5 is not headroom
    /// for its own sake. 4.5:1 is a threshold on two flat colours; a chip prints
    /// pt(9)–pt(12.5) type, antialiased, so every glyph's edge pixels are blends
    /// of ink and fill and the *measured* ratio off a capture comes in below the
    /// computed one — 4.56 computed read 4.3 on the picture, and the second line
    /// read 3.9. Solved at 6.0 against the old heavy fills, these inks land at
    /// 8.9–9.6:1 on the tinted ones, which is the direction a weaker fill moves
    /// the only ratio that matters here.
    readonly property var textsDark: ["#bbdede", "#c7ddb9", "#e6d6c2", "#efd0c7",
                                      "#c3daed", "#d2dbbd", "#ddd5e8", "#d6d7d0"]

    readonly property var barsLight: ["#0c757b", "#4a7d35", "#8a5a2f", "#b0512f",
                                      "#23608f", "#59682c", "#6b4a8f", "#68695b"]
    /// Light mode's text used to *be* its bar. It cannot be any more: the
    /// fills darkened to make a chip a shape, and the bar hues are now 3.3–4.7:1
    /// on them. These are the same inks stepped down until every one clears
    /// 4.6:1 — still recognisably the hue, which is what a colour-coded
    /// calendar is for.
    readonly property var textsLight: ["#085256", "#305224", "#664323", "#783821",
                                       "#1c4d74", "#434e21", "#593d77", "#4b4b41"]

    readonly property var bars: Theme.dark ? tokens.barsDark : tokens.barsLight
    readonly property var fills: tokens.bars.map(hue => tokens.tintOf(hue))
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

    // --- the same three, once the clock is in the room --------------------------
    //
    // `HuePolicy` decides *whether* an event is past and *how far down* a past
    // one goes; this is where those three numbers meet a Theme. Every one of
    // these is the plain colour above when `past` is false, so a caller that
    // does not know about the clock — the month chip, the drag ghost, the
    // quick-create swatches — keeps exactly the picture it had.

    readonly property real pastTintAlpha: tokens.hues.pastTintAlpha(Theme.dark)
    readonly property real pastInkStrength: tokens.hues.pastInkStrength(Theme.dark)

    /// The eight fills again at the past alpha — computed the same way and from
    /// the same one number, so the two strengths cannot drift apart the way two
    /// hand-written tables did.
    readonly property var pastFills: tokens.bars.map(
        hue => tokens.hues.tint(hue, String(Theme.surface), tokens.pastTintAlpha))

    readonly property var pastBars: tokens.bars.map(
        hue => tokens.hues.tint(hue, String(Theme.surface),
                                tokens.hues.pastBarStrength))

    readonly property var pastTexts: tokens.texts.map(
        (ink, i) => tokens.hues.tint(String(ink), String(tokens.pastFills[i]),
                                     tokens.pastInkStrength))

    function barFor(index: int, past: bool): color {
        const i = tokens.wrap(index);
        return past === true ? tokens.pastBars[i] : tokens.bars[i];
    }

    function fillFor(index: int, past: bool): color {
        const i = tokens.wrap(index);
        return past === true ? tokens.pastFills[i] : tokens.fills[i];
    }

    function textFor(index: int, past: bool): color {
        const i = tokens.wrap(index);
        return past === true ? tokens.pastTexts[i] : tokens.texts[i];
    }

    /// A past chip's hairline is drawn off its own quieted bar, so the edge
    /// recedes with the rest of it rather than outlining a faded card in a live
    /// colour — which is what an unchanged border did on the first capture, and
    /// it made the past chips read as *selected*.
    function chipBorderFor(index: int, past: bool): color {
        return Qt.alpha(tokens.barFor(index, past), Theme.dark ? 0.28 : 0.22);
    }

    function fillHoverFor(index: int, past: bool): color {
        return Qt.tint(tokens.fillFor(index, past),
                       Qt.alpha(Theme.surfaceOverlay, 0.12));
    }

    function monogramFillFor(index: int, past: bool): color {
        return tokens.textFor(index, past);
    }

    function monogramInkFor(index: int, past: bool): color {
        return tokens.fillFor(index, past);
    }

    // --- neutral furniture ------------------------------------------------------
    //
    // The gutter's hours, the weekday caps and the band's own label are
    // *rulings*, not content, and they are drawn in the palette's greens
    // desaturated onto their own luminance grey by `HuePolicy.neutralise`. The
    // ratio each one held is unchanged — that is the property the mix is built
    // around and the property the test asserts — so this is a hue change and
    // never a contrast one. See `HuePolicy.neutralise` for why the chrome gives
    // up the forest and the content keeps it.
    //
    // 0.75 rather than 1.0: at a full mix the gutter is a dead grey pasted onto
    // a green page and reads as a different application's furniture. Three
    // quarters lands it neutral to the eye while a trace of the page's own
    // warmth stays in it, which is what makes the grid look built rather than
    // imported.
    readonly property real gridNeutrality: 0.75

    readonly property color gridMuted: tokens.hues.neutralise(
        String(Theme.textMuted), tokens.gridNeutrality)
    readonly property color gridSecondary: tokens.hues.neutralise(
        String(Theme.textSecondary), tokens.gridNeutrality)

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
