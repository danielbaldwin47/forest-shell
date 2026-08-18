// The people control: who is coming, a field to type into, and the rows that
// field turns up.
//
// ## One control, not two
//
// The invited list and the search box are the same widget on purpose. A picker
// that put "who is coming" somewhere else would need two answers to "is this
// person already on the list" — one the reader gives by looking up, one the
// search gives by hiding them — and the two would disagree the moment anything
// scrolled. Here the invited rows sit directly above the field that adds to
// them, so an added guest appears one row above the caret it was typed into.
//
// That is also what makes Backspace-on-empty legible: the thing it removes is
// the row immediately above the caret, which is where the eye already is.
//
// ## What it decides: nothing
//
// The ranking, the invite row, the wrap-around highlight and the initials are
// all `GuestPolicy` — `offer`, `moveSelection`, `initials` — and every one of
// them is tested at the first seam. What is left here is a field, a list, four
// keys and two signals.
//
// ## What it logs
//
// A search line per keystroke and nothing else. The store logs the add and the
// remove, because the store is what they happen to; this logs the *query*,
// which nothing else can see and which is the only way seam 2 can tell "typed
// and found two people" apart from "typed and found nobody". Empty queries are
// silent: opening the panel is not a search.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Services.Calendar

Item {
    id: picker

    /// Everybody the shell knows about — `CalendarStore.contacts`.
    property var contacts: []

    /// Who is on the event right now, as contact ids.
    property var guestIds: []

    /// The event, for the log line. `""` outside an editor.
    property string eventId: ""

    /// What is in the field. A property rather than the field's own state so a
    /// capture can pose a typed query without a keyboard — the same trick
    /// `CalendarView.commandQuery` plays on the command menu.
    property string query: ""

    /// Which row the highlight is on, and whether the results are showing at
    /// all. Posed for the same reason.
    property int highlight: 0
    property bool listOpen: false

    /// How many result rows are on screen before the list scrolls. Five, not
    /// `GuestPolicy.limit`'s eight: eight 40px rows is 320px of dropdown, which
    /// on a 360-wide panel is a list taller than the panel it hangs off.
    property int maxRows: 5

    signal added(string contactId)
    signal removed(string contactId)

    /// A `Ctrl` chord typed into the field, handed back up. See
    /// `EventEditor.chordPressed` for why a text field must not keep them.
    signal chordPressed(var event)

    property GuestPolicy guests: GuestPolicy {}

    /// The field itself, so whatever hosts this can put it in its own tab
    /// order. Handing out the item is what lets the editor above say
    /// `KeyNavigation.tab: guestPicker.fieldItem` and have one predictable
    /// order rather than whatever the scene graph's traversal happens to be.
    property alias fieldItem: field

    /// Who is coming, resolved for drawing.
    readonly property var invited:
        picker.guests.displayList(picker.guestIds, picker.contacts, null)

    /// What the field's contents turn up: the search, plus an `Invite …` row
    /// when the query is an address nobody owns. Already-invited people are
    /// excluded, which is what stops the same person being added twice from the
    /// keyboard at all — the store's own `(already)` line is the backstop for
    /// the ones that arrive over IPC.
    readonly property var rows:
        picker.guests.offer(picker.contacts, picker.query, picker.guestIds)

    readonly property bool resultsShown:
        picker.listOpen && picker.rows.length > 0

    implicitHeight: column.implicitHeight
    height: picker.implicitHeight

    function takeFocus(): void {
        field.forceActiveFocus();
    }

    /// Add whatever the highlight is on. Nothing when the list is empty, which
    /// is what makes Enter on a query that matched nobody a no-op rather than
    /// an accidental invite of the first person in the address book.
    function commit(): void {
        const list = picker.rows;
        if (list.length === 0)
            return;
        const row = list[Math.max(0, Math.min(picker.highlight, list.length - 1))];
        picker.added(row.id);
        picker.query = "";
        picker.highlight = 0;
    }

    function step(delta: int): void {
        picker.highlight = picker.guests.moveSelection(picker.highlight,
                                                       picker.rows.length, delta);
    }

    /// Uninvite the last person on the list — Backspace in an empty field. The
    /// *last*, because that is the one the field is sitting under.
    function removeLast(): void {
        const party = picker.invited;
        if (party.length === 0)
            return;
        picker.removed(party[party.length - 1].id);
    }

    onQueryChanged: {
        // A fresh query means a fresh list, so the old highlight index is a
        // pointer into a list that no longer exists.
        picker.highlight = 0;
        if (picker.query.length === 0)
            return;
        picker.listOpen = true;
        // Asked for again rather than read off `rows`. The binding is dirty at
        // this instant and not yet re-evaluated, so the line came out one
        // keystroke behind — measured: typing "mi" logged `"mi" 8 results`,
        // which is the answer to "m". A log that lags the thing it reports is
        // worse than no log, because seam 2 believes it.
        const found = picker.guests.offer(picker.contacts, picker.query,
                                          picker.guestIds);
        Logger.log("calendar", "guest search \"" + picker.query + "\" "
                   + found.length + " results");
    }

    Column {
        id: column

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.space1

        /// Who is coming. One row each, name and address, with the disc in that
        /// person's own colour — here a row *is* a person, unlike on an event
        /// chip where the discs all wear the event's hue.
        Repeater {
            model: picker.invited

            delegate: Item {
                id: guestRow

                required property var modelData

                width: column.width
                height: 32

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: -Theme.space2
                    anchors.rightMargin: -Theme.space2
                    radius: Theme.radiusSm
                    color: guestHover.containsMouse ? Theme.surfaceOverlay : "transparent"
                }

                AvatarChip {
                    id: guestAvatar

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    size: 24
                    initials: guestRow.modelData.initials
                    fill: guestRow.modelData.colour
                    ink: Theme.bgBase
                }

                Text {
                    anchors.left: guestAvatar.right
                    anchors.leftMargin: Theme.space3
                    anchors.right: removeButton.left
                    anchors.rightMargin: Theme.space2
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: guestRow.modelData.name
                    color: Theme.textPrimary
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(12.5)
                }

                /// The × — always drawn, never hover-only. A remove control
                /// that appears under the pointer is one nobody knows is there
                /// until they happen to sweep the row, and this list is short
                /// enough that eight faint glyphs cost nothing.
                Item {
                    id: removeButton

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: removeHover.containsMouse
                               ? Theme.textPrimary : Theme.textMuted
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(14)
                    }

                    MouseArea {
                        id: removeHover

                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: picker.removed(guestRow.modelData.id)
                    }
                }

                MouseArea {
                    id: guestHover

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    // Below the × on purpose: this one only lights the row.
                    z: -1
                }
            }
        }

        /// The field. Borderless with a rule under it, the same affordance the
        /// quick-create title uses, so the two panels do not disagree about
        /// what a text field looks like.
        Item {
            id: fieldRow

            width: column.width
            height: 30

            Text {
                anchors.left: field.left
                anchors.verticalCenter: field.verticalCenter
                visible: picker.query.length === 0
                text: picker.invited.length > 0 ? "Add another guest" : "Add guests"
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(12.5)
            }

            TextInput {
                id: field

                objectName: "calendarGuestField"

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Math.ceil(contentHeight) + 2
                color: Theme.textPrimary
                selectionColor: Qt.alpha(Theme.accentPrimary, 0.35)
                selectedTextColor: Theme.textPrimary
                cursorDelegate: Rectangle {
                    width: 2
                    color: Theme.accentPrimary
                }
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(12.5)

                // Bound both ways, so a posed `query` types itself in and a
                // typed one poses the list.
                text: picker.query
                onTextChanged: picker.query = field.text
                onActiveFocusChanged: {
                    if (field.activeFocus)
                        picker.listOpen = true;
                }

                Keys.onPressed: keyEvent => {
                    if (keyEvent.modifiers & Qt.ControlModifier) {
                        picker.chordPressed(keyEvent);
                        return;
                    }
                    switch (keyEvent.key) {
                    case Qt.Key_Down:
                        picker.step(1);
                        keyEvent.accepted = true;
                        break;
                    case Qt.Key_Up:
                        picker.step(-1);
                        keyEvent.accepted = true;
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        picker.commit();
                        keyEvent.accepted = true;
                        break;
                    case Qt.Key_Backspace:
                        // Only on an empty field: a Backspace that ate a
                        // character *and* a guest would be a keystroke nobody
                        // could predict.
                        if (field.text.length === 0) {
                            picker.removeLast();
                            keyEvent.accepted = true;
                        }
                        break;
                    case Qt.Key_Escape:
                        // One Escape empties the field, the next closes the
                        // panel above — the same one-per-layer rule the window
                        // applies to its overlays.
                        if (field.text.length > 0) {
                            picker.query = "";
                            keyEvent.accepted = true;
                        }
                        break;
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: field.activeFocus ? Theme.accentPrimary
                                         : Qt.alpha(Theme.borderSubtle, 0.6)
            }
        }

        /// The results. A raised plate rather than a floating layer: it takes
        /// the room it needs and pushes the rest of the panel down, which costs
        /// a little height and buys a list that can never be clipped by the
        /// panel it hangs off or fall outside the window's edge. The panel is
        /// already placed by `CreatePolicy.popoverAnchor`, which clamps to the
        /// window — and it can only do that if the height it is handed is the
        /// whole height.
        Item {
            width: column.width
            height: picker.resultsShown ? results.height + Theme.space1 : 0
            visible: picker.resultsShown
            clip: true

            Rectangle {
                id: results

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: resultList.height + Theme.space1 * 2
                radius: Theme.radiusSm
                color: Theme.bgSunken
                border.width: 1
                border.color: Theme.borderSubtle

                ListView {
                    id: resultList

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: Theme.space1
                    height: Math.min(picker.rows.length, picker.maxRows) * 40
                    clip: true
                    interactive: picker.rows.length > picker.maxRows
                    model: picker.rows
                    currentIndex: picker.highlight
                    highlightMoveDuration: 0
                    // Follow the highlight, so an arrow key past the fifth row
                    // scrolls rather than losing the selection off the bottom.
                    highlightRangeMode: ListView.ApplyRange
                    preferredHighlightBegin: 0
                    preferredHighlightEnd: height

                    delegate: Item {
                        id: resultRow

                        required property int index
                        required property var modelData

                        width: resultList.width
                        height: 40

                        readonly property bool on: resultRow.index === picker.highlight

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space1
                            anchors.rightMargin: Theme.space1
                            radius: Theme.radiusSm
                            color: resultRow.on ? Theme.surfaceOverlay
                                 : resultHover.containsMouse
                                   ? Qt.alpha(Theme.surfaceOverlay, 0.5)
                                   : "transparent"

                            /// The same 2px anchor the command menu's selected
                            /// row wears, for the same reason: a flat band
                            /// loses the eye on keyboard repeat.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: Theme.space1
                                width: Theme.rail
                                radius: Theme.rail
                                color: Theme.accentPrimary
                                visible: resultRow.on
                            }
                        }

                        AvatarChip {
                            id: resultAvatar

                            anchors.left: parent.left
                            anchors.leftMargin: Theme.space3
                            anchors.verticalCenter: parent.verticalCenter
                            size: 26
                            initials: resultRow.modelData.initials
                            fill: resultRow.modelData.invite
                                  ? Theme.surfaceOverlay : resultRow.modelData.colour
                            ink: resultRow.modelData.invite
                                 ? Theme.textSecondary : Theme.bgBase
                        }

                        Text {
                            id: resultName

                            anchors.left: resultAvatar.right
                            anchors.leftMargin: Theme.space3
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.space3
                            anchors.top: parent.top
                            anchors.topMargin: resultRow.modelData.email.length > 0
                                               && !resultRow.modelData.invite ? 5 : 0
                            height: resultRow.modelData.email.length > 0
                                    && !resultRow.modelData.invite
                                    ? 17 : resultRow.height
                            verticalAlignment: resultRow.modelData.email.length > 0
                                               && !resultRow.modelData.invite
                                               ? Text.AlignTop : Text.AlignVCenter
                            elide: Text.ElideRight
                            text: resultRow.modelData.label
                            color: Theme.textPrimary
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(12.5)
                            font.weight: resultRow.on ? Theme.weightMedium
                                                      : Theme.weightRegular
                        }

                        Text {
                            anchors.left: resultName.left
                            anchors.right: resultName.right
                            anchors.top: resultName.bottom
                            visible: !resultRow.modelData.invite
                                     && resultRow.modelData.email.length > 0
                            elide: Text.ElideRight
                            text: resultRow.modelData.email
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(11)
                        }

                        MouseArea {
                            id: resultHover

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: picker.highlight = resultRow.index
                            onClicked: {
                                picker.highlight = resultRow.index;
                                picker.commit();
                                picker.takeFocus();
                            }
                        }
                    }
                }
            }
        }
    }
}
