// What the control centre decides (#44): which tiles the grid has, what each
// one says, which sliders exist on this machine, and the two lines in the
// bottom strip.
//
// The picture is Surfaces/Drawers/ControlCenter.qml and is seam 3's problem.
// Everything here is a decision, and the interesting ones are all about
// *absence*: a tower has no battery, a desktop may have no bluetooth radio and
// no backlight, and a machine with no VPN configured must not show a tile that
// does nothing when pressed.
import QtQuick
import QtTest
import "../Surfaces/Drawers"

TestCase {
    name: "ControlCenterPolicy"

    ControlCenterPolicy { id: policy }

    // A machine with everything: the baseline every test below subtracts from.
    function fullFacts() {
        return {
            wifi: { available: true, on: true, label: "PUMPKINCURRY" },
            bluetooth: { present: true, on: true, label: "1 device" },
            dnd: { on: false },
            nightlight: { available: true, on: false, temperature: 4000 },
            keepawake: { on: false },
            dark: true,
            powerprofile: { available: true, profile: "balanced" },
            vpn: { available: true, on: false, name: "" },
            volume: { available: true, percent: 45, muted: false },
            mic: { available: true, percent: 80, muted: false },
            brightness: { available: true, percent: 60 }
        };
    }

    function ids(list) {
        return list.map(item => item.id);
    }

    function byId(list, id) {
        return list.filter(item => item.id === id)[0] ?? null;
    }

    // --- the grid ------------------------------------------------------------

    function test_the_grid_is_nine_tiles_in_a_fixed_order() {
        // Fixed, because grid position is muscle memory: the tile you reach for
        // without looking must not move because a radio came up.
        compare(policy.columns, 3);
        compare(ids(policy.tiles(fullFacts())),
                ["wifi", "bluetooth", "dnd", "nightlight", "keepawake",
                 "mode", "powerprofile", "vpn", "wallpaper"]);
    }

    function test_hardware_that_is_not_there_has_no_tile() {
        // The same rule Services/Networking/BluetoothPolicy.qml states for the
        // bar: a control nobody can act on is furniture. A radio that is *off*
        // is a different thing entirely and keeps its tile — that is the tile
        // you press to turn it on.
        const facts = fullFacts();
        facts.bluetooth.present = false;
        facts.vpn.available = false;
        facts.nightlight.available = false;
        facts.powerprofile.available = false;

        compare(ids(policy.tiles(facts)),
                ["wifi", "dnd", "keepawake", "mode", "wallpaper"]);
    }

    function test_a_radio_that_is_off_still_has_its_tile() {
        const facts = fullFacts();
        facts.wifi.on = false;
        facts.bluetooth.on = false;

        verify(byId(policy.tiles(facts), "wifi") !== null);
        verify(byId(policy.tiles(facts), "bluetooth") !== null);
    }

    function test_the_grid_reflows_rather_than_leaving_a_hole() {
        // Nine tiles is three rows; eight is 3-3-2 and not 3-3-1-with-a-gap.
        const rows = policy.rows(policy.tiles(fullFacts()));
        compare(rows.length, 3);
        compare(rows[0].length, 3);
        compare(rows[2].length, 3);

        const facts = fullFacts();
        facts.bluetooth.present = false;
        const short = policy.rows(policy.tiles(facts));
        compare(short.length, 3);
        compare(short[2].length, 2);
    }

    function test_an_empty_grid_is_no_rows_rather_than_one_empty_row() {
        compare(policy.rows([]).length, 0);
        compare(policy.rows(null).length, 0);
    }

    // --- what a tile says ----------------------------------------------------

    function test_wifi_reads_its_network_when_it_is_on_one() {
        const facts = fullFacts();
        const on = byId(policy.tiles(facts), "wifi");
        compare(on.on, true);
        compare(on.label, "Wi-Fi");
        compare(on.detail, "PUMPKINCURRY");
        compare(on.icon, "wifi");

        facts.wifi.on = false;
        const off = byId(policy.tiles(facts), "wifi");
        compare(off.on, false);
        compare(off.detail, "Off");
        compare(off.icon, "wifi-off");
    }

    function test_bluetooth_reads_what_is_on_the_other_end_of_it() {
        const facts = fullFacts();
        compare(byId(policy.tiles(facts), "bluetooth").detail, "1 device");
        compare(byId(policy.tiles(facts), "bluetooth").icon, "bluetooth");

        facts.bluetooth.on = false;
        compare(byId(policy.tiles(facts), "bluetooth").on, false);
        compare(byId(policy.tiles(facts), "bluetooth").icon, "bluetooth-off");
    }

    function test_do_not_disturb_is_a_plain_on_off() {
        const facts = fullFacts();
        compare(byId(policy.tiles(facts), "dnd").detail, "Off");
        facts.dnd.on = true;
        compare(byId(policy.tiles(facts), "dnd").on, true);
        compare(byId(policy.tiles(facts), "dnd").detail, "On");
        compare(byId(policy.tiles(facts), "dnd").icon, "bell-off");
    }

    function test_night_light_shows_the_temperature_it_is_holding() {
        // The number is the whole reason the tile is not just a lamp: "on" says
        // nothing about how warm, and the warmth is what the user tuned.
        const facts = fullFacts();
        compare(byId(policy.tiles(facts), "nightlight").detail, "Off");

        facts.nightlight.on = true;
        const on = byId(policy.tiles(facts), "nightlight");
        compare(on.detail, "4000K");
        compare(on.icon, "moon-star");
    }

    function test_the_mode_tile_is_lit_for_the_mode_that_is_not_the_default() {
        // Dark is what the shell ships (#8), so a dark shell shows an unlit
        // tile — a grid where something is always filled teaches nobody
        // anything. Light is the deviation, and deviations are what a filled
        // tile means.
        const facts = fullFacts();
        const dark = byId(policy.tiles(facts), "mode");
        compare(dark.on, false);
        compare(dark.detail, "Dark");
        compare(dark.icon, "moon");

        facts.dark = false;
        const light = byId(policy.tiles(facts), "mode");
        compare(light.on, true);
        compare(light.detail, "Light");
        compare(light.icon, "sun");
    }

    function test_the_power_profile_tile_names_the_profile() {
        const facts = fullFacts();
        const balanced = byId(policy.tiles(facts), "powerprofile");
        compare(balanced.detail, "Balanced");
        compare(balanced.on, false);       // balanced is the machine's default
        compare(balanced.icon, "gauge");

        facts.powerprofile.profile = "performance";
        compare(byId(policy.tiles(facts), "powerprofile").detail, "Performance");
        compare(byId(policy.tiles(facts), "powerprofile").on, true);
        compare(byId(policy.tiles(facts), "powerprofile").icon, "zap");

        facts.powerprofile.profile = "power-saver";
        compare(byId(policy.tiles(facts), "powerprofile").detail, "Power Saver");
        compare(byId(policy.tiles(facts), "powerprofile").on, true);
        compare(byId(policy.tiles(facts), "powerprofile").icon, "leaf");
    }

    function test_an_unknown_power_profile_is_shown_rather_than_hidden() {
        // powerprofilesctl lists whatever the daemon offers, and a machine may
        // carry a vendor profile this shell has never heard of. Showing its raw
        // name is honest; dropping the tile would hide a profile the user is
        // actually running.
        const facts = fullFacts();
        facts.powerprofile.profile = "vendor-turbo";
        compare(byId(policy.tiles(facts), "powerprofile").detail, "vendor-turbo");
        compare(byId(policy.tiles(facts), "powerprofile").icon, "gauge");
    }

    function test_vpn_names_the_tunnel_it_is_up_on() {
        const facts = fullFacts();
        compare(byId(policy.tiles(facts), "vpn").detail, "Off");
        compare(byId(policy.tiles(facts), "vpn").icon, "shield-off");

        facts.vpn.on = true;
        facts.vpn.name = "work";
        compare(byId(policy.tiles(facts), "vpn").on, true);
        compare(byId(policy.tiles(facts), "vpn").detail, "work");
        compare(byId(policy.tiles(facts), "vpn").icon, "shield");
    }

    function test_keep_awake_says_what_it_is_doing() {
        const facts = fullFacts();
        compare(byId(policy.tiles(facts), "keepawake").detail, "Off");
        compare(byId(policy.tiles(facts), "keepawake").icon, "coffee");

        facts.keepawake.on = true;
        compare(byId(policy.tiles(facts), "keepawake").on, true);
        compare(byId(policy.tiles(facts), "keepawake").detail, "On");
    }

    function test_the_wallpaper_tile_is_a_door_and_never_lit() {
        // It opens a drill-in rather than switching something on, so it has no
        // on-state to show. Stub until the wallpaper ticket.
        const tile = byId(policy.tiles(fullFacts()), "wallpaper");
        compare(tile.on, false);
        compare(tile.detail, "");
        compare(tile.icon, "wallpaper");
        compare(tile.drillIn, true);
    }

    function test_only_the_wallpaper_tile_is_a_drill_in() {
        for (const tile of policy.tiles(fullFacts()))
            compare(tile.drillIn, tile.id === "wallpaper");
    }

    // --- the sliders ---------------------------------------------------------

    function test_all_three_sliders_are_there_on_a_laptop() {
        compare(ids(policy.sliders(fullFacts())), ["volume", "mic", "brightness"]);
    }

    function test_a_machine_without_a_backlight_has_no_brightness_slider() {
        // A tower on a DisplayPort monitor has no `/sys/class/backlight`, and a
        // slider that moves nothing is worse than an absent one.
        const facts = fullFacts();
        facts.brightness.available = false;
        compare(ids(policy.sliders(facts)), ["volume", "mic"]);
    }

    function test_a_machine_with_no_microphone_has_no_mic_slider() {
        const facts = fullFacts();
        facts.mic.available = false;
        compare(ids(policy.sliders(facts)), ["volume", "brightness"]);
    }

    function test_a_slider_carries_its_glyph_and_its_reading() {
        const facts = fullFacts();
        const volume = policy.sliders(facts)[0];
        compare(volume.percent, 45);
        compare(volume.label, "Volume");
        compare(volume.icon, "volume-2");
        compare(volume.mutable, true);

        facts.volume.muted = true;
        compare(policy.sliders(facts)[0].icon, "volume-x");
        compare(policy.sliders(facts)[0].muted, true);
    }

    function test_the_mic_slider_mutes_and_the_brightness_slider_does_not() {
        const sliders = policy.sliders(fullFacts());
        compare(sliders[1].icon, "mic");
        compare(sliders[1].mutable, true);
        compare(sliders[2].icon, "sun");
        compare(sliders[2].mutable, false);
    }

    function test_a_muted_mic_says_so_on_its_glyph() {
        const facts = fullFacts();
        facts.mic.muted = true;
        compare(policy.sliders(facts)[1].icon, "mic-off");
    }

    // --- moving a slider -----------------------------------------------------

    function test_a_slider_position_is_a_whole_percent_within_range() {
        compare(policy.percent(0.455), 46);
        compare(policy.percent(0), 0);
        compare(policy.percent(1), 100);
        // PipeWire allows over-unity volume; the track does not.
        compare(policy.percent(1.4), 100);
        compare(policy.percent(-0.2), 0);
        compare(policy.percent(NaN), 0);
    }

    function test_a_percent_comes_back_as_the_fraction_the_service_wants() {
        compare(policy.fraction(46), 0.46);
        compare(policy.fraction(0), 0);
        compare(policy.fraction(100), 1);
        compare(policy.fraction(140), 1);
        compare(policy.fraction(-5), 0);
    }

    function test_the_keyboard_and_the_wheel_move_a_slider_by_five() {
        // The same step the bar's scroll uses, so the two agree about what one
        // notch means.
        compare(policy.step, 5);
        compare(policy.nudge(45, 1), 50);
        compare(policy.nudge(45, -1), 40);
        compare(policy.nudge(98, 1), 100);
        compare(policy.nudge(2, -1), 0);
        // Off the grid, a nudge lands on it rather than staying off it.
        compare(policy.nudge(43, 1), 45);
        compare(policy.nudge(43, -1), 40);
    }

    // --- the bottom strip ----------------------------------------------------

    function test_a_tower_has_no_battery_line() {
        compare(policy.batteryLine({ hasBattery: false, label: "0%",
                                     state: "unknown", timeRemaining: "" }), "");
    }

    function test_a_draining_battery_reads_level_then_time() {
        compare(policy.batteryLine({ hasBattery: true, label: "84%",
                                     state: "discharging",
                                     timeRemaining: "3h 20m" }),
                "84% · 3h 20m left");
    }

    function test_a_battery_with_no_estimate_yet_reads_the_level_alone() {
        // UPower reports nothing until the rate settles, and "0m left" would be
        // a lie for the first minute after every boot.
        compare(policy.batteryLine({ hasBattery: true, label: "84%",
                                     state: "discharging", timeRemaining: "" }),
                "84%");
    }

    function test_a_charging_battery_says_so_and_counts_up() {
        compare(policy.batteryLine({ hasBattery: true, label: "62%",
                                     state: "charging", timeRemaining: "40m" }),
                "Charging · 62% · 40m to full");
        compare(policy.batteryLine({ hasBattery: true, label: "62%",
                                     state: "charging", timeRemaining: "" }),
                "Charging · 62%");
    }

    function test_a_full_battery_on_the_cable_stops_counting() {
        // Nothing is going to happen to it, and "0m to full" on a machine that
        // has been plugged in overnight is the readout looking broken.
        compare(policy.batteryLine({ hasBattery: true, label: "100%",
                                     state: "full", timeRemaining: "2h" }),
                "Fully charged");
    }

    // --- what the log says ---------------------------------------------------
    //
    // One line per toggle, which is what makes the grid drivable from
    // tools/drawer-harness.sh. #81 was a lifecycle with no log line and
    // one bug then had two candidate causes for a week.

    function test_a_toggle_logs_what_it_did() {
        compare(policy.toggled("wifi", true), "wifi on");
        compare(policy.toggled("wifi", false), "wifi off");
        compare(policy.toggled("keepawake", true), "keepawake on");
    }

    function test_a_control_with_no_on_state_still_logs_the_press() {
        // The power profile cycles and the wallpaper tile opens a door; neither
        // has an on/off to name, and a press nothing logged is #81.
        compare(policy.pressed("powerprofile"), "powerprofile pressed");
        compare(policy.pressed("wallpaper"), "wallpaper pressed");
    }

    function test_a_toggle_that_could_not_run_logs_why() {
        compare(policy.refused("vpn", "no connection configured"),
                "vpn unchanged — no connection configured");
    }

    function test_a_slider_logs_where_it_landed() {
        compare(policy.moved("brightness", 60), "brightness 60%");
    }
}
