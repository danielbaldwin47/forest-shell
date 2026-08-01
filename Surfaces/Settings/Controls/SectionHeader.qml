// A group heading inside a settings tab (#54): the design system's tiny
// all-caps label, with a rule running out to the right so a long tab reads as
// bands rather than as one list.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core

RowLayout {
    id: root

    required property string text

    Layout.fillWidth: true
    Layout.topMargin: Theme.space4
    spacing: Theme.space3

    Text {
        text: root.text.toUpperCase()
        color: Theme.textMuted
        font.family: Theme.fontUi
        font.pointSize: Theme.pt(Theme.capsSize)
        font.weight: Theme.weightMedium
        font.letterSpacing: Theme.tracking(Theme.capsSize, Theme.capsTrackingEm)
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: Theme.hairline
        color: Theme.borderSubtle
    }
}
