// One notification popup (#42).
//
// Everything it shows comes off the Toast it is given — the notification, and
// where that notification is in its life. It owns no timing of its own: the
// toast decides when it is leaving, this file decides what leaving looks like.
//
// The motion is #27's toast row. The card **condenses in place**: opacity plus
// a 1% scale settle over 240ms, no slide, because in this design language
// surfaces materialize out of fog rather than arriving from off-screen. The
// exit is 140ms and opacity-only — the global rule that exits do not transform.
// The one translate in the shell belongs to the stack, not to the card, and
// lives in Surfaces/Notifications/Popups.qml.
//
// Not a widget: it reads Theme, and it knows what a notification is. Widgets/
// is for the parts that know neither (#12 §3).
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import qs.Core
import qs.Services.Notifications
import qs.Widgets

Rectangle {
    id: card

    /// The popup's state. Required, and filled straight from the popup model's
    /// row — the role is named `toast`, and a required property of a delegate's
    /// root is what a model row binds to.
    required property Toast toast

    readonly property Notification notification: card.toast.notification

    /// The urgency colour. Ember is urgent and lamplight is attention, which is
    /// exactly what the two levels mean; a low-urgency card gets the dormant
    /// stone instead, so a backup finishing does not read like a fire (#8 §2).
    readonly property color accent: {
        if (card.notification.urgency === NotificationUrgency.Critical)
            return Theme.accentEmber;
        if (card.notification.urgency === NotificationUrgency.Low)
            return Theme.accentStone;
        return Theme.accentWarm;
    }

    /// The freedesktop convention: the action identified as "default" is what
    /// clicking the body does, and it is never drawn as a button. The rest are.
    readonly property var defaultAction: {
        const actions = card.notification.actions;
        for (let i = 0; i < actions.length; i++)
            if (actions[i].identifier === "default")
                return actions[i];
        return null;
    }

    readonly property var buttonActions: {
        const out = [];
        const actions = card.notification.actions;
        for (let i = 0; i < actions.length; i++)
            if (actions[i].identifier !== "default")
                out.push(actions[i]);
        return out;
    }

    /// What to put in the badge: the notification's own image if it sent one,
    /// its app icon from the icon theme otherwise, and nothing if neither
    /// resolves — in which case the Lucide bell below stands in.
    readonly property string badgeSource: {
        if (card.notification.image !== "")
            return card.url(card.notification.image);
        if (card.notification.appIcon !== "")
            return Quickshell.iconPath(card.notification.appIcon, true);
        return "";
    }

    /// A notification's image arrives either as a path or as a URL into
    /// Quickshell's own image provider (inline pixmap data). Only the first
    /// needs turning into a URL, and Paths.fileUrl would mangle the second.
    function url(value: string): string {
        return value.indexOf("://") >= 0 ? value : Paths.fileUrl(value);
    }

    implicitHeight: layout.implicitHeight + Theme.space4 * 2

    color: Theme.surfaceRaised
    radius: Theme.radiusMd
    border.width: Theme.hairline
    // A critical notification is the one card allowed to announce itself before
    // it is read.
    border.color: card.notification.urgency === NotificationUrgency.Critical
                  ? Theme.accentEmber : Theme.borderSubtle

    // --- motion --------------------------------------------------------------

    // Flipped one beat after construction so the Behaviours have somewhere to
    // travel from. Entering *and* leaving are the same two properties, which is
    // what stops an interrupted entrance from fighting an exit.
    property bool settled: false
    Component.onCompleted: card.settled = true

    opacity: card.settled && !card.toast.leaving ? 1 : 0
    // Deliberately not tied to `leaving`: the exit is opacity-only (#27), so
    // the scale settle happens on the way in and then stays put.
    scale: card.settled ? 1 : 0.99

    Behavior on opacity {
        NumberAnimation {
            duration: card.toast.leaving ? Theme.exitDuration(Theme.motionStandard)
                                         : Theme.motionStandard
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.fogEase
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: Theme.motionStandard
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.fogEase
        }
    }

    // --- input ---------------------------------------------------------------

    // A card under the pointer is a card being read, and does not time out. A
    // Binding rather than a signal handler so the hold is released when this
    // card goes away — the pointer can leave by the card being unloaded, and a
    // toast stuck held would never expire.
    HoverHandler { id: hover }

    Binding {
        target: card.toast
        property: "held"
        value: hover.hovered
    }

    // Left-click takes the default action where there is one, and otherwise
    // means "I have seen this". Middle-click always means the latter.
    //
    // A MouseArea and not a TapHandler because the buttons inside are
    // MouseAreas: item-level input is what reliably stops a click on an action
    // from also counting as a click on the card behind it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton || !card.defaultAction)
                card.toast.dismiss();
            else
                card.toast.invoke(card.defaultAction);
        }
    }

    // --- content -------------------------------------------------------------

    RowLayout {
        id: layout

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Theme.space4
        }
        spacing: Theme.space3

        Item {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 32
            implicitHeight: 32

            Image {
                id: badge
                anchors.fill: parent
                source: card.badgeSource
                sourceSize: Qt.size(64, 64)   // 2× for the 1.5-scale panel (#22)
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready
            }

            // Every notification has a badge, even the ones sent by something
            // with no icon at all — an empty square would read as a broken card.
            Icon {
                anchors.centerIn: parent
                visible: !badge.visible
                name: "bell"
                size: 20
                color: card.accent
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space1

            Text {
                Layout.fillWidth: true
                text: card.notification.appName.toUpperCase()
                visible: text !== ""
                color: Theme.textMuted
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(Theme.capsSize)
                font.weight: Theme.weightMedium
                font.letterSpacing: Theme.tracking(Theme.capsSize, Theme.capsTrackingEm)
            }

            Text {
                Layout.fillWidth: true
                text: card.notification.summary
                color: Theme.textPrimary
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(13)
                font.weight: Theme.weightMedium
            }

            Text {
                Layout.fillWidth: true
                text: card.notification.body
                visible: text !== ""
                color: Theme.textSecondary
                wrapMode: Text.Wrap
                maximumLineCount: 4   // a toast is a summary; the center has the rest (#43)
                elide: Text.ElideRight
                lineHeight: Theme.lineHeightBody
                lineHeightMode: Text.ProportionalHeight
                // Body markup is advertised to clients, so it has to be
                // rendered. Hyperlinks are not advertised and nothing here
                // handles a click on one.
                textFormat: Text.StyledText
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(12)
            }

            // Wrapping, because an action's label is whatever the client wrote:
            // three buttons that do not fit on one line stack instead of
            // pushing each other off the card.
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space1
                visible: card.buttonActions.length > 0
                spacing: Theme.space2

                Repeater {
                    model: card.buttonActions

                    Rectangle {
                        id: button

                        required property var modelData

                        implicitWidth: buttonLabel.implicitWidth + Theme.space4
                        implicitHeight: buttonLabel.implicitHeight + Theme.space2
                        radius: Theme.radiusSm
                        color: buttonHover.hovered ? Theme.surfaceOverlay : "transparent"
                        border.width: Theme.hairline
                        border.color: Theme.borderSubtle

                        Text {
                            id: buttonLabel
                            anchors.centerIn: parent
                            text: button.modelData.text
                            // Teal is the interactive accent, and an action is
                            // the only interactive thing on the card (#8 §2).
                            color: Theme.accentPrimary
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(12)
                            font.weight: Theme.weightMedium
                        }

                        HoverHandler { id: buttonHover }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: card.toast.invoke(button.modelData)
                        }
                    }
                }
            }
        }

        // Dismiss. Only drawn under the pointer: the shell is quiet until it is
        // being used, and the card is dismissable by clicking it anyway.
        MouseArea {
            id: close

            Layout.alignment: Qt.AlignTop
            implicitWidth: 20
            implicitHeight: 20
            hoverEnabled: true
            opacity: hover.hovered ? 1 : 0
            onClicked: card.toast.dismiss()

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.motionFast
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.fogEase
                }
            }

            Icon {
                anchors.centerIn: parent
                name: "x"
                size: 14
                color: close.containsMouse ? Theme.textPrimary : Theme.textMuted
            }
        }
    }
}
