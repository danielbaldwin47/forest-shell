// Wallpaper — where the picker looks, and which image is up (#55, for #45).
//
// ## Why this is a list of names and not a grid of thumbnails
//
// The grid exists already: it is the control centre's picker (#45), reached
// from the wallpaper tile, and it is the right surface for choosing an image
// *by looking at it*. A second grid here would decode the whole folder again on
// a page nobody opened to browse pictures — by some distance the most expensive
// thing the shell can rebuild (#75) — to answer a question this page is asked
// for a different reason: which file is up, and where the picker is pointed.
//
// So the row is the filename with a tick beside the current one, the folder is
// a text field, and the path is editable directly for the case the picker
// cannot serve at all — a wallpaper that lives outside the folder, which
// `wallpaper.path` explicitly allows.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets
import qs.Surfaces.Background
import qs.Surfaces.Settings.Controls

TabPage {
    id: page

    title: "Wallpaper"
    section: "wallpaper"
    blurb: "The image behind everything. The control centre's wallpaper tile opens a "
           + "picker with thumbnails; this is the same two keys behind it."

    SectionHeader { text: "Where to look" }

    SettingRow {
        label: "Folder"
        hint: "Kept as written, `~/` and all: this config travels between machines and a "
              + "home directory does not. A folder that is not there is not an error — the "
              + "picker says where it looked and shows nothing."
        binding: folderBinding

        ConfigBinding { id: folderBinding; path: "wallpaper.folder" }

        SettingText {
            binding: folderBinding
            placeholder: "~/Pictures/Wallpapers"
            validate: text => text === "" || text.startsWith("/") || text.startsWith("~")
        }
    }

    SectionNote {
        note: Wallpapers.empty
              ? "Nothing found in " + Wallpapers.folder + "."
              : Wallpapers.entries.length + " image"
                + (Wallpapers.entries.length === 1 ? "" : "s") + " in " + Wallpapers.folder + "."
    }

    SectionHeader { text: "Current" }

    SettingRow {
        label: "Path"
        hint: "The image itself, which may live anywhere — the folder above is only where "
              + "the picker looks. Editing this is the way to use a wallpaper that is not "
              + "in it."
        binding: pathBinding

        ConfigBinding { id: pathBinding; path: "wallpaper.path" }

        SettingText {
            binding: pathBinding
            placeholder: "none"
            validate: text => text === "" || text.startsWith("/") || text.startsWith("~")
        }
    }

    Repeater {
        model: Wallpapers.entries

        Rectangle {
            id: entryRow

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: 32
            radius: Theme.radiusSm
            color: rowHover.hovered ? Theme.surfaceOverlay
                                    : (entryRow.modelData.current ? Theme.surfaceRaised
                                                                  : "transparent")

            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Wallpapers.choose(entryRow.modelData.path) }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space3
                anchors.rightMargin: Theme.space3
                spacing: Theme.space3

                Icon {
                    name: entryRow.modelData.current ? "check" : "image"
                    size: 13
                    color: entryRow.modelData.current ? Theme.accentPrimary : Theme.textMuted
                }

                Text {
                    Layout.fillWidth: true
                    text: entryRow.modelData.name
                    color: entryRow.modelData.current ? Theme.textPrimary : Theme.textSecondary
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(11.5)
                    elide: Text.ElideRight
                }
            }
        }
    }
}
