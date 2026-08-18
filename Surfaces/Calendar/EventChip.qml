// One event, drawn on the time grid.
//
// The chip owns no arithmetic. Where it goes and how big it is were decided by
// `TimeGridPolicy.eventRect` and `EventLayoutPolicy.layout` before it was
// built; which hue it wears was decided by `HuePolicy`; what may be printed
// inside the box those two chose was decided by
// `EventLayoutPolicy.chipContent`. What is left here is the picture: a hue bar,
// a tinted fill, one or two lines of text, and the two states a pointer can put
// it in.
//
// ## The one thing the chip measures for itself
//
// `chipContent` cannot answer "how many glyphs fit" — that is a font metric,
// and a policy that could read a font could not be tested offscreen. So the
// chip measures its own title with `TextMetrics` and hands the *number* back to
// `clipTitle`, which decides what to do with it. The decision (cut at the last
// whole word) stays pure; only the measurement is here. This is what turns
// `D…` into `Design…` in a packed column — `Text.ElideRight` alone cuts
// mid-glyph and names nothing.
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

    /// The event record: `{id, title, start, end, ...}`.
    required property var event

    /// Its hue index, resolved through `CalendarTokens`.
    property int hue: 0

    /// The event's real duration in minutes. Passed in rather than derived from
    /// `height`, because `chipMinH` floors a short event's height and the
    /// content rule needs the duration that was floored, not the floor.
    property real minutes: 60

    property bool selected: false

    /// 12h or 24h, from the shell's one clock-format knob.
    property bool use24: false

    /// Set when the event runs past this day's top or bottom edge.
    property bool continuesAbove: false
    property bool continuesBelow: false

    property CalendarFormat format: CalendarFormat {}

    property EventLayoutPolicy layoutPolicy: EventLayoutPolicy {}

    readonly property bool hovered: pointer.containsMouse

    /// Everything the box's own size decides: which lines print, at what size,
    /// with how much padding. One object, so the chip can never take its title
    /// rule from one branch and its padding from another.
    readonly property var content:
        chip.layoutPolicy.chipContent(chip.width, chip.height, chip.minutes)

    readonly property string rawTitle:
        chip.event ? (chip.event.title || "Untitled") : ""

    signal activated(string id)

    implicitHeight: CalendarTokens.chipMinH

    /// The selection ring. See the header for why it is not a border.
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

        /// The accent bar. Full height and hard-edged against the rounded
        /// corners the body clips it into, which is what makes the hue readable
        /// at a glance on a chip too small for anything else.
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: chip.content.bar
            color: CalendarTokens.bar(chip.hue)
        }

        /// Title over time — the roomy case, and every packed chip tall enough
        /// to have a second line.
        Item {
            id: stacked

            visible: chip.content.mode === "stacked"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: chip.content.padLeft
            anchors.rightMargin: chip.content.padRight
            anchors.topMargin: chip.content.padTop

            Text {
                id: stackedTitle

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                text: chip.clippedTitle
                // Wrapping is the packed column's whole answer: four glyphs on
                // a line is `Des…` however it is cut, and the same chip has
                // vertical room its duration already paid for.
                wrapMode: chip.content.titleLines > 1 ? Text.WordWrap : Text.NoWrap
                elide: Text.ElideRight
                maximumLineCount: chip.content.titleLines
                color: CalendarTokens.text(chip.hue)
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(chip.content.titleSize)
                font.weight: Theme.weightMedium
            }

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: stackedTitle.bottom
                anchors.topMargin: chip.content.narrow ? 0 : 1
                visible: chip.content.showTime
                text: chip.timeLabel
                // A time that elides is not a time. Where the last pixel or two
                // is missing the glyphs shrink instead — the one place on this
                // surface where type is not on the scale, and cheaper than
                // printing `10:3…`.
                fontSizeMode: Text.HorizontalFit
                minimumPointSize: Theme.pt(8)
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Qt.alpha(CalendarTokens.text(chip.hue), 0.78)
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(chip.content.timeSize)
                font.weight: Theme.weightRegular
            }
        }

        /// One line — a half-hour meeting, or a chip too short for two. The
        /// time is right-aligned when there is one, so a column of them lines
        /// its times up down the right edge instead of ragging after titles of
        /// different lengths.
        Item {
            id: single

            visible: chip.content.mode !== "stacked"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: chip.content.padLeft
            anchors.rightMargin: chip.content.padRight

            Text {
                id: inlineTime

                visible: chip.content.showTime
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: chip.timeLabel
                color: Qt.alpha(CalendarTokens.text(chip.hue), 0.78)
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(chip.content.timeSize)
                font.weight: Theme.weightRegular
            }

            Text {
                anchors.left: parent.left
                anchors.right: inlineTime.visible ? inlineTime.left : parent.right
                anchors.rightMargin: inlineTime.visible ? Theme.space2 : 0
                anchors.verticalCenter: parent.verticalCenter
                text: chip.clippedTitle
                elide: Text.ElideRight
                maximumLineCount: 1
                color: CalendarTokens.text(chip.hue)
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(chip.content.titleSize)
                font.weight: Theme.weightMedium
            }
        }
    }

    // --- the two strings, and the one measurement behind them -----------------

    /// The time, in the form the width can carry: the whole range where it
    /// fits, the start alone where it does not, and an arrow where the event
    /// runs off an edge of the day.
    readonly property string timeLabel: {
        if (!chip.event)
            return "";
        if (chip.continuesAbove)
            return "→ " + chip.format.chipTime(chip.event.end, chip.use24);
        if (chip.continuesBelow || chip.content.timeForm === "start")
            return chip.format.chipTime(chip.event.start, chip.use24);
        return chip.format.timeRange(chip.event.start, chip.event.end, chip.use24);
    }

    TextMetrics {
        id: titleMetrics

        font.family: Theme.fontUi
        font.pointSize: Theme.pt(chip.content.titleSize)
        font.weight: Theme.weightMedium
        text: chip.rawTitle
    }

    /// The title, cut to fit at a word boundary. The width available is the
    /// text box the content rule sized, less whatever an inline time is taking
    /// off the end of the same line.
    readonly property string clippedTitle: {
        // Wrapping already breaks at word boundaries and elides the last line,
        // so the hand-cut form is only for the chips held to one.
        if (chip.content.titleLines > 1)
            return chip.rawTitle;
        const inlineCost = chip.content.mode === "inline"
            ? inlineTime.implicitWidth + Theme.space2 : 0;
        const avail = chip.content.textWidth - inlineCost;
        if (chip.rawTitle.length === 0 || titleMetrics.width <= avail)
            return chip.rawTitle;
        const advance = titleMetrics.width / chip.rawTitle.length;
        return chip.layoutPolicy.clipTitle(chip.rawTitle, Math.floor(avail / advance));
    }

    MouseArea {
        id: pointer

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.activated(chip.event ? chip.event.id : "")
    }
}
