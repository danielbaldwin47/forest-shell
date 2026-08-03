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
import qs.Core
import qs.Widgets
import qs.Services.Hardware
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

    // Whether "the field can hear a keyboard" has already been logged, so the
    // line is evidence of the first focus rather than a running commentary.
    property bool focusReported: false

    // Inferred from the keystroke rather than read from a device — see
    // LockPolicy.capsFromKey. Undefined until the user types a cased letter,
    // which is exactly when it starts to matter.
    property bool capsLock: false

    // Composition, not tokens: where the horizon sits on this particular
    // surface. The clock rides above the optical centre so the summoned field
    // lands near it rather than pushing the whole block off balance, and the
    // brief's negative tracking at display sizes (§4) is a per-surface taste
    // call the design system deliberately does not fix.
    readonly property real clockRise: 0.14
    readonly property int statusIconSize: 15
    readonly property real statusTextSize: 12.5
    readonly property real displayTrackingEm: -0.02
    readonly property real fieldTrackingEm: 0.08

    // One instance per surface, like Core/SettingsSchema.qml's `Coerce {}`:
    // a stateless bag of pure functions is cheaper to build than to share.
    LockPolicy { id: policy }

    // Everything in the status strip is the same shape: a glyph and a line, one
    // colour between them. Inline components live on the file's root object.
    component StatusItem: Row {
        id: item

        property alias icon: glyph.name
        property string label
        property color tint: Theme.textMuted
        /// A tiny all-caps label rather than an ordinary line — the shell's one
        /// type-level distinction between a reading and a warning (#8).
        property bool warning: false

        spacing: Theme.space2

        Icon {
            id: glyph
            size: surface.statusIconSize
            color: item.tint
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: item.label
            color: item.tint
            font.family: Theme.fontUi
            font.weight: item.warning ? Theme.weightMedium : Theme.weightRegular
            font.pointSize: item.warning ? Theme.pt(Theme.capsSize)
                                         : Theme.pt(surface.statusTextSize)
            font.letterSpacing: item.warning
                ? Theme.tracking(Theme.capsSize, Theme.capsTrackingEm) : 0
        }
    }


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
            // Opacity, so it is the half of the refusal gesture that survives
            // reduced effects — the shake next to it is not (#69).
            NumberAnimation {
                target: fog; property: "opacity"; to: Theme.fogPulseOpacity
                duration: Theme.duration(Theme.motionFast)
                easing.type: Easing.Bezier; easing.bezierCurve: Theme.fogEase
            }
            NumberAnimation {
                target: fog; property: "opacity"; to: Theme.fogWashOpacity
                duration: Theme.duration(Theme.motionStandard)
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

    // *How* it is written is not the lock's to decide (#93). The lock used to
    // follow the locale while the bar hardcoded 24-hour, so one shell showed
    // two clocks; both read Core/TimeFormat.qml now.

    Column {
        id: clockBlock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -parent.height * surface.clockRise
        spacing: Theme.space3

        // The one serif touch in the shell (#8: Newsreader Light, clock only,
        // used once and never twice).
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, TimeFormat.time)
            color: Theme.textPrimary
            font.family: Theme.fontDisplay
            font.weight: Theme.weightDisplay
            font.pointSize: Theme.pt(96)
            // Brief §4: slight negative tracking at large sizes.
            font.letterSpacing: Theme.tracking(96, surface.displayTrackingEm)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, TimeFormat.date)
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
        // materializes out of the fog rather than sliding in. Reduced effects
        // drops the settle and keeps the fade (#69).
        scale: surface.summoned || !Theme.animateTransforms ? 1 : 0.99

        transform: Translate { id: nudge }

        Behavior on opacity {
            NumberAnimation {
                duration: surface.summoned ? Theme.duration(Theme.motionStandard)
                                           : Theme.exitDuration(Theme.motionStandard)
                easing.type: Easing.Bezier; easing.bezierCurve: Theme.fogEase
            }
        }

        Behavior on scale {
            enabled: Theme.animateTransforms
            NumberAnimation {
                duration: Theme.duration(Theme.motionStandard)
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
                // `readOnly`, never `enabled: false`: disabling an item clears
                // its active focus and re-enabling does not give it back, which
                // would kill type-to-summon for the rest of the lock. Read-only
                // still receives keys, it just refuses to record them.
                readOnly: surface.auth.busy
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
                font.letterSpacing: Theme.tracking(15, surface.fieldTrackingEm)
                selectionColor: Theme.accentDeep
                selectedTextColor: Theme.textPrimary
                cursorVisible: surface.summoned && !surface.auth.busy

                onTextChanged: surface.auth.buffer = text
                onAccepted: surface.auth.submit()

                // Each lock surface is its own window, so focus has to be taken
                // rather than inherited — an output that comes up mid-lock is
                // otherwise deaf.
                //
                // Taken when the window is shown and again when it is activated,
                // never at `Component.onCompleted` (#81): Quickshell builds the
                // lock surfaces *before* it takes the compositor lock — it
                // preloads them so the first frame is not blank — so at
                // construction this window is not mapped, cannot hold active
                // focus, and `forceActiveFocus()` there is a silent no-op.
                Connections {
                    target: field.Window.window

                    function onVisibleChanged() {
                        if (field.Window.window.visible)
                            field.forceActiveFocus();
                    }

                    function onActiveChanged() {
                        if (field.Window.window.active)
                            field.forceActiveFocus();
                    }
                }

                // The one thing no headless check and no harness can stand in
                // for: whether a real keystroke would land here. Logged once
                // when it arrives, and complained about if it never does —
                // silence on this line means the lock cannot hear a keyboard.
                onActiveFocusChanged: {
                    if (field.activeFocus && !surface.focusReported) {
                        surface.focusReported = true;
                        focusWatchdog.stop();
                        Logger.log("lock", "field has focus on " + surface.screen.name);
                    }
                }

                Timer {
                    id: focusWatchdog
                    interval: policy.conversationTimeoutMs
                    running: true
                    onTriggered: {
                        if (!field.activeFocus)
                            Logger.warn("lock", "field never took focus on " + surface.screen.name
                                        + " — the lock cannot hear a keyboard");
                    }
                }

                // Runs before the input handles the key and does not consume
                // it, so the character that summoned the field is also the
                // first character of the password.
                Keys.onPressed: event => {
                    surface.summon();
                    // Reopens a conversation that ended without prompting —
                    // see LockAuth.rearm(). A no-op on every other keystroke.
                    surface.auth.rearm();

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
                        duration: Theme.duration(Theme.motionFast)
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
    //
    // The shake is movement, so reduced effects drops it (#69) and the fog
    // pulse carries the refusal on its own. That the two are separate
    // animations is what makes dropping one of them leave a gesture rather than
    // nothing: a refusal is still visibly a refusal with the knob on.
    SequentialAnimation {
        id: shake

        readonly property int leg: Theme.motionFast / 4
        readonly property real swing: Theme.space2

        NumberAnimation { target: nudge; property: "x"; to: -shake.swing; duration: shake.leg }
        NumberAnimation { target: nudge; property: "x"; to: shake.swing; duration: shake.leg }
        NumberAnimation { target: nudge; property: "x"; to: -shake.swing / 2; duration: shake.leg }
        NumberAnimation { target: nudge; property: "x"; to: 0; duration: shake.leg }
    }

    Connections {
        target: surface.auth

        function onFailed() {
            if (Theme.animateTransforms)
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
        // machine that locks in front of other people. Zero shows nothing at
        // all rather than a nought — the empty lock screen is the quiet one.
        StatusItem {
            icon: "bell"
            label: Config.values.system.lock.notificationCount
                   ? policy.notificationSummary(SessionLock.notificationCount) : ""
            visible: label !== ""
        }

        // Only while discharging: the lid is usually shut between locking and
        // unlocking, so "is it still on mains" is the one hardware fact worth
        // the space. On AC it is noise.
        //
        // Read through the power service (#36), which is what the note here
        // used to promise: the bar's battery module and this pill now share one
        // definition of "low", and they are on screen together often enough
        // that two would be visible as a disagreement.
        StatusItem {
            id: batteryPill

            visible: !Power.onMains && Power.hasBattery
            // The service's own glyph, not a second opinion about it: a lock
            // and a bar that drew different batteries for the same charge would
            // be the disagreement this read was meant to end.
            icon: Power.icon
            label: Power.label
            // Ember here and not on the bar: the lock's status strip sits over
            // the fog wash rather than over a wallpaper, so the colour that
            // fails the bar's contrast rule passes on this surface.
            tint: Power.low ? Theme.accentEmber : Theme.textMuted
        }

        // The lamplight role: attention, exactly one element at a time (#8).
        // Caps lock and a live fingerprint reader never both apply — the reader
        // stops prompting the moment the user starts typing.
        StatusItem {
            visible: surface.capsLock
            icon: "arrow-big-up"
            label: "Caps Lock"
            tint: Theme.accentWarm
            warning: true
        }
    }

    // The parallel conversation, when there is one. Its own line under the
    // strip so the two PAM contexts never overwrite each other on screen: what
    // fprintd says ("Place your finger on the reader") is about a device, not
    // about the password attempt above it.
    StatusItem {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: statusStrip.bottom
        anchors.topMargin: Theme.space4

        visible: surface.auth.fingerprintActive
        icon: "fingerprint-pattern"
        label: surface.auth.fingerprintMessage
    }
}
