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

    /// `GuestPolicy.summary` for this event, resolved by the view that has the
    /// contact book. `null` — the default — is a chip with nothing to say about
    /// guests, which is every chip in a week column: the guest line is a thing
    /// a *wide* chip earns, and `chipContent.showGuests` is the gate.
    property var guests: null

    readonly property int guestCount:
        (chip.guests && chip.guests.count) ? chip.guests.count : 0

    /// The event's real duration in minutes. Passed in rather than derived from
    /// `height`, because `chipMinH` floors a short event's height and the
    /// content rule needs the duration that was floored, not the floor.
    property real minutes: 60

    /// How many cascade steps into an overlap cluster this chip is — 0 for a
    /// chip that shares its column side by side, higher for one drawn over a
    /// neighbour. `EventLayoutPolicy.layout` decides it; the chip only reads it
    /// as "am I a card lying on another card", which is a picture and so lives
    /// here.
    property int depth: 0

    /// How many pixels of this chip a cascaded neighbour leaves visible.
    /// `Infinity` — the default — is "all of them", which is every chip nothing
    /// is drawn over.
    property real clearHeight: Infinity

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
        chip.layoutPolicy.chipContent(chip.width, chip.height, chip.minutes,
                                      chip.clearHeight)

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

    /// The lift under a cascaded chip.
    ///
    /// A chip drawn over another needs an edge that is not the other chip's
    /// fill, or the two tints run together and the stack reads as one chip with
    /// a scratch down it. This is that edge and it is deliberately *one* pixel
    /// of the page colour: the reference's own answer to the same problem is a
    /// rail, a sliver of the chip beneath and a pale shadow gap stacked up to
    /// about twelve pixels of decoration, which is a stripe pattern rather than
    /// a shadow. One dark pixel outside the corner reads as a card lying on a
    /// card and costs the chip underneath nothing.
    Rectangle {
        visible: chip.depth > 0
        anchors.fill: parent
        anchors.margins: -1
        radius: (chip.content.tight ? 3 : Theme.radiusSm) + 1
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Theme.bgBase, 0.85)
    }

    Rectangle {
        id: body

        anchors.fill: parent
        clip: true
        // A 6px radius on a 40px chip eats the top and bottom of the accent
        // bar clipped inside it, and the bar then reads as a floating tick
        // rather than the chip's own edge. The packed tier corners at 3, which
        // is still a corner and leaves the bar whole.
        radius: chip.content.tight ? 3 : Theme.radiusSm
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
            // Bounded by the visible box for the reason the one-line row below
            // is, even though both its children hang off the top edge.
            height: Math.min(parent.height, chip.clearHeight)
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
                // `Text.Wrap`, not `WordWrap`: word boundaries first, and a
                // break inside a word only where no boundary can fit. Under
                // `WordWrap` a word wider than the box overhangs and is clipped
                // by the body with no ellipsis to say so — a silent lie about
                // the title, where `Wrap` at least admits the cut.
                wrapMode: chip.content.titleLines > 1 ? Text.Wrap : Text.NoWrap
                elide: Text.ElideRight
                maximumLineCount: chip.content.titleLines
                color: CalendarTokens.text(chip.hue)
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(chip.content.titleSize)
                font.weight: Theme.weightMedium
            }

            Text {
                id: stackedTime

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: stackedTitle.bottom
                // The banner tier has already spent its slack on the second
                // line; a leading of even one pixel is the pixel that would
                // clip its descenders against the card below.
                anchors.topMargin:
                    (chip.content.narrow || chip.content.banner) ? 0 : 1
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
                font.features: CalendarTokens.tabularFigures
                // Full strength, not the 0.78 the spec asked for. Measured with
                // `tools/measure-contrast.py`'s arithmetic: the eight dark texts
                // on their own fills are 4.56-5.43:1 at alpha 1 and **3.44-4.00
                // at 0.78** — so the fade the spec wanted for hierarchy was
                // spending the one ratio a chip is not allowed to spend. Size
                // and weight carry the hierarchy instead; they cost nothing
                // legibility owns.
                color: CalendarTokens.text(chip.hue)
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(chip.content.timeSize)
                // Regular carries the hierarchy at the roomy sizes; at the
                // banner and tight tiers it stops carrying anything. A pt(9)
                // stem is under a pixel wide, so half its coverage is
                // antialiasing and the *measured* ratio off a capture drops
                // roughly a point below the computed one. Medium puts the ink
                // back without moving the size, and at 9 against a 10.5 title
                // the size difference is still the hierarchy.
                font.weight: (chip.content.banner || chip.content.tight)
                    ? Theme.weightMedium : Theme.weightRegular
            }

            /// The guest line — the third thing a wide chip says, and the one
            /// the day view exists to have room for.
            ///
            /// Avatars in the chip's **own hue** rather than in a per-person
            /// colour. A guest palette would put four unrelated colours inside
            /// one tinted box and the chip would stop reading as one event; the
            /// initials are what tell people apart, and the hue is what tells
            /// events apart. `GuestPolicy.colourFor` stays for the picker,
            /// where a row *is* a person.
            Row {
                id: guestRow

                visible: chip.content.showGuests && chip.guestCount > 0
                // Left edge only: a `Row` sizes itself from its children, and
                // anchoring both sides would fight that. The body clips, which
                // is the backstop if a name ever runs the width.
                anchors.left: parent.left
                anchors.top: stackedTime.bottom
                anchors.topMargin: 3
                spacing: Theme.space1

                Repeater {
                    model: (guestRow.visible && chip.guests) ? chip.guests.shown : []

                    delegate: Rectangle {
                        id: avatar

                        required property var modelData

                        width: 18
                        height: 18
                        radius: Theme.radiusFull
                        color: CalendarTokens.monogramFill(chip.hue)

                        Text {
                            anchors.centerIn: parent
                            text: avatar.modelData.initials
                            color: CalendarTokens.monogramInk(chip.hue)
                            font.family: Theme.fontUi
                            // 9.5 and not 8.5. Two glyphs at 8.5 are 9px of
                            // type inside an 18px disc — the disc reads and the
                            // letters do not, which is the worst of both.
                            font.pointSize: Theme.pt(9.5)
                            font.weight: Theme.weightMedium
                        }
                    }
                }

                /// The guests, named rather than counted — the discs beside it
                /// already say how many there are, and a `2 guests` after two
                /// discs is the same fact twice. See `GuestPolicy.nameLine`.
                Text {
                    id: guestLabel

                    anchors.verticalCenter: parent.verticalCenter
                    visible: guestLabel.text !== ""
                    text: chip.guests ? (chip.guests.line || "") : ""
                    elide: Text.ElideRight
                    color: CalendarTokens.text(chip.hue)
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(chip.content.guestSize)
                    font.weight: Theme.weightRegular
                }
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
            // **The box is the visible box, not the chip.** A one-line chip
            // centres its line, and a cascaded chip covered 30 minutes into a
            // 90-minute box centres it 42px down — behind the card that covers
            // it. Bounding the row by the clear band puts the line where it can
            // be read; on every chip nothing covers, `clearHeight` is infinite
            // and this is the chip's own height, as it was.
            height: Math.min(parent.height, chip.clearHeight)
            anchors.leftMargin: chip.content.padLeft
            anchors.rightMargin: chip.content.padRight

            Text {
                id: inlineTime

                visible: chip.content.showTime && chip.inlineTimeShown
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: chip.timeLabel
                // Full strength, for the reason the stacked time above is.
                color: CalendarTokens.text(chip.hue)
                font.features: CalendarTokens.tabularFigures
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(chip.content.timeSize)
                font.weight: Theme.weightRegular
            }

            Text {
                anchors.left: parent.left
                anchors.right: inlineTime.visible ? inlineTime.left : parent.right
                // `space1` and not `space2`: on a one-line chip the gap is the
                // only thing standing between a whole title and `Stand…`, and
                // four pixels of air already separate two runs of type at
                // different weights.
                anchors.rightMargin: inlineTime.visible ? Theme.space1 : 0
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

        /// The resize grip: a 24x3 pill on the bottom edge, in the chip's hue.
        ///
        /// **Under the pointer only**, and it took a capture to settle which
        /// way round. Drawn always it was meant to say "this edge can be taken
        /// hold of"; what it actually did on a still page was put a faint
        /// centred dash inside every chip, and the reading that came back was
        /// not "handle" but "rendering fault" — a mark with no edge, no
        /// gradient and nothing to grab. An affordance that has to be explained
        /// is decoration. It appears when the pointer is on the chip, which is
        /// the only moment a hand can act on it, and brightens again on the
        /// resize strip itself.
        ///
        /// Which chips get one is `EventLayoutPolicy.showsGrip` — a height and a
        /// clear height, so a half-hour chip and a chip buried under a cascaded
        /// neighbour both keep their one clean line.
        Rectangle {
            visible: chip.hovered
                     && chip.layoutPolicy.showsGrip(chip.height, chip.clearHeight)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            width: 24
            height: 3
            radius: 1.5
            color: CalendarTokens.bar(chip.hue)
            opacity: resizeEdge.containsMouse ? 0.95 : 0.7

            Behavior on opacity {
                enabled: Theme.duration(Theme.motionFast) > 0
                NumberAnimation {
                    duration: Theme.duration(Theme.motionFast)
                    easing.type: Easing.OutCubic
                }
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
        const meridiem = chip.content.timeMeridiem;
        if (chip.continuesAbove)
            return "→ " + chip.format.startTime(chip.event.end, chip.use24, meridiem);
        if (chip.continuesBelow || chip.content.timeForm === "start")
            return chip.format.startTime(chip.event.start, chip.use24, meridiem);
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
    /// Whether the one-line row keeps its time. The two measurements are the
    /// chip's; the rule is `EventLayoutPolicy.inlineTimeFits`.
    readonly property bool inlineTimeShown:
        chip.content.mode !== "inline"
        || chip.layoutPolicy.inlineTimeFits(chip.content.textWidth,
                                            titleMetrics.width,
                                            inlineTime.implicitWidth,
                                            Theme.space1)

    readonly property string clippedTitle: {
        // Wrapping already breaks at word boundaries and elides the last line,
        // so the hand-cut form is only for the chips held to one.
        if (chip.content.titleLines > 1)
            return chip.rawTitle;
        const inlineCost = (chip.content.mode === "inline" && chip.inlineTimeShown)
            ? inlineTime.implicitWidth + Theme.space1 : 0;
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

    /// The bottom strip, over the body's own pointer area so the edge answers
    /// with the resize cursor rather than the hand. 6px, which is the smallest
    /// strip a pointer lands on reliably and half of what would eat the last
    /// line of type on a chip that shows one.
    MouseArea {
        id: resizeEdge

        visible: chip.layoutPolicy.showsGrip(chip.height, chip.clearHeight)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 6
        hoverEnabled: true
        cursorShape: Qt.SizeVerCursor
    }
}
