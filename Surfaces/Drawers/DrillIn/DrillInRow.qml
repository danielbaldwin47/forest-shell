// One row inside a control-centre detail view (#45): a glyph, a name, a line
// under it, and an optional trailing slot.
//
// Four of the five panels are a list of these — networks, devices, outputs,
// tunnels — because they are all the same gesture: a thing with a state, that a
// press changes. Only the wallpaper picker is not, and that is because it is a
// grid of pictures rather than a list of names.
//
// ## The text column is what this layout protects
//
// #80 was a row whose text starved because something beside it grew, and every
// list here is fed arbitrary text from outside the shell: an SSID is whatever
// somebody named their router, a bluetooth device is whatever the vendor
// flashed, a PipeWire description is whatever the driver reports. So the glyph
// and the trailing slot are both fixed-width and the middle takes the rest,
// and both lines in the middle elide rather than wrapping — a two-line SSID
// would make one row twice the height of its neighbours.
//
// The `data` assignment below is the same guard DrillInPanel.qml explains at
// length: a `default property alias` on a root object captures this file's own
// children too, so without it the `RowLayout` would be reparented into the
// trailing slot that lives inside it.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets

Rectangle {
    id: row

    required property string glyph
    required property string label

    /// The line under the name. Absent rather than blank when empty, so a row
    /// with nothing to add is a short row rather than one with a gap in it.
    property string detail: ""

    /// Drawn as engaged: the connected network, the current output, the tunnel
    /// that is up. The same `accentPrimary` the shell uses for a live thing,
    /// on the glyph and the name rather than as a fill — nine tiles of fill is
    /// a grid, but a list of fills is a list nobody can read down.
    property bool active: false

    /// Greyed and unpressable: a network this shell cannot join, a device BlueZ
    /// is busy with. Still drawn, because a row that vanished would be a row
    /// the user has to wonder about.
    property bool dimmed: false

    /// What goes on the right — a lock, a tick, a slider, nothing.
    default property alias trailing: trailingSlot.data

    signal activated
    /// The second gesture, where a row has one: forget this network, unpair
    /// this device. Right-click, and only that — a destructive act behind a
    /// long-press is one people trigger by accident on a laptop trackpad.
    signal secondary

    width: parent ? parent.width : 0
    implicitHeight: 44
    radius: Theme.radiusMd
    color: hover.hovered && !row.dimmed ? Theme.surfaceRaised : "transparent"

    // A fill, so it fades, at the in-place step — nothing but this rectangle
    // changes (Core/EffectsPolicy.qml).
    Behavior on color {
        ColorAnimation {
            duration: Theme.duration(Theme.motionFast)
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.fogEase
        }
    }

    data: [
        HoverHandler {
            id: hover
            cursorShape: row.dimmed ? Qt.ArrowCursor : Qt.PointingHandCursor
        },

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: if (!row.dimmed) row.activated();
        },

        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: if (!row.dimmed) row.secondary();
        },

        RowLayout {
            anchors.fill: row
            anchors.leftMargin: Theme.space2
            anchors.rightMargin: Theme.space2
            spacing: Theme.space2

            Icon {
                Layout.alignment: Qt.AlignVCenter
                name: row.glyph
                size: 18
                color: row.dimmed ? Theme.textMuted
                     : row.active ? Theme.accentPrimary
                                  : Theme.textSecondary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: row.label
                    // Elided and never wrapped: an SSID is arbitrary text from
                    // outside the shell, and a two-line one would make this row
                    // twice the height of its neighbours.
                    elide: Text.ElideRight
                    color: row.dimmed ? Theme.textMuted : Theme.textPrimary
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(11.5)
                    font.weight: row.active ? Theme.weightMedium : Theme.weightRegular
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: row.detail
                    elide: Text.ElideRight
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(10)
                }
            }

            // Fixed by whatever is put in it, never by the text beside it —
            // which is the #80 rule stated as a layout.
            Item {
                id: trailingSlot

                Layout.alignment: Qt.AlignVCenter
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
            }
        }
    ]
}
