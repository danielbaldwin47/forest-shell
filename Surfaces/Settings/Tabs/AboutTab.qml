// About — what this is, what it is built out of, and whether its release notes
// have been read (#55).
//
// The one tab with no config section, so it edits one key and that key is
// state: `seen.changelogVersion` in `state.json`. Everything else here is read
// from Surfaces/Settings/AboutFacts.qml, which is where the version string
// lives — a Quickshell config directory has no manifest to read one out of, so
// some file has to state it and that is the file whose job it is.
//
// There is no changelog *document* in the repo yet. The flag is still the right
// thing to surface: it is what suppresses a what's-new notice, it is the kind of
// state that is invisible until it misbehaves, and the row is the only way to
// ask for the notice again. A tab that hid it until the notes existed would be
// hiding the half of the pair that can go wrong.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets
import qs.Surfaces.Settings
import qs.Surfaces.Settings.Controls

TabPage {
    id: page

    title: "About"
    section: ""
    blurb: facts.tagline

    AboutFacts { id: facts }

    SectionHeader { text: "Version" }

    SettingRow {
        label: "forest-shell"
        hint: "Pre-1.0 on purpose: v1 is the last item on the build plan, and a shell that "
              + "called itself 1.0 before its own plan said so would be the version number "
              + "lying about the thing it exists to describe."
        enabled: false

        Text {
            text: facts.version
            color: Theme.textSecondary
            font.family: Theme.fontMono
            font.pointSize: Theme.pt(11.5)
        }
    }

    SettingRow {
        label: "Release notes"
        hint: "Which version's notes this machine has been shown. A version rather than a "
              + "yes/no, so upgrading announces itself with nothing written — and clearing "
              + "it is how to ask for the notice again."

        RowLayout {
            spacing: Theme.space3

            Text {
                text: facts.seenLabel(page.seenVersion)
                color: page.seen ? Theme.textSecondary : Theme.textMuted
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(11.5)
                elide: Text.ElideRight
            }

            IconButton {
                name: "rotate-ccw"
                possible: page.seenVersion !== ""
                onTapped: ShellState.set("seen.changelogVersion", "")
            }
        }
    }

    SectionHeader { text: "Built with" }

    Repeater {
        model: facts.credits

        SettingRow {
            id: creditRow

            required property var modelData

            label: creditRow.modelData.name
            hint: creditRow.modelData.what

            Text {
                text: creditRow.modelData.url.replace(/^https?:\/\//, "")
                color: linkHover.hovered ? Theme.accentPrimary : Theme.textMuted
                font.family: Theme.fontMono
                font.pointSize: Theme.pt(11)
                elide: Text.ElideRight

                FogColorBehavior on color {}

                HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Qt.openUrlExternally(creditRow.modelData.url) }
            }
        }
    }

    // --- the one piece of state this tab reads -------------------------------

    readonly property string seenVersion: ShellState.values.seen.changelogVersion
    readonly property bool seen: facts.changelogSeen(page.seenVersion)
}
