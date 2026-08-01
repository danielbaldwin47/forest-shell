// Pure parsing of /proc, so startup timing can be asserted without a shell.
// Run with tests/run.sh (qmltestrunner cannot load Quickshell's QML modules —
// they are baked into the quickshell binary — so only Quickshell-free files are
// testable here; see Core/ProcessClock.qml).
import QtQuick
import QtTest
import "../Core"

TestCase {
    name: "ProcessClock"

    ProcessClock { id: clock }

    // Real /proc/self/stat of a process whose comm contains both a space and
    // the parens that make naive field splitting wrong.
    readonly property string selfStat:
        "1234 (qs upstream) S 1 1234 1234 0 -1 4194560 5723 0 0 0 41 12 0 0 20 0 14 0 987654 " +
        "1234567890 4321 18446744073709551615 1 1 0 0 0 0 0 4096 17642 0 0 0 17 3 0 0 0 0 0"

    readonly property string procStat:
        "cpu  100 200 300 400\n" +
        "cpu0 10 20 30 40\n" +
        "intr 12345\n" +
        "btime 1754000000\n" +
        "processes 98765\n"

    function test_bootTimeMs() {
        compare(clock.bootTimeMs(procStat), 1754000000000);
    }

    function test_bootTimeMs_missing() {
        verify(isNaN(clock.bootTimeMs("cpu 1 2 3\nprocesses 5\n")));
    }

    function test_startTicks_skips_comm_field() {
        // Field 22 counting from the pid; the comm parens are skipped wholesale.
        compare(clock.startTicks(selfStat), 987654);
    }

    function test_startTicks_comm_with_parens() {
        const stat = "77 (weird)name)) S 1 77 77 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 4242 " +
                     "0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0";
        compare(clock.startTicks(stat), 4242);
    }

    function test_startTicks_garbage() {
        verify(isNaN(clock.startTicks("not a stat line")));
    }

    function test_processStartMs() {
        // btime + starttime/USER_HZ: 1754000000000 + 987654/100*1000
        compare(clock.processStartMs(selfStat, procStat), 1754000000000 + 9876540);
    }

    function test_processStartMs_unparseable_is_nan() {
        verify(isNaN(clock.processStartMs("garbage", procStat)));
        verify(isNaN(clock.processStartMs(selfStat, "garbage")));
    }

    function test_formatElapsed() {
        compare(clock.formatElapsed(0), "+0ms");
        compare(clock.formatElapsed(1234.7), "+1235ms");
    }
}
