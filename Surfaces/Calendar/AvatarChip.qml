// One person, drawn as a disc of their initials.
//
// There are three places in this surface that draw a guest — the chip's guest
// row, the event editor's invited list, and the picker's results — and before
// this file there was one of them, open-coded, which is how the other two would
// have ended up 18px in one place and 26 in another with three different ideas
// about what point size fits inside a circle.
//
// ## What it decides: nothing
//
// The initials are `GuestPolicy.initials`, the type size is
// `CalendarTokens.monogramPt`, and the two colours are handed in — because the
// *right* pair depends on where the disc is standing, and only the caller knows
// that. Inside a tinted event chip the pair is the chip's own ink and fill
// (`CalendarTokens.monogramFill`/`monogramInk`), so four guests do not put four
// unrelated colours inside one event. In the picker a row *is* a person, so the
// pair is that person's own colour and the page's base. Both are legitimate and
// neither belongs to this file.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Item {
    id: avatar

    /// One or two glyphs — `GuestPolicy.initials(name)`. Passed in rather than
    /// derived from a name here, because every caller already has the policy's
    /// answer in the row it is drawing.
    property string initials: ""

    /// The disc.
    property color fill: Theme.surfaceOverlay

    /// The letters on it.
    property color ink: Theme.textPrimary

    /// Across, in pixels. The type follows it.
    property int size: 24

    /// A ring in the page's own background, for a row of discs that overlap.
    /// Zero — no ring at all — for discs with air between them.
    property int ringWidth: 0
    property color ringColour: Theme.surface

    implicitWidth: avatar.size
    implicitHeight: avatar.size
    width: avatar.implicitWidth
    height: avatar.implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusFull
        color: avatar.fill
        border.width: avatar.ringWidth
        border.color: avatar.ringColour

        Text {
            anchors.centerIn: parent
            text: avatar.initials
            color: avatar.ink
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(CalendarTokens.monogramPt(avatar.size))
            font.weight: Theme.weightMedium
        }
    }
}
