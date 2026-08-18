// The calendar's command menu — Ctrl+K, a search field, and every verb the
// keyboard has, named.
//
// ## What it is for
//
// Not speed. A person who knows `M` presses `M`; this is for the person who
// does not, and its real job is to *teach the keymap* — which is why every row
// carries the shortcut that would have run it. Notion's palette does the same
// thing and it is the single best idea in that surface.
//
// ## What it decides: nothing
//
// The list is `KeyNavPolicy.commands(ctx)`, narrowed by `KeyNavPolicy.filter`,
// flattened into headings-plus-rows by `KeyNavPolicy.menuRows`, and the
// highlight moves by `KeyNavPolicy.stepRow`. All four are at the first seam
// with `tests/tst_keynavpolicy.qml` holding them to account, so what this file
// contains is rectangles, motion and one text field.
//
// The one thing worth saying about the shape: the model is a **flat** row list
// with headings in it, not a list of sections. The highlight is an index into
// what is on screen, and a nested model would make it a pair of indices — the
// shape that goes wrong the first time a query empties a group.
//
// ## Why the selected row has a bar
//
// `DESIGN-SPEC.md`: Notion's selection is a flat grey band with no anchor, and
// on keyboard repeat the eye loses which row it is on because nothing about the
// band says *where* it starts. A 2px accent rail at the left edge is a fixed
// point the eye can track down the list.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Widgets

Item {
    id: menu

    /// The keymap. Handed in rather than instantiated, so the menu, the sheet
    /// and the window's own key routing are all reading one table.
    property KeyNavPolicy keyNav: KeyNavPolicy {}

    /// What `KeyNavPolicy.commands` needs to name its context-dependent rows —
    /// `{view, selectedId, selectedTitle}`.
    property var ctx: ({})

    /// The query, live. Bound both ways so the capture harness can pose a typed
    /// menu: a picture of an empty field is a picture of a state that says
    /// nothing about whether filtering works.
    property string query: ""

    /// A row was run. The id is `KeyNavPolicy`'s (`"view.month"`), never an
    /// index, so filtering cannot change what running a row does.
    signal accepted(string commandId)

    /// The scrim was clicked. Escape is deliberately *not* handled here — it
    /// belongs to `KeyNavPolicy.action`, which already knows an overlay is open,
    /// and a second Escape rule in this file is how the two get out of step.
    signal dismissed

    readonly property var rows: menu.keyNav.menuRows(
        menu.keyNav.filter(menu.keyNav.commands(menu.ctx), menu.query))

    /// Which row the eye is on. Reset on every keystroke, because a highlight
    /// left at index 4 of a list the query just cut to two is a highlight on
    /// nothing.
    property int highlight: 0
    onRowsChanged: menu.highlight = menu.keyNav.firstRow(menu.rows)

    function step(delta: int): void {
        menu.highlight = menu.keyNav.stepRow(menu.rows, menu.highlight, delta);
    }

    function run(): void {
        const row = menu.highlight >= 0 && menu.highlight < menu.rows.length
                  ? menu.rows[menu.highlight] : null;
        if (row && row.kind === "command")
            menu.accepted(row.command.id);
    }

    /// The caret arrives with the menu. A palette that opens unfocused is a
    /// palette that eats the first word typed into it.
    Component.onCompleted: {
        menu.highlight = menu.keyNav.firstRow(menu.rows);
        field.forceActiveFocus();
    }

    // --- the scrim ------------------------------------------------------------
    //
    // `CalendarTokens.scrimWash` and not the shell's `fogWash`, which is a
    // desktop scrim and measured as nothing at all over a dark grid — the
    // token carries the measurement.

    Rectangle {
        anchors.fill: parent
        color: CalendarTokens.scrimWash

        MouseArea {
            // pointer-exempt: the scrim is the way out, not a control. A hand
            // over the whole calendar would say every hour of it is clickable,
            // when the only thing clicking does is put the menu away —
            // `Surfaces/Drawers/DrawerWindow.qml` makes the same call for its
            // fog and for the same reason.
            anchors.fill: parent
            onClicked: menu.dismissed()
        }
    }

    // --- the card -------------------------------------------------------------

    Item {
        id: panel

        width: 560
        height: card.height
        x: Math.round((menu.width - width) / 2)
        // 18% down: high enough that the card is in the eye's resting third,
        // low enough that the list below it has somewhere to grow. Clamped, so
        // a short window puts the card at a margin rather than off the bottom.
        y: Math.max(Theme.space4,
                    Math.min(Math.round(menu.height * 0.18),
                             menu.height - height - Theme.space4))

        /// Elevation as stacked plates rather than a `MultiEffect` — the effect
        /// draws nothing on the offscreen scenegraph (`Widgets/Icon.qml`
        /// measured it), and a card that is invisible in half the capture modes
        /// is a card nobody can judge. The ambient plate is 1.5x the popover's,
        /// which is the spec's way of saying this floats higher than they do.
        Rectangle {
            anchors.fill: card
            anchors.margins: -9
            radius: Theme.radiusLg + 9
            color: CalendarTokens.shadowAmbient
        }

        Rectangle {
            anchors.fill: card
            anchors.margins: -3
            anchors.topMargin: -1
            anchors.bottomMargin: -5
            radius: Theme.radiusLg + 3
            color: CalendarTokens.shadowKey
        }

        Rectangle {
            id: card

            width: parent.width
            height: header.height + 1 + listBox.height + 1 + footer.height
            radius: Theme.radiusLg
            color: Theme.surfaceRaised
            border.width: 1
            /// `borderStrong`, not `borderSubtle`, and the two plates behind
            /// this rectangle are why. A shadow is black ink, and this card sits
            /// on a scrim that is *already* black ink at 52% — so the plates buy
            /// nothing in dark mode and the card's own edge is the only thing
            /// separating it from the wash. At `borderSubtle` the round-2
            /// capture's top-left corner dissolved into the backdrop. The
            /// plates stay for light mode, where the page has somewhere to fall.
            border.color: Theme.borderStrong
            clip: true

            scale: Theme.animateTransforms ? 0.97 : 1
            opacity: Theme.animateTransforms ? 0 : 1
            Component.onCompleted: {
                card.scale = 1;
                card.opacity = 1;
            }
            Behavior on scale {
                NumberAnimation {
                    duration: Theme.duration(Theme.motionFast)
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.duration(Theme.motionFast)
                    easing.type: Easing.OutCubic
                }
            }

            // --- the search row -----------------------------------------------

            Item {
                id: header

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 56

                Icon {
                    id: magnifier

                    anchors.left: parent.left
                    // The glyph gives back the 2px of padding Lucide draws into
                    // its own box, so its ink lands on the same rail as the
                    // section headings and the footer caps rather than 2px
                    // right of them — `CalendarTokens.glyphInk` has the whole
                    // argument.
                    anchors.leftMargin: Theme.space4 - CalendarTokens.glyphInk
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 18
                    color: Theme.textMuted
                }

                TextInput {
                    id: field

                    anchors.left: magnifier.right
                    anchors.leftMargin: Theme.space3
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.space4
                    anchors.verticalCenter: parent.verticalCenter

                    focus: true
                    color: Theme.textPrimary
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(15)
                    font.weight: Theme.weightRegular
                    selectionColor: Qt.alpha(Theme.accentPrimary, 0.35)
                    selectedTextColor: Theme.textPrimary

                    // Bound both ways: typing writes the same string the binding
                    // would produce, and setting `query` from outside actually
                    // reaches the field — which is what lets the harness pose a
                    // typed menu rather than an empty one.
                    text: menu.query
                    onTextChanged: menu.query = text

                    // The built-in caret is turned off and drawn below instead.
                    //
                    // Not for colour — a `cursorDelegate` would have handled
                    // that. For *presence*: Qt blinks the delegate, so the caret
                    // is absent from half the frames, and a capture is one
                    // frame. Round 2's picture of this field was judged as a
                    // field with no caret at all, which loses the one mark that
                    // says the thing is typeable — the field is otherwise a
                    // magnifier and a grey line of placeholder.
                    cursorDelegate: Item {}

                    // Up/Down/Enter belong to the list under the field, and a
                    // single-line TextInput has nothing to do with any of them.
                    // Escape is left alone on purpose — see `dismissed`.
                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Down:
                            menu.step(1);
                            event.accepted = true;
                            break;
                        case Qt.Key_Up:
                            menu.step(-1);
                            event.accepted = true;
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            menu.run();
                            event.accepted = true;
                            break;
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        // 3px, which is the caret's width plus a hair: an empty
                        // field puts the caret at x 0 and the placeholder would
                        // otherwise start underneath it. Typed text starts at 0
                        // and the placeholder is gone by then, so the 3px is
                        // never a jump anyone sees.
                        anchors.leftMargin: 3
                        anchors.verticalCenter: parent.verticalCenter
                        visible: field.text.length === 0
                        text: qsTr("Search commands")
                        color: Theme.textMuted
                        font: field.font
                    }

                    /// The caret, always on. The menu opens focused and closes
                    /// on Escape, so for as long as this rectangle exists the
                    /// field owns the keyboard — there is no state where a
                    /// blink-off frame is telling the truth about it.
                    Rectangle {
                        id: caret

                        x: field.cursorRectangle.x
                        y: field.cursorRectangle.y
                        width: 2
                        height: field.cursorRectangle.height
                        radius: 1
                        color: Theme.accentPrimary
                    }
                }
            }

            Rectangle {
                id: hairline

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: header.bottom
                height: 1

                /// `borderStrong`, not `borderSubtle`. This rule separates the
                /// two halves of the menu — what you typed from what it found —
                /// and it is the only thing doing that job, with no change of
                /// ground either side of it. At `borderSubtle` it measured
                /// 1.27:1 on the card, which is a hairline you have to be told
                /// is there. The hairlines inside a *list* can be that quiet
                /// because the rows carry the structure; this one cannot.
                color: Theme.borderStrong
            }

            // --- the rows ------------------------------------------------------

            Item {
                id: listBox

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: hairline.bottom
                // The list is as tall as its content up to a ceiling, so a menu
                // with two rows in it is a small card rather than a tall one
                // with a hole in the bottom.
                //
                // The ceiling is 60% of the *window*, and it is on the list
                // rather than on the card on purpose: a cap on the card would
                // have to come out of something, and the two things it would
                // come out of — the field you are typing into and the legend
                // that says how to leave — are the two that must never scroll
                // away. So the list scrolls and the chrome stays whole.
                //
                // 0.66 and not 0.6: the whole grouped keymap is 452px tall on a
                // 760px window and 0.6 clipped it by four — a menu that scrolls
                // by half a row is a menu that looks broken rather than long.
                // The cap is still a cap; it is just set above the one list
                // this surface is guaranteed to draw.
                height: menu.rows.length === 0
                      ? 64
                      : Math.min(list.contentHeight, Math.round(menu.height * 0.66))
                        + Theme.space2 * 2

                ListView {
                    id: list

                    anchors.fill: parent
                    anchors.topMargin: Theme.space2
                    anchors.bottomMargin: Theme.space2
                    clip: true
                    interactive: contentHeight > height
                    model: menu.rows
                    currentIndex: menu.highlight
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: 0
                    preferredHighlightBegin: 0
                    preferredHighlightEnd: height
                    highlightRangeMode: ListView.ApplyRange
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: rowItem

                        required property int index
                        required property var modelData

                        readonly property bool isGroup: rowItem.modelData.kind === "group"
                        readonly property bool selected: !rowItem.isGroup
                                                       && rowItem.index === menu.highlight

                        width: ListView.view.width
                        // A heading is a label *for* the rows beneath it, so it
                        // has to sit closer to them than to the group it just
                        // left — otherwise it floats equidistant and binds to
                        // neither, which is what round 2 measured: 38px above,
                        // 40px below, four headings that named nothing.
                        //
                        // 42 tall with the label 4px off its own bottom puts 55
                        // device px of air above the caps and 25 below, better
                        // than 2:1, and the binding is no longer something the
                        // reader has to work out.
                        //
                        // The *first* heading is 32, because the rule under the
                        // search field is already doing the separating there and
                        // a full measure of air under it would open a hole in
                        // the top of the list.
                        height: rowItem.isGroup ? (rowItem.index === 0 ? 32 : 42) : 40

                        // --- a heading ---------------------------------------

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.space4
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Theme.space1
                            visible: rowItem.isGroup
                            text: rowItem.isGroup ? String(rowItem.modelData.label) : ""
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(Theme.capsSize)
                            font.weight: Theme.weightMedium
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: Theme.capsTrackingEm * Theme.pt(Theme.capsSize)
                        }

                        // --- a command ---------------------------------------

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space2
                            anchors.rightMargin: Theme.space2
                            visible: !rowItem.isGroup
                            radius: Theme.radiusSm
                            // The band and the rail are one hue at two
                            // lightnesses — `CalendarTokens.menuSelectFill`
                            // carries the measurement and the argument.
                            color: rowItem.selected ? CalendarTokens.menuSelectFill
                                                    : "transparent"

                            /// The anchor the eye tracks — see the header.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.topMargin: 6
                                anchors.bottomMargin: 6
                                width: Theme.rail
                                radius: Theme.rail / 2
                                color: Theme.accentPrimary
                                visible: rowItem.selected
                            }
                        }

                        Icon {
                            id: rowIcon

                            anchors.left: parent.left
                            // Same rail as the magnifier above and the headings
                            // beside it — see `CalendarTokens.glyphInk`.
                            anchors.leftMargin: Theme.space4 - CalendarTokens.glyphInk
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !rowItem.isGroup
                            name: rowItem.isGroup ? "" : String(rowItem.modelData.command.icon)
                            size: 18
                            // Deliberately *not* brighter on the selected row.
                            // The selection is one band plus one rail; a row
                            // that also swapped its icon colour, its label
                            // weight and its badge would be four marks saying
                            // one thing, and the first capture read as a row
                            // shouting rather than a row chosen.
                            color: Theme.textSecondary
                        }

                        Text {
                            anchors.left: rowIcon.right
                            anchors.leftMargin: Theme.space3
                            anchors.right: badge.left
                            anchors.rightMargin: Theme.space3
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !rowItem.isGroup
                            text: rowItem.isGroup ? "" : String(rowItem.modelData.label)
                            elide: Text.ElideRight
                            color: Theme.textPrimary
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(13.5)
                            font.weight: Theme.weightRegular
                        }

                        Keycaps {
                            id: badge

                            anchors.right: parent.right
                            anchors.rightMargin: Theme.space4
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !rowItem.isGroup
                            // One badge per row — `KeyNavPolicy.menuKeys` picks
                            // which of a row's ways in the menu prints, and the
                            // shortcuts sheet keeps the rest.
                            caps: rowItem.isGroup
                                ? []
                                : menu.keyNav.keyCaps(
                                      menu.keyNav.menuKeys(rowItem.modelData.command))
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !rowItem.isGroup
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // Hover moves the highlight rather than drawing a
                            // second one: two selection colours on one list is
                            // the state where a click and Enter disagree about
                            // what is about to run.
                            onEntered: menu.highlight = rowItem.index
                            onClicked: menu.accepted(rowItem.modelData.command.id)
                        }
                    }
                }

                // --- the scroll affordances ------------------------------------
                //
                // A list that scrolls has to say so. Both marks are bound to
                // `list` rather than to a row count, so a query that shortens
                // the list takes them away and neither can be left claiming
                // there is more when there is not.

                /// More below, as a fade rather than a hard cut: the row under
                /// the ceiling is half-drawn on purpose, which is the oldest
                /// and most honest way of saying the list continues.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 24
                    visible: list.interactive && !list.atYEnd
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.alpha(Theme.surfaceRaised, 0) }
                        GradientStop { position: 1; color: Theme.surfaceRaised }
                    }
                }

                /// How far down, and how much of it there is.
                Rectangle {
                    readonly property real track: listBox.height - Theme.space2 * 2

                    anchors.right: parent.right
                    anchors.rightMargin: 3
                    width: 3
                    radius: 1.5
                    visible: list.interactive
                    color: Theme.borderStrong
                    y: Theme.space2 + list.visibleArea.yPosition * track
                    height: Math.max(24, list.visibleArea.heightRatio * track)
                }

                /// A query that matched nothing is a state, not an error — say
                /// so, rather than collapsing to a hairline under the field.
                Text {
                    anchors.centerIn: parent
                    visible: menu.rows.length === 0
                    text: qsTr("No matching command")
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(13.5)
                }
            }

            // --- the legend ----------------------------------------------------
            //
            // What the rows cannot say: how to move between them, take one, and
            // leave. Three marks on a quieter ground than the list, so the band
            // reads as the card's edge rather than a fourth group of commands —
            // which is also why it is the one part of the card that never
            // scrolls. `KeyNavPolicy.menuFooter` chooses the three.

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: listBox.bottom
                height: 1
                color: Theme.borderSubtle
            }

            Rectangle {
                id: footer

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 36
                color: Qt.alpha(Theme.bgSunken, 0.5)

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.space4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space3

                    Repeater {
                        model: menu.keyNav.menuFooter()

                        delegate: Row {
                            id: hint

                            required property int index
                            required property var modelData

                            spacing: Theme.space2

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: hint.index > 0
                                text: "·"
                                color: Theme.textMuted
                                opacity: 0.6
                                font.family: Theme.fontUi
                                font.pointSize: Theme.pt(12)
                            }

                            Keycaps {
                                anchors.verticalCenter: parent.verticalCenter
                                caps: menu.keyNav.keyCaps(hint.modelData.keys)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(hint.modelData.label)
                                color: Theme.textMuted
                                font.family: Theme.fontUi
                                font.pointSize: Theme.pt(11.5)
                                font.weight: Theme.weightRegular
                            }
                        }
                    }
                }
            }
        }
    }
}
