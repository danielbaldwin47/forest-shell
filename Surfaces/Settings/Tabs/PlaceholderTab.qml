// A tab whose controls have not been built yet.
//
// Nothing reaches this today: #54 built four tabs and #55 the other six, so
// every id in the registry has a page. It stays because it is what `pageFor`
// falls through to and what the `built` flag selects — an eleventh tab landing
// half-built should say so on a navigable page rather than open an empty one,
// which is the state this component exists to make impossible.
//
// Navigable rather than hidden, and not empty: it lists whatever keys the
// section already has, with their live values, so the tab is a true statement
// about the config rather than a promise. Hand-editing `settings.json` is
// supported for the life of the shell — a section without a GUI is less
// convenient, not unavailable — and this is where that is said out loud.
//
// The list is read from the schema, so a key added by the ticket that builds the
// feature shows up here before its control does, with no edit to this file.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Surfaces.Settings.Controls

TabPage {
    id: page

    blurb: "No controls for this one yet. The keys below are live: edit "
           + "`~/.config/forest-shell/settings.json` and the shell picks them up as you "
           + "save."

    SectionHeader {
        text: page.keys.length > 0 ? "In the file today" : "Nothing configurable yet"
    }

    Repeater {
        model: page.keys

        RowLayout {
            id: keyRow

            required property string modelData

            Layout.fillWidth: true
            spacing: Theme.space4

            Text {
                Layout.fillWidth: true
                text: page.section + "." + keyRow.modelData
                color: Theme.textSecondary
                font.family: Theme.fontMono
                font.pointSize: Theme.pt(11.5)
                elide: Text.ElideRight
            }

            Text {
                text: page.render(page.section + "." + keyRow.modelData)
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pointSize: Theme.pt(11.5)
            }
        }
    }

    /// Leaf paths under this section, relative to it. Empty for a section whose
    /// ticket has not landed at all, and for About, which has no section.
    readonly property var keys: page.section === ""
        ? []
        : store.leafPathsUnder(Config.schema.spec, page.section)
               .map(path => path.slice(page.section.length + 1))

    function render(path: string): string {
        const values = Config.values;
        return JSON.stringify(store.getPath(values, path));
    }

    SpecStore { id: store }
}
