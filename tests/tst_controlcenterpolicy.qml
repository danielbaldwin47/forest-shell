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
            brightness: { available: true, percent: 60 },
            recording: { available: true, on: false, detail: "GPU" }
        };
    }

    function ids(list) {
        return list.map(item => item.id);
    }

    function byId(list, id) {
        return list.filter(item => item.id === id)[0] ?? null;
    }

    // --- the grid ------------------------------------------------------------

    function test_the_grid_is_ten_tiles_in_a_fixed_order() {
        // Fixed, because grid position is muscle memory: the tile you reach for
        // without looking must not move because a radio came up.
        //
        // Ten since #52, which is 3x3 plus one rather than the 3x3 #44 asked
        // for. The tenth is last for that reason — it lands in a short row of
        // its own instead of pushing anything sideways.
        compare(policy.columns, 3);
        compare(ids(policy.tiles(fullFacts())),
                ["wifi", "bluetooth", "dnd", "nightlight", "keepawake",
                 "mode", "powerprofile", "vpn", "wallpaper", "recording"]);
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
        facts.recording.available = false;

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
        // Ten tiles is 3-3-3-1, and the 1 is a short row rather than a row with
        // two invisible pressable holes in it. Nine is three full rows, which
        // is what a machine without an encoder gets back.
        const rows = policy.rows(policy.tiles(fullFacts()));
        compare(rows.length, 4);
        compare(rows[0].length, 3);
        compare(rows[2].length, 3);
        compare(rows[3].length, 1);

        const noEncoder = fullFacts();
        noEncoder.recording.available = false;
        compare(policy.rows(policy.tiles(noEncoder)).length, 3);

        // Eight is 3-3-2 and not 3-3-1-with-a-gap: the layout left-aligns a
        // short row rather than padding it with pressable holes.
        const facts = fullFacts();
        facts.bluetooth.present = false;
        facts.recording.available = false;
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

    // --- recording (#52) -----------------------------------------------------

    /// The same rule the hardware tiles follow: a control that cannot do the
    /// thing is worse than no control. Here it means a machine with neither
    /// encoder installed is back to the nine tiles it had before #52.
    function test_the_recording_tile_is_absent_without_an_encoder() {
        const facts = fullFacts();
        facts.recording.available = false;
        compare(byId(policy.tiles(facts), "recording"), null);
        verify(ids(policy.tiles(fullFacts())).indexOf("recording") >= 0);
    }

    /// The detail line is the tile's whole argument for existing before you
    /// press it: it says whether this machine encodes on the GPU or in
    /// software, which nothing else in the shell can answer.
    function test_the_idle_recording_tile_names_the_engine() {
        const tile = byId(policy.tiles(fullFacts()), "recording");
        compare(tile.on, false);
        compare(tile.detail, "GPU");
        compare(tile.icon, "circle-dot");
        compare(tile.label, "Recording");
    }

    /// The glyph changes and the label does not — "Recording" reading "Stop"
    /// would describe the press where every other tile describes the subject.
    function test_a_running_recording_lights_the_tile_and_shows_a_stop_glyph() {
        const facts = fullFacts();
        facts.recording.on = true;
        facts.recording.detail = "0:12";
        const tile = byId(policy.tiles(facts), "recording");
        compare(tile.on, true);
        compare(tile.icon, "square");
        compare(tile.label, "Recording");
        compare(tile.detail, "0:12");
    }

    /// Last, so the short row it creates is at the bottom — see `tileOrder`.
    function test_the_recording_tile_is_last_in_the_grid() {
        const list = ids(policy.tiles(fullFacts()));
        compare(list[list.length - 1], "recording");
    }

    function test_the_wallpaper_tile_is_a_door_and_never_lit() {
        // It opens the picker rather than switching something on, so it has no
        // on-state to show and no body press that could mean anything else.
        const tile = byId(policy.tiles(fullFacts()), "wallpaper");
        compare(tile.on, false);
        compare(tile.detail, "");
        compare(tile.icon, "wallpaper");
        compare(tile.drillIn, "wallpaper");
        compare(tile.doorOnly, true);
    }

    function test_three_tiles_are_a_switch_and_a_door_at_once() {
        // #45: Wi-Fi, Bluetooth and VPN each have a state to toggle *and* a
        // list to choose from, so the chevron opens the list and the body still
        // flips the switch. The map itself is DrillInPolicy's — this is the
        // check that the grid asks it rather than restating it.
        const tiles = policy.tiles(fullFacts());
        compare(byId(tiles, "wifi").drillIn, "wifi");
        compare(byId(tiles, "bluetooth").drillIn, "bluetooth");
        compare(byId(tiles, "vpn").drillIn, "vpn");
        for (const id of ["wifi", "bluetooth", "vpn"])
            compare(byId(tiles, id).doorOnly, false);
    }

    function test_the_switches_that_are_only_switches_carry_no_chevron() {
        for (const tile of policy.tiles(fullFacts()))
            if (["dnd", "nightlight", "keepawake", "mode", "powerprofile"]
                    .indexOf(tile.id) >= 0)
                compare(tile.drillIn, "");
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

    // --- the slider model's identity (#192) -----------------------------------
    //
    // The surface latches its `Repeater` to `sliderIds` and reassigns only when
    // `sameIds` says the set changed, because a new array identity destroys and
    // re-creates every delegate and a re-created slider animates its fill up
    // from empty. What seam 1 can check is the decision underneath that: which
    // facts move the id list, and which — the ones that move on every volume
    // key — must not.

    function test_the_id_list_is_the_sliders_in_order() {
        compare(policy.sliderIds(fullFacts()), ["volume", "mic", "brightness"]);
    }

    function test_absent_hardware_leaves_the_id_list() {
        const facts = fullFacts();
        facts.brightness.available = false;
        compare(policy.sliderIds(facts), ["volume", "mic"]);
    }

    function test_a_level_or_mute_change_does_not_change_the_id_list() {
        // The whole point. These are the changes that arrive on every volume
        // key, every brightness step and every drag frame; if any of them moved
        // the id list the latch would reassign and the fill would replay.
        const before = policy.sliderIds(fullFacts());

        const louder = fullFacts();
        louder.volume.percent = 90;
        louder.brightness.percent = 12;
        verify(policy.sameIds(before, policy.sliderIds(louder)));

        const muted = fullFacts();
        muted.volume.muted = true;
        muted.mic.muted = true;
        verify(policy.sameIds(before, policy.sliderIds(muted)));
    }

    function test_hardware_arriving_or_going_does_change_the_id_list() {
        const full = policy.sliderIds(fullFacts());

        const noMic = fullFacts();
        noMic.mic.available = false;
        verify(!policy.sameIds(full, policy.sliderIds(noMic)));

        // And back again: the latch has to reassign in both directions, or a
        // microphone plugged in mid-session never gets a row.
        verify(policy.sameIds(full, policy.sliderIds(fullFacts())));
    }

    function test_reordering_the_sliders_changes_the_id_list() {
        // #55's configured order. Same three sliders, different sequence, so
        // comparing lengths alone would miss it.
        verify(!policy.sameIds(["volume", "mic", "brightness"],
                               ["mic", "volume", "brightness"]));
    }

    function test_same_ids_survives_an_empty_or_missing_list() {
        // Not the startup path — the surface holds `null` until its first
        // latch and skips the comparison entirely for it, precisely so an
        // empty machine still logs. This is the path *after* that: a machine
        // that latched `[]` and is asked again, which has to compare equal or
        // it would relatch and relog on every service tick.
        verify(policy.sameIds([], []));
        verify(policy.sameIds(null, []));
        verify(policy.sameIds(undefined, null));
        verify(!policy.sameIds([], ["volume"]));
    }

    function test_a_latched_delegate_gets_its_own_row() {
        const row = policy.sliderRow("volume", fullFacts());
        compare(row.id, "volume");
        compare(row.percent, 45);
        compare(row.present, true);
    }

    function test_a_slider_whose_hardware_went_says_it_is_not_there() {
        // The one turn between hardware going away and the latch catching up.
        // The row has to be *marked* rather than merely zeroed: the surface
        // hides a row that says it is gone, and a 0% row it drew instead would
        // animate the fill down to empty — this ticket backwards.
        const facts = fullFacts();
        facts.mic.available = false;
        const row = policy.sliderRow("mic", facts);
        compare(row.present, false);
        compare(row.id, "mic");
    }

    function test_a_machine_with_no_sliders_at_all_has_an_empty_id_list() {
        const facts = fullFacts();
        facts.volume.available = false;
        facts.mic.available = false;
        facts.brightness.available = false;
        compare(policy.sliderIds(facts), []);
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

    // --- what the Control Center tab edits (#55) -----------------------------
    //
    // The grid, the sliders, the column count and the step are settings now,
    // and this policy is where a configured list becomes a drawn one. The
    // panel binds these four properties to `Config.values.controlCenter`; the
    // defaults above are what the file says when nobody has touched it, which
    // tests/tst_schemas.qml pins against the schema.

    ControlCenterPolicy {
        id: configured
        tileOrder: ["dnd", "nonesuch", "wifi"]
        sliderOrder: ["brightness", "volume"]
        columns: 2
        step: 10
    }

    function test_a_configured_grid_is_drawn_in_the_order_it_names() {
        // Grid position is muscle memory, so the order is fixed — but it is the
        // *user's* fixed order now rather than this file's, which is the whole
        // of what the tab edits.
        const tiles = configured.tiles(fullFacts()).map(tile => tile.id);
        compare(tiles, ["dnd", "wifi"]);
    }

    function test_a_tile_this_shell_cannot_draw_is_dropped_rather_than_refused() {
        // Same rule Surfaces/Drawers/DashboardRegistry.qml follows, and the
        // reason the schema coerces this list to plain strings rather than a
        // closed enum: a config written by a newer shell keeps its tile, and
        // this one leaves a gap-free grid instead of a hole or a crash.
        verify(configured.tile("nonesuch", fullFacts()) === null);
        compare(configured.tiles(fullFacts()).length, 2);
    }

    function test_a_configured_slider_list_is_honoured_the_same_way() {
        const sliders = configured.sliders(fullFacts()).map(slider => slider.id);
        compare(sliders, ["brightness", "volume"]);
    }

    function test_the_column_count_is_what_chunks_the_rows() {
        // Two columns is three rows of the six tiles a two-column grid gets,
        // and the short last row is still short rather than padded.
        const rows = configured.rows(["a", "b", "c"]);
        compare(rows.length, 2);
        compare(rows[0], ["a", "b"]);
        compare(rows[1], ["c"]);
    }

    function test_a_configured_step_is_the_notch_the_arrows_move() {
        // The nudge still lands *on* the step grid rather than adding to
        // wherever a drag left the value — at 10, 43 up is 50 and not 53.
        compare(configured.nudge(43, 1), 50);
        compare(configured.nudge(43, -1), 40);
    }

    function test_an_empty_grid_in_the_file_is_an_empty_grid() {
        // Not a fallback to the default list: emptying the grid is a thing the
        // tab lets you do, and quietly restoring ten tiles would be the panel
        // ignoring the file.
        empty.tileOrder = [];
        compare(empty.tiles(fullFacts()).length, 0);
    }

    ControlCenterPolicy { id: empty }
}
