// Control Center — the toggle grid, the sliders above it, and the OSD (#55, for
// #44, #45, #46).
//
// The grid is an ordered list of tile names and not ten switches, for the same
// reason the bar's modules are three lists: membership *is* the enable flag, so
// a tile that is off is a tile that is not in the list and there is no second
// flag to disagree with it. Removing one parks it in the pool underneath.
//
// What this tab cannot promise is that every tile in the list appears: absent
// hardware has no tile whatever the file says (Surfaces/Drawers/
// ControlCenterPolicy.qml states that rule), so a tower still shows no
// bluetooth. The list is a preference about order and membership, not a claim
// about what this machine has — and the note under the grid says so, because a
// user who adds `bluetooth` on a desktop and sees nothing appear deserves the
// reason rather than a bug report.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Surfaces.Settings.Controls

TabPage {
    id: page

    title: "Control Center"
    section: "controlCenter"
    blurb: "The panel behind the bar's chevron: a row of sliders, a grid of toggles, and "
           + "the pill that pops up when a volume or brightness key is pressed."

    SectionHeader { text: "Toggle grid" }

    SectionNote {
        note: "In the order they are drawn. A tile that is in no list is off, so removing "
              + "one parks it in the pool below rather than losing it. Hardware this "
              + "machine does not have shows no tile whatever this list says — a bluetooth "
              + "entry on a tower is inert rather than broken."
    }

    OrderedList {
        path: "controlCenter.tiles"
        pool: page.tilePool
        mono: false
        labelFor: id => page.tileTitles[id] ?? id
        emptyNote: "no tiles — the panel is sliders and the bottom strip"
    }

    SettingRow {
        label: "Tiles per row"
        hint: "Three is what the 380px panel fits with a readable label under each glyph. "
              + "Wider rows make smaller tiles, not a wider panel."
        binding: columnsBinding

        ConfigBinding { id: columnsBinding; path: "controlCenter.columns" }

        SettingSlider { binding: columnsBinding; from: 2; to: 5 }
    }

    SectionHeader { text: "Sliders" }

    SectionNote {
        note: "Above the grid, in this order. The same rule applies: a machine with no "
              + "backlight has no brightness slider however this reads."
    }

    OrderedList {
        path: "controlCenter.sliders"
        pool: page.sliderPool
        mono: false
        labelFor: id => page.sliderTitles[id] ?? id
        emptyNote: "no sliders — the panel opens on the grid"
    }

    SettingRow {
        label: "Scroll step"
        hint: "Percent per wheel notch or arrow press. One key and not one per channel: a "
              + "notch should mean one thing in the shell. The bar's scroll uses it too."
        binding: stepBinding

        ConfigBinding { id: stepBinding; path: "controlCenter.step" }

        SettingSlider { binding: stepBinding; from: 1; to: 25 }
    }

    SectionHeader { text: "On-screen display" }

    SectionNote {
        note: "The pill that reports a volume, mic or brightness change — the three "
              + "channels the sliders above own, which is why it is configured here and "
              + "not in a section of its own."
    }

    SettingRow {
        label: "Time on screen"
        hint: "Milliseconds. Bounded either side rather than at zero: a 0 here would be a "
              + "surface that maps and unmaps in one frame."
        binding: timeoutBinding

        ConfigBinding { id: timeoutBinding; path: "controlCenter.osd.timeout" }

        SettingSlider { binding: timeoutBinding; from: 300; to: 10000 }
    }

    SettingRow {
        label: "Position"
        hint: "An edge with the pill centred against it, or the middle of the screen. "
              + "Bottom by default: the bar owns the top and the notification stack owns "
              + "the top-right corner."
        binding: positionBinding

        ConfigBinding { id: positionBinding; path: "controlCenter.osd.position" }

        SettingChoice {
            binding: positionBinding
            options: Config.schema.osdPositions.map(value => ({ value: value }))
        }
    }

    SettingRow {
        label: "Margin"
        hint: "Its gap from that edge, in px. Applied to the anchored edge only, and "
              + "ignored when the pill is centred."
        enabled: positionBinding.value !== "center"
        binding: marginBinding

        ConfigBinding { id: marginBinding; path: "controlCenter.osd.margin" }

        SettingSlider { binding: marginBinding; from: 0; to: 400 }
    }

    // --- what the vocabulary is called ---------------------------------------
    //
    // The ids are the file's; these are what the GUI calls them. Held here and
    // not in the schema for the reason the launcher's prefixes are held in its
    // tab: a display name is the settings window's business, and the policy
    // next door already carries its own copy for the tile face — which says
    // "Wi-Fi" under a glyph and cannot also be a settings-row label.

    readonly property var tileTitles: ({
        wifi: "Wi-Fi",
        bluetooth: "Bluetooth",
        dnd: "Do Not Disturb",
        nightlight: "Night Light",
        keepawake: "Keep Awake",
        mode: "Theme",
        powerprofile: "Power Profile",
        vpn: "VPN",
        wallpaper: "Wallpaper picker",
        recording: "Screen recording"
    })

    readonly property var sliderTitles: ({
        volume: "Volume",
        mic: "Microphone",
        brightness: "Brightness"
    })

    /// Every tile the shell can draw that is not currently in the grid.
    readonly property var tilePool: {
        const placed = Config.values.controlCenter.tiles;
        return Config.schema.controlCenterTiles.filter(id => placed.indexOf(id) < 0);
    }

    readonly property var sliderPool: {
        const placed = Config.values.controlCenter.sliders;
        return Config.schema.controlCenterSliders.filter(id => placed.indexOf(id) < 0);
    }
}
