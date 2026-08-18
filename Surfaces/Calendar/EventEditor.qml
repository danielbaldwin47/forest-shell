// The event panel: everything about one event, opened by Enter on a selection,
// by `ipc call calendar openEvent`, or by a click on its chip.
//
// ## A popover on the chip, not a panel down the right-hand side
//
// The reference puts this in a permanent right-hand rail. That is the wrong
// shape *here*, and the reason is the grid rather than taste: a rail is 360px
// the week columns do not have. Opening one on a 1180-wide window takes each of
// the seven columns from ~118 to ~66 — so the act of opening an event reflows
// every chip on screen, and the chip that was just clicked slides out from
// under the pointer. Notion can afford it because its rail is *always* there;
// paying that cost only on open is the worst of the two arrangements.
//
// So it is an anchored popover, placed by `CreatePolicy.popoverAnchor` — the
// same arithmetic, the same flip and the same clamp the quick-create panel
// uses. Two panels on one surface that appear in different places by different
// rules would be two panels a person has to learn separately.
//
// The width is the spec's 360 and not quick-create's 320: this one carries a
// guest list, and a name plus an address on a 320 row elides one of them.
//
// ## What it decides: nothing
//
// Placement is `CreatePolicy`, every label is `CalendarFormat`, the guest
// ranking is `GuestPolicy`, and the hues are `CalendarTokens`. What is left is
// a focus order, four verbs and an Escape.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Services.Calendar
import qs.Widgets

Item {
    id: editor

    /// The event being edited — `{id, title, start, end, colour, guests}`.
    required property var event

    /// Its hue index, so the swatch row shows which one is on.
    property int hue: 0

    property bool use24: false

    /// Everybody the shell knows about, handed down rather than read here, so
    /// the panel has one source of people and the capture harness can pose it.
    property var contacts: []

    /// Which side of the chip the placement put it on, so the scale-in grows
    /// out of the anchored edge.
    property bool flipped: false

    /// Where the caret points, in this panel's own coordinates. See
    /// `QuickCreatePopover.caretY` — same decision, same policy, so the two
    /// panels point at their chip the same way.
    property real caretY: 0

    /// A posed query for the picker, and whether its list is showing. Both
    /// exist for tools/capture-harness.sh: a photograph of a closed picker says
    /// nothing about whether searching works.
    property string guestQuery: ""
    property bool guestListOpen: false

    property CalendarFormat format: CalendarFormat {}

    signal renamed(string title)
    signal recoloured(string colour)
    signal guestAdded(string contactId)
    signal guestRemoved(string contactId)
    signal deleted
    signal dismissed(string reason)

    /// A `Ctrl` chord that arrived while one of this panel's fields held the
    /// caret. It goes back to the window rather than being handled here.
    ///
    /// It has to, because Qt binds several of them *inside* a `TextInput` —
    /// `Ctrl+K` is `QKeySequence::DeleteEndOfLine` on this platform — so a
    /// panel with the caret would silently swallow the command menu's own
    /// shortcut. Measured: with the editor open, `Ctrl+K` reached nothing.
    ///
    /// The event travels rather than a verb: whoever handles it accepts it if
    /// it is one of theirs and leaves it alone if it is not, so `Ctrl+A` and
    /// `Ctrl+V` still do what a text field does.
    signal chordPressed(var event)

    /// True while a `Ctrl` chord is worth forwarding at all. Bare keys are the
    /// field's own business — that is what `KeyNavPolicy`'s `typing` gate is
    /// for at the other end.
    function forwardChord(keyEvent: var): void {
        if (keyEvent.modifiers & Qt.ControlModifier)
            editor.chordPressed(keyEvent);
    }

    readonly property string eventId: editor.event ? editor.event.id : ""

    width: 360
    height: card.height

    /// Focus arrives on the title, with the caret at the end and **nothing
    /// selected**. Quick-create selects all because the title there is a
    /// placeholder somebody is expected to replace; here it is a name that
    /// already means something, and a panel whose first keystroke silently
    /// erases it is a panel that eats work.
    function takeFocus(): void {
        titleField.forceActiveFocus();
        titleField.cursorPosition = titleField.text.length;
    }

    function commitTitle(): void {
        const name = titleField.text.trim();
        if (name.length > 0 && editor.event && name !== editor.event.title)
            editor.renamed(name);
    }

    Component.onCompleted: editor.takeFocus()

    // Escape closes the panel — but only once whatever has the caret has
    // declined it. The picker takes the first one when its field has something
    // typed in it, which is the one-Escape-per-layer rule the window applies to
    // its own overlays.
    Keys.onPressed: keyEvent => {
        if (keyEvent.key === Qt.Key_Escape) {
            editor.commitTitle();
            editor.dismissed("escape");
            keyEvent.accepted = true;
        }
    }

    /// The elevation, as stacked plates rather than a `MultiEffect` — the
    /// effect draws nothing on the offscreen scenegraph, and a panel invisible
    /// in half the capture modes is a panel nobody can judge.
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
        height: rows.implicitHeight + Theme.space4 * 2
        radius: Theme.radiusMd
        color: Theme.surfaceRaised
        border.width: 1
        border.color: Theme.borderSubtle

        transformOrigin: editor.flipped ? Item.TopRight : Item.TopLeft
        scale: Theme.animateTransforms ? CalendarTokens.popoverScaleFrom : 1
        opacity: Theme.animateTransforms ? 0 : 1
        Component.onCompleted: {
            card.scale = 1;
            card.opacity = 1;
        }
        Behavior on scale {
            enabled: Theme.animateTransforms
            NumberAnimation {
                duration: Theme.duration(CalendarTokens.motionPopover)
                easing.type: Easing.OutCubic
            }
        }
        Behavior on opacity {
            enabled: Theme.animateTransforms
            NumberAnimation {
                duration: Theme.duration(CalendarTokens.motionPopover)
                easing.type: Easing.OutCubic
            }
        }

        /// The caret, pointing back at the chip this editor is about. Same
        /// 10px square turned 45° the quick-create panel uses, and the same 1px
        /// plate opening the seam where it meets the card.
        Rectangle {
            id: caret

            width: 10
            height: 10
            x: editor.flipped ? card.width - width / 2 : -width / 2
            y: Math.max(6, Math.min(card.height - 16, editor.caretY - height / 2))
            rotation: 45
            color: card.color
            border.width: 1
            border.color: card.border.color
        }

        Rectangle {
            x: editor.flipped ? card.width - caret.width + 1 : 0
            y: caret.y - 4
            width: caret.width - 1
            height: caret.height + 8
            color: card.color
        }

        Column {
            id: rows

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.space4
            spacing: Theme.space3

            /// The name. Borderless, for the same reason quick-create's is: a
            /// box round it would make it one field among several when it is
            /// the heading of the whole panel.
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
                    text: editor.event && editor.event.title ? editor.event.title : ""
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

                    // Tab is spelled out rather than left to the scene graph's
                    // own traversal, so "focus the guests field" is one key
                    // with one answer — which is what seam 2 drives.
                    KeyNavigation.tab: guestPicker.fieldItem

                    // Enter and focus loss both commit; Escape is the panel's,
                    // handled above.
                    onEditingFinished: editor.commitTitle()

                    Keys.onPressed: keyEvent => editor.forwardChord(keyEvent)
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    visible: !titleField.activeFocus
                    color: Theme.borderSubtle
                }

                /// The focus ring — see `QuickCreatePopover` for the argument.
                /// This panel has two focusable fields rather than one, which
                /// makes it stronger here: Tab moves between them, and a ring
                /// says which one has the keys at a glance where two accent
                /// underlines a hundred pixels apart do not.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -Theme.space2
                    anchors.bottomMargin: -Theme.space1
                    visible: titleField.activeFocus
                    radius: Theme.radiusSm
                    color: Qt.alpha(Theme.accentPrimary, 0.06)
                    border.width: 2
                    border.color: Theme.accentPrimary
                }
            }

            /// When it is. A row, so the icon column starts here and every
            /// section below lines up under it.
            Item {
                width: parent.width
                height: 36

                Icon {
                    id: clockIcon

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    name: "clock"
                    size: 20
                    color: Theme.textMuted
                }

                Text {
                    anchors.left: clockIcon.right
                    anchors.leftMargin: Theme.space3
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: editor.event
                          ? editor.format.dayTitle(
                                editor.format.time.dayOf(editor.event.start))
                            + "  ·  "
                            + editor.format.timeRange(editor.event.start,
                                                      editor.event.end, editor.use24)
                          : ""
                    color: Theme.textSecondary
                    font.family: Theme.fontUi
                    font.features: CalendarTokens.tabularFigures
                    font.pointSize: Theme.pt(12.5)
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }

            /// Guests. The heading row carries the icon; the picker sits under
            /// it in the same left inset as the text beside every other icon,
            /// so the panel reads as one column of content rather than two.
            Item {
                width: parent.width
                height: 24

                Icon {
                    id: guestsIcon

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    name: "users"
                    size: 20
                    color: Theme.textMuted
                }

                Text {
                    anchors.left: guestsIcon.right
                    anchors.leftMargin: Theme.space3
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Guests"
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(Theme.capsSize)
                    font.letterSpacing: Theme.pt(Theme.capsSize) * Theme.capsTrackingEm
                    font.capitalization: Font.AllUppercase
                }
            }

            Item {
                width: parent.width
                height: guestPicker.height

                GuestPicker {
                    id: guestPicker

                    x: guestsIcon.width + Theme.space3
                    width: parent.width - x

                    eventId: editor.eventId
                    contacts: editor.contacts
                    guestIds: editor.event && editor.event.guests
                              ? editor.event.guests : []

                    query: editor.guestQuery
                    listOpen: editor.guestListOpen

                    onChordPressed: keyEvent => editor.chordPressed(keyEvent)

                    onAdded: contactId => editor.guestAdded(contactId)
                    onRemoved: contactId => editor.guestRemoved(contactId)
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }

            /// The hue. Eight circles, the event's own ringed — the same row
            /// quick-create carries, so recolouring is the same gesture
            /// wherever an event is open.
            Item {
                width: parent.width
                height: 24

                Icon {
                    id: hueIcon

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    name: "palette"
                    size: 20
                    color: Theme.textMuted
                }

                Row {
                    anchors.left: hueIcon.right
                    anchors.leftMargin: Theme.space3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space2

                    Repeater {
                        model: CalendarTokens.hues.count

                        delegate: Rectangle {
                            id: swatch

                            required property int index

                            readonly property bool on: swatch.index === editor.hue

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
                                onClicked: editor.recoloured(
                                    CalendarTokens.hues.names[swatch.index])
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }

            /// The one destructive verb, last and in the ember — where the
            /// spec puts destructive rows, and as far from the title field as
            /// the panel goes.
            Item {
                id: deleteRow

                width: parent.width
                height: 36

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: -Theme.space2
                    anchors.rightMargin: -Theme.space2
                    radius: Theme.radiusSm
                    color: deletePointer.containsMouse ? Theme.surfaceOverlay
                                                       : "transparent"
                }

                Icon {
                    id: deleteIcon

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    name: "trash-2"
                    size: 20
                    color: Theme.accentEmber
                }

                Text {
                    anchors.left: deleteIcon.right
                    anchors.leftMargin: Theme.space3
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Delete event"
                    color: Theme.accentEmber
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(12.5)
                    font.weight: Theme.weightMedium
                }

                MouseArea {
                    id: deletePointer

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        editor.deleted();
                        editor.dismissed("delete");
                    }
                }
            }
        }
    }
}
