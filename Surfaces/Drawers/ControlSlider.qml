// One slider of the control centre (#44): volume, microphone, brightness.
//
// A glyph, a track and a reading. The glyph is a *button* on the two sliders
// that can mute and dead on the one that cannot — a screen at 0% is not the
// same act as a muted speaker, and there is nothing to restore it to.
//
// ## Why the value is pushed rather than bound
//
// The track's fill is bound to the service, which is what makes an external
// change — a volume key, `brightnessctl` in a terminal — move it. But a *drag*
// cannot be: binding the fill to the service and the service to the drag is a
// loop, and the loop's visible form is a handle that lags the pointer and
// then springs back when the service catches up. So a drag takes the track
// over (`dragging`), the fill follows the pointer directly, and the service is
// what the drag *writes* — the binding resumes when the finger lifts.
//
// The percent-to-fraction conversion, the clamp and the notch size are all
// ControlCenterPolicy.qml's, so `tests/` can check them without a compositor.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets

Item {
    id: slider

    /// The row ControlCenterPolicy handed over: `{ id, percent, icon, label,
    /// muted, mutable }`.
    required property var model
    required property ControlCenterPolicy policy

    /// A new position, in whole percent. Raised continuously through a drag —
    /// the services all take a live value, and a slider that only committed on
    /// release would be a volume you cannot hear yourself setting.
    signal moved(int percent)

    /// The glyph was pressed on a slider that can mute.
    signal muteToggled

    /// Whether the pointer owns the value right now. See the header.
    property bool dragging: false
    property int dragPercent: 0

    readonly property int value: slider.dragging ? slider.dragPercent
                                                 : slider.model.percent

    implicitHeight: 36

    RowLayout {
        anchors.fill: parent
        spacing: Theme.space3

        // The glyph, and on two of the three sliders also the mute button. Its
        // width is fixed so the track starts at the same x on all three — three
        // tracks that begin at three different places is the row looking ragged
        // for no reason.
        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 24
            implicitHeight: 24

            HoverHandler {
                id: glyphHover
                enabled: slider.model.mutable === true
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                enabled: slider.model.mutable === true
                onTapped: slider.muteToggled()
            }

            Icon {
                anchors.centerIn: parent
                name: slider.model.icon
                size: 18
                // Muted is a state worth seeing without reading the glyph
                // shape: lamplight is the shell's "attention, exactly one
                // element at a time" (#8 §2), and a muted microphone in a call
                // is the one thing in this panel worth that.
                color: slider.model.muted ? Theme.accentWarm
                     : glyphHover.hovered ? Theme.textPrimary
                     : Theme.textSecondary
            }
        }

        Item {
            id: track

            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 24

            function percentAt(x: real): int {
                return track.width <= 0 ? 0
                     : slider.policy.clampPercent(x / track.width * 100);
            }

            Rectangle {
                id: groove

                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: Theme.bgSunken

                Rectangle {
                    width: groove.width * slider.value / 100
                    height: groove.height
                    radius: groove.radius
                    // A muted slider keeps its position and loses its colour:
                    // the level is still what it will come back to.
                    color: slider.model.muted ? Theme.accentStone : Theme.accentPrimary

                    // No `Behavior` while the pointer owns it — an animation on
                    // a dragged value is a handle that trails the finger.
                    Behavior on width {
                        enabled: !slider.dragging
                        NumberAnimation {
                            duration: Theme.duration(Theme.motionFast)
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Theme.fogEase
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                // Taller than the groove it drives: a 6px hit target is a
                // slider you miss.
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onPressed: mouse => {
                    slider.dragging = true;
                    slider.dragPercent = track.percentAt(mouse.x);
                    slider.moved(slider.dragPercent);
                }

                onPositionChanged: mouse => {
                    if (!slider.dragging)
                        return;
                    slider.dragPercent = track.percentAt(mouse.x);
                    slider.moved(slider.dragPercent);
                }

                onReleased: slider.dragging = false
                onCanceled: slider.dragging = false

                onWheel: wheel => {
                    const direction = wheel.angleDelta.y > 0 ? 1 : -1;
                    slider.moved(slider.policy.nudge(slider.value, direction));
                }
            }
        }

        // The reading. A fixed width, because a number that changes width as it
        // passes 100 drags the track's right edge with it on every notch.
        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 34
            horizontalAlignment: Text.AlignRight
            text: slider.value + "%"
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(10.5)
        }
    }
}
