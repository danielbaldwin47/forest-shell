// The Wi-Fi detail view (#45): what is on the air, what the machine is on, and
// the passphrase prompt for joining something new.
//
// ## The scanner is held by this panel, not by a button
//
// Services/Networking/Networking.qml leaves `scannerEnabled` off, because a
// scanning radio is a wakeup every few seconds against an idle budget of one a
// minute (#22 §5). It is turned on by whoever is looking and off again when
// they stop — and "who is looking" is this panel being open, which is why the
// hold and the release live in
// Surfaces/Drawers/ControlCenterActions.qml's `setPanel` rather than in this
// file. A panel that took the scanner in `Component.onCompleted` would drop it
// on destruction, and the destruction of a drawer's contents is exactly the
// path that is easiest to get wrong.
//
// ## The prompt is not inside a row
//
// It is the panel's own state (`ControlCenterActions.prompt`). A prompt living
// in a delegate would lose what the user had typed the moment a neighbouring
// access point appeared or dropped, because that republishes the list and
// rebuilds every delegate in it (#75). It is also why the text field is one
// field reused rather than one per row.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets
import qs.Services.Networking
import qs.Surfaces.Drawers

DrillInPanel {
    id: panel

    name: "wifi"

    // The scan is not instant and an empty list is the normal first second of
    // one. Saying so is the difference between "there is nothing here" and
    // "nothing yet".
    activity: Networking.scanning ? "scanning…" : ""

    note: {
        if (!Networking.available)
            return "No NetworkManager on this machine.";
        if (!Networking.wifiEnabled)
            return "The Wi-Fi radio is off. Turn it on from the tile.";
        if (Networking.lastFailure !== "")
            return Networking.lastFailureSsid + ": " + Networking.lastFailure;
        return Networking.wifiNetworks.length === 0 && !Networking.scanning
             ? "No networks found." : "";
    }

    noteIsProblem: Networking.lastFailure !== ""

    onBackRequested: ControlCenterActions.back("back")

    Repeater {
        // The stable list, republished only when the shape of it changes —
        // never for a signal strength (#75, and the facade's own comment).
        model: Networking.wifiNetworks

        DrillInRow {
            id: networkRow

            required property var modelData

            readonly property bool prompting:
                ControlCenterActions.prompt === networkRow.modelData.ssid

            // Bound to the *live* network rather than to the row's snapshot,
            // which is the whole trick that lets the list stay still while the
            // signal moves: nothing is rebuilt for this to change.
            glyph: Networking.wifi.icon(networkRow.modelData.live
                                        ? networkRow.modelData.live.signalStrength
                                        : networkRow.modelData.strength)
            label: networkRow.modelData.ssid
            detail: Networking.wifi.detail(networkRow.modelData)
            active: networkRow.modelData.connected
            dimmed: !Networking.wifi.joinable(networkRow.modelData)

            onActivated: ControlCenterActions.network(networkRow.modelData.ssid)
            // Forget, on the rows where there is something saved to forget.
            onSecondary: if (networkRow.modelData.known)
                ControlCenterActions.forgetNetwork(networkRow.modelData.ssid);

            Icon {
                visible: Networking.wifi.lockIcon(networkRow.modelData) !== ""
                         && !networkRow.prompting
                name: "lock"
                size: 12
                color: Theme.textMuted
            }
        }
    }

    // --- the prompt ----------------------------------------------------------
    //
    // One field for the whole panel, shown under the list rather than inside
    // the row it belongs to — see the header. It names the network it is for,
    // because a bare "Password:" under a list of thirty is a prompt you have to
    // scroll to identify.

    Rectangle {
        id: prompt

        width: parent ? parent.width : 0
        // A `Column` skips an invisible child entirely, so there is no reserved
        // gap where the prompt is not.
        height: promptColumn.implicitHeight + Theme.space2 * 2
        visible: ControlCenterActions.prompt !== ""
        radius: Theme.radiusMd
        color: Theme.surfaceRaised
        border.width: Theme.hairline
        border.color: Theme.borderSubtle

        // Focus arrives with the prompt: the user pressed a network to get
        // here, and a field they then have to click is a field that reads as
        // broken.
        onVisibleChanged: if (visible) field.takeFocus();

        ColumnLayout {
            id: promptColumn

            x: Theme.space2
            y: Theme.space2
            width: prompt.width - Theme.space2 * 2
            spacing: Theme.space1

            Text {
                Layout.fillWidth: true
                text: "Passphrase for " + ControlCenterActions.prompt
                elide: Text.ElideRight
                color: Theme.textSecondary
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(10.5)
            }

            TextField {
                id: field

                Layout.fillWidth: true
            }
        }
    }

    // A plain field rather than a `Controls` one: the shell's settings window
    // draws its own (Surfaces/Settings/Controls/SettingText.qml) and this is the
    // same argument one panel over — a themed `TextField` from QtQuick.Controls
    // brings a style with it that has to be fought back to the shell's own
    // tokens. Local to this file because it is this prompt's furniture: it is
    // the only masked field in the shell outside the lock screen, which has its
    // own for reasons of its own (#47).
    component TextField: Rectangle {
        id: fieldRoot

        implicitHeight: 30
        radius: Theme.radiusSm
        color: Theme.bgSunken
        border.width: Theme.hairline
        border.color: input.activeFocus ? Theme.accentPrimary : Theme.borderSubtle

        // Named `takeFocus` and not `forceActiveFocus`: every `Item` already has
        // one of the latter, and shadowing it with a function that does
        // something subtly different is how a caller comes to get the wrong one.
        function takeFocus(): void {
            input.forceActiveFocus();
        }

        // Cleared whenever the prompt moves to another network, so a passphrase
        // typed for one AP is never submitted to a different one.
        Connections {
            target: ControlCenterActions
            function onPromptChanged() { input.text = ""; }
        }

        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: Theme.space2
            anchors.rightMargin: reveal.width + Theme.space2 * 2
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Theme.textPrimary
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(11)
            echoMode: reveal.shown ? TextInput.Normal : TextInput.Password
            // The passphrase is a secret in a live process. Predictive text and
            // an input method holding a copy of it are both things this field
            // has no use for.
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText

            onAccepted: ControlCenterActions.passphrase(ControlCenterActions.prompt,
                                                        input.text)
            Keys.onEscapePressed: ControlCenterActions.passphrase(
                ControlCenterActions.prompt, "")

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: input.text === ""
                text: "Enter to join, Escape to cancel"
                color: Theme.textMuted
                font: input.font
            }
        }

        // The eye. A passphrase typed blind into a field that will reject it
        // eight characters later is the case this exists for.
        Item {
            id: reveal

            property bool shown: false

            anchors {
                right: parent.right
                rightMargin: Theme.space2
                verticalCenter: parent.verticalCenter
            }
            implicitWidth: 18
            implicitHeight: 18

            HoverHandler {
                id: revealHover
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: reveal.shown = !reveal.shown
            }

            Icon {
                anchors.centerIn: parent
                name: reveal.shown ? "eye-off" : "eye"
                size: 16
                color: revealHover.hovered ? Theme.accentPrimary : Theme.textMuted
            }
        }
    }
}
