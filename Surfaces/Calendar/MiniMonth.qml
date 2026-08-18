// The sidebar's month map: six rows of seven, a heading that names the month,
// and a band showing where in it the grid beside it is pointed.
//
// ## It pages independently of the grid
//
// The steppers move the *sidebar's* month and nothing else, so you can look
// ahead to December without losing the week you are working in. Clicking a day
// is the thing that moves the grid. Notion's mini-month does the same, and the
// reason is that a mini-month which dragged the main view with it is just a
// second, worse set of chevrons.
//
// The one time it moves by itself is when the grid lands in a month it is not
// showing — `MiniMonthPolicy.snapMonth` — because a map of August above a grid
// of December is a map of nowhere.
//
// ## Every decision here is in the policy
//
// Which cells the band covers, what the seven letters are, where a step lands
// and what the calendar rows are called all live in `MiniMonthPolicy`, tested
// offscreen. This file owns pixels: how wide a cell is, what a band is drawn
// with, and which of the four numeral colours a cell gets.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Widgets

Item {
    id: mini

    /// The day the grid beside this one is built around, and today.
    property string anchorDate: ""
    property string todayIso: ""

    /// `day`, `week` or `month` — what the band means. See `MiniMonthPolicy`.
    property string view: "week"

    property int firstDay: 1

    property MiniMonthPolicy policy: MiniMonthPolicy {}

    /// A day was clicked. The sidebar does not move the grid itself for the same
    /// reason the toolbar does not — see `CalendarView.qml`'s header.
    signal dayRequested(string iso)

    /// The month this one is showing, as any day inside it. State rather than a
    /// binding: the steppers write to it, and the anchor only overrides it when
    /// the grid has moved out of the month altogether.
    property string displayIso: mini.anchorDate

    onAnchorDateChanged: mini.displayIso = mini.policy.snapMonth(mini.displayIso, mini.anchorDate)

    readonly property var grid: mini.policy.month.grid(mini.displayIso, mini.firstDay, mini.todayIso)
    readonly property var letters: mini.policy.initials(mini.firstDay)

    /// A whole number of pixels per column. The sidebar is now sized to hold
    /// exactly seven of `CalendarTokens.miniDayW` between its two pads, so this
    /// divides — but the floor stays, because a fractional column width puts
    /// the band's rounded end half a pixel inside the last cell on some rows
    /// and outside it on others, and a map that is handed an odd width should
    /// misplace a pixel at the edge rather than at every joint.
    readonly property int dayW: Math.floor(mini.width / 7)
    readonly property int dayH: CalendarTokens.miniDayW

    /// How tall the heading band is, and where inside it the month name's
    /// baseline sits (`-1` centres it). Both are the caller's, because the
    /// sidebar spends its own chrome band on this heading so that it lands on
    /// the toolbar title's baseline across the divider.
    property int headingH: 28
    property real headingBaseline: -1

    /// **Zero at the width the sidebar hands it, and that is the point.**
    ///
    /// This used to centre a 5px remainder, which bought equal facing margins
    /// at the price of a third left edge in the column: the grid started
    /// `gridX` px right of the `CALENDARS` and `UPCOMING` labels hung from the
    /// body's own inset, and the week band — the largest coloured shape in the
    /// sidebar — started there with it. Two edges 3px apart read as one edge
    /// drawn badly.
    ///
    /// The fix is upstream, in `CalendarTokens.sidebarW`: the column is sized
    /// to hold seven whole cells between two pads, so the remainder is zero and
    /// the map, the labels and the band all begin at `sidebarPad`. The
    /// expression stays because it is what keeps that true at any width — a
    /// sidebar someone widens later centres its remainder instead of dumping it
    /// on the right.
    readonly property int gridW: mini.dayW * 7
    readonly property int gridX: Math.round((mini.width - mini.gridW) / 2)

    implicitHeight: heading.height + mini.dayH + rows.height

    // --- the heading ---------------------------------------------------------

    Item {
        id: heading

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: mini.headingH

        /// Centred by default, and pinned to a baseline when the caller gives
        /// one. The sidebar hands it the toolbar title's baseline: the two
        /// headings sit either side of a hairline divider, and two lines of
        /// type at the same size half a leading apart read as a mistake in a
        /// way that a 4px difference in *fill* height never does.
        Text {
            id: headingText

            anchors.left: parent.left
            anchors.leftMargin: mini.gridX
            anchors.verticalCenter: mini.headingBaseline < 0 ? parent.verticalCenter : undefined
            y: mini.headingBaseline < 0 ? 0 : mini.headingBaseline - headingText.baselineOffset
            text: mini.policy.format.miniMonthTitle(mini.displayIso)
            color: Theme.textPrimary
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(14)
            font.weight: Theme.weightMedium
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: mini.gridX
            anchors.verticalCenter: headingText.verticalCenter
            spacing: Theme.space1

            Stepper {
                glyph: "chevron-left"
                onTapped: mini.displayIso = mini.policy.step(mini.displayIso, -1)
            }

            Stepper {
                glyph: "chevron-right"
                onTapped: mini.displayIso = mini.policy.step(mini.displayIso, 1)
            }
        }
    }

    // --- the seven letters ---------------------------------------------------

    /// The label row is a row of the grid, not a caption above it: same height,
    /// no margin, so `Su` sits exactly one row pitch above the `26` under it.
    /// It was `space2` and a 20px row — 26px centre to centre against a 30px
    /// pitch — and 4px of tightening is enough to read as a header that slipped
    /// rather than as the first line of a table.
    Row {
        id: letterRow

        x: mini.gridX
        anchors.top: heading.bottom
        height: mini.dayH

        Repeater {
            model: mini.letters

            delegate: Item {
                id: letterCell

                required property string modelData

                width: mini.dayW
                height: letterRow.height

                /// No caps tracking, unlike every other small label in the
                /// shell: tracking is what makes an all-caps label read as a
                /// label, and these are `Su`/`Mo`, which are words. Tracking
                /// them would also push the pair off the column centre, since
                /// the trailing letter's space is drawn and the centring is
                /// not told about it.
                Text {
                    anchors.centerIn: parent
                    text: letterCell.modelData
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(11.5)
                    font.weight: Theme.weightMedium
                }
            }
        }
    }

    // --- the six rows --------------------------------------------------------

    Column {
        id: rows

        x: mini.gridX
        anchors.top: letterRow.bottom
        width: mini.gridW

        Repeater {
            model: mini.grid

            delegate: Item {
                id: weekRow

                required property var modelData

                readonly property var band: mini.policy.band(weekRow.modelData, mini.view, mini.anchorDate)

                width: mini.gridW
                height: mini.dayH

                /// One rectangle for the whole run, so the rounded ends land on
                /// the outside of the period rather than around every day in
                /// it. `radiusFull` on a 30px row is a stadium, which is what a
                /// week reads as and what a single day reads as a circle.
                Rectangle {
                    visible: !!weekRow.band
                    x: weekRow.band ? weekRow.band.start * mini.dayW : 0
                    width: weekRow.band
                           ? (weekRow.band.end - weekRow.band.start + 1) * mini.dayW
                           : 0
                    height: mini.dayH
                    radius: Theme.radiusFull
                    // One value, no stroke — `CalendarTokens.bandFill` carries
                    // the argument for why the hairline that used to ride on
                    // top of this fill was fussiness rather than definition.
                    color: CalendarTokens.bandFill
                }

                Row {
                    Repeater {
                        model: weekRow.modelData

                        delegate: Item {
                            id: cell

                            required property var modelData
                            required property int index

                            readonly property bool banded:
                                !!weekRow.band
                                && cell.index >= weekRow.band.start
                                && cell.index <= weekRow.band.end

                            /// The anchor day itself, when the band is wider
                            /// than one cell. In a day view the band *is* the
                            /// cell, so a ring round it would be a ring round a
                            /// filled circle.
                            readonly property bool anchored:
                                cell.modelData.iso === mini.anchorDate
                                && !cell.modelData.isToday
                                && mini.view !== "day"

                            width: mini.dayW
                            height: mini.dayH

                            /// **24 — between the 26 that outranked the grid's
                            /// own today mark and the 20 that strangled the
                            /// numeral.** The mini-month's today is the
                            /// *secondary* mark: the grid beside it draws today
                            /// as a 22px disc in a 200px cell, so a 26px disc in
                            /// a 30px cell had the weaker marker as the louder
                            /// object. 20 fixed the order and broke the disc: a
                            /// two-digit numeral at 13pt is ~15px wide, which
                            /// left 2–3px of ring either side — a circle drawn
                            /// tight against its own contents reads as a
                            /// mistake, not as a mark. 24 gives the numeral
                            /// ~4.5px of rim all round, and still sits under the
                            /// grid's 22px disc in a cell six times its area.
                            Rectangle {
                                anchors.centerIn: parent
                                width: 24
                                height: 24
                                radius: Theme.radiusFull
                                color: cell.modelData.isToday
                                       ? Theme.accentPrimary
                                       : (dayPointer.containsMouse
                                          ? CalendarTokens.chromeHover : "transparent")
                                border.width: cell.anchored ? 1 : 0
                                border.color: Theme.borderStrong
                            }

                            /// **Out-of-month days are dimmed by colour, never
                            /// by opacity.** `textMuted` at 0.45 — which is
                            /// what the spec asked for — composites to
                            /// rgb(72,85,78) on this panel's rgb(28,38,33):
                            /// **2.0:1**, which is not a quiet numeral but an
                            /// absent one. The rows either side of the month
                            /// went blank, and a mini-month whose first and
                            /// last rows are empty stops reading as a
                            /// continuous strip of days.
                            ///
                            /// At full strength `textMuted` is 4.6:1 against
                            /// the same panel where an in-month numeral is
                            /// 7.5:1 — 15 points of L* between them, so the
                            /// step is still plainly a step, and both ends of
                            /// it are legible. De-emphasis is a difference the
                            /// eye can measure; dissolving into the ground is
                            /// not de-emphasis, it is deletion.
                            Text {
                                anchors.centerIn: parent
                                text: cell.modelData.day
                                color: {
                                    if (cell.modelData.isToday)
                                        return Theme.bgBase;
                                    if (!cell.modelData.inMonth)
                                        return Theme.textMuted;
                                    return cell.banded ? Theme.textPrimary : Theme.textSecondary;
                                }
                                font.family: Theme.fontUi
                                font.pointSize: Theme.pt(13)
                                font.weight: cell.modelData.isToday ? Theme.weightMedium : Theme.weightRegular
                                font.features: CalendarTokens.tabularFigures
                            }

                            MouseArea {
                                id: dayPointer

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mini.dayRequested(cell.modelData.iso)
                            }
                        }
                    }
                }
            }
        }
    }

    /// A 24x24 stepper: a bare glyph with a hit area and a hover wash, one size
    /// and one value below the toolbar's chevrons.
    ///
    /// **This pair and the toolbar's must not be twins, and for a round they
    /// were.** Both were bordered boxes with the same two glyphs, 300px apart
    /// on the same bar, and nothing in either said which one moved the grid —
    /// the more consequential of the two questions this window asks. The cue
    /// cannot be position alone, because a mini-month's steppers sit above its
    /// own grid exactly as the toolbar's sit beside its own title.
    ///
    /// So it is size and value: the toolbar's are 30px glyphs at
    /// `textSecondary` beside a 20pt month title; these are 24px glyphs at
    /// `textMuted` beside a 14pt one. Two ranks of the same gesture, which is
    /// what they are — one moves what you are working in, the other moves what
    /// you are looking up.
    ///
    /// The middle pass here was a box, on the argument that an undressed glyph
    /// gives the pointer nothing to aim at. The hover wash is that target, and
    /// it costs nothing when the pointer is elsewhere.
    component Stepper: Rectangle {
        id: stepper

        property string glyph: ""

        signal tapped

        width: 24
        height: 24
        radius: Theme.radiusSm
        color: stepPointer.containsMouse ? CalendarTokens.chromeHover : "transparent"

        Behavior on color {
            enabled: Theme.animateTransforms
            ColorAnimation { duration: Theme.duration(Theme.motionFast) }
        }

        Icon {
            anchors.centerIn: parent
            name: stepper.glyph
            size: 14
            color: stepPointer.containsMouse ? Theme.textSecondary : Theme.textMuted
        }

        MouseArea {
            id: stepPointer

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: stepper.tapped()
        }
    }
}
