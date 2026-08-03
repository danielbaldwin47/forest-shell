// Appearance — theming mode, dark/light, reduced effects, palette overrides
// (#54).
//
// The three theming modes are all listed and only one is selectable: fixed
// forest is what the shell does today, and the constrained accent (#58) and the
// full matugen palette (#59) are ticketed. Listing them greyed is the honest
// shape — the key is in the file, a hand-edit can set it, and the mode will
// start working when its service lands rather than appearing in the window from
// nowhere.
//
// Palette overrides are the one open map in the config: role → colour, applied
// on top of whichever palette the mode produced (Core/Tokens.qml). The role list
// is the token set itself, so a role that does not exist cannot be typed here —
// which matters, because the same value hand-edited into the file is only
// dropped with a warning on stderr.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Surfaces.Settings.Controls

TabPage {
    id: page

    title: "Appearance"
    section: "appearance"
    blurb: "How the shell is coloured. Everything below re-evaluates live — there is "
           + "nothing to reload, and nothing to restart."

    SectionHeader { text: "Theme" }

    SettingRow {
        label: "Theming mode"
        hint: "Fixed forest is the shipped palette. The wallpaper-coupled modes arrive "
              + "with their services and are inert until then."
        binding: modeBinding

        ConfigBinding { id: modeBinding; path: "appearance.mode" }

        SettingChoice {
            binding: modeBinding
            options: [
                { value: "forest", label: "Fixed forest" },
                { value: "accent", label: "Constrained accent", enabled: false },
                { value: "dynamic", label: "Full dynamic", enabled: false }
            ]
        }
    }

    SettingRow {
        label: "Dark mode"
        hint: "v1 ships dark-first; the light table is a seed, and the roles it does "
              + "not name fall back to their dark value."
        binding: darkBinding

        ConfigBinding { id: darkBinding; path: "appearance.darkMode" }

        SettingSwitch { binding: darkBinding }
    }

    SectionHeader { text: "Themes" }

    SectionNote {
        note: "A theme is a skin and never a layout: the palette overrides below, the "
              + "bar's surface and ridgeline styling, and the theming mode. Bar geometry, "
              + "module lists and every service setting stay on this machine. Applying one "
              + "copies its keys into settings.json — there is no live link afterwards, so "
              + "editing a knob is editing your settings and not the theme."
    }

    ThemeSection {}

    SectionHeader { text: "Effects" }

    SettingRow {
        label: "Reduced effects"
        hint: "The one degrade knob, in cost order: no compositor blur, no decorative "
              + "effects, and every transition becomes a 140 ms fade with nothing moving. "
              + "A supported look, not a stripped one."
        binding: reducedBinding

        ConfigBinding { id: reducedBinding; path: "appearance.reducedEffects" }

        SettingSwitch { binding: reducedBinding }
    }

    SectionHeader { text: "Palette overrides" }

    SectionNote {
        note: "One colour per role, over the current mode. Blank means the shipped value. "
              + "`#RGB`, `#RRGGBB` and `#AARRGGBB` are the forms Qt parses — a name like "
              + "\"teal\" is refused, so an override cannot smuggle in a hue the palette "
              + "never sampled."
    }

    Repeater {
        model: page.roles

        RowLayout {
            id: roleRow

            required property string modelData

            Layout.fillWidth: true
            spacing: Theme.space4

            // The colour as it actually resolves — mode plus override — so the
            // swatch is what the shell is painting, not what was typed.
            Rectangle {
                implicitWidth: 22
                implicitHeight: 22
                radius: Theme.radiusSm
                color: Theme.palette[roleRow.modelData]
                border.width: Theme.hairline
                border.color: Theme.borderSubtle
            }

            Text {
                Layout.fillWidth: true
                text: roleRow.modelData
                color: Theme.textSecondary
                font.family: Theme.fontMono
                font.pointSize: Theme.pt(11.5)
                elide: Text.ElideRight
            }

            ConfigBinding {
                id: roleBinding
                path: "appearance.paletteOverrides"
                knob: roleRow.modelData
            }

            SettingText {
                binding: roleBinding
                placeholder: "default"
                // Empty is how a role is *un*-overridden — the key leaves the
                // map rather than being set to a colour that does not parse.
                validate: text => text === "" || Theme.isColor(text)
                submit: text => text === "" ? roleBinding.removeKnob()
                                            : roleBinding.commit(text)
            }

            IconButton {
                name: "x"
                hoverColor: Theme.accentEmber
                visible: roleBinding.value !== undefined
                onTapped: roleBinding.removeKnob()
            }
        }
    }

    /// The token set, from the resolved palette — a role that is not in it does
    /// not exist (Core/Tokens.qml).
    readonly property var roles: Object.keys(Theme.palette)
}
