// One shortcut, printed as keycaps.
//
// Shared by the command menu's rows and the shortcuts sheet's table, which is
// the whole reason it is a file: two places drawing `Ctrl+N` slightly
// differently is exactly the sort of drift nobody notices until both are on
// screen at once, and the shortcuts sheet exists to put them on screen at once.
//
// It draws and decides nothing: what a shortcut string breaks into is
// `KeyNavPolicy.keyCaps`, at the first seam, where `/` meaning "or" and `+`
// meaning "at the same time" are checked rather than assumed. This file turns
// that list into rectangles.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Row {
    id: keycaps

    /// `KeyNavPolicy.keyCaps(...)` output — `[{kind: "key"|"sep", text}]`.
    property var caps: []

    /// The cap face. `bgSunken` rather than `surfaceOverlay` so a badge reads
    /// as *recessed* on a raised card — the physical metaphor a keycap is.
    property color faceColor: Theme.bgSunken
    property color textColor: Theme.textSecondary

    spacing: Theme.space1

    Repeater {
        model: keycaps.caps

        delegate: Item {
            id: cap

            required property var modelData

            readonly property bool isKey: !!cap.modelData && cap.modelData.kind === "key"

            // 22 wide minimum so `D` and `W` are the same size as each other
            // rather than the width of their own glyph — a row of badges that
            // jitters by letter reads as a bug in the type.
            implicitWidth: cap.isKey
                         ? Math.max(22, glyph.implicitWidth + Theme.space2 * 2)
                         : glyph.implicitWidth
            implicitHeight: 20

            Rectangle {
                anchors.fill: parent
                visible: cap.isKey
                radius: 4
                color: keycaps.faceColor
                border.width: 1
                border.color: Theme.borderSubtle
            }

            Text {
                id: glyph

                anchors.centerIn: parent
                text: cap.modelData ? String(cap.modelData.text) : ""
                color: keycaps.textColor
                // Mono on the cap, the UI face on the slash between two of
                // them: the slash is prose, not a key.
                font.family: cap.isKey ? Theme.fontMono : Theme.fontUi
                font.pointSize: Theme.pt(10.5)
                font.weight: Theme.weightMedium
                opacity: cap.isKey ? 1 : 0.7
            }
        }
    }
}
