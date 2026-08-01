// Wall-clock age of this process, from /proc.
//
// The startup budget (#22: first frame ≤ 1.5 s, interactive ≤ 2 s) is measured
// from *process launch*, and the QML engine only exists well after that — so
// `Date.now()` at the first line of QML is already late by an unknown amount.
// /proc/self/stat field 22 (starttime, in clock ticks since boot) plus
// /proc/stat's `btime` gives the real launch instant.
//
// Pure text in, numbers out: no file IO, no Quickshell imports, so tests/ can
// exercise it under qmltestrunner. Core/Logger.qml does the reading.
import QtQuick

QtObject {
    // USER_HZ. 100 on every Linux/x86 kernel; sysconf(_SC_CLK_TCK) is not
    // reachable from QML, and a wrong value here only skews the log timestamps.
    readonly property int ticksPerSecond: 100

    // `btime <seconds since epoch>` in /proc/stat. NaN when absent.
    function bootTimeMs(procStatText) {
        const match = /^btime[ \t]+(\d+)/m.exec(procStatText || "");
        return match ? parseInt(match[1], 10) * 1000 : NaN;
    }

    // Field 22 of /proc/self/stat. The comm field (2) is parenthesised and may
    // itself contain spaces and parens, so fields are counted from the *last*
    // ')' — which is what proc(5) tells you to do.
    function startTicks(selfStatText) {
        const text = selfStatText || "";
        const close = text.lastIndexOf(")");
        if (close < 0)
            return NaN;
        const fields = text.slice(close + 1).trim().split(/\s+/);
        // fields[0] is field 3 (state), so field 22 sits at index 19.
        const value = parseInt(fields[19], 10);
        return isNaN(value) ? NaN : value;
    }

    // Epoch milliseconds at which this process was launched.
    function processStartMs(selfStatText, procStatText) {
        const boot = bootTimeMs(procStatText);
        const ticks = startTicks(selfStatText);
        if (isNaN(boot) || isNaN(ticks))
            return NaN;
        return boot + (ticks / ticksPerSecond) * 1000;
    }

    function formatElapsed(ms) {
        return "+" + Math.round(ms) + "ms";
    }
}
