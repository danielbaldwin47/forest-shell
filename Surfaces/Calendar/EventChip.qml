// One event, drawn on the time grid.
//
// The chip owns no arithmetic. Where it goes and how big it is were decided by
// `TimeGridPolicy.eventRect` and `EventLayoutPolicy.layout` before it was
// built; which hue it wears was decided by `HuePolicy`; whether it has room for
// two lines was decided by `EventLayoutPolicy.isCompact`. What is left here is
// the picture: a hue bar, a tinted fill, two lines of text, and the two states
// a pointer can put it in.
//
// ## Why the ring is a sibling and not a border
//
// The body clips — a 20px chip with a 15-character title has to elide inside
// its own rounded corners, and `clip` is what makes the corners real. A
// selection ring drawn as that body's `border` would then sit *inside* the
// chip and eat two pixels of the fill, and on a chip packed against its
// neighbour those two pixels are the gap. Drawn as a sibling at
// `anchors.margins: -1` it sits one pixel outside instead, in the gutter the
// packing already leaves, and the chip does not change size when it is picked.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Item {
    id: chip

    /// The event, as the store holds it. Read rather than destructured into
    /// six properties because every caller has the whole thing in hand and a
    /// delegate with six bindings is six chances to bind one to the wrong row.
    required property var event

    /// Which of the eight hues, already resolved.
    property int hue: 0

    /// One line rather than two, with the time set after the title. The layout
    /// policy decides it; the chip only obeys.
    property bool compact: false

    property bool selected: false

    /// A 24-hour clock, from `Core/TimeFormat.qml` by way of the view. Passed
    /// down rather than read here so one calendar cannot show two clocks.
    property bool use24: false

    /// The event carries on above or below this column — it crosses a midnight.
    /// The chip squares off the cut end so it does not read as a start.
    property bool continuesAbove: false
    property bool continuesBelow: false

    property CalendarFormat format: CalendarFormat {}

    property EventLayoutPolicy layoutPolicy: EventLayoutPolicy {}

    readonly property bool hovered: pointer.containsMouse

    /// Whether there is room for the time under the title. Asked of the chip's
    /// own width, so a chip narrowed by a three-way overlap drops the line the
    /// moment the packing decides it, with no second threshold in the view.
    readonly property bool showsTime: chip.layoutPolicy.showsTimeLine(chip.width)

    signal activated(string id)

    implicitHeight: CalendarTokens.chipMinH

    /// The selection ring: one pixel outside the body, two thick, in the hue.
    /// Radius one larger than the body's so the two curves stay concentric —
    /// an offset ring at the same radius reads as a printing misregistration.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        radius: Theme.radiusSm + 1
        color: "transparent"
        border.width: Theme.rail
        border.color: CalendarTokens.bar(chip.hue)
        visible: chip.selected
    }

    Rectangle {
        id: body

        anchors.fill: parent
        clip: true
        radius: Theme.radiusSm
        color: chip.hovered ? CalendarTokens.fillHover(chip.hue) : CalendarTokens.fill(chip.hue)
        border.width: 1
        border.color: CalendarTokens.chipBorder(chip.hue)

        Behavior on color {
            enabled: Theme.animateTransforms
            ColorAnimation { duration: Theme.duration(Theme.motionFast) }
        }

        /// The hue bar, full height. It is drawn inside the clipped body, so
        /// the body's own rounded corners are what round its ends — which is
        /// why it needs no radius of its own and no special case at a midnight
        /// cut.
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: CalendarTokens.chipBar
            color: CalendarTokens.bar(chip.hue)
        }

        /// Two lines, or one, both anchored and neither in a positioner.
        ///
        /// A `Row` or `Column` sized by `anchors.left`/`right` whose children
        /// read `parent.width` back is a binding loop — QML breaks it by
        /// dropping the child's width, and a title with width 0 elides to
        /// nothing and disappears, leaving a chip that shows only its time.
        /// Measured on the first capture of this file, on exactly that Row.
        Item {
            id: stacked

            visible: !chip.compact
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: CalendarTokens.chipBar + Theme.space2
            anchors.rightMargin: Theme.space2
            anchors.topMargin: Theme.space1

            Text {
                id: stackedTitle

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                text: chip.event ? (chip.event.title || "Untitled") : ""
                elide: Text.ElideRight
                maximumLineCount: 1
                color: CalendarTokens.text(chip.hue)
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(12.5)
                font.weight: Theme.weightMedium
            }

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: stackedTitle.bottom
                anchors.topMargin: 1
                // Dropped on a chip too narrow to hold a time: see
                // `EventLayoutPolicy.showsTimeLine`.
                visible: chip.showsTime
                text: chip.timeLabel
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Qt.alpha(CalendarTokens.text(chip.hue), 0.72)
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(11)
                font.weight: Theme.weightRegular
            }
        }

        Item {
            visible: chip.compact
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: CalendarTokens.chipBar + Theme.space2
            anchors.rightMargin: Theme.space2

            Text {
                id: inlineTime

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: chip.timeLabel
                color: Qt.alpha(CalendarTokens.text(chip.hue), 0.72)
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(11)
                font.weight: Theme.weightRegular
            }

            // The title yields to the time rather than the other way round:
            // "Standup" elided to "Stand…" is still legible, "9a" elided to
            // "9" is a different time.
            Text {
                anchors.left: parent.left
                anchors.right: inlineTime.left
                anchors.rightMargin: Theme.space2
                anchors.baseline: inlineTime.baseline
                text: chip.event ? (chip.event.title || "Untitled") : ""
                elide: Text.ElideRight
                maximumLineCount: 1
                color: CalendarTokens.text(chip.hue)
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(12.5)
                font.weight: Theme.weightMedium
            }
        }
    }

    /// `"10 – 11:30a"` on a chip that begins where it looks like it does, and
    /// the start alone on one continuing from yesterday — a chip whose top edge
    /// is a midnight cut must not print a start time it does not have.
    readonly property string timeLabel: {
        if (!chip.event)
            return "";
        if (chip.continuesAbove)
            return "→ " + chip.format.chipTime(chip.event.end, chip.use24);
        if (chip.compact || chip.continuesBelow)
            return chip.format.chipTime(chip.event.start, chip.use24);
        return chip.format.timeRange(chip.event.start, chip.event.end, chip.use24);
    }

    MouseArea {
        id: pointer

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.activated(chip.event ? chip.event.id : "")
    }
}
