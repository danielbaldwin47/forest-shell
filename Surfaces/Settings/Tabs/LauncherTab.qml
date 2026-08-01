// Launcher — providers, and the Ask Claude surface (#54, for #39–#41).
//
// The launcher is a prefix dispatcher: each provider owns a character, and
// turning one off is a decision about a feature rather than about ordering,
// which is why this is six switches and not a reorderable registry like the
// bar's.
//
// Ask Claude is the one provider with settings of its own. It runs the Claude
// Code CLI in headless print mode on *subscription* auth, so there is no API key
// and no endpoint here — what this tab configures is what the run is allowed to
// be: which model answers, how hard it thinks, which tools it may load, and
// whether it may act without asking.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Surfaces.Settings.Controls

TabPage {
    id: page

    title: "Launcher"
    section: "launcher"
    blurb: "Super+Space, then a prefix. Providers are dispatched on the first character "
           + "typed; with none of them, the field searches applications."

    SectionHeader { text: "Providers" }

    Repeater {
        model: page.providers

        SettingRow {
            id: providerRow

            required property var modelData

            label: providerRow.modelData.title
            hint: providerRow.modelData.hint
            binding: providerBinding

            ConfigBinding {
                id: providerBinding
                path: "launcher.providers." + providerRow.modelData.id
            }

            SettingSwitch { binding: providerBinding }
        }
    }

    SectionHeader { text: "Ask Claude" }

    SettingRow {
        label: "Model"
        hint: "The default for a bare `?`. `?haiku`, `?sonnet` and `?opus` override it for "
              + "one question. Haiku is the default because Opus showed no latency or "
              + "quality advantage at launcher prompt sizes."
        binding: modelBinding

        ConfigBinding { id: modelBinding; path: "launcher.claude.model" }

        SettingChoice {
            binding: modelBinding
            options: Config.schema.claudeModels.map(value => ({ value: value }))
        }
    }

    SettingRow {
        label: "Effort"
        hint: "There is no \"off\": a value the CLI does not recognise silently falls back "
              + "to its default, which is why this is a closed list."
        binding: effortBinding

        ConfigBinding { id: effortBinding; path: "launcher.claude.effort" }

        SettingChoice {
            binding: effortBinding
            options: Config.schema.claudeEfforts.map(value => ({ value: value }))
        }
    }

    SettingRow {
        label: "Tools"
        hint: "Read-only plus web by default. These both restrict what is loaded and grant "
              + "permission to use it — either one alone is not a restriction."
        binding: toolsBinding

        ConfigBinding { id: toolsBinding; path: "launcher.claude.tools" }

        SettingChips {
            binding: toolsBinding
            choices: Config.schema.claudeTools
        }
    }

    SettingRow {
        label: "Permission mode"
        hint: "`default` asks for nothing beyond the tools above. The wider two let a "
              + "launcher answer edit files and run commands without a prompt — there is "
              + "no dialog to approve them with until that lands post-v1."
        binding: permissionBinding

        ConfigBinding { id: permissionBinding; path: "launcher.claude.permissionMode" }

        SettingChoice {
            binding: permissionBinding
            options: [
                { value: "default", label: "Ask nothing extra" },
                { value: "acceptEdits", label: "Accept edits" },
                { value: "bypassPermissions", label: "Bypass all" }
            ]
        }
    }

    Text {
        Layout.fillWidth: true
        visible: permissionBinding.value === "bypassPermissions"
        text: "Bypass all: anything Ask Claude decides to do, it does. With the read-only "
              + "toolset above that is a narrow blast radius; widen the tools too and it "
              + "is not."
        color: Theme.accentWarm
        font.family: Theme.fontUi
        font.pointSize: Theme.pt(11.5)
        lineHeight: Theme.lineHeightBody
        lineHeightMode: Text.ProportionalHeight
        wrapMode: Text.WordWrap
    }

    // The six providers and the character each answers to (#9). Held here and
    // not in the schema: the prefix is the launcher's, and the config only says
    // whether the provider is on.
    readonly property var providers: [
        { id: "apps", title: "Applications", hint: "No prefix — fuzzy search over desktop entries." },
        { id: "calculator", title: "Calculator", hint: "`=`, or a leading digit." },
        { id: "clipboard", title: "Clipboard history", hint: "`;` — the cliphist store, images included." },
        { id: "emoji", title: "Emoji", hint: "`:`" },
        { id: "actions", title: "Shell actions", hint: "`/` — dark mode, wallpaper, session, settings pages." },
        { id: "claude", title: "Ask Claude", hint: "`?` — turns the panel into a chat." }
    ]
}
