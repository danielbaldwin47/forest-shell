// What one screen shows while the session is locked (#30, #47).
//
// Quiet by default and quiet on purpose: the wallpaper under a veil and a fog
// wash, a serif clock, and nothing else. There is no field, no prompt and no
// avatar until a key is pressed — **type-to-summon** — which is both the design
// (a locked machine should look like a view, not like a login box) and the
// privacy position: a lock screen facing a room says the time and how many
// notifications are waiting, never whose machine it is or what anyone said.
//
// The band structure is the brief's (#8 §3.2, §5): the veil is the vertical
// luminance gradient, the field is a horizon hairline rather than a box (the
// launcher's "clearing" device, #11), and the status strip is a second, fainter
// band at the foot. No mountains are drawn — "ridgeline restraint" here means
// horizontal strata and receding contrast, not scenery.
//
// One of these exists per screen and they are all interchangeable: everything
// that is session state — the buffer, the conversation, the messages — lives in
// the shared LockAuth, so typing on one monitor and pressing Enter on another
// is one attempt (#22 §1: lock covers every output).
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Core
import qs.Widgets
import qs.Services.System
import qs.Surfaces.Background

Item {
    id: surface

    required property ShellScreen screen

    /// The session's one PAM conversation, shared by every screen.
    required property LockAuth auth

    // Revealed by a keystroke, and held open while there is anything to say:
    // something typed, a conversation in flight, a message under the field, or
    // faillock refusing — the last of which never retreats, because it is the
    // one thing here the user cannot type their way past.
    readonly property bool summoned: keyed || auth.buffer.length > 0 || auth.busy
                                     || auth.message !== ""

    property bool keyed: false

    // Inferred from the keystroke rather than read from a device — see
    // LockPolicy.capsFromKey. Undefined until the user types a cased letter,
    // which is exactly when it starts to matter.
    property bool capsLock: false

    LockPolicy { id: policy }

    function summon() {
        surface.keyed = true;
        retreat.restart();
    }

    // --- ground --------------------------------------------------------------

    // The same wallpaper the desktop is showing, decoded by the same rules
    // (bounded `sourceSize`, one gradient underneath for the unset case). The
    // lock is its own Wayland surface, so nothing shows through it — the
    // wallpaper has to be drawn again rather than revealed. It asks for exactly
    // the size the background window asked for, so on the usual path it comes
    // back from Qt's pixmap cache rather than decoding a second time.
    Wallpaper {
        anchors.fill: parent
        screen: surface.screen
    }

    // Brief §3.2 — dark at the bottom, bright at the top.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            // Qt.rgba over the token's own components rather than Qt.alpha,
            // which is a Qt 6.x addition this shell does not need to depend on.
            GradientStop {
                position: 0.0
                color: Qt.rgba(Theme.bgBase.r, Theme.bgBase.g, Theme.bgBase.b, Theme.veilTop)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(Theme.bgBase.r, Theme.bgBase.g, Theme.bgBase.b, Theme.veilBottom)
            }
        }
    }

    // Brief §3.1 — pale mist, not a black dim. The only thing that ever
    // animates here is this opacity (#8).
    Rectangle {
        id: fog
        anchors.fill: parent
        color: Theme.fogWash
        opacity: Theme.fogWashOpacity

        SequentialAnimation {
            id: fogPulse
            NumberAnimation {
                target: fog; property: "opacity"; to: Theme.fogPulseOpacity
                duration: Theme.motionFast
                easing.type: Easing.Bezier; easing.bezierCurve: Theme.fogEase
            }
            NumberAnimation {
                target: fog; property: "opacity"; to: Theme.fogWashOpacity
                duration: Theme.motionStandard
                easing.type: Easing.Bezier; easing.bezierCurve: Theme.fogEase
            }
        }
    }

    // --- clock ---------------------------------------------------------------

    // Ticks once a minute, natively, and only while this surface exists (#22
    // §5: no ambient loops, and seconds are not on screen so nothing needs to
    // sample them).
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Column {
        id: clockBlock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -parent.height * 0.14
        spacing: Theme.space3

        // The one serif touch in the shell (#8: Newsreader Light, clock only,
        // used once and never twice).
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date,
                                    policy.timeFormat(policy.use24Hour(
                                        Qt.locale().timeFormat(Locale.ShortFormat))))
            color: Theme.textPrimary
            font.family: Theme.fontDisplay
            font.weight: Theme.weightDisplay
            font.pointSize: Theme.pt(96)
            // Brief §4: slight negative tracking at large sizes.
            font.letterSpacing: Theme.tracking(96, -0.02)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, policy.dateFormat)
            color: Theme.textSecondary
            font.family: Theme.fontUi
            font.weight: Theme.weightRegular
            font.pointSize: Theme.pt(15)
        }
    }

    // --- the summoned field --------------------------------------------------

    Item {
        id: authBlock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: clockBlock.bottom
        anchors.topMargin: Theme.space10
        width: Math.min(360, surface.width - Theme.space10 * 2)
        height: fieldRow.height
                + (messageText.visible ? messageText.height + Theme.space3 : 0)

        // Never `visible: false`: an invisible item cannot hold key focus, and
        // key focus is the entire summon mechanism. Opacity does not affect
        // input, so the field is always listening and the first keystroke both
        // reveals it and lands in it.
        opacity: surface.summoned ? 1 : 0
        // The 1% scale settle every entering surface uses (#27) — the field
        // materializes out of the fog rather than sliding in.
        scale: surface.summoned ? 1 : 0.99

        transform: Translate { id: nudge }

        Behavior on opacity {
            NumberAnimation {
                duration: surface.summoned ? Theme.motionStandard
                                           : Theme.exitDuration(Theme.motionStandard)
                easing.type: Easing.Bezier; easing.bezierCurve: Theme.fogEase
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: Theme.motionStandard
                easing.type: Easing.Bezier; easing.bezierCurve: Theme.fogEase
            }
        }

        Item {
            id: fieldRow

            width: parent.width
            height: field.implicitHeight + Theme.space3

            TextInput {
                id: field

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: horizon.top
                anchors.bottomMargin: Theme.space2

                focus: true
                enabled: !surface.auth.busy
                horizontalAlignment: TextInput.AlignHCenter
                // PAM says whether the answer is a secret: a password is dotted,
                // an OTP or a device prompt is not.
                echoMode: surface.auth.responseVisible ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                passwordMaskDelay: 0

                color: Theme.textPrimary
                font.family: Theme.fontUi
                font.weight: Theme.weightRegular
                font.pointSize: Theme.pt(15)
                // Dots are wide enough to read as a row of stones at this
                // tracking; without it they clump.
                font.letterSpacing: Theme.tracking(15, 0.08)
                selectionColor: Theme.accentDeep
                selectedTextColor: Theme.textPrimary
                cursorVisible: surface.summoned && !surface.auth.busy

                onTextChanged: surface.auth.buffer = text
                onAccepted: surface.auth.submit()

                // Runs before the input handles the key and does not consume
                // it, so the character that summoned the field is also the
                // first character of the password.
                Keys.onPressed: event => {
                    surface.summon();

                    if (event.key === Qt.Key_Escape) {
                        surface.auth.clear();
                        event.accepted = true;
                        return;
                    }

                    const caps = policy.capsFromKey(
                        event.text, (event.modifiers & Qt.ShiftModifier) !== 0);
                    if (caps !== "unknown")
                        surface.capsLock = caps === "on";
                }
            }

            // The field is a horizon line, not a box (brief §6.5). It lights
            // teal while it has focus and something to say, and that is the
            // only interactive accent on this screen.
            Rectangle {
                id: horizon

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Theme.hairline
                color: surface.auth.busy ? Theme.accentDeep
                     : field.text.length > 0 ? Theme.accentPrimary
                     : Theme.borderSubtle

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.motionFast
                        easing.type: Easing.Bezier; easing.bezierCurve: Theme.fogEase
                    }
                }
            }
        }

        // Whatever PAM said, verbatim — including faillock's lockout text,
        // which is the only lockout state the shell has (#30). Ember when the
        // account is locked, because that is the one message here that is not
        // answerable by trying again.
        Text {
            id: messageText

            anchors.top: fieldRow.bottom
            anchors.topMargin: Theme.space3
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width

            text: surface.auth.message
            visible: text !== ""
            color: surface.auth.lockedOut ? Theme.accentEmber
                 : surface.auth.messageIsError ? Theme.textPrimary
                 : Theme.textSecondary
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.family: Theme.fontUi
            font.weight: Theme.weightRegular
            font.pointSize: Theme.pt(12.5)
            lineHeight: Theme.lineHeightBody
            lineHeightMode: Text.ProportionalHeight
        }
    }

    // A refusal shakes the field and thickens the fog (#30). The gesture is one
    // step of the ladder end to end — the legs are that step divided, not four
    // new durations — and it is a nudge, not a slide: nothing here travels far
    // enough to read as movement across the screen (#27).
    SequentialAnimation {
        id: shake

        readonly property int leg: Theme.motionFast / 4
        readonly property real throw_: Theme.space2

        NumberAnimation { target: nudge; property: "x"; to: -shake.throw_; duration: shake.leg }
        NumberAnimation { target: nudge; property: "x"; to: shake.throw_; duration: shake.leg }
        NumberAnimation { target: nudge; property: "x"; to: -shake.throw_ / 2; duration: shake.leg }
        NumberAnimation { target: nudge; property: "x"; to: 0; duration: shake.leg }
    }

    Connections {
        target: surface.auth

        function onFailed() {
            shake.restart();
            fogPulse.restart();
            // The retreat timer was last wound by the keystroke *before* the
            // Enter that failed, and PAM held it off while it was busy. Without
            // this, walking away from one wrong password leaves the field and
            // "Authentication failed" on screen until someone touches the
            // keyboard again.
            retreat.restart();
        }

        // A field the user has typed into no longer follows its binding, so a
        // buffer cleared from anywhere else has to be pushed back into it.
        function onCleared() {
            field.text = "";
        }

        function onBufferChanged() {
            if (field.text !== surface.auth.buffer)
                field.text = surface.auth.buffer;
        }
    }

    // Back into the fog when nothing has happened for a while, so a cat on the
    // keyboard does not leave the shell looking like a login box all night.
    Timer {
        id: retreat
        interval: policy.summonTimeoutMs
        onTriggered: {
            if (surface.auth.lockedOut
                    || !policy.mayRetreat(surface.auth.buffer.length > 0, surface.auth.busy))
                return;
            surface.keyed = false;
            surface.capsLock = false;
            surface.auth.clearMessage();
        }
    }

    // --- status strip --------------------------------------------------------

    // The second band (brief §5: horizontal strata over boxed cards). Everything
    // here is legible from across a room and tells that room nothing: a count,
    // a percentage, and a warning about a key.
    Row {
        id: statusStrip

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.space9
        spacing: Theme.space6

        // Count only, never contents (#9), and switchable off entirely for a
        // machine that locks in front of other people.
        Row {
            spacing: Theme.space2
            visible: notifications.text !== ""

            Icon {
                name: "bell"
                size: 15
                color: Theme.textMuted
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                id: notifications
                anchors.verticalCenter: parent.verticalCenter
                text: Config.values.system.lock.notificationCount
                      ? policy.notificationSummary(SessionLock.notificationCount) : ""
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.weight: Theme.weightRegular
                font.pointSize: Theme.pt(12.5)
            }
        }

        // Only while discharging: the lid is usually shut between locking and
        // unlocking, so "is it still on mains" is the one hardware fact worth
        // the space. On AC it is noise.
        //
        // Read straight off the native UPower singleton rather than through a
        // service, because there is no battery service yet — #36 builds one,
        // and this becomes a read of it.
        Row {
            id: batteryPill

            spacing: Theme.space2
            visible: UPower.onBattery && UPower.displayDevice.isLaptopBattery

            readonly property real fraction: UPower.displayDevice.percentage
            readonly property bool low: policy.batteryLow(fraction)

            Icon {
                name: batteryPill.low ? "battery-low" : "battery-medium"
                size: 15
                color: batteryPill.low ? Theme.accentEmber : Theme.textMuted
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: policy.batteryPercent(batteryPill.fraction) + "%"
                color: batteryPill.low ? Theme.accentEmber : Theme.textMuted
                font.family: Theme.fontUi
                font.weight: Theme.weightRegular
                font.pointSize: Theme.pt(12.5)
            }
        }

        // The lamplight role: attention, exactly one element at a time (#8).
        // Caps lock and a live fingerprint reader never both apply — the reader
        // stops prompting the moment the user starts typing.
        Row {
            spacing: Theme.space2
            visible: surface.capsLock

            Icon {
                name: "arrow-big-up"
                size: 15
                color: Theme.accentWarm
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Caps Lock"
                color: Theme.accentWarm
                font.family: Theme.fontUi
                font.weight: Theme.weightMedium
                font.pointSize: Theme.pt(Theme.capsSize)
                font.letterSpacing: Theme.tracking(Theme.capsSize, Theme.capsTrackingEm)
            }
        }
    }

    // The parallel conversation, when there is one. Its own line under the
    // strip so the two PAM contexts never overwrite each other on screen: what
    // fprintd says ("Place your finger on the reader") is about a device, not
    // about the password attempt above it.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: statusStrip.bottom
        anchors.topMargin: Theme.space4
        spacing: Theme.space2
        visible: surface.auth.fingerprintActive

        Icon {
            name: "fingerprint-pattern"
            size: 15
            color: Theme.textMuted
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: surface.auth.fingerprintMessage
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.weight: Theme.weightRegular
            font.pointSize: Theme.pt(12.5)
        }
    }
}
