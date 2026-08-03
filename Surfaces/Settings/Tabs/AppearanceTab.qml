// Appearance — theming mode, dark/light, reduced effects, palette overrides
// (#54).
//
// All three theming modes are here: fixed forest is what the shell has always
// done, the constrained accent arrived with Services/Theming/ (#58), and the
// full matugen palette (#59) is selectable on a machine that has matugen and
// greyed with a hint on one that does not. Greyed rather than hidden is the
// honest shape — the key is in the file, a hand-edit can set it, and a control
// that vanished would make an optional dependency look like a missing feature.
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
import qs.Services.Theming
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
        hint: "Fixed forest is the shipped palette. Constrained accent lets the wallpaper "
              + "slide the teal between sage and lake blue and changes nothing else — the "
              + "backgrounds, the warm accents and every text colour stay put. Full "
              + "dynamic hands the wallpaper to matugen and wears the whole palette it "
              + "generates, measured back up to the same contrast floor the shipped one "
              + "holds."
        binding: modeBinding

        ConfigBinding { id: modeBinding; path: "appearance.mode" }

        SettingChoice {
            binding: modeBinding
            options: [
                { value: "forest", label: "Fixed forest" },
                { value: "accent", label: "Constrained accent" },
                // The one control in the window whose availability is a fact
                // about the machine. matugen is optional and the mode cannot
                // run without it, so the choice is greyed rather than hidden:
                // the key stays hand-editable, the hint below says what to
                // install, and a click that quietly did nothing never happens.
                { value: "dynamic", label: "Full dynamic", enabled: Matugen.available }
            ]
        }
    }

    Text {
        Layout.fillWidth: true
        visible: Matugen.probed && !Matugen.available
        text: "Full dynamic needs matugen, which is not installed. Install it and reopen "
              + "the shell — nothing else changes, and the other two modes never needed it."
        color: Theme.textMuted
        font.family: Theme.fontUi
        font.pointSize: Theme.pt(11.5)
        lineHeight: Theme.lineHeightBody
        lineHeightMode: Text.ProportionalHeight
        wrapMode: Text.WordWrap
    }

    SettingRow {
        // Only where it means something: with any other mode selected this is a
        // switch that governs a subprocess nobody is running.
        visible: modeBinding.value === "dynamic" && Matugen.available
        label: "Restyle other apps"
        hint: "Off, matugen only ever answers the shell. On, it also renders the templates "
              + "in your own ~/.config/matugen/config.toml — every wallpaper change writes "
              + "those files, reloads the apps they name and runs their post-hooks. Nothing "
              + "happens until you have written some; see Services/Theming/README.md."
        binding: templatesBinding

        ConfigBinding { id: templatesBinding; path: "appearance.matugenTemplates" }

        SettingSwitch { binding: templatesBinding }
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
