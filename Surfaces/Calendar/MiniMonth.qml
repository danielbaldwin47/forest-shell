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

    /// A whole number of pixels per column: 248 of sidebar less two `space4`
    /// pads does not divide by seven, and a fractional column width puts the
    /// band's rounded end half a pixel inside the last cell on some rows and
    /// outside it on others.
    readonly property int dayW: Math.floor(mini.width / 7)
    readonly property int dayH: 30

    /// The remainder is split between the two edges rather than dumped on the
    /// right, and that is a correction. Left-aligning the grid put its first
    /// day circle 19px from the sidebar's edge and its last 25px from the
    /// divider, because two shortfalls stack on the right: the fractional
    /// column remainder, plus the 2px the circle is inset inside its own cell.
    /// A block whose two margins differ by a quarter reads as slipped, and the
    /// mini-month is the largest block in this column — it is what the eye
    /// squares the sidebar against.
    ///
    /// What the left rail actually costs is `gridX` pixels of disagreement
    /// with the labels hung from the body's left edge — 3 at this width, less
    /// than the 2px the circles are already inset by, and invisible where a
    /// 6px asymmetry between two facing margins is not.
    readonly property int gridW: mini.dayW * 7
    readonly property int gridX: Math.round((mini.width - mini.gridW) / 2)

    implicitHeight: heading.height + mini.dayH + rows.height

    // --- the heading ---------------------------------------------------------

    Item {
        id: heading

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 28

        Text {
            anchors.left: parent.left
            anchors.leftMargin: mini.gridX
            anchors.verticalCenter: parent.verticalCenter
            text: mini.policy.format.miniMonthTitle(mini.displayIso)
            color: Theme.textPrimary
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(14)
            font.weight: Theme.weightMedium
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: mini.gridX
            anchors.verticalCenter: parent.verticalCenter
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
                    color: CalendarTokens.bandFill
                    border.width: 1
                    border.color: CalendarTokens.bandBorder
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

                            Rectangle {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                radius: Theme.radiusFull
                                color: cell.modelData.isToday
                                       ? Theme.accentPrimary
                                       : (dayPointer.containsMouse ? Theme.surfaceRaised : "transparent")
                                border.width: cell.anchored ? 1 : 0
                                border.color: Theme.borderStrong
                            }

                            /// **Out-of-month days are dimmed by colour, never
                            /// by opacity.** `textMuted` at 0.45 — which is
                            /// what the spec asked for — composites to
                            /// rgb(67,79,73) on this panel's rgb(20,27,23):
                            /// **2.05:1**, which is not a quiet numeral but an
                            /// absent one. The rows either side of the month
                            /// went blank, and a mini-month whose first and
                            /// last rows are empty stops reading as a
                            /// continuous strip of days.
                            ///
                            /// At full strength `textMuted` is 5.1:1 against
                            /// the same panel where an in-month numeral is
                            /// 8.5:1 — 16 points of L* between them, so the
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

    /// A 24x24 stepper — the toolbar's chevron button at a smaller size, and
    /// wearing the same fill and hairline.
    ///
    /// It was a bare glyph on transparent, on the argument that a pair of boxes
    /// inside a heading would out-shout the month name they belong to. The
    /// picture disagreed: every other control in this window — the chevrons,
    /// Today, the create button one band above these — is a bordered box, so
    /// two undressed glyphs read as decoration rather than as the only pair of
    /// buttons on the panel, and there is nothing to aim at until the pointer
    /// is already on them. Shrinking the box from 30 to 24 is the deference the
    /// heading needed; removing it was deference to the point of hiding.
    component Stepper: Rectangle {
        id: stepper

        property string glyph: ""

        signal tapped

        width: 24
        height: 24
        radius: Theme.radiusSm
        color: stepPointer.containsMouse ? Theme.surfaceOverlay : Theme.surfaceRaised
        border.width: 1
        border.color: Theme.borderSubtle

        Behavior on color {
            enabled: Theme.animateTransforms
            ColorAnimation { duration: Theme.duration(Theme.motionFast) }
        }

        Icon {
            anchors.centerIn: parent
            name: stepper.glyph
            size: 14
            color: Theme.textSecondary
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
