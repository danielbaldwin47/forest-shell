// The month (#49).
//
// A month grid, the weekday it opens on, today under a teal disc, and two
// chevrons to page with. There is no event backend behind it and there is not
// meant to be — #49 says month grid only, and a calendar that showed an empty
// agenda under it would be promising one.
//
// **Nothing in this file computes a date.** Which weekday the 1st falls on, what
// fills the corners of the grid, whether a cell is today and what paging does at
// the year boundary are all Surfaces/Drawers/CalendarPolicy.qml, where `tests/`
// reaches them — every one of those is an off-by-one waiting to happen, and none
// of them is visible in a screenshot until it is a day out. What is left here is
// a `Repeater` and a colour.
//
// The month it shows is its own state and not the clock's: paging away from
// this month is a thing you did, and a tick that snapped the grid back would be
// the shell arguing with the pointer. `today` still comes from the clock, so the
// highlight moves at midnight wherever the grid is parked.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets
// Its own directory, explicitly: this file is loaded by URL, and a file
// Quickshell serves through its interceptor gets no implicit sibling
// resolution — without this line `CardFrame` is "not a type" and the card
// drops out of the dashboard with one warning (#73).
import qs.Surfaces.Drawers.Cards
// The month arithmetic lives one directory up, beside the drawer that stacks
// these cards — the same placement the control centre's detail views use for
// theirs.
import qs.Surfaces.Drawers

CardFrame {
    id: card

    /// The dashboard's pose, or null for the live shell. Only `now` is read
    /// here, and only to decide which cell is today: a capture of a calendar
    /// taken on a different day is a different picture, so seam 3 needs to be
    /// able to fix the date (Surfaces/Drawers/Dashboard.qml holds the shape).
    property var facts: null

    readonly property CalendarPolicy policy: CalendarPolicy {}

    readonly property date today: card.facts && card.facts.now ? card.facts.now : Time.now

    /// The month on screen, which is where paging leaves it.
    property int shownYear: card.today.getFullYear()
    property int shownMonth: card.today.getMonth() + 1

    /// Which day the locale's week starts on — Monday in most of Europe, Sunday
    /// in the US. Asked of the locale rather than configured, for the reason
    /// Core/ClockFormat.qml gives about the 12/24-hour choice: the key that
    /// would override it belongs to #50, and naming one here would be a key that
    /// ticket has to migrate away from.
    readonly property int firstDay: Qt.locale().firstDayOfWeek

    readonly property var weeks: card.policy.weeks(card.shownYear, card.shownMonth,
                                                   card.firstDay)

    /// A cell's width, and so the card's grid pitch. Seven of these plus the
    /// frame's padding is the panel's width, so the number is chosen by the
    /// panel rather than by the day: 380 - 2*12 (panel) - 2*12 (card) = 332,
    /// and 332 / 7 is 47.
    readonly property int cellSize: Math.floor((card.width - Theme.space3 * 2)
                                               / card.policy.columns)

    /// And a cell's height, which is *not* the same number. Square cells make
    /// six rows 282px tall, and a month that fills two thirds of the panel
    /// leaves no room for the cards under it — the grid is read across a row at
    /// a time, so the air it needs is horizontal.
    readonly property int cellHeight: Math.min(card.cellSize, 34)

    // No caption: the month's own name is the heading, and a "CALENDAR" over
    // "August 2026" is a word saying what the line below it already says.

    // --- the month, and the two chevrons --------------------------------------

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space2

        Text {
            Layout.fillWidth: true
            text: Qt.formatDate(new Date(card.shownYear, card.shownMonth - 1, 1),
                                "MMMM yyyy")
            color: Theme.textPrimary
            elide: Text.ElideRight
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(12)
            font.weight: Theme.weightMedium
        }

        // Back to the month the clock is in. Absent while it is already there,
        // rather than greyed: a control that does nothing is furniture, and this
        // one has a perfectly good absence to fall back on.
        RoundIconButton {
            glyph: "rotate-ccw"
            size: 14
            diameter: 24
            visible: card.shownYear !== card.today.getFullYear()
                     || card.shownMonth !== card.today.getMonth() + 1
            onPressed: card.page(0)
        }

        RoundIconButton {
            glyph: "chevron-left"
            size: 14
            diameter: 24
            onPressed: card.page(-1)
        }

        RoundIconButton {
            glyph: "chevron-right"
            size: 14
            diameter: 24
            onPressed: card.page(1)
        }
    }

    // --- the weekday header ---------------------------------------------------

    RowLayout {
        Layout.fillWidth: true
        spacing: 0

        Repeater {
            model: card.policy.weekdays(card.firstDay)

            Text {
                required property int modelData

                Layout.preferredWidth: card.cellSize
                horizontalAlignment: Text.AlignHCenter
                // The locale's own abbreviation, which is two letters in some
                // languages and three in others — and never this file's guess.
                text: Qt.locale().dayName(modelData, Locale.ShortFormat)
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(10.5)
                font.weight: Theme.weightMedium
            }
        }
    }

    // --- the grid -------------------------------------------------------------

    Repeater {
        model: card.weeks

        RowLayout {
            required property var modelData

            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: parent.modelData

                Item {
                    id: cell

                    required property var modelData

                    readonly property bool isToday: card.policy.isToday(
                        cell.modelData, card.today.getFullYear(),
                        card.today.getMonth() + 1, card.today.getDate())

                    implicitWidth: card.cellSize
                    implicitHeight: card.cellHeight

                    // Today, and the one warm-free emphasis the shell has for
                    // "here": a filled disc rather than a ring, because a ring
                    // at this size reads as a hover state (#10's lamplight rule
                    // keeps amber for attention, and today is not attention).
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) - 2
                        height: width
                        radius: width / 2
                        visible: cell.isToday
                        color: Theme.accentDeep
                    }

                    Text {
                        anchors.centerIn: parent
                        text: cell.modelData.day
                        // Three weights of presence: today, this month, and the
                        // neighbours that fill the corners. The neighbours stay
                        // legible rather than being hidden — a grid with holes
                        // in it reads as a missing day.
                        color: cell.isToday ? Theme.bgBase
                             : cell.modelData.current ? Theme.textPrimary
                                                      : Theme.textMuted
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(11)
                        font.weight: cell.isToday ? Theme.weightMedium : Theme.weightRegular
                    }
                }
            }
        }
    }

    /// Page the grid. `0` is "back to today", which is a jump rather than a
    /// step and so is not a delta.
    function page(delta: int): void {
        if (delta === 0) {
            card.shownYear = card.today.getFullYear();
            card.shownMonth = card.today.getMonth() + 1;
        } else {
            const next = card.policy.shift(card.shownYear, card.shownMonth, delta);
            card.shownYear = next.year;
            card.shownMonth = next.month;
        }

        Logger.log("dashboard", "calendar " + card.shownMonth + "/" + card.shownYear);
    }

    // The card's line, and what a harness reads to know the grid was built from
    // a real month rather than drawn empty (#81: a surface gets a log line per
    // state change worth asserting on).
    Component.onCompleted: Logger.log("dashboard",
        "calendar " + card.shownMonth + "/" + card.shownYear
        + " (" + card.weeks.length + " rows, week starts " + card.firstDay + ")")
}
