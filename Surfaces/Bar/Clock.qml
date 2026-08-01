// The clock (#35): the one place the display face is allowed on the bar.
//
// Newsreader Light, once and never twice (#8) — a serif at 14px among Plex
// chrome is the bar's single moment of warmth, and it is spent here. The date
// beside it stays Plex, muted, so the two do not compete.
//
// It ticks once a minute, aligned to the minute, because no seconds are
// visible: a bar clock waking 60 times a minute is most of a wakeup budget
// (#22 §5) spent on a digit nobody can see. `SystemClock` does the aligning —
// a 60s timer would drift and would tick at whatever second the shell started.
//
// Format is fixed here rather than configured: 24-hour time, locale-independent
// day and month. The clock format setting belongs to the weather & time section
// (#50), which owns 12/24h alongside units and location.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Core

Item {
    id: root

    /// Bar context, assigned by BarSlot.qml. See Workspaces.qml.
    property var screen: null
    property bool vertical: false

    readonly property string timeText: Qt.formatDateTime(clock.date, "HH:mm")
    readonly property string dateText: Qt.formatDateTime(clock.date, "ddd d MMM")

    implicitWidth: root.vertical ? stacked.implicitWidth : wide.implicitWidth
    implicitHeight: root.vertical ? stacked.implicitHeight : wide.implicitHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    component Face: Text {
        color: Theme.textPrimary
        font.family: Theme.fontDisplay
        font.pixelSize: 14
        font.weight: Theme.weightDisplay
    }

    // A vertical bar has no room for the date, so it carries the time alone —
    // the module is the same module, sideways.
    Row {
        id: wide
        anchors.centerIn: parent
        visible: !root.vertical
        spacing: Theme.space2

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.dateText
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Theme.weightRegular
        }

        Face {
            anchors.verticalCenter: parent.verticalCenter
            text: root.timeText
        }
    }

    Face {
        id: stacked
        anchors.centerIn: parent
        visible: root.vertical
        text: root.timeText
    }
}
