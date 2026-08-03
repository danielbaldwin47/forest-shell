// The chrome every dashboard card wears (#49): a caption, and a surface to sit
// on.
//
// A shared frame rather than each card drawing its own, for the reason the
// control centre's detail views share one: the cards are a *stack*, and a stack
// whose members disagree about their padding, radius or caption weight reads as
// several unrelated panels rather than as one dashboard. The cards then differ
// only in what they are about, which is the point.
//
// ## Why the frame's own children are assigned to `data`
//
// Because `default property alias content` below would otherwise swallow them.
// A default property declared on a root object applies to the children declared
// in *this* file too, so the caption and the body column would both be
// reparented into the body column — which is the column being made a child of
// itself. The explicit `data` assignment is what keeps the file's own children
// out of the alias (the same trap, and the same fix, as
// Surfaces/Drawers/DrillIn/DrillInPanel.qml).
import QtQuick
import QtQuick.Layouts
import qs.Core

Rectangle {
    id: frame

    /// The caption over the card. Empty means no caption and no space where one
    /// would have been — the media card names itself with the track it is
    /// playing, and a "MEDIA" over that is a word saying what the picture below
    /// it already says.
    property string title: ""

    /// Where a card's contents go.
    default property alias content: body.data

    color: Theme.surfaceRaised
    radius: Theme.radiusMd
    border.width: Theme.hairline
    border.color: Theme.borderSubtle

    // Sized from its contents rather than anchored to them, for the reason
    // Surfaces/Drawers/ControlCenter.qml documents: an `anchors.fill` between a
    // layout and its container is a height cycle, and Qt breaks it by zeroing
    // the layout.
    implicitHeight: column.implicitHeight + Theme.space3 * 2

    data: [
        ColumnLayout {
            id: column

            x: Theme.space3
            y: Theme.space3
            width: frame.width - Theme.space3 * 2
            spacing: Theme.space2

            Text {
                Layout.fillWidth: true
                visible: frame.title !== ""
                text: frame.title.toUpperCase()
                color: Theme.textMuted
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(Theme.capsSize)
                font.letterSpacing: Theme.tracking(Theme.capsSize, Theme.capsTrackingEm)
                font.weight: Theme.weightMedium
            }

            ColumnLayout {
                id: body

                Layout.fillWidth: true
                spacing: Theme.space2
            }
        }
    ]
}
