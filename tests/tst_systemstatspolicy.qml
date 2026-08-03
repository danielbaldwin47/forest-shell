// The system monitor's readings (#50): four kernel texts in, four rows out.
//
// Seam 1 (CLAUDE.md). The sampler next door is a timer, a `FileView` and a
// `Process`; everything that could be *wrong* about a reading — which fields
// /proc/stat's first line holds, which of memory's numbers counts as used,
// which of a machine's six thermal sensors is the one worth showing — is here,
// where a test can hand it a file from a machine that is not this one.
import QtQuick
import QtTest
import "../Services/System"

TestCase {
    name: "SystemStatsPolicy"

    SystemStatsPolicy { id: policy }

    // --- /proc/stat -----------------------------------------------------------

    readonly property string procStat:
        "cpu  1000 20 300 8000 100 0 40 0 0 0\n"
      + "cpu0 500 10 150 4000 50 0 20 0 0 0\n"
      + "cpu1 500 10 150 4000 50 0 20 0 0 0\n"
      + "intr 12345\n"
      + "btime 1700000000\n"

    function test_the_aggregate_line_is_the_one_that_is_read() {
        // Summing the per-core lines under it would double every reading.
        const totals = policy.cpuTotals(procStat);
        compare(totals.total, 9460);
        // idle + iowait.
        compare(totals.idle, 8100);
    }

    function test_a_machine_that_is_not_reporting_is_not_a_reading_of_zero() {
        compare(policy.cpuTotals(""), null);
        compare(policy.cpuTotals("intr 12345\n"), null);
        compare(policy.cpuTotals("cpu  broken numbers here\n"), null);
    }

    function test_busy_is_the_ratio_of_two_deltas() {
        // 100 ticks pass, 25 of them idle.
        const busy = policy.cpuBusy({ total: 1000, idle: 500 }, { total: 1100, idle: 525 });
        compare(Math.round(busy * 100), 75);
    }

    function test_the_first_sample_is_a_baseline_and_not_an_idle_machine() {
        // A single /proc/stat read is ticks *since boot*, so there is no
        // percentage in it at all. NaN and not 0 — a sparkline that opened with
        // a bar at the floor would be claiming the machine was asleep.
        verify(isNaN(policy.cpuBusy(null, { total: 1000, idle: 500 })));
        verify(isNaN(policy.cpuBusy(undefined, undefined)));
    }

    function test_two_reads_inside_one_tick_answer_nothing_rather_than_a_division_by_zero() {
        verify(isNaN(policy.cpuBusy({ total: 1000, idle: 500 }, { total: 1000, idle: 500 })));
    }

    function test_counters_that_went_backwards_are_refused() {
        // What a suspend/resume looks like from here.
        verify(isNaN(policy.cpuBusy({ total: 2000, idle: 900 }, { total: 1000, idle: 500 })));
        verify(isNaN(policy.cpuBusy({ total: 1000, idle: 900 }, { total: 1100, idle: 800 })));
    }

    function test_a_fully_busy_and_a_fully_idle_interval_both_land_in_range() {
        compare(policy.cpuBusy({ total: 0, idle: 0 }, { total: 100, idle: 0 }), 1);
        compare(policy.cpuBusy({ total: 0, idle: 0 }, { total: 100, idle: 100 }), 0);
    }

    // --- /proc/meminfo --------------------------------------------------------

    readonly property string meminfo:
        "MemTotal:       16384000 kB\n"
      + "MemFree:         1024000 kB\n"
      + "MemAvailable:    8192000 kB\n"
      + "Buffers:          512000 kB\n"
      + "Cached:          6000000 kB\n"

    function test_cache_is_not_counted_as_used_memory() {
        // The reading that separates a monitor from a scaremonger: MemFree on
        // this machine is 6%, MemAvailable is 50%, and only one of them is what
        // "memory in use" means on Linux.
        const memory = policy.memory(meminfo);
        compare(memory.totalKb, 16384000);
        compare(memory.usedKb, 8192000);
        compare(memory.fraction, 0.5);
    }

    function test_a_kernel_too_old_to_publish_availability_falls_back() {
        const memory = policy.memory(
            "MemTotal:       16384000 kB\nMemFree:         1024000 kB\n"
          + "Buffers:          512000 kB\nCached:          6000000 kB\n");
        // free + buffers + cached = 7536000 available.
        compare(memory.usedKb, 8848000);
    }

    function test_meminfo_without_a_total_is_not_a_reading() {
        compare(policy.memory(""), null);
        compare(policy.memory("MemFree: 1024 kB\n"), null);
        compare(policy.memory("MemTotal: 0 kB\n"), null);
    }

    // --- df -------------------------------------------------------------------

    function test_the_disk_is_asked_about_in_posix_units() {
        // Without `-P` a long device name wraps; without `-k` the block size
        // comes from the environment.
        const command = policy.diskCommand("/home");
        compare(command, ["df", "-P", "-k", "/home"]);
        compare(policy.diskCommand(""), ["df", "-P", "-k", "/"]);
    }

    function test_a_df_answer_becomes_a_fraction() {
        const disk = policy.disk(
            "Filesystem     1024-blocks      Used Available Capacity Mounted on\n"
          + "/dev/nvme0n1p2   982940000 491470000 441000000      53% /\n");
        compare(disk.totalKb, 982940000);
        compare(disk.usedKb, 491470000);
        compare(Math.round(disk.fraction * 100), 50);
    }

    function test_a_wrapped_device_name_is_read_from_the_last_line() {
        // `df -P` is meant to prevent this, and a mapper name long enough still
        // wraps on some coreutils builds. Counting from the end costs nothing
        // and survives it.
        const disk = policy.disk(
            "Filesystem 1024-blocks Used Available Capacity Mounted on\n"
          + "/dev/mapper/luks-8ac1f0d2-1f4e-4b5a-9a1e-0e2b7c6d5f4a\n"
          + "                 1000 400 600 40% /\n");
        compare(disk.usedKb, 400);
    }

    function test_a_df_that_failed_is_not_a_full_disk() {
        compare(policy.disk(""), null);
        compare(policy.disk("df: /nope: No such file or directory\n"), null);
        compare(policy.disk("Filesystem 1024-blocks Used\nnonsense here now\n"), null);
    }

    // --- hwmon ----------------------------------------------------------------

    readonly property string sensors:
        "nvme\t/sys/class/hwmon/hwmon0/temp1_input\n"
      + "iwlwifi_1\t/sys/class/hwmon/hwmon1/temp1_input\n"
      + "coretemp\t/sys/class/hwmon/hwmon2/temp1_input\n"
      + "coretemp\t/sys/class/hwmon/hwmon2/temp2_input\n"
      + "acpitz\t/sys/class/hwmon/hwmon3/temp1_input\n"

    function test_the_processor_package_is_preferred_over_the_ssd_and_the_radio() {
        // "The temperature" of a machine means the CPU, and hwmon numbers are
        // assigned in probe order — so the first sensor found is as likely to
        // be the wireless card as anything.
        compare(policy.pickSensor(sensors), "/sys/class/hwmon/hwmon2/temp1_input");
    }

    function test_the_package_beats_the_thermal_zone_and_the_zone_beats_nothing() {
        compare(policy.pickSensor("acpitz\t/sys/class/hwmon/hwmon0/temp1_input\n"),
                "/sys/class/hwmon/hwmon0/temp1_input");
    }

    function test_a_machine_this_table_has_never_heard_of_still_gets_a_reading() {
        compare(policy.pickSensor("weird_soc_thing\t/sys/class/hwmon/hwmon0/temp1_input\n"),
                "/sys/class/hwmon/hwmon0/temp1_input");
    }

    function test_a_machine_with_no_thermal_sensor_at_all_answers_empty() {
        // Most virtual machines. The row is then absent rather than dashed.
        compare(policy.pickSensor(""), "");
        compare(policy.pickSensor("garbage without a tab\n"), "");
    }

    function test_millidegrees_become_degrees() {
        compare(policy.temperature("54000\n"), 54);
        compare(policy.temperature("54000"), 54);
    }

    function test_a_driver_that_writes_plain_degrees_is_not_reported_as_45000() {
        compare(policy.temperature("45"), 45);
    }

    function test_an_unreadable_sensor_is_not_a_temperature() {
        verify(isNaN(policy.temperature("")));
        verify(isNaN(policy.temperature("no such file")));
        verify(isNaN(policy.temperature("0")));
    }

    // --- history --------------------------------------------------------------

    function test_a_sample_is_appended_and_the_oldest_falls_off_the_end() {
        let history = [];
        for (let i = 0; i < 5; i++)
            history = policy.push(history, i / 10, 3);
        compare(history.length, 3);
        compare(Math.round(history[2] * 10), 4);
        compare(Math.round(history[0] * 10), 2);
    }

    function test_pushing_hands_back_a_new_array() {
        // The sparkline redraws on identity change; a mutation in place would
        // leave it showing the history it was constructed with.
        const before = [0.1, 0.2];
        const after = policy.push(before, 0.3, 10);
        compare(before.length, 2);
        compare(after.length, 3);
    }

    function test_a_sample_out_of_range_is_clamped_and_a_missing_one_is_kept_as_a_gap() {
        compare(policy.push([], 1.4, 10)[0], 1);
        compare(policy.push([], -3, 10)[0], 0);
        verify(isNaN(policy.push([], NaN, 10)[0]));
    }

    function test_history_starts_from_nothing_rather_than_throwing() {
        compare(policy.push(null, 0.5, 10).length, 1);
        compare(policy.push(undefined, 0.5, 10).length, 1);
    }

    // --- words ----------------------------------------------------------------

    function test_a_fraction_reads_as_a_percentage_and_an_absent_one_as_a_dash() {
        compare(policy.percent(0.423), "42%");
        compare(policy.percent(1), "100%");
        compare(policy.percent(NaN), "—");
    }

    function test_sizes_are_binary_because_the_kernel_reports_them_that_way() {
        // 16 GiB of RAM must not read as 17.2 of anything.
        compare(policy.sizeLabel(16 * 1024 * 1024), "16.0 GiB");
        compare(policy.sizeLabel(8192), "8 MiB");
        compare(policy.sizeLabel(512), "512 KiB");
        compare(policy.sizeLabel(NaN), "");
    }

    function test_the_sparkline_spends_its_height_on_temperatures_a_computer_reaches() {
        // 0–100 would put every idle reading in the bottom third.
        compare(policy.temperatureFraction(30), 0);
        compare(policy.temperatureFraction(95), 1);
        compare(Math.round(policy.temperatureFraction(62.5) * 100), 50);
        compare(policy.temperatureFraction(10), 0);
        verify(isNaN(policy.temperatureFraction(NaN)));
    }

    // --- the rows -------------------------------------------------------------

    readonly property var sample: ({
        cpu: 0.42, memory: 0.5, disk: 0.53, temperature: 62.5,
        memoryUsedKb: 8192000, memoryTotalKb: 16384000,
        diskUsedKb: 491470000, diskTotalKb: 982940000
    })

    function test_the_card_gets_four_rows_in_a_fixed_order() {
        const rows = policy.rows(sample, ({}));
        compare(rows.map(row => row.key), ["cpu", "memory", "disk", "temperature"]);
        compare(rows[0].label, "CPU");
        compare(rows[0].value, "42%");
        compare(rows[3].value, "63°C");
    }

    function test_a_row_says_what_its_percentage_is_a_percentage_of_where_there_is_one() {
        const rows = policy.rows(sample, ({}));
        compare(rows[1].detail, "7.8 GiB of 15.6 GiB");
        // A processor at 42% is not 42% of anything a number would help with.
        compare(rows[0].detail, "");
        compare(rows[3].detail, "");
    }

    function test_a_machine_with_no_thermal_sensor_gets_three_rows_and_no_dash() {
        const rows = policy.rows({ cpu: 0.42, memory: 0.5, disk: 0.53 }, ({}));
        compare(rows.length, 3);
        compare(rows.map(row => row.key).indexOf("temperature"), -1);
    }

    function test_the_first_sample_of_a_freshly_opened_card_has_no_cpu_row_yet() {
        // `cpuBusy` answers NaN until there are two samples, and the row is
        // absent for that one tick rather than drawn at zero.
        const rows = policy.rows({ cpu: NaN, memory: 0.5 }, ({}));
        compare(rows.map(row => row.key), ["memory"]);
    }

    function test_each_row_carries_its_own_history() {
        const rows = policy.rows(sample, { cpu: [0.1, 0.2], memory: [0.5] });
        compare(rows[0].history, [0.1, 0.2]);
        compare(rows[1].history, [0.5]);
        // A row nobody has sampled twice yet draws an empty sparkline rather
        // than reading `undefined.length`.
        compare(rows[2].history, []);
    }

    // --- the bar module -------------------------------------------------------

    function test_the_bar_readout_is_the_two_numbers_that_change() {
        compare(policy.barLabel(sample), "CPU 42%  RAM 50%");
    }

    function test_a_bar_readout_with_nothing_sampled_yet_is_empty() {
        // The module hides itself on this rather than showing "CPU —".
        compare(policy.barLabel(({})), "");
        compare(policy.barLabel(null), "");
    }

    function test_the_bar_readout_survives_the_first_tick_with_no_cpu_delta() {
        compare(policy.barLabel({ cpu: NaN, memory: 0.5 }), "CPU —  RAM 50%");
    }

    // --- the log lines --------------------------------------------------------

    function test_starting_and_stopping_both_say_so() {
        // The acceptance criterion "sampling verifiably stops when the
        // dashboard is closed" is read out of these two lines by
        // tools/drawer-harness.sh (#81).
        compare(policy.watching(1, 1000), "sampling every 1000ms for 1 watcher(s)");
        compare(policy.idle(), "sampling stopped — nothing is watching");
    }

    function test_a_sample_summarises_as_one_line() {
        compare(policy.summary(sample), "cpu 42%, memory 50%, disk 53%, temp 63°C");
    }
}
