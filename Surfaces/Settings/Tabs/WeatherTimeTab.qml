// Weather & Time — where the weather card is about, and how warm the screen
// goes at night (#55, for #50, #44).
//
// ## The clock row that is not here
//
// This tab is where a clock-format control belongs and there is deliberately no
// key behind one yet. The format is derived from the locale today
// (Core/ClockFormat.qml), the bar and the lock screen still hold two copies of
// that rule, and collapsing them is #93's — a key invented here would be a key
// #93 has to migrate away from. So the section states the rule, shows what this
// machine currently resolves to, and says where the switch is going. A tab that
// silently omitted the row would leave a user hunting for a setting nobody has
// written yet.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Surfaces.Settings.Controls

TabPage {
    id: page

    title: "Weather & Time"
    section: "weatherTime"
    blurb: "The weather card's location and units, the clock's format, and the night "
           + "light's warmth — the settings about where and when this machine is."

    FieldPolicy { id: fields }

    SectionHeader { text: "Weather" }

    SectionNote {
        note: "Open-Meteo, which needs no account and no key. Nothing is requested at all "
              + "until a place is named below."
    }

    SettingRow {
        label: "Where"
        hint: "Blank is *neither*: the card says it has not been told where it is and no "
              + "request is made. **This IP address** is the opt-in that asks a "
              + "geolocation service what this address looks like — the one request this "
              + "shell makes that tells a third party something rather than only asking "
              + "it something, which is why it is a choice and not a fallback."
        binding: placeBinding

        ConfigBinding { id: placeBinding; path: "weatherTime.weather.place" }

        SettingChoice {
            binding: placeBinding
            // One key, three states, and only two of them are words: these
            // chips write those two and the field below writes the third. With
            // a place name in the key neither chip is current, which is the
            // honest reading — the answer is in the box under them.
            //
            // `auto` was reachable before this by typing it into the field and
            // no other way, which is a mode nothing on the page mentioned. The
            // ticket names it as a thing of its own, and a mode you have to
            // know the magic word for is not one the GUI offers.
            options: [
                { value: "", label: "Not set" },
                { value: "auto", label: "This IP address" }
            ]
        }
    }

    SettingRow {
        label: "Place"
        hint: "A place name, geocoded once and then cached with the reading. Typing one "
              + "replaces whichever of the two above is set."
        binding: placeBinding

        SettingText { binding: placeBinding; placeholder: "Lisbon" }
    }

    SettingRow {
        label: "Units"
        hint: "One word for both: nobody wants their temperature in Celsius and their "
              + "wind in miles per hour."
        binding: unitsBinding

        ConfigBinding { id: unitsBinding; path: "weatherTime.weather.units" }

        SettingChoice {
            binding: unitsBinding
            options: fields.options(Config.schema.weatherUnits,
                                    { "metric": "Metric", "imperial": "Imperial" })
        }
    }

    SettingRow {
        label: "Refresh"
        hint: "Minutes between re-fetches of an *open* dashboard — nothing polls behind a "
              + "closed drawer. Thirty is roughly how often the upstream model updates; "
              + "below five a card refreshes faster than the forecast changes."
        binding: refreshBinding

        ConfigBinding { id: refreshBinding; path: "weatherTime.weather.refreshMinutes" }

        SettingSlider { binding: refreshBinding; from: 5; to: 720 }
    }

    SettingRow {
        label: "Forecast days"
        hint: "Rows in the strip, today included. Seven is the API's free ceiling; past "
              + "four the rows stop fitting the 380px panel as rows."
        binding: daysBinding

        ConfigBinding { id: daysBinding; path: "weatherTime.weather.days" }

        SettingSlider { binding: daysBinding; from: 1; to: 7 }
    }

    SectionHeader { text: "Clock" }

    SectionNote {
        note: "There is no 12/24-hour switch yet, and this is where it will be. The format "
              + "follows this machine's locale today, and the bar and the lock screen each "
              + "hold their own copy of that rule — collapsing the two and giving the "
              + "format a key is #93."
    }

    SettingRow {
        label: "Current format"
        hint: "Derived from the locale, not stored. The date reads " + page.clock.dateFormat
              + " on the dashboard header."
        enabled: false

        Text {
            text: page.timeFormat
            color: Theme.textSecondary
            font.family: Theme.fontMono
            font.pointSize: Theme.pt(11.5)
        }
    }

    SectionHeader { text: "Night light" }

    SectionNote {
        note: "Warmth and the commands that apply it. *When* it runs is on the System tab, "
              + "with the rest of the machine's schedule; the warmth is here because this "
              + "section is the one that owns sunset."
    }

    SettingRow {
        label: "Temperature"
        hint: "Kelvin. 4000 is a warm evening that is still legible for text; the range is "
              + "what the tools themselves accept."
        binding: temperatureBinding

        ConfigBinding { id: temperatureBinding; path: "weatherTime.nightLight.temperature" }

        SettingSlider { binding: temperatureBinding; from: 1000; to: 6500 }
    }

    SettingRow {
        label: "Warm command"
        hint: "What warms the screen. `{temp}` is substituted with the temperature above. "
              + "A command rather than a toggle because what does this differs by "
              + "compositor — hyprsunset here, wlsunset or gammastep elsewhere. Blanking "
              + "it removes the control centre's tile rather than leaving one that fails "
              + "on every press."
        binding: commandBinding

        ConfigBinding { id: commandBinding; path: "weatherTime.nightLight.command" }

        SettingText {
            binding: commandBinding
            placeholder: "hyprctl hyprsunset temperature {temp}"
        }
    }

    SettingRow {
        label: "Restore command"
        hint: "What puts it back."
        binding: offCommandBinding

        ConfigBinding { id: offCommandBinding; path: "weatherTime.nightLight.offCommand" }

        SettingText {
            binding: offCommandBinding
            placeholder: "hyprctl hyprsunset identity"
        }
    }

    // --- the interim clock rule (#93) ----------------------------------------

    readonly property ClockFormat clock: ClockFormat {}

    /// What the bar is actually drawing, worked out the same way it works it
    /// out. Read-only and shown rather than described: "follows the locale" is
    /// not an answer to "why is my clock in 12-hour", and the format string is.
    readonly property string timeFormat:
        page.clock.timeFormatFor(Qt.locale().timeFormat(Locale.ShortFormat))
}
