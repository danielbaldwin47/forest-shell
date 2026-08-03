// System — screenshots, the recorder, the idle ladder, the lock, the night
// light's schedule, and what ends a session (#55, for #51, #52, #48, #47, #38).
//
// The fattest tab, and it is one tab on purpose: #21 fixes the config at nine
// sections and the window at ten tabs, so everything the shell *does to the
// machine* rather than draws on it lands here. The headings are what make it
// navigable — six of them, in the order a machine's day goes: what you capture,
// what happens when you stop touching it, and what ends it.
//
// Two acceptance criteria of #55 are met by *binding* rather than by anything
// this file does, which is worth saying because it looks like a gap:
//
//   - the ladder applies without a restart — Services/System/Idle.qml binds
//     `Config.values.system.idle` and each monitor's timeout derives from it,
//     so a minute written here rearms the monitor that reads it;
//   - the session menu uses the commands — Surfaces/Drawers/SessionMenu.qml
//     binds `Config.values.system.session.commands` live.
//
// Neither needs a signal, and a `keyChanged` handler here would be a second
// path to the same value.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Surfaces.Settings.Controls

TabPage {
    id: page

    title: "System"
    section: "system"
    blurb: "What the shell does to the machine rather than draws on it: captures, the idle "
           + "ladder, the lock, and the commands that end a session."

    FieldPolicy { id: fields }

    // --- screenshots ---------------------------------------------------------

    SectionHeader { text: "Screenshots" }

    SettingRow {
        label: "Directory"
        hint: "Blank means `~/Pictures/Screenshots`, worked out when a shot is taken "
              + "rather than written into this file — a literal home path here would "
              + "travel to a machine where it is wrong."
        binding: shotDirectoryBinding

        ConfigBinding { id: shotDirectoryBinding; path: "system.screenshot.directory" }

        SettingText {
            binding: shotDirectoryBinding
            placeholder: "~/Pictures/Screenshots"
            validate: text => fields.looksLikePath(text)
        }
    }

    SettingRow {
        label: "Copy to clipboard"
        hint: "As well as to disk, which is what most screenshots are for. Needs `wl-copy` "
              + "— without it the shell puts the file's *path* on the clipboard and says "
              + "so in the log rather than failing quietly."
        binding: clipboardBinding

        ConfigBinding { id: clipboardBinding; path: "system.screenshot.copyToClipboard" }

        SettingSwitch { binding: clipboardBinding }
    }

    SettingRow {
        label: "Editor"
        hint: "The optional hand-off after a shot. A tool name rather than a switch: "
              + "`satty` and `swappy` take the same `-f <file>`. Blank turns it off, which "
              + "is a different outcome from configured-and-missing and gets a different "
              + "log line."
        binding: editorBinding

        ConfigBinding { id: editorBinding; path: "system.screenshot.editor" }

        SettingText { binding: editorBinding; placeholder: "none" }
    }

    SettingRow {
        label: "Snap to windows"
        hint: "Pulls a drag's edges onto nearby window edges — the difference between a "
              + "screenshot of a window and one with four pixels of desktop down one side."
        binding: snapBinding

        ConfigBinding { id: snapBinding; path: "system.screenshot.snapToWindows" }

        SettingSwitch { binding: snapBinding }
    }

    // --- the recorder --------------------------------------------------------

    SectionHeader { text: "Screen recording" }

    SectionNote {
        note: "Naming an encoder is a preference and not a demand: one that is not "
              + "installed falls through to the other and the shell says so, because a "
              + "machine that silently cannot record is the worse answer."
    }

    SettingRow {
        label: "Directory"
        hint: "Blank means `~/Videos/Recordings`, worked out at use for the reason the "
              + "screenshot directory is."
        binding: recordDirectoryBinding

        ConfigBinding { id: recordDirectoryBinding; path: "system.recording.directory" }

        SettingText {
            binding: recordDirectoryBinding
            placeholder: "~/Videos/Recordings"
            validate: text => fields.looksLikePath(text)
        }
    }

    SettingRow {
        label: "Encoder"
        hint: "`auto` prefers the GPU one, which is the whole point: a 60fps capture that "
              + "costs a few percent of one core rather than a whole one."
        binding: engineBinding

        ConfigBinding { id: engineBinding; path: "system.recording.engine" }

        SettingChoice {
            binding: engineBinding
            // The list is the schema's; only the wording is this window's.
            options: fields.options(Config.schema.recordingEngines, {
                "auto": "Auto",
                "gpu-screen-recorder": "GPU",
                "wf-recorder": "Software"
            })
        }
    }

    SettingRow {
        label: "Framerate"
        hint: "60 rather than 30: what most screen recordings are of is a UI, and a UI at "
              + "30fps looks like the UI is stuttering rather than like the recording is."
        binding: framerateBinding

        ConfigBinding { id: framerateBinding; path: "system.recording.framerate" }

        SettingSlider { binding: framerateBinding; from: 1; to: 240 }
    }

    SettingRow {
        label: "Audio"
        hint: "`both` is the commentary case and gets two tracks on the GPU encoder, so an "
              + "editor can mute one. `wf-recorder` has a single audio switch and narrows "
              + "the middle two — with a log line rather than in silence."
        binding: audioBinding

        ConfigBinding { id: audioBinding; path: "system.recording.audio" }

        SettingChoice {
            binding: audioBinding
            options: fields.options(Config.schema.recordingAudio, {
                "none": "None", "desktop": "Desktop",
                "mic": "Microphone", "both": "Both"
            })
        }
    }

    SettingRow {
        label: "Quality"
        hint: "gpu-screen-recorder's own preset words, passed through untranslated. "
              + "`wf-recorder` has no equivalent and ignores this."
        enabled: engineBinding.value !== "wf-recorder"
        binding: qualityBinding

        ConfigBinding { id: qualityBinding; path: "system.recording.quality" }

        SettingChoice {
            binding: qualityBinding
            options: fields.options(Config.schema.recordingQualities, {
                "medium": "Medium", "high": "High",
                "very_high": "Very high", "ultra": "Ultra"
            })
        }
    }

    SettingRow {
        label: "Container"
        hint: "Also the file extension. mp4 for anything that has to be uploaded, mkv for "
              + "a long capture that might be interrupted."
        binding: containerBinding

        ConfigBinding { id: containerBinding; path: "system.recording.container" }

        SettingChoice {
            binding: containerBinding
            // No labels: `mp4` and `mkv` are what the files are called.
            options: fields.options(Config.schema.recordingContainers, {})
        }
    }

    // --- the idle ladder -----------------------------------------------------

    SectionHeader { text: "Idle" }

    SectionNote {
        note: "Four stages, each with its own switch and its own pair of minutes. **0 is "
              + "off on that power source** — which is how mains suspend is off while "
              + "battery suspend is on, without a second toggle to keep in agreement with "
              + "the first. Inhibitors are respected on every rung and are not a setting: "
              + "a switch for that would be a switch that makes a film stop halfway. "
              + "Changes apply without restarting the shell."
    }

    IdleStage {
        stage: "dim"
        title: "Dim the screen"
        hint: "Down to the level below, restored on the first activity."

        SettingRow {
            label: "Dim level"
            hint: "Percent of the backlight, not a fraction of the current brightness."
            binding: dimLevelBinding

            ConfigBinding { id: dimLevelBinding; path: "system.idle.dim.level" }

            SettingSlider { binding: dimLevelBinding; from: 1; to: 100 }
        }
    }

    IdleStage {
        stage: "lock"
        title: "Lock"
        hint: "The shell's own lock surface, reached in-process rather than by running "
              + "anything."
    }

    IdleStage {
        id: dpmsStage

        stage: "dpms"
        title: "Turn the screen off"
        hint: "Blanks the outputs. What blanks them differs by compositor, so it is a "
              + "command."

        SettingRow {
            label: "When locked"
            hint: "Seconds, not minutes: while locked the screen shows a clock nobody is "
                  + "reading, so this stage and only this stage tightens. A number under a "
                  + "minute written as a fraction of one is a number nobody can check."
            enabled: dpmsStage.on
            binding: lockedSecondsBinding

            ConfigBinding { id: lockedSecondsBinding; path: "system.idle.dpms.lockedSeconds" }

            SettingSlider { binding: lockedSecondsBinding; from: 5; to: 600 }
        }

        SettingRow {
            label: "Off command"
            hint: "Blanking either command turns the stage into a logged refusal rather "
                  + "than a silent no-op."
            enabled: dpmsStage.on
            binding: dpmsOffBinding

            ConfigBinding { id: dpmsOffBinding; path: "system.idle.dpms.offCommand" }

            SettingText { binding: dpmsOffBinding; placeholder: "hyprctl dispatch dpms off" }
        }

        SettingRow {
            label: "On command"
            enabled: dpmsStage.on
            binding: dpmsOnBinding

            ConfigBinding { id: dpmsOnBinding; path: "system.idle.dpms.onCommand" }

            SettingText { binding: dpmsOnBinding; placeholder: "hyprctl dispatch dpms on" }
        }
    }

    IdleStage {
        stage: "suspend"
        title: "Suspend"
        hint: "Runs the session's own suspend command below — the menu's Suspend and the "
              + "ladder's last rung are the same act, so there is one key for it. Off on "
              + "mains by default: a plugged-in machine that suspends itself is one that "
              + "drops your ssh sessions while you read."
    }

    // --- the lock ------------------------------------------------------------

    SectionHeader { text: "Lock screen" }

    SectionNote {
        note: "There is no retry limit, no lockout duration and no failed-attempt count "
              + "here: faillock owns all three through PAM, and the shell keeps no counts "
              + "of its own."
    }

    SettingRow {
        label: "Notification count"
        hint: "The number waiting, never the contents. Off is for a machine that locks in "
              + "front of other people."
        binding: notificationCountBinding

        ConfigBinding { id: notificationCountBinding; path: "system.lock.notificationCount" }

        SettingSwitch { binding: notificationCountBinding }
    }

    SettingRow {
        label: "PAM stack"
        hint: "The system stack, so the lock inherits faillock and whatever else the "
              + "distro already trusts — the shell writes nothing to /etc. `login` is an "
              + "Arch and Debian assumption rather than a law, which is the only reason "
              + "this is a setting."
        binding: pamBinding

        ConfigBinding { id: pamBinding; path: "system.lock.pamConfig" }

        SettingText { binding: pamBinding; placeholder: "login" }
    }

    SettingRow {
        label: "Fingerprint"
        hint: "Latent: this permits it, fprintd decides. Off means do not even probe."
        binding: fingerprintBinding

        ConfigBinding { id: fingerprintBinding; path: "system.lock.fingerprint" }

        SettingSwitch { binding: fingerprintBinding }
    }

    SettingRow {
        label: "Fingerprint PAM stack"
        enabled: fingerprintBinding.value === true
        binding: fingerprintPamBinding

        ConfigBinding { id: fingerprintPamBinding; path: "system.lock.fingerprintPamConfig" }

        SettingText { binding: fingerprintPamBinding; placeholder: "fprintd" }
    }

    // --- the night light's schedule ------------------------------------------

    SectionHeader { text: "Night light schedule" }

    SectionNote {
        note: "*When* the screen warms. How warm, and what applies it, are on the Weather "
              + "& Time tab with the location that will drive sunset."
    }

    SettingRow {
        label: "On a schedule"
        binding: scheduleBinding

        ConfigBinding { id: scheduleBinding; path: "system.nightLight.enabled" }

        SettingSwitch { binding: scheduleBinding }
    }

    Repeater {
        model: [
            { key: "from", label: "From", placeholder: "20:00" },
            { key: "to", label: "To", placeholder: "07:00" }
        ]

        SettingRow {
            id: scheduleRow

            required property var modelData

            label: scheduleRow.modelData.label
            hint: "24-hour, `HH:MM`."
            enabled: scheduleBinding.value === true
            binding: timeBinding

            ConfigBinding {
                id: timeBinding
                path: "system.nightLight." + scheduleRow.modelData.key
            }

            SettingText {
                binding: timeBinding
                placeholder: scheduleRow.modelData.placeholder
                validate: text => fields.isClockTime(text)
            }
        }
    }

    SettingRow {
        label: "Scheduled temperature"
        hint: "The warmth the schedule applies. Separate from the tile's on the Weather & "
              + "Time tab: a manual press and a sunset are two acts, and a machine may "
              + "want a gentler evening than a deliberate one."
        enabled: scheduleBinding.value === true
        binding: scheduleTemperatureBinding

        ConfigBinding { id: scheduleTemperatureBinding; path: "system.nightLight.temperature" }

        SettingSlider { binding: scheduleTemperatureBinding; from: 1000; to: 6500 }
    }

    // --- the session ---------------------------------------------------------

    SectionHeader { text: "Session commands" }

    SectionNote {
        note: "What ends a session differs by init system and by machine, so these are "
              + "commands and not switches. A key blanked here means *not on this "
              + "machine*: the row stays on the session menu and refuses with a line "
              + "naming the key, which beats a button that quietly is not there. Lock is "
              + "deliberately not among them — it is a surface this shell owns and is "
              + "reached in-process."
    }

    Repeater {
        model: page.sessionCommands

        SettingRow {
            id: commandRow

            required property var modelData

            label: commandRow.modelData.label
            hint: commandRow.modelData.hint ?? ""
            binding: commandBinding

            ConfigBinding {
                id: commandBinding
                path: "system.session.commands." + commandRow.modelData.key
            }

            SettingText {
                binding: commandBinding
                placeholder: commandRow.modelData.placeholder
            }
        }
    }

    // --- the session's four --------------------------------------------------
    //
    // The labels and the order Surfaces/Drawers/SessionPolicy.qml draws the menu
    // in, minus the lock it deliberately does not run a command for.

    readonly property var sessionCommands: [
        { key: "logout", label: "Log out", placeholder: "hyprctl dispatch exit" },
        { key: "suspend", label: "Suspend", placeholder: "systemctl suspend",
          hint: "Also what the idle ladder's last rung runs." },
        { key: "reboot", label: "Restart", placeholder: "systemctl reboot" },
        { key: "shutdown", label: "Shut down", placeholder: "systemctl poweroff" }
    ]
}
