// Logging with a process-relative timestamp.
//
// Startup is budgeted from process launch (#22: first frame ≤ 1.5 s,
// interactive ≤ 2 s), and those budgets are checked by reading the log — so
// every line carries the age of the process, not the age of the QML engine.
// The launch instant comes from /proc via Core/ProcessClock.qml.
//
// If /proc is unreadable the timestamps are relative to the first log call
// instead, which is a long way into startup and would read as a suspiciously
// fast shell — so that fallback announces itself once, in the log.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property real processStartMs: {
        const fromProc = clock.processStartMs(selfStat.text(), procStat.text());
        return isNaN(fromProc) ? firstLogMs : fromProc;
    }

    // When /proc fails, timestamps count from here — the moment the first line
    // was logged, not the moment the process started.
    readonly property real firstLogMs: Date.now()

    readonly property bool timestampsFromProcess:
        !isNaN(clock.processStartMs(selfStat.text(), procStat.text()))

    function elapsedMs(): real {
        return Date.now() - processStartMs;
    }

    function log(tag: string, message: string) {
        console.log(clock.formatElapsed(elapsedMs()), tag + ":", message);
    }

    function warn(tag: string, message: string) {
        console.warn(clock.formatElapsed(elapsedMs()), tag + ":", message);
    }

    Component.onCompleted: {
        if (!timestampsFromProcess)
            warn("logger", "/proc unreadable — timestamps count from the first log line, "
                 + "not from process start; startup budgets cannot be read off this log");
    }

    // Startup stage marker — the log evidence the staging is really staged.
    function stage(name: string) {
        log("startup", "stage " + name);
    }

    ProcessClock { id: clock }

    // printErrors off: these are best-effort reads, and a missing /proc is a
    // fallback path, not something to shout about in a clean startup log.
    FileView {
        id: selfStat
        path: "/proc/self/stat"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: procStat
        path: "/proc/stat"
        blockLoading: true
        printErrors: false
    }
}
