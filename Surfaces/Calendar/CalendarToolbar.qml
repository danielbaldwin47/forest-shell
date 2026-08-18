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
// ## Today is a button that knows when it is pointless
//
// It goes to `opacityInert` and stops taking clicks when today is already on
// screen. Notion leaves it live, which teaches the hand to press a button that
// does nothing — and a control that sometimes does nothing is worse than one
// that is visibly unavailable.
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
        anchors.verticalCenter: parent.verticalCenter
        text: toolbar.titleParts.lead
        color: Theme.textPrimary
        font.family: Theme.fontDisplay
        font.pointSize: Theme.pt(20)
        font.weight: Theme.weightDisplay
    }

    Text {
        id: yearText

        anchors.left: leadText.right
        anchors.leftMargin: Theme.space2
        anchors.baseline: leadText.baseline
        text: toolbar.titleParts.year
        color: Theme.textMuted
        font.family: Theme.fontUi
        font.pointSize: Theme.pt(20)
        font.weight: Theme.weightRegular
    }

    // --- the controls ---------------------------------------------------------

    Row {
        anchors.right: parent.right
        anchors.rightMargin: Theme.space4
        anchors.verticalCenter: parent.verticalCenter
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

        /// Today.
        Rectangle {
            id: todayButton

            width: todayLabel.implicitWidth + Theme.space4
            height: CalendarTokens.controlH
            radius: Theme.radiusSm
            color: todayPointer.containsMouse && toolbar.showsToday === false
                   ? Theme.surfaceOverlay : "transparent"
            border.width: 1
            border.color: Theme.borderSubtle
            opacity: toolbar.showsToday ? Theme.opacityInert : 1.0

            Text {
                id: todayLabel

                anchors.centerIn: parent
                text: "Today"
                color: Theme.textSecondary
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(12.5)
                font.weight: Theme.weightMedium
            }

            MouseArea {
                id: todayPointer

                anchors.fill: parent
                enabled: !toolbar.showsToday
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: toolbar.todayRequested()
            }
        }

        /// The view switcher. The thumb is one item that slides, not three that
        /// fade: a moving thumb says the three segments are one control, which
        /// is the whole reason to use a segmented switch instead of three
        /// buttons.
        Rectangle {
            id: switcher

            width: switcher.segmentW * toolbar.segments.length
            height: CalendarTokens.controlH
            radius: Theme.radiusSm
            color: Theme.surfaceOverlay

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

                x: switcher.activeIndex * switcher.segmentW
                y: 0
                width: switcher.segmentW
                height: parent.height
                radius: Theme.radiusSm
                color: Theme.surfaceRaised
                border.width: 1
                border.color: Theme.borderSubtle

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
    }

    /// A 30x30 icon button. Inline rather than in `Widgets/` because it is the
    /// chevron pair and nothing else: the moment a second surface wants one, it
    /// moves out of here and gains a header of its own.
    component ChevronButton: Rectangle {
        id: chevron

        property string glyph: ""

        signal tapped

        width: CalendarTokens.controlH
        height: CalendarTokens.controlH
        radius: Theme.radiusSm
        color: chevronPointer.containsMouse ? Theme.surfaceOverlay : "transparent"

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
