// The bar across the top of the calendar: what you are looking at, on the
// left; how to move and what to look at, on the right.
//
// ## No separate month band
//
// Notion spends 44px on a row that says nothing but the month, above a toolbar
// that had room for it. Folding the title into the toolbar gives those pixels
// to the grid — most of an hour row on a 760px window — and costs nothing,
// because the title and the controls never come close to meeting at any width
// this window can be dragged to.
//
// ## The switcher is segmented, not a dropdown
//
// Day/Week/Month is three options that never grows a fourth, and it is the
// control on this surface reached most often. Notion puts it behind a dropdown:
// two clicks and a menu that covers the grid you are trying to compare against.
// Segmented, it is one click and nothing moves.
//
// ## Moving and looking are two different clusters
//
// The chevrons and Today move the *period*; the switcher changes the *scale*.
// Those are different questions, so they sit at different ends of the bar —
// and the moving ones sit beside the title, because the title is what they
// change. Notion puts its chevrons next to the title for the same reason; a
// pair of arrows parked at the far right is a control whose effect happens
// 900px away from it.
//
// ## Four controls, four ranks — the bar's one hierarchy
//
// A pass of this bar dressed every control the same: the create button, Today,
// both chevrons and the selected segment of the switcher were one dark chip
// with one hairline, at four sizes. Read at a glance that is a row of five
// identical objects, so nothing in it is primary, nothing is quiet, and the
// switcher — whose whole job is to say *this one* — read as unselected.
//
// Sameness was the wrong answer to a real question. The controls do not do the
// same kind of thing, so they are drawn at the rank they hold:
//
// - **The period cluster is a well with three tiles in it** — `‹ Today ›`, on
//   the switcher's own sunken track. It holds the most-pressed controls in the
//   window, so it is the one that must have a visible edge to press inside of;
//   an earlier pass left the chevrons as bare glyphs on the argument that a box
//   around each of a pair says what the glyphs already say, and the capture
//   answered that a pair with no box says nothing at all until the pointer
//   finds it. Grouped, they cannot be mistaken for the mini-month's steppers
//   300px away either — that pair is 24px, unboxed and dimmer, which is the
//   rank a map's controls hold against a grid's.
// - **The switcher is the same well with a lifted tile in it**, and the tile is
//   the lightest surface in the window (`CalendarTokens.switcherThumb`), which
//   is the property that has to hold for a segmented control to have a state at
//   all. Two wells on one bar is a rhyme, not a repetition: they are the same
//   kind of question — which period, which scale — asked twice.
// - **Create is the one coloured field, and it is the deep teal rather than the
//   bright one.** It is the only control here that *makes* something, so it
//   keeps hue where everything else has value; it stopped being the brightest
//   object in a window it is pressed in once an hour. `CalendarTokens.
//   createFill` carries that measurement.
//
// ## Today is a button that knows when it is pointless
//
// It stops taking clicks when today is already on screen. Notion leaves it
// live, which teaches the hand to press a button that does nothing — and a
// control that sometimes does nothing is worse than one that visibly has
// nowhere to go.
//
// **How it rests is measured, not chosen.** An earlier pass faded the whole
// button to `Theme.opacityInert`, which is what the spec asks for and what the
// picture proved wrong: 0.4 of `textPrimary` over the raised fill lands at
// `#707364` on a `#0b100d` bar — **3.9:1**, under AA, and dimmer than the
// chevron glyphs either side of it. The most-used action in the bar read as
// broken rather than as resting, which is the opposite of the point.
//
// So the rank difference lives in the *label* and the label alone: the tile
// keeps its place in the cluster, while the label steps from `textPrimary`
// when the button is live down to `textMuted` when it is not. `textMuted` and
// not `textSecondary`, because a resting Today anywhere near the value of the
// chevrons either side of it is a button that never looks inert, which is the
// whole claim. `textMuted` is 5.6:1 — plainly a step below the glyphs it sits
// between, still comfortably readable, and not the 3.9:1 `opacityInert` was.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Widgets

Item {
    id: toolbar

    /// `day`, `week` or `month`.
    property string view: "week"

    /// The day the view is built around, and today, so the Today button can
    /// tell whether it has anywhere to go.
    property string anchorDate: ""
    property string todayIso: ""

    property int firstDay: 1

    property CalendarFormat format: CalendarFormat {}

    /// The verbs. `CalendarWindow` owns what they do — this file owns only
    /// where you press to ask for them.
    signal viewRequested(string name)
    signal stepRequested(int delta)
    signal todayRequested
    signal createRequested

    /// The views, left to right. The same array `CalendarWindow.views` holds,
    /// but stated here in *display* order rather than borrowed: the singleton's
    /// list is what IPC will accept, and the day one arrives out of order is
    /// not the day this control should reorder itself.
    readonly property var segments: ["day", "week", "month"]

    /// Whether the current period already contains today. Whole-period rather
    /// than same-day, because in a week view "today" is the week you are in —
    /// a live Today button on the week that already shows today is the dead
    /// button this control exists to avoid.
    readonly property bool showsToday: {
        if (!toolbar.todayIso || !toolbar.anchorDate)
            return false;
        if (toolbar.view === "day")
            return toolbar.anchorDate === toolbar.todayIso;
        if (toolbar.view === "week") {
            const time = toolbar.format.time;
            return time.weekStart(toolbar.anchorDate, toolbar.firstDay)
                === time.weekStart(toolbar.todayIso, toolbar.firstDay);
        }
        return toolbar.anchorDate.slice(0, 7) === toolbar.todayIso.slice(0, 7);
    }

    readonly property var titleParts:
        toolbar.format.titleParts(toolbar.view, toolbar.anchorDate, toolbar.firstDay)

    implicitHeight: CalendarTokens.toolbarH

    Rectangle {
        anchors.fill: parent
        // The chrome plane, shared with the sidebar — see
        // `CalendarTokens.chromeGround` for why the bar is no longer the same
        // value as the grid under it.
        color: CalendarTokens.chromeGround

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.borderSubtle
        }
    }

    // --- the title ------------------------------------------------------------

    /// Two faces on one baseline, which a `Row` cannot do: a positioner aligns
    /// tops, and Newsreader's ascent is not Plex's, so a top-aligned pair sits
    /// visibly astride two different lines. Anchored to the toolbar directly —
    /// a wrapper `Item` sized from its own children's `implicitWidth` is a
    /// binding loop, and the loop QML breaks leaves the year drawn at x=0 on
    /// top of the month.
    Text {
        id: leadText

        anchors.left: parent.left
        anchors.leftMargin: Theme.space4
        // Baseline rather than centre — `CalendarTokens.titleBaseline` says why
        // the two headings in this band cannot both be centred.
        y: CalendarTokens.titleBaseline - leadText.baselineOffset
        text: toolbar.titleParts.lead
        color: Theme.textPrimary
        font.family: Theme.fontDisplay
        font.pointSize: Theme.pt(20)
        font.weight: Theme.weightDisplay
    }

    /// The year. It was `textMuted`, three steps down from the month beside it,
    /// which read as a stray token rather than as part of the title;
    /// `textSecondary` keeps it subordinate without detaching it.
    ///
    /// One word space, and only one. An earlier pass gave the week title
    /// `space2` on the argument that "22" and "2026" would otherwise run
    /// together — true of "Aug 16 – 22 2026", which is not a string anything
    /// should have been setting: `CalendarFormat.titleParts` now leaves the
    /// comma on the lead, so the pair reads "Aug 16 – 22," + "2026" and wants
    /// exactly the gap any comma wants. The doubled space that fix replaced was
    /// the visible half of the missing punctuation.
    ///
    /// The `space2` branch survives for a lead that ends in a bare numeral,
    /// which no current format produces and the next one might.
    Text {
        id: yearText

        anchors.left: leadText.right
        anchors.leftMargin: /[0-9]$/.test(toolbar.titleParts.lead) ? Theme.space2 : Theme.space1
        anchors.baseline: leadText.baseline
        text: toolbar.titleParts.year
        color: Theme.textSecondary
        font.family: Theme.fontUi
        font.pointSize: Theme.pt(20)
        font.weight: Theme.weightRegular
    }

    // --- the controls ---------------------------------------------------------

    /// The moving controls, beside the title they move. `space4` after the
    /// year — the same inset the title takes from the left edge and the
    /// switcher takes from the right — so the bar reads as three groups on one
    /// rhythm rather than as a title with an argument next to it.
    /// **The moving controls are one segmented cluster, not three loose
    /// objects.** They were a bare pair of chevrons and an outlined Today, and
    /// the capture said what that costs: the chevrons had no drawn hit area at
    /// all and Today's box was a hairline on a bar of nearly its own value, so
    /// the two most-pressed controls in the window were also its faintest,
    /// while the create button — one press an hour — was its loudest. Weight
    /// should follow how often a hand reaches for a thing.
    ///
    /// A well with three tiles in it fixes both ends at once. The cluster is
    /// the same sunken track the switcher uses, which is now plainly readable
    /// against the lifted chrome, and it says the three controls are one
    /// question — *which period* — the way the switcher says its three are the
    /// scale. `‹ Today ›` and not `‹ › Today`: the destination belongs between
    /// the two steps that walk past it, and the hairlines between the tiles are
    /// what give each glyph an edge to be pressed inside of.
    Rectangle {
        id: nav

        anchors.left: yearText.right
        // `space4` after the year — the same inset the title takes from the
        // left edge and the switcher takes from the right — so the bar reads as
        // three groups on one rhythm rather than as a title with an argument
        // next to it.
        anchors.leftMargin: Theme.space4
        anchors.verticalCenter: parent.verticalCenter

        width: navRow.width
        height: CalendarTokens.controlH
        radius: Theme.radiusSm
        color: Theme.bgSunken
        border.width: 1
        border.color: Theme.borderSubtle
        // The tiles are square-cornered inside a rounded well, so the two at
        // the ends have to be cut to it.
        clip: true

        Row {
            id: navRow

            height: parent.height

            IconButton {
                glyph: "chevron-left"
                glyphColor: Theme.textPrimary
                onTapped: toolbar.stepRequested(-1)
            }

            NavRule {}

            /// Today, as the middle tile. See the header for why the label
            /// carries the rank rather than the button's opacity.
            Rectangle {
                id: todayButton

                readonly property bool live: !toolbar.showsToday

                width: todayLabel.implicitWidth + Theme.space3 * 2
                height: CalendarTokens.controlH
                color: todayPointer.containsMouse && todayButton.live
                       ? CalendarTokens.chromeHover
                       : "transparent"

                Behavior on color {
                    enabled: Theme.animateTransforms
                    ColorAnimation { duration: Theme.duration(Theme.motionFast) }
                }

                Text {
                    id: todayLabel

                    anchors.centerIn: parent
                    text: "Today"
                    color: todayButton.live ? Theme.textPrimary : Theme.textMuted
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(12.5)
                    font.weight: Theme.weightMedium

                    Behavior on color {
                        enabled: Theme.animateTransforms
                        ColorAnimation { duration: Theme.duration(Theme.motionFast) }
                    }
                }

                MouseArea {
                    id: todayPointer

                    anchors.fill: parent
                    enabled: todayButton.live
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toolbar.todayRequested()
                }
            }

            NavRule {}

            IconButton {
                glyph: "chevron-right"
                glyphColor: Theme.textPrimary
                onTapped: toolbar.stepRequested(1)
            }
        }
    }

    // --- making one ------------------------------------------------------------

    /// New event. It used to sit at the top of the sidebar, above a wordmark,
    /// which put the window's one *creating* control in the column that holds
    /// its two *filtering* lists — and left the mini-month's month heading with
    /// nowhere to sit but below the chrome band, off the toolbar title's
    /// baseline. Moving it here fixes both: the sidebar band becomes the map's
    /// heading, and every control in this window now lives on one bar.
    ///
    /// It rides beside the switcher rather than past it, so the switcher keeps
    /// the `space4` right inset that answers the title's left one.
    ///
    /// **Filled, not outlined.** An earlier pass gave it accent *strokes* in a
    /// box identical to Today's, on the argument that an accent field would be
    /// the loudest area in the window. It would not: 900 square pixels of teal
    /// against a 1180x760 window is a full stop, not a shout, and it is the
    /// only mark in the chrome that says where the one creating action is.
    /// Every other use of saturation on this surface belongs to an event's hue
    /// or to today, and neither of those lives in the toolbar, so nothing here
    /// is competing with it.
    IconButton {
        id: createButton

        // **24px clear of the switcher, not 12.** The two sat a `space3` apart
        // and read as one four-tile cluster — a teal square that looked like a
        // fourth segment of a control it has nothing to do with. `space6` (24)
        // is the gap this bar already uses between unrelated groups, and it is
        // the smallest one at which the capture stops grouping them.
        anchors.right: switcher.left
        anchors.rightMargin: Theme.space6
        anchors.verticalCenter: parent.verticalCenter
        glyph: "plus"
        glyphColor: CalendarTokens.createInk
        restFill: CalendarTokens.createFill
        hoverFill: CalendarTokens.accentHover
        onTapped: toolbar.createRequested()
    }

    // --- the scale ------------------------------------------------------------

    /// The view switcher. The thumb is one item that slides, not three that
    /// fade: a moving thumb says the three segments are one control, which
    /// is the whole reason to use a segmented switch instead of three
    /// buttons.
    ///
    /// **The track is darker than the thumb, which is the reverse of the
    /// spec, because the spec named tokens rather than values.** It asked for
    /// a `surfaceOverlay` track under a `surfaceRaised` thumb — and in the
    /// dark palette `surfaceOverlay` is `#243029` while `surfaceRaised` is
    /// `#1c2621`, so the selected segment was drawn *darker than its own
    /// track*: a hole where the picture needed a raised tile, wearing the same
    /// fill-plus-hairline as the resting Today and chevron buttons beside it.
    /// Selection and rest were the same treatment, which leaves the control
    /// with no state at all.
    ///
    /// So the roles are taken by value: the track is `bgSunken` (`#070a08`, a
    /// well sunk through the chrome plane) and the thumb is `CalendarTokens.
    /// switcherThumb`, which is taken past the top of the surface ladder rather
    /// than borrowed from it. `surfaceOverlay` was the first fix and only half
    /// of one — two steps over the track is a tile you can find once you are
    /// looking for it, and this control is read at a glance or not at all. The
    /// selected segment is now the lightest thing in the window, which is the
    /// only property that has to hold: a segmented control says "this one" by
    /// lifting it, and lifting is a lightness, not a token name.
    Rectangle {
        id: switcher

        anchors.right: parent.right
        anchors.rightMargin: Theme.space4
        anchors.verticalCenter: parent.verticalCenter

        width: switcher.segmentW * toolbar.segments.length + switcher.inset * 2
        height: CalendarTokens.controlH
        radius: Theme.radiusSm
        // The well, not the raised thing. See the header: `surfaceOverlay` is
        // the *lighter* of the two, so the spec's track/thumb pairing drew the
        // selected segment as a hole.
        color: Theme.bgSunken
        border.width: 1
        border.color: Theme.borderSubtle

        /// The thumb floats inside the track rather than filling it edge to
        /// edge. Without the inset a selected end segment shares its outer
        /// corner with the track, and a thumb whose corner is the track's
        /// corner stops reading as a thing sitting *in* something.
        readonly property int inset: 3

        readonly property int activeIndex: Math.max(0, toolbar.segments.indexOf(toolbar.view))

        /// Every segment is the width of the widest label, not of its own.
        /// A thumb that resized as it slid would be three controls
        /// pretending to be one, and "Day" and "Month" differ by enough
        /// that the eye reads the jump as a glitch rather than as motion.
        readonly property real segmentW: Math.ceil(widest.width) + Theme.space3 * 2

        TextMetrics {
            id: widest

            font.family: Theme.fontUi
            font.pointSize: Theme.pt(12.5)
            font.weight: Theme.weightMedium
            text: "Month"
        }

        Rectangle {
            id: thumb

            x: switcher.inset + switcher.activeIndex * switcher.segmentW
            y: switcher.inset
            width: switcher.segmentW
            height: parent.height - switcher.inset * 2
            radius: Theme.radiusSm - 1
            color: CalendarTokens.switcherThumb
            border.width: CalendarTokens.switcherEdge.a > 0 ? 1 : 0
            border.color: CalendarTokens.switcherEdge

            Behavior on x {
                enabled: Theme.animateTransforms
                NumberAnimation {
                    duration: Theme.duration(Theme.motionFast)
                    easing.type: Easing.InOutQuad
                }
            }
        }

        Row {
            id: segmentRow

            x: switcher.inset
            height: parent.height

            Repeater {
                model: toolbar.segments

                delegate: Item {
                    id: segment

                    required property string modelData
                    required property int index

                    readonly property bool active: segment.index === switcher.activeIndex

                    width: switcher.segmentW
                    height: switcher.height

                    Text {
                        id: segmentLabel

                        anchors.centerIn: parent
                        text: segment.modelData.charAt(0).toUpperCase()
                              + segment.modelData.slice(1)
                        /// The label carries the state as well as the thumb
                        /// does. `textSecondary` for the resting segments was
                        /// 9.3:1 against the bar — as loud as the selected one
                        /// for anything but a side-by-side comparison, so the
                        /// control's answer to "which view am I in" rested on
                        /// a 33/255 fill alone. `textMuted` at regular weight
                        /// is 5.6:1: plainly readable, plainly quieter, and the
                        /// selected segment now differs in fill, value *and*
                        /// weight — three signals, none of them subtle.
                        color: segment.active ? CalendarTokens.switcherInk : Theme.textMuted
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(12.5)
                        font.weight: segment.active ? Theme.weightMedium : Theme.weightRegular
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: toolbar.viewRequested(segment.modelData)
                    }
                }
            }
        }
    }

    /// A 30x30 icon button in two dresses — bare (the chevrons) and filled (the
    /// create button). Inline rather than in `Widgets/` because it is this
    /// bar's three icon buttons and nothing else: the moment a second surface
    /// wants one, it moves out of here and gains a header of its own.
    ///
    /// The rest fill is transparent by default, so a chevron is a glyph with a
    /// hit area and a hover wash and no drawn box at all. See the header for
    /// why that is the rank a chevron holds.
    /// The hairline between two tiles of the nav cluster. A full-height rule
    /// rather than an inset one: the tiles are the hit areas, and a rule that
    /// stopped short of the track's edges would draw the cluster as three
    /// floating labels again.
    component NavRule: Rectangle {
        width: 1
        height: CalendarTokens.controlH
        color: Theme.borderSubtle
    }

    component IconButton: Rectangle {
        id: chevron

        property string glyph: ""
        property color glyphColor: Theme.textSecondary
        property color restFill: "transparent"
        property color hoverFill: CalendarTokens.chromeHover

        signal tapped

        width: CalendarTokens.controlH
        height: CalendarTokens.controlH
        radius: Theme.radiusSm
        color: chevronPointer.containsMouse ? chevron.hoverFill : chevron.restFill

        Behavior on color {
            enabled: Theme.animateTransforms
            ColorAnimation { duration: Theme.duration(Theme.motionFast) }
        }

        Icon {
            anchors.centerIn: parent
            name: chevron.glyph
            size: 16
            color: chevron.glyphColor
        }

        MouseArea {
            id: chevronPointer

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chevron.tapped()
        }
    }
}
