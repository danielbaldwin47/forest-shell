pragma Singleton

// The machine's own vital signs (#50, #12 §3).
//
//     SystemStats.rows      // what the card draws, one entry per readout
//     SystemStats.sample    // the latest reading, as fractions
//     SystemStats.watch() / SystemStats.release()
//
// Native sampling, decided in #9: `/proc/stat`, `/proc/meminfo`,
// `/sys/class/hwmon` and one `df`, with no dgop, btop or fastfetch anywhere near
// it. Every parse and every threshold is in Services/System/SystemStatsPolicy.qml
// on the QtQuick-only side of the line; this file is the timer, the three
// `FileView`s and the one `Process`.
//
// ## The subscription is the whole design
//
// A monitor is the one service in this shell that costs something *continuously*
// — four file reads a second, forever — and #22 §5's idle budget does not have
// room for that behind a closed drawer. So nothing here samples unless somebody
// says they are looking:
//
//     Component.onCompleted:  SystemStats.watch()
//     Component.onDestruction: SystemStats.release()
//
// The dashboard card takes a subscription while it exists (the drawer destroys
// its slot on close, so the release is the panel going away), and the optional
// bar module takes one for as long as it is on the bar — a bar configured with
// the module therefore samples all session, which is the cost the user opted
// into by putting a live readout on their bar.
//
// `watchers` is a count and not a flag because both can hold one at once: the
// card opening over a bar that already has the module must not start a second
// timer, and the card closing must not stop the module's.
//
// The two log lines this emits are the acceptance criterion "sampling verifiably
// stops when the dashboard is closed" — #81's rule that a lifecycle nothing logs
// is a lifecycle with two candidate causes. `tools/drawer-harness.sh` reads them.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core

Singleton {
    id: root

    readonly property SystemStatsPolicy policy: SystemStatsPolicy {}

    readonly property var settings: Config.values.dashboard.systemMonitor

    // --- who is looking -------------------------------------------------------

    property int watchers: 0

    function watch(): void {
        root.watchers += 1;
        if (root.watchers === 1) {
            // The probe is the one thing that has to happen before the first
            // sample rather than with it: a temperature row that appeared a few
            // seconds after the other three would read as the card still
            // loading.
            if (!root.probed)
                root.probe();
            root.readDisk();
            Logger.log("sysmon", root.policy.watching(root.watchers, root.intervalMs));
        }
    }

    function release(): void {
        root.watchers = Math.max(0, root.watchers - 1);
        if (root.watchers === 0) {
            // The counters are *not* cleared. Reopening the dashboard within a
            // minute should show the minute of history it already has, and the
            // CPU baseline is what makes the first sample after a reopen a real
            // percentage instead of a gap — for as long as that baseline is
            // still recent, which is `previousCpuAt`'s whole job.
            Logger.log("sysmon", root.policy.idle());
        }
    }

    readonly property int intervalMs: Math.max(1, root.settings.intervalSeconds) * 1000

    // --- the readings ---------------------------------------------------------

    /// Busy fraction of the last interval, or NaN until there are two samples.
    property real cpu: NaN
    property real memory: NaN
    property real disk: NaN

    /// Degrees Celsius, or NaN on a machine with no sensor this shell can find
    /// — most virtual machines, and the reason the row is droppable.
    property real temperature: NaN

    property real memoryUsedKb: NaN
    property real memoryTotalKb: NaN
    property real diskUsedKb: NaN
    property real diskTotalKb: NaN

    /// Everything a consumer reads, in one object, so the card and the bar
    /// module cannot disagree about what a reading is.
    readonly property var sample: ({
        cpu: root.cpu,
        memory: root.memory,
        disk: root.disk,
        temperature: root.temperature,
        memoryUsedKb: root.memoryUsedKb,
        memoryTotalKb: root.memoryTotalKb,
        diskUsedKb: root.diskUsedKb,
        diskTotalKb: root.diskTotalKb
    })

    /// A minute of each, oldest first. Written whole on every tick, because a
    /// sparkline redraws on identity change and a mutation in place would leave
    /// it showing the array it was constructed with.
    property var history: ({ cpu: [], memory: [], disk: [], temperature: [] })

    readonly property var rows: root.policy.rows(root.sample, root.history)

    /// The bar module's one line, or empty before the first sample.
    readonly property string barLabel: root.policy.barLabel(root.sample)

    // --- sampling -------------------------------------------------------------

    /// The previous `/proc/stat` totals, and when they were taken. CPU is the
    /// only reading that needs two samples to mean anything — the file counts
    /// ticks since boot.
    ///
    /// The timestamp is what keeps a reopen honest. The counters survive
    /// `release()` on purpose, so a dashboard closed and reopened inside a
    /// minute picks its history back up — but a snapshot from an hour ago is
    /// not a baseline, it is an hour's average, and drawing it as this second's
    /// first bar would report an idle machine as busy (or the reverse) at every
    /// open. Past `staleBaselineTicks` intervals it is dropped, and the first
    /// bar after that is the honest gap a first sample always is.
    property var previousCpu: null
    property real previousCpuAt: 0

    readonly property int staleBaselineTicks: 4

    /// How many ticks between `df` runs. Disk usage moves by the gigabyte over
    /// hours, and it is the one reading here that costs a process rather than a
    /// file read, so it is not worth a subprocess a second.
    readonly property int diskEvery: 30
    property int tick: 0

    Timer {
        interval: root.intervalMs
        repeat: true
        running: root.watchers > 0
        triggeredOnStart: true

        onTriggered: {
            root.tick += 1;
            procStat.reload();
            procMeminfo.reload();
            if (root.sensorPath !== "")
                sensor.reload();
            if (root.tick % root.diskEvery === 0)
                root.readDisk();
        }
    }

    /// One tick's readings appended to the history.
    ///
    /// Called from the `/proc/stat` handler rather than from the timer, so that
    /// the CPU value recorded is the one just computed rather than the previous
    /// tick's — the other three are instantaneous and are recorded as they
    /// stand.
    function record(): void {
        const cap = root.policy.historyLength;
        root.history = {
            cpu: root.policy.push(root.history.cpu, root.cpu, cap),
            memory: root.policy.push(root.history.memory, root.memory, cap),
            disk: root.policy.push(root.history.disk, root.disk, cap),
            temperature: root.policy.push(root.history.temperature,
                                          root.policy.temperatureFraction(root.temperature), cap)
        };
    }

    FileView {
        id: procStat

        path: "/proc/stat"
        printErrors: false

        onLoaded: {
            const now = Date.now();
            const fresh = root.previousCpu !== null
                && (now - root.previousCpuAt) <= root.intervalMs * root.staleBaselineTicks;

            const totals = root.policy.cpuTotals(procStat.text());
            root.cpu = root.policy.cpuBusy(fresh ? root.previousCpu : null, totals);
            if (totals !== null) {
                root.previousCpu = totals;
                root.previousCpuAt = now;
            }
            root.record();
        }
    }

    FileView {
        id: procMeminfo

        path: "/proc/meminfo"
        printErrors: false

        onLoaded: {
            const reading = root.policy.memory(procMeminfo.text());
            if (reading === null)
                return;
            root.memory = reading.fraction;
            root.memoryUsedKb = reading.usedKb;
            root.memoryTotalKb = reading.totalKb;
        }
    }

    // --- the thermal sensor ---------------------------------------------------

    property bool probed: false
    property string sensorPath: ""

    function probe(): void {
        root.probed = true;
        sensorProbe.command = root.policy.sensorProbeCommand();
        sensorProbe.running = true;
    }

    Process {
        id: sensorProbe

        stdout: StdioCollector { id: sensorProbeOut }

        onExited: (exitCode, exitStatus) => {
            root.sensorPath = exitCode === 0 ? root.policy.pickSensor(sensorProbeOut.text) : "";
            // A machine with no sensor is a normal machine — this line is why
            // the card has three rows on it rather than four.
            Logger.log("sysmon", root.sensorPath === ""
                       ? "no thermal sensor — the temperature row is off"
                       : "thermal sensor: " + root.sensorPath);
            if (root.sensorPath !== "")
                sensor.reload();
        }
    }

    FileView {
        id: sensor

        path: root.sensorPath
        printErrors: false

        onLoaded: root.temperature = root.policy.temperature(sensor.text())
    }

    // --- the disk -------------------------------------------------------------

    function readDisk(): void {
        if (df.running)
            return;
        df.command = root.policy.diskCommand(root.settings.diskPath);
        df.running = true;
    }

    Process {
        id: df

        stdout: StdioCollector { id: dfOut }

        onExited: (exitCode, exitStatus) => {
            const reading = exitCode === 0 ? root.policy.disk(dfOut.text) : null;
            if (reading === null) {
                // A path that is not a mount point is a hand-edit worth a line:
                // the row simply vanishes otherwise.
                Logger.warn("sysmon", "could not read the disk at "
                            + (root.settings.diskPath || "/"));
                return;
            }
            root.disk = reading.fraction;
            root.diskUsedKb = reading.usedKb;
            root.diskTotalKb = reading.totalKb;
        }
    }

    // A different filesystem to watch: the reading on screen is now about
    // somewhere else, so it is taken again rather than left until the next
    // half-minute.
    Connections {
        target: Config

        function onKeyChanged(path, value, previous) {
            if (path === "dashboard.systemMonitor.diskPath" && root.watchers > 0)
                root.readDisk();
        }
    }
}
