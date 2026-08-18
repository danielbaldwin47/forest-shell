// One edge of a dashed rectangle, in plain `QtQuick`, **two pixels thick and
// two colours**.
//
// `QtQuick.Shapes` would draw this in four lines and is installed here, but it
// is a second scene-graph renderer pulled in for one hairline, and the harness
// that has to photograph it runs offscreen as well as on a session. A run of
// rectangles is arithmetic the plain renderer already does, and the arithmetic
// is one line: an edge `n` long carries `(n + gap) / (dash + gap)` marks.
//
// The two colours are the reason it is 2px. The origin outline is drawn in the
// drag's own hue, and during a **resize** it lies across the lifted card, which
// is that same hue at full strength — measured 1.0:1, which is to say the
// pre-drag extent was not on the picture at all. One pixel of the hue with one
// pixel of the lift ink under it reads either way round: the hue carries it
// over the grid, the ink carries it over the card. It is the halo the now-line
// already uses, cut into dashes.
//
// It is a file rather than an inline `component` because two surfaces draw the
// same mark: `WeekView` outlines the extent a resize is leaving, and
// `EventChip` hollows itself into the slot a move is leaving. An inline
// component is reachable from exactly one file, and a second copy of a dash
// pattern is a second thing to keep in step.
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: edge

    property bool vertical: false
    property color ink: "transparent"
    property color halo: "transparent"

    readonly property int dash: CalendarTokens.vacatedDash
    readonly property real span: edge.vertical ? edge.height : edge.width

    clip: true

    Repeater {
        model: Math.max(1, Math.ceil((edge.span + edge.dash) / (edge.dash * 2)))

        delegate: Rectangle {
            required property int index

            color: edge.ink
            x: edge.vertical ? 0 : index * edge.dash * 2
            y: edge.vertical ? index * edge.dash * 2 : 0
            width: edge.vertical ? 1 : edge.dash
            height: edge.vertical ? edge.dash : 1

            Rectangle {
                x: edge.vertical ? 1 : 0
                y: edge.vertical ? 0 : 1
                width: parent.width
                height: parent.height
                color: edge.halo
            }
        }
    }
}
