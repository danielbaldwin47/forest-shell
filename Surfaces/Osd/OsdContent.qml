// The pill itself (#46): a glyph, a track and a reading.
//
// The same vocabulary as the control centre's slider
// (Surfaces/Drawers/ControlSlider.qml) with the one thing that makes it a
// slider taken out — nothing here is draggable, because the OSD is what the
// machine says back, not a control. That is deliberate: the two are the same
// three channels, and reading one after the other should not feel like two
// different shells.
//
// Dumb by contract. Everything it draws arrives as a property, so the capture
// harness can pose it (`--surface osd`) without a service, a compositor or a
// keypress — and what it poses is this file, not a copy of it.
//
// The motion is #27's OSD row, and no more than it: the *window* fades in over
// 240 and out over 140 (OsdWindow.qml owns that, because a window is what
// enters and leaves), and the one thing that moves in here is the track's fill
// when the level does — the in-place 140.
//
// It moves *within a channel only*. A second channel taking the pill over
// while it is still up is not an in-place update of anything: the fill
// travelling from 45% volume to 90% brightness is one bar animating between
// two numbers that have nothing to do with each other, and it reads as the
// volume having changed. So a channel switch snaps, and only a level change
// travels. Under `reducedEffects` nothing travels at all (#69: transforms off,
// opacity only).
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets

Item {
    id: pill

    required property OsdPolicy policy

    /// What is being reported: one of `policy.channels`, or `""`.
    required property string channel
    required property int percent
    required property bool muted

    /// True for the instant a new channel's value is landing. See the header:
    /// the fill snaps between channels and travels within one.
    ///
    /// `Qt.callLater` and not a timer — it runs after the properties this pop
    /// is assigning have all propagated, which is exactly the window the fill
    /// needs to be re-bound in, and it costs no wakeup when the pill is idle.
    property bool switchingChannel: false

    onChannelChanged: {
        pill.switchingChannel = true;
        Qt.callLater(() => pill.switchingChannel = false);
    }

    // The pill's size is OsdPolicy's, not this file's: the window has to know
    // how big its surface is before this item exists, and two copies of that
    // number drift into a window that resizes itself the first time it shows.
    implicitWidth: pill.policy.pillWidth
    implicitHeight: pill.policy.pillHeight

    Rectangle {
        id: surface

        anchors.fill: parent
        radius: Theme.radiusFull
        // Raised rather than `surface`: this floats over whatever is on screen,
        // and it is the same fill a notification card uses for the same reason.
        color: Theme.surfaceRaised
        border.width: Theme.hairline
        border.color: Theme.borderSubtle

        RowLayout {
            anchors {
                fill: parent
                leftMargin: Theme.space5
                rightMargin: Theme.space5
            }
            spacing: Theme.space4

            Icon {
                name: pill.policy.icon(pill.channel, pill.percent, pill.muted)
                size: 20
                // The muted state is said twice — glyph and reading — and drawn
                // once: an ember mute would make "quiet" look like "urgent",
                // which is the one thing the accent structure forbids (#8).
                color: pill.muted ? Theme.textMuted : Theme.textSecondary
                Layout.alignment: Qt.AlignVCenter
            }

            // The track. A well and a fill, which is the same pair the control
            // centre draws — see ControlSlider.qml.
            Rectangle {
                id: track

                Layout.fillWidth: true
                Layout.preferredHeight: 6
                Layout.alignment: Qt.AlignVCenter

                radius: height / 2
                color: Theme.bgSunken

                Rectangle {
                    id: fill

                    width: track.width * pill.policy.fraction(pill.percent)
                    height: track.height
                    radius: track.radius
                    // Muted is drawn as dormant rather than as absent: the
                    // level underneath is unchanged and unmuting returns to it,
                    // so the track keeps saying where it will come back to.
                    color: pill.muted ? Theme.accentStone : Theme.accentPrimary

                    // #27's in-place update, and the only animation on this
                    // surface. A width is a transform in all but name, so
                    // reduced effects takes it away and the fill arrives at its
                    // new place instead of travelling there (#69) — and so does
                    // a channel switch, for the reason the header gives.
                    Behavior on width {
                        enabled: Theme.animateTransforms && !pill.switchingChannel
                        NumberAnimation {
                            duration: Theme.duration(pill.policy.inPlaceMs)
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Theme.fogEase
                        }
                    }
                }
            }

            // The reading. Fixed width, right-aligned: the string is four
            // characters at 100% and two at 5%, and a track that resized itself
            // as the number grew would be an in-place update that moved the
            // thing it is updating.
            Text {
                text: pill.policy.readout(pill.channel, pill.percent, pill.muted)
                color: Theme.textPrimary
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(12.5)
                font.weight: Theme.weightMedium
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: 52
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
