// The panel that opens on the chip a drag just made.
//
// ## Why the event already exists by the time this opens
//
// The obvious design is a form that *makes* the event when it is submitted, and
// it is the wrong one here. The gesture that opened this panel already said
// everything an event needs — a day, a start, a length — and the chip is
// already on the grid where the pointer left it. A panel that held the event
// hostage until a title was typed would mean a drag that lost its work to a
// stray click on the grid, which is the one thing a drag must never do.
//
// So the store commits on release and this panel *renames* what is already
// there. That decides the two exits, and they are deliberately different:
//
//   - **Escape keeps the event** under the default title `New event`. The
//     drag happened; throwing it away because the person did not want to name
//     it yet would be discarding work they did on purpose. `New event` and not
//     `Untitled event` — the reference's word — because the list this shows up
//     in is a calendar, where "untitled" reads as an error state and "new"
//     reads as a thing to get back to.
//   - **Discard deletes it**, and says so in a word, because that is the exit
//     for "I did not mean to drag at all" and it needs to be reachable without
//     a second gesture on the chip.
//
// ## What it decides: nothing
//
// Placement is `CreatePolicy.popoverAnchor` — side, flip and clamp are
// arithmetic and are tested there. Every label is `CalendarFormat`. The panel's
// own job is to hold a focused field and route four verbs at the store.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Item {
    id: popover

    /// The event this panel is naming — `{id, title, start, end, colour}`.
    required property var event

    /// Its hue index, so the swatch row can show which one is on.
    property int hue: 0

    property bool use24: false

    /// Which side of the chip it ended up on, so the scale-in grows out of the
    /// anchored edge rather than the far one. `CreatePolicy.popoverAnchor`
    /// decides it and the view does the placing — a panel that positioned
    /// itself would have to know what it is inside, and this one is hosted by
    /// the week grid today and by the month grid tomorrow.
    property bool flipped: false

    property CalendarFormat format: CalendarFormat {}

    signal renamed(string title)
    signal recoloured(string colour)
    signal discarded
    signal dismissed(string reason)

    readonly property string eventId: popover.event ? popover.event.id : ""

    /// 320 wide is the spec's; the height is whatever the rows come to, so a
    /// change to the type scale moves the panel rather than clipping it.
    width: 320
    height: card.height

    /// Focus arrives with the panel and not a click later: the whole point of
    /// the gesture is that the next thing typed is the title.
    function takeFocus(): void {
        titleField.forceActiveFocus();
        titleField.selectAll();
    }

    Component.onCompleted: popover.takeFocus()

    /// The elevation, as three stacked plates rather than a `MultiEffect`:
    /// the effect draws nothing on the offscreen scenegraph (`Widgets/Icon.qml`
    /// measured it), and a popover that is invisible in half the capture modes
    /// is a popover nobody can judge.
    Rectangle {
        anchors.fill: card
        anchors.margins: -6
        radius: Theme.radiusMd + 6
        color: CalendarTokens.shadowAmbient
    }

    Rectangle {
        anchors.fill: card
        anchors.margins: -2
        anchors.topMargin: -1
        anchors.bottomMargin: -3
        radius: Theme.radiusMd + 2
        color: CalendarTokens.shadowKey
    }

    Rectangle {
        id: card

        width: parent.width
        height: rows.height + Theme.space4 * 2
        radius: Theme.radiusMd
        color: Theme.surfaceRaised
        border.width: 1
        border.color: Theme.borderSubtle

        /// Scale-and-fade in from the anchored edge, `motionFast`, the same
        /// motion every other popover in this surface uses.
        transformOrigin: popover.flipped ? Item.TopRight : Item.TopLeft
        scale: Theme.animateTransforms ? 0.96 : 1
        opacity: Theme.animateTransforms ? 0 : 1
        Component.onCompleted: {
            card.scale = 1;
            card.opacity = 1;
        }
        Behavior on scale {
            enabled: Theme.animateTransforms
            NumberAnimation {
                duration: Theme.duration(Theme.motionFast)
                easing.type: Easing.OutCubic
            }
        }
        Behavior on opacity {
            enabled: Theme.animateTransforms
            NumberAnimation {
                duration: Theme.duration(Theme.motionFast)
                easing.type: Easing.OutCubic
            }
        }

        Column {
            id: rows

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.space4
            spacing: Theme.space3

            /// The title field. Borderless, because a box around it would make
            /// it look like one field among several when it is the only one the
            /// panel exists for — the caret and the rule under it are the whole
            /// affordance.
            Item {
                width: parent.width
                height: titleField.height + Theme.space2 + 1

                Text {
                    anchors.left: titleField.left
                    anchors.verticalCenter: titleField.verticalCenter
                    visible: titleField.text.length === 0
                    text: "New event"
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(14)
                }

                TextInput {
                    id: titleField

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: Math.ceil(contentHeight) + 2
                    color: Theme.textPrimary
                    selectionColor: Qt.alpha(Theme.accentPrimary, 0.35)
                    selectedTextColor: Theme.textPrimary
                    cursorDelegate: Rectangle {
                        width: 2
                        color: Theme.accentPrimary
                    }
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(14)
                    font.weight: Theme.weightMedium

                    // Enter commits the name, Escape leaves the event alone.
                    // Both are accepted here rather than left to bubble: the
                    // window's own Escape closes the whole calendar, and a
                    // person dismissing a naming panel is not asking for that.
                    Keys.onPressed: keyEvent => {
                        if (keyEvent.key === Qt.Key_Escape) {
                            popover.dismissed("escape");
                            keyEvent.accepted = true;
                        } else if (keyEvent.key === Qt.Key_Return
                                   || keyEvent.key === Qt.Key_Enter) {
                            const name = titleField.text.trim();
                            if (name.length > 0)
                                popover.renamed(name);
                            popover.dismissed("commit");
                            keyEvent.accepted = true;
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: titleField.activeFocus ? Theme.accentPrimary : Theme.borderSubtle
                }
            }

            /// When it is, in the grammar the chips use.
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: popover.event
                      ? popover.format.dayTitle(popover.format.time.dayOf(popover.event.start))
                        + "  ·  "
                        + popover.format.timeRange(popover.event.start, popover.event.end,
                                                   popover.use24)
                      : ""
                color: Theme.textSecondary
                font.family: Theme.fontUi
                font.features: CalendarTokens.tabularFigures
                font.pointSize: Theme.pt(12.5)
            }

            /// The colour row. Eight circles, the event's own ringed — the one
            /// property of an event that is faster to pick than to describe.
            Row {
                spacing: Theme.space2

                Repeater {
                    model: CalendarTokens.hues.count

                    delegate: Rectangle {
                        id: swatch

                        required property int index

                        readonly property bool on: swatch.index === popover.hue

                        width: 16
                        height: 16
                        radius: Theme.radiusFull
                        color: CalendarTokens.bar(swatch.index)

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -3
                            radius: Theme.radiusFull
                            color: "transparent"
                            border.width: Theme.rail
                            border.color: Theme.borderStrong
                            visible: swatch.on
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -2
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popover.recoloured(CalendarTokens.hues.names[swatch.index])
                        }
                    }
                }
            }

            /// Guests. The field is here and the picker is not: the piece that
            /// wires it is the next one, and a panel that grew a row later
            /// would be a panel whose height nobody had judged. It reads as an
            /// empty field, which is what it is.
            Item {
                width: parent.width
                height: 24

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add guests"
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(12.5)
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Qt.alpha(Theme.borderSubtle, 0.6)
                }
            }

            /// Discard on the left, Save on the right — destructive away from
            /// the pointer's resting place, which is the corner it just came
            /// from.
            Item {
                width: parent.width
                height: CalendarTokens.controlH

                Row {
                    anchors.right: parent.right
                    spacing: Theme.space2

                    Rectangle {
                        id: discardButton

                        width: discardLabel.implicitWidth + Theme.space4 * 2
                        height: CalendarTokens.controlH
                        radius: Theme.radiusSm
                        color: discardPointer.containsMouse ? Theme.surfaceOverlay : "transparent"
                        border.width: 1
                        border.color: Theme.borderSubtle

                        Text {
                            id: discardLabel

                            anchors.centerIn: parent
                            text: "Discard"
                            color: Theme.textSecondary
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(12.5)
                            font.weight: Theme.weightMedium
                        }

                        MouseArea {
                            id: discardPointer

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                popover.discarded();
                                popover.dismissed("discard");
                            }
                        }
                    }

                    Rectangle {
                        width: saveLabel.implicitWidth + Theme.space4 * 2
                        height: CalendarTokens.controlH
                        radius: Theme.radiusSm
                        color: savePointer.containsMouse
                               ? Qt.lighter(Theme.accentPrimary, 1.08)
                               : Theme.accentPrimary

                        Text {
                            id: saveLabel

                            anchors.centerIn: parent
                            text: "Save"
                            color: Theme.bgBase
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(12.5)
                            font.weight: Theme.weightMedium
                        }

                        MouseArea {
                            id: savePointer

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const name = titleField.text.trim();
                                if (name.length > 0)
                                    popover.renamed(name);
                                popover.dismissed("commit");
                            }
                        }
                    }
                }
            }
        }
    }
}
