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
// The three moving controls also share one treatment. An earlier pass had bare
// chevrons next to a bordered Today pill, which read as two ranks of control
// where there is only one: all three do the same kind of thing, so all three
// are the same button.
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
// So the rank difference lives in the *label* and the label alone: the box
// never fades, so all three controls stay one treatment, while the label steps
// from `textPrimary` when the button is live down to `textMuted` when it is
// not. `textMuted` and not `textSecondary`, because `textSecondary` is what
// the chevron glyphs either side wear: a resting Today at the same value as
// its live neighbours is a button that never looks inert, which is the whole
// claim. `textMuted` is 5.6:1 — one visible step below the chevrons, three
// steps below its own live state, and still comfortably readable, which
// `opacityInert` at 3.9:1 was not.
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
        color: "transparent"

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
    Row {
        anchors.left: yearText.right
        anchors.leftMargin: Theme.space4
        anchors.verticalCenter: parent.verticalCenter
        // `space3` between groups, `space2` inside the pair below. Equal gaps
        // across all three made the chevrons and Today one undifferentiated
        // run of buttons; the pair is one control with two ends, and it has to
        // look tighter than the gap to its neighbour or it never groups.
        spacing: Theme.space3

        Row {
            spacing: Theme.space2

            ChevronButton {
                glyph: "chevron-left"
                onTapped: toolbar.stepRequested(-1)
            }

            ChevronButton {
                glyph: "chevron-right"
                onTapped: toolbar.stepRequested(1)
            }
        }

        /// Today, in the same clothes as the chevrons beside it — one box, two
        /// ranks, and the rank is carried by the label. See the header for the
        /// measurement that put it there rather than in the button's opacity.
        Rectangle {
            id: todayButton

            readonly property bool live: !toolbar.showsToday

            width: todayLabel.implicitWidth + Theme.space4
            height: CalendarTokens.controlH
            radius: Theme.radiusSm
            color: todayPointer.containsMouse && todayButton.live
                   ? Theme.surfaceOverlay
                   : Theme.surfaceRaised
            border.width: 1
            border.color: Theme.borderSubtle

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
    /// So the roles are taken by value: the track is `bgSunken` (`#070a08`,
    /// a well under the `bgBase` bar) and the thumb is `surfaceOverlay`, two
    /// steps up from it and one step above every resting button in the bar.
    /// The selected segment is now the lightest thing in the toolbar, which is
    /// the only property that has to hold — a segmented control says "this
    /// one" by lifting it, and lifting is a lightness, not a token name.
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
            color: Theme.surfaceOverlay

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
                        color: segment.active ? Theme.textPrimary : Theme.textSecondary
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(12.5)
                        font.weight: Theme.weightMedium
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

    /// A 30x30 icon button, wearing the same fill and hairline as the Today
    /// button it stands next to — the one treatment the header argues for.
    /// Inline rather than in `Widgets/` because it is the chevron pair and
    /// nothing else: the moment a second surface wants one, it moves out of
    /// here and gains a header of its own.
    component ChevronButton: Rectangle {
        id: chevron

        property string glyph: ""

        signal tapped

        width: CalendarTokens.controlH
        height: CalendarTokens.controlH
        radius: Theme.radiusSm
        color: chevronPointer.containsMouse ? Theme.surfaceOverlay : Theme.surfaceRaised
        border.width: 1
        border.color: Theme.borderSubtle

        Behavior on color {
            enabled: Theme.animateTransforms
            ColorAnimation { duration: Theme.duration(Theme.motionFast) }
        }

        Icon {
            anchors.centerIn: parent
            name: chevron.glyph
            size: 16
            color: Theme.textSecondary
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
