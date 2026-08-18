// Every keyboard shortcut the calendar has, on one card. `?` opens it.
//
// ## Why it is generated and not typed
//
// A help sheet written by hand is a help sheet that is wrong within a month —
// the keymap gains a binding, nobody edits the prose, and the surface whose
// entire job is to be trustworthy about the keyboard starts lying about it.
// Every row here comes from `KeyNavPolicy.shortcutsTable()`, the same table
// `KeyNavPolicy.action` dispatches on, so a shortcut cannot exist and be
// missing from the help.
//
// The two columns are `KeyNavPolicy.shortcutsColumns()` and not a `Flow`: a
// flow would break a group across the gutter the moment the table grew a row,
// and a heading at the bottom of the left column with its rows at the top of
// the right one is the one thing a two-column reference must never do. The
// split is by printed height, checked in `tests/tst_keynavpolicy.qml`.
//
// ## What it does not do
//
// It does not close itself. Escape is `KeyNavPolicy.action`'s — it already
// knows an overlay is open — and a sheet with its own Escape rule is how the
// two get out of step. This file draws.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Widgets

Item {
    id: sheet

    /// The keymap, handed in so the sheet, the menu and the window's own key
    /// routing all read one table.
    property KeyNavPolicy keyNav: KeyNavPolicy {}

    /// The scrim was clicked, or the close button was.
    signal dismissed

    readonly property var columns: sheet.keyNav.shortcutsColumns()

    Rectangle {
        anchors.fill: parent
        color: CalendarTokens.scrimWash

        MouseArea {
            // pointer-exempt: the scrim dismisses, it does not act. Same call
            // the command menu's scrim makes.
            anchors.fill: parent
            onClicked: sheet.dismissed()
        }
    }

    Item {
        id: panel

        // 700 and not the spec's 640, which was measured wrong: at this type
        // scale a 640 card gives each column 270px, and `Backspace / Del`
        // against `Delete the selected event` needs 282 — so the one row whose
        // shortcut is hardest to remember was the one row printed as "Delete
        // the selected e…". A keyboard reference that abbreviates the thing it
        // is documenting is worse than one 60px wider.
        //
        // It is a maximum as much as a size: on a window dragged small, a modal
        // larger than what it is modal over has its own edges off screen.
        width: Math.min(700, sheet.width - Theme.space6 * 2)
        height: card.height
        x: Math.round((sheet.width - width) / 2)
        y: Math.max(Theme.space4, Math.round((sheet.height - height) / 2))

        /// Stacked plates rather than a `MultiEffect`, for the reason
        /// `Widgets/Icon.qml` measured: the effect draws nothing offscreen, and
        /// a card invisible in half the capture modes is one nobody can judge.
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
            height: heading.height + table.height + Theme.space6 * 2 + Theme.space5
            radius: Theme.radiusLg
            color: Theme.surfaceRaised
            border.width: 1
            border.color: Theme.borderSubtle

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

            // --- the title row -------------------------------------------------

            Item {
                id: heading

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.space6
                anchors.bottomMargin: 0
                height: 28

                Icon {
                    id: mark

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    name: "keyboard"
                    size: 18
                    color: Theme.textSecondary
                }

                Text {
                    anchors.left: mark.right
                    anchors.leftMargin: Theme.space3
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Keyboard shortcuts")
                    color: Theme.textPrimary
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(15)
                    font.weight: Theme.weightMedium
                }

                /// `Esc` rather than an ✕: the sheet is a keyboard reference, so
                /// the way out of it is named in the same alphabet as everything
                /// else on the card.
                Rectangle {
                    id: dismiss

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: escCaps.width + Theme.space2 * 2
                    height: 28
                    radius: Theme.radiusSm
                    color: closer.containsMouse ? Theme.surfaceOverlay : "transparent"

                    Keycaps {
                        id: escCaps

                        anchors.centerIn: parent
                        caps: sheet.keyNav.keyCaps("Esc")
                    }

                    MouseArea {
                        id: closer

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sheet.dismissed()
                    }
                }
            }

            // --- the two columns -----------------------------------------------

            Row {
                id: table

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: heading.bottom
                anchors.topMargin: Theme.space5
                anchors.leftMargin: Theme.space6
                anchors.rightMargin: Theme.space6
                spacing: Theme.space7

                height: Math.max(left.height, right.height)

                Column {
                    id: left

                    width: Math.floor((table.width - table.spacing) / 2)
                    spacing: Theme.space4

                    Repeater {
                        model: sheet.columns.length > 0 ? sheet.columns[0] : []
                        delegate: groupBlock
                    }
                }

                Column {
                    id: right

                    width: table.width - table.spacing - left.width
                    spacing: Theme.space4

                    Repeater {
                        model: sheet.columns.length > 1 ? sheet.columns[1] : []
                        delegate: groupBlock
                    }
                }
            }
        }
    }

    /// One heading and the rows under it. Shared by both columns so the two
    /// halves of the card cannot drift apart typographically.
    Component {
        id: groupBlock

        Column {
            id: block

            required property var modelData

            width: parent ? parent.width : 0
            spacing: Theme.space1

            Text {
                text: block.modelData ? String(block.modelData.group) : ""
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(Theme.capsSize)
                font.weight: Theme.weightMedium
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Theme.capsTrackingEm * Theme.pt(Theme.capsSize)
                bottomPadding: Theme.space1
            }

            Repeater {
                model: block.modelData ? block.modelData.rows : []

                delegate: Item {
                    id: row

                    required property var modelData

                    width: block.width
                    height: 26

                    Text {
                        anchors.left: parent.left
                        anchors.right: caps.left
                        anchors.rightMargin: Theme.space3
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData ? String(row.modelData.label) : ""
                        elide: Text.ElideRight
                        color: Theme.textSecondary
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(12.5)
                    }

                    Keycaps {
                        id: caps

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        caps: row.modelData ? sheet.keyNav.keyCaps(row.modelData.keys) : []
                    }
                }
            }
        }
    }
}
