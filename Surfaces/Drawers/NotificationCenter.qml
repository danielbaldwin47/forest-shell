// The notification centre (#43) — the shared drawer window's third tenant.
//
// History, grouped by app, hanging from the top-right corner under the bar
// indicator that opens it. One group per app rather than a flat list because a
// flat one is what the popup stack already is: the centre exists for the case
// where twelve things arrived and eleven of them are from one chat.
//
// **Expand to read.** A collapsed group shows its newest summary on one line;
// the open one shows every row it has, with bodies unclipped — the toast caps
// the body at four lines and says "the centre has the rest" (#42), and this is
// where the rest is. One group is open at a time, which keeps the panel a
// readable length without a scroll position that jumps as groups grow.
//
// **Clearing is not ruling.** The per-group `x` clears that app's rows; what an
// app is *allowed* to do is a standing decision and lives in the settings
// window's Notifications tab (#54). Tidying up after an app must not silence
// it, so the two acts are in two places and neither reaches the other.
//
// While this exists, `Notifications.centerOpen` is true and popups are
// suppressed — a toast on top of the list it is already in is the same thing
// twice (#9). The service does the suppressing; this file only says when.
//
// The decisions are all next door in Services/Notifications/NotificationPolicy
// .qml, which imports nothing but QtQuick so `tests/` can reach them: grouping,
// what "unread" means, what a per-app clear removes, how a timestamp is
// spelled. What is here is the picture.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Core
import qs.Widgets
import qs.Services.Notifications

FocusScope {
    id: root

    /// Raised when the centre wants the drawer gone. Nothing in here closes it
    /// on its own — clearing the last row leaves an empty panel rather than a
    /// surface that vanishes out from under the pointer that emptied it.
    signal closeRequested(string reason)

    /// History as the centre draws it (#43), live: an app that notifies while
    /// this is open grows a group under the pointer.
    readonly property var groups: Notifications.groups

    /// The app whose group is open, by key, or "" for none. A key and not an
    /// index, so a group that moves to the top because it just notified again
    /// stays the one that is open.
    property string expanded: ""

    /// A component dimension, not a token (#8): wide enough for two lines of a
    /// notification body at 12pt, narrow enough to leave the desktop visible
    /// beside it.
    readonly property int panelWidth: 400

    /// Never taller than the screen it hangs on, less its margins. The panel is
    /// its content's height until it hits this, and scrolls after.
    readonly property int maxPanelHeight: Math.max(160, root.height - Theme.space4 * 2)

    focus: true

    // The centre is open exactly as long as this item exists — it is created
    // when the drawer opens and destroyed a fade after it closes. Set here
    // rather than in Drawers.qml because the service may not import a surface:
    // Services/ is below Surfaces/ and an import the other way is the cycle
    // Core/ServiceInit.qml exists to avoid.
    //
    // The one caveat is the fade: the flag stays true for the ~240 ms the panel
    // takes to leave, so a notification arriving inside that window is
    // suppressed by a centre the user has already dismissed. It is in history,
    // and the alternative — popping a toast over a panel still on screen — is
    // the thing the flag is for.
    Component.onCompleted: Notifications.centerOpen = true
    Component.onDestruction: Notifications.centerOpen = false

    /// Whether the centre is the drawer that is *open*, which is not the same
    /// question as whether this item exists — it outlives the close by one fade.
    readonly property bool shown: Drawers.current === "notificationcenter"

    // "Seen" is stamped on the closing edge as well as the opening one, because
    // what arrived while the panel was up was read off the panel. It is stamped
    // *here* rather than left to the destruction above, and that is the whole
    // reason this property exists: the fade is ~240 ms, and a badge that stays
    // lit for a quarter of a second after the user has finished reading is a
    // badge that is wrong for as long as anyone is looking at it.
    onShownChanged: if (!root.shown) Notifications.markSeen()

    Rectangle {
        id: panel

        anchors {
            top: parent.top
            right: parent.right
            margins: Theme.space4
        }

        /// The panel's inset, which is also what the layout inside it is
        /// short of the panel's own width. Held as a property because both
        /// halves of the sizing below need it and they must not disagree.
        readonly property int padding: Theme.space3

        width: root.panelWidth
        height: Math.min(column.implicitHeight + panel.padding * 2, root.maxPanelHeight)

        color: Theme.surface
        radius: Theme.radiusLg
        border.width: Theme.hairline
        border.color: Theme.borderSubtle

        // First child: the card's own controls are hit-tested before it. See
        // Surfaces/Drawers/PressCatcher.qml (#193).
        PressCatcher {}

        // Sized *from* the panel rather than anchored to it, which is not a
        // style choice: the panel's height comes from this layout's implicit
        // height, and an `anchors.fill` would make the layout's height come
        // straight back from the panel's. Qt breaks that cycle by zeroing the
        // layout, and the panel then draws as its header alone with every item
        // in it stacked at x=0 — which is exactly what the first capture of
        // this surface photographed (tools/capture-harness.sh --surface center).
        //
        // The width is not part of the loop, so it is bound outright; the
        // height is handed down from the panel once the panel has decided.
        ColumnLayout {
            id: column

            x: panel.padding
            y: panel.padding
            width: panel.width - panel.padding * 2
            height: panel.height - panel.padding * 2
            spacing: Theme.space2

            // --- the header ---------------------------------------------------

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                Text {
                    text: "NOTIFICATIONS"
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(Theme.capsSize)
                    font.weight: Theme.weightMedium
                    font.letterSpacing: Theme.tracking(Theme.capsSize, Theme.capsTrackingEm)
                }

                // Why nothing is popping, in the panel that is showing what
                // popped instead. The service reports it in the same vocabulary
                // the log lines use, and `center` is filtered out here — the
                // centre being open is a fact the user can see.
                Text {
                    readonly property string reason: Notifications.suppression

                    Layout.fillWidth: true
                    visible: text !== ""
                    text: reason === "dnd" ? "· do not disturb"
                        : reason === "fullscreen" ? "· fullscreen" : ""
                    color: Theme.accentWarm
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(Theme.capsSize)
                    font.weight: Theme.weightMedium
                    font.letterSpacing: Theme.tracking(Theme.capsSize, Theme.capsTrackingEm)
                }

                Item { Layout.fillWidth: true }

                // Clear all. Teal, because it is the one interactive thing in
                // the header and teal is what interactive means (#8 §2).
                Text {
                    id: clearAll

                    visible: root.groups.length > 0
                    text: "Clear all"
                    color: clearAllHover.hovered ? Theme.accentPrimary : Theme.textSecondary
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(11.5)
                    font.weight: Theme.weightMedium

                    HoverHandler {
                        id: clearAllHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: {
                            root.expanded = "";
                            Notifications.clearAll();
                        }
                    }
                }
            }

            // --- nothing to read ----------------------------------------------

            Text {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space2
                Layout.bottomMargin: Theme.space3
                visible: root.groups.length === 0
                text: Notifications.dnd
                      ? "Nothing here. Do not disturb is on — notifications are still "
                        + "remembered, they just do not interrupt."
                      : "Nothing here."
                color: Theme.textMuted
                wrapMode: Text.Wrap
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(12)
            }

            // --- the groups ---------------------------------------------------

            Flickable {
                id: scroll

                Layout.fillWidth: true
                Layout.fillHeight: true
                // What the panel is sized from, and what the layout squeezes
                // when the content is taller than the screen allows.
                Layout.preferredHeight: groupsColumn.implicitHeight
                visible: root.groups.length > 0

                contentWidth: width
                contentHeight: groupsColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: groupsColumn

                    width: scroll.width
                    spacing: Theme.space2

                    Repeater {
                        model: root.groups

                        Column {
                            id: group

                            required property var modelData

                            readonly property bool open: root.expanded === group.modelData.appKey
                            readonly property var newest: group.modelData.rows[0]

                            width: groupsColumn.width
                            spacing: Theme.space1

                            // --- the group's own row ---------------------------

                            Rectangle {
                                id: groupHeader

                                width: parent.width
                                height: 44
                                radius: Theme.radiusMd
                                color: group.open || groupHover.hovered ? Theme.surfaceRaised
                                                                        : "transparent"

                                // A fill, so it fades, at the in-place step —
                                // nothing but this rectangle changes
                                // (Core/EffectsPolicy.qml).
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.duration(Theme.motionFast)
                                        easing.type: Easing.Bezier
                                        easing.bezierCurve: Theme.fogEase
                                    }
                                }

                                // The handler that already draws the highlight
                                // carries the cursor too (#185): the header is
                                // the `TapHandler` below, and one hover is
                                // enough to say so.
                                HoverHandler {
                                    id: groupHover

                                    cursorShape: Qt.PointingHandCursor
                                }

                                TapHandler {
                                    onTapped: root.expanded = group.open ? ""
                                                                        : group.modelData.appKey
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space3
                                    anchors.rightMargin: Theme.space2
                                    spacing: Theme.space3

                                    AppBadge {
                                        Layout.alignment: Qt.AlignVCenter
                                        row: group.newest
                                        size: 22
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        Text {
                                            Layout.fillWidth: true
                                            // The app's own name, and the key
                                            // only for a row that carries no
                                            // name at all — a header reading
                                            // `org.mozilla.firefox` when the
                                            // client said "Firefox" is the id
                                            // leaking into the picture.
                                            text: group.modelData.appName
                                                  || "Unidentified app"
                                            color: Theme.textPrimary
                                            elide: Text.ElideRight
                                            font.family: Theme.fontUi
                                            font.pointSize: Theme.pt(12.5)
                                            font.weight: Theme.weightMedium
                                        }

                                        // The newest summary, until the group
                                        // is open and every summary is on
                                        // screen anyway.
                                        Text {
                                            Layout.fillWidth: true
                                            visible: !group.open
                                            text: group.newest ? group.newest.summary : ""
                                            color: Theme.textSecondary
                                            elide: Text.ElideRight
                                            font.family: Theme.fontUi
                                            font.pointSize: Theme.pt(11.5)
                                        }
                                    }

                                    // How many, once there is more than one:
                                    // "1" beside a summary is a number that
                                    // tells nobody anything.
                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        visible: group.modelData.count > 1
                                        implicitWidth: Math.max(18, countText.implicitWidth
                                                                    + Theme.space2)
                                        implicitHeight: 18
                                        radius: height / 2
                                        color: Theme.bgSunken

                                        Text {
                                            id: countText

                                            anchors.centerIn: parent
                                            text: Notifications.policy
                                                      .countLabel(group.modelData.count)
                                            color: Theme.textSecondary
                                            font.family: Theme.fontUi
                                            font.pointSize: Theme.pt(10.5)
                                            font.weight: Theme.weightMedium
                                        }
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: Notifications.policy
                                                  .relativeTime(group.modelData.latest,
                                                                Time.now.getTime())
                                        color: Theme.textMuted
                                        font.family: Theme.fontUi
                                        font.pointSize: Theme.pt(10.5)
                                    }

                                    // Clear this app. Under the pointer only —
                                    // the shell is quiet until it is being used
                                    // — and a `MouseArea` rather than a
                                    // handler, because item-level input is what
                                    // stops the click from also toggling the
                                    // group behind it.
                                    MouseArea {
                                        id: clearGroup

                                        Layout.alignment: Qt.AlignVCenter
                                        implicitWidth: 22
                                        implicitHeight: 22
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        opacity: groupHover.hovered ? 1 : 0

                                        onClicked: {
                                            if (group.open)
                                                root.expanded = "";
                                            Notifications.clearApp(group.modelData.appKey);
                                        }

                                        Behavior on opacity {
                                            NumberAnimation {
                                                duration: Theme.duration(Theme.motionFast)
                                                easing.type: Easing.Bezier
                                                easing.bezierCurve: Theme.fogEase
                                            }
                                        }

                                        Icon {
                                            anchors.centerIn: parent
                                            name: "x"
                                            size: 14
                                            color: clearGroup.containsMouse ? Theme.textPrimary
                                                                            : Theme.textMuted
                                        }
                                    }
                                }
                            }

                            // --- the rows, once it is open ---------------------

                            Repeater {
                                model: group.open ? group.modelData.rows : []

                                Rectangle {
                                    id: entry

                                    required property var modelData

                                    readonly property color accent:
                                        entry.modelData.urgency === "critical" ? Theme.accentEmber
                                      : entry.modelData.urgency === "low" ? Theme.accentStone
                                      : Theme.accentWarm

                                    width: groupsColumn.width
                                    implicitHeight: rowLayout.implicitHeight + Theme.space3 * 2
                                    radius: Theme.radiusMd
                                    color: Theme.surfaceRaised
                                    border.width: Theme.hairline
                                    // The one row allowed to announce itself
                                    // after the fact, for the same reason the
                                    // toast is (#42).
                                    border.color: entry.modelData.urgency === "critical"
                                                  ? Theme.accentEmber : "transparent"

                                    HoverHandler { id: entryHover }

                                    RowLayout {
                                        id: rowLayout

                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            top: parent.top
                                            margins: Theme.space3
                                        }
                                        spacing: Theme.space3

                                        // The urgency, as the only colour on a
                                        // row: the toast carries it on a border
                                        // that has to be visible from across
                                        // the room, and a list of twenty of
                                        // those would be a list nobody can read
                                        // (#8 §2).
                                        Rectangle {
                                            Layout.alignment: Qt.AlignTop
                                            Layout.topMargin: 5
                                            implicitWidth: 6
                                            implicitHeight: 6
                                            radius: 3
                                            color: entry.accent
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.space1

                                            Text {
                                                Layout.fillWidth: true
                                                text: entry.modelData.summary
                                                visible: text !== ""
                                                color: Theme.textPrimary
                                                wrapMode: Text.Wrap
                                                font.family: Theme.fontUi
                                                font.pointSize: Theme.pt(12.5)
                                                font.weight: Theme.weightMedium
                                            }

                                            // Unclipped, which is the whole
                                            // point of the centre: the toast
                                            // caps this at four lines and says
                                            // the rest is here (#42).
                                            Text {
                                                Layout.fillWidth: true
                                                text: entry.modelData.body
                                                visible: text !== ""
                                                color: Theme.textSecondary
                                                wrapMode: Text.Wrap
                                                lineHeight: Theme.lineHeightBody
                                                lineHeightMode: Text.ProportionalHeight
                                                // Markup is advertised to
                                                // clients, so it is rendered.
                                                // Hyperlinks are not, and
                                                // nothing here handles a click.
                                                textFormat: Text.StyledText
                                                font.family: Theme.fontUi
                                                font.pointSize: Theme.pt(12)
                                            }
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignTop
                                            text: Notifications.policy
                                                      .relativeTime(entry.modelData.time,
                                                                    Time.now.getTime())
                                            color: Theme.textMuted
                                            font.family: Theme.fontUi
                                            font.pointSize: Theme.pt(10.5)
                                        }

                                        MouseArea {
                                            id: dismissRow

                                            Layout.alignment: Qt.AlignTop
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            opacity: entryHover.hovered ? 1 : 0

                                            // By the row key and not by index:
                                            // the list can change between the
                                            // frame that drew this and the
                                            // click (#76).
                                            onClicked: Notifications.dismiss(entry.modelData.key)

                                            Behavior on opacity {
                                                NumberAnimation {
                                                    duration: Theme.duration(Theme.motionFast)
                                                    easing.type: Easing.Bezier
                                                    easing.bezierCurve: Theme.fogEase
                                                }
                                            }

                                            Icon {
                                                anchors.centerIn: parent
                                                name: "x"
                                                size: 12
                                                color: dismissRow.containsMouse
                                                       ? Theme.textPrimary : Theme.textMuted
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
