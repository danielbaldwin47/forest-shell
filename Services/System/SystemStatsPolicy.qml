// What the machine is doing, read out of text (#50).
//
// #9 decided the system monitor samples natively — `/proc/stat`, `/proc/meminfo`,
// `/sys/class/hwmon`, `df` — rather than shelling out to dgop or btop, and this
// file is the whole of that decision: every reading the card and the bar module
// show is a parse of one of those four texts, plus the arithmetic that turns two
// consecutive `/proc/stat` snapshots into a percentage.
//
// On the QtQuick-only side of the line, so `tests/` reaches it (CLAUDE.md, seam
// 1). What is left next door in Services/System/SystemStats.qml is a `FileView`,
// a `Process` and a timer that must not be running while nobody is looking.
//
// ## Why CPU is the only one that needs two samples
//
// /proc/stat counts *ticks since boot*, so a single read says how busy the
// machine has been since it was switched on — which is a number that barely
// moves and is never what anyone means by "CPU". The percentage is the ratio of
// two deltas, so the first sample after the card opens can only produce a
// baseline; `cpuBusy` answers NaN for it rather than a zero, because a sparkline
// that opened with a bar at the floor would be claiming an idle machine.
//
// Memory, disk and temperature are all instantaneous, and are read as they are.
import QtQuick

QtObject {
    id: root

    /// The four readouts, in the order the card stacks them. Held here rather
    /// than in the card because the bar module shows a subset of the same list
    /// and the two must not disagree about what a row is called.
    readonly property var readouts: ["cpu", "memory", "disk", "temperature"]

    readonly property var labels: ({
        cpu: "CPU", memory: "Memory", disk: "Disk", temperature: "Temp"
    })

    readonly property var icons: ({
        cpu: "cpu", memory: "memory-stick", disk: "hard-drive",
        temperature: "thermometer"
    })

    /// How many samples a sparkline keeps. 60 at the default one-second cadence
    /// is a minute of history, which is the span over which "it is busy now"
    /// and "it has been busy" are different statements.
    readonly property int historyLength: 60

    // --- /proc/stat -----------------------------------------------------------

    /// The aggregate `cpu` line as `{ total, idle }`, or null.
    ///
    /// The first line only: the per-core `cpu0…` lines below it are the same
    /// counters split up, and a monitor that summed them would double every
    /// reading. `iowait` counts as idle — a machine waiting on a disk is not
    /// one whose processor is doing anything, and every top-like tool splits it
    /// the same way.
    function cpuTotals(text: string): var {
        const match = /^cpu[ \t]+(.*)$/m.exec(String(text ?? ""));
        if (!match)
            return null;

        const fields = match[1].trim().split(/\s+/).map(Number);
        if (fields.length < 4 || fields.some(isNaN))
            return null;

        let total = 0;
        for (const value of fields)
            total += value;

        return { total: total, idle: fields[3] + (fields.length > 4 ? fields[4] : 0) };
    }

    /// The fraction of the interval between two snapshots that was not idle.
    ///
    /// NaN when there is nothing to compare against — no previous sample, or
    /// two reads inside the same clock tick, which is what a fast reopen of the
    /// card produces. The caller draws a gap rather than a zero.
    function cpuBusy(previous: var, next: var): real {
        if (previous === null || previous === undefined
                || next === null || next === undefined)
            return NaN;

        const total = next.total - previous.total;
        const idle = next.idle - previous.idle;
        // A counter that went backwards is a suspend/resume or a read of a
        // different machine's file in a harness; either way it is not a
        // percentage.
        if (total <= 0 || idle < 0)
            return NaN;

        return Math.max(0, Math.min(1, (total - idle) / total));
    }

    // --- /proc/meminfo --------------------------------------------------------

    /// `{ totalKb, usedKb, fraction }`, or null.
    ///
    /// Used is total minus **MemAvailable**, not minus MemFree: page cache is
    /// memory the kernel will hand back the moment anything asks for it, and a
    /// monitor that counted it as used reports every Linux machine as nearly
    /// full. The `MemFree + Buffers + Cached` fallback is for kernels older
    /// than 3.14, which do not publish MemAvailable at all.
    function memory(text: string): var {
        const body = String(text ?? "");
        const field = name => {
            const match = new RegExp("^" + name + ":[ \\t]+(\\d+)", "m").exec(body);
            return match ? parseInt(match[1], 10) : NaN;
        };

        const total = field("MemTotal");
        if (isNaN(total) || total <= 0)
            return null;

        let available = field("MemAvailable");
        if (isNaN(available)) {
            const free = field("MemFree");
            const buffers = field("Buffers");
            const cached = field("Cached");
            if (isNaN(free))
                return null;
            available = free + (isNaN(buffers) ? 0 : buffers) + (isNaN(cached) ? 0 : cached);
        }

        const used = Math.max(0, total - available);
        return { totalKb: total, usedKb: used, fraction: Math.min(1, used / total) };
    }

    // --- df -------------------------------------------------------------------

    /// `df -P -k <path>`. POSIX output, so the columns cannot be rearranged by
    /// a `DF_BLOCK_SIZE` in the environment, and one filesystem is asked for
    /// rather than all of them — the card is about the disk the user's files
    /// are on, and a machine with fifteen mounts would otherwise need the card
    /// to choose one anyway.
    function diskCommand(path: string): var {
        const target = String(path ?? "").trim();
        return ["df", "-P", "-k", target === "" ? "/" : target];
    }

    /// `{ totalKb, usedKb, fraction }` out of that, or null.
    ///
    /// The last line, not the second, and the columns are found by anchoring on
    /// the capacity percentage rather than by counting from the left. Both are
    /// the same fault: `df` wraps a long device name — a LUKS mapper name is
    /// routinely long enough — onto a line of its own, and every column on the
    /// line below it then sits one place earlier than the header says. Anchored
    /// on the `53%`, `Used` is always two fields before it whether the name
    /// wrapped or not.
    function disk(text: string): var {
        const lines = String(text ?? "").trim().split("\n").filter(line => line.trim() !== "");
        if (lines.length < 2)
            return null;

        const fields = lines[lines.length - 1].trim().split(/\s+/);
        let capacity = -1;
        for (let i = 0; i < fields.length; i++)
            if (/^\d+%$/.test(fields[i]))
                capacity = i;
        if (capacity < 3)
            return null;

        const total = Number(fields[capacity - 3]);
        const used = Number(fields[capacity - 2]);
        if (isNaN(total) || isNaN(used) || total <= 0)
            return null;

        return { totalKb: total, usedKb: used, fraction: Math.min(1, used / total) };
    }

    // --- /sys/class/hwmon -----------------------------------------------------

    /// One shell line that prints `name<tab>path` for every hwmon temperature
    /// input on the machine. A shell and not a `FileView`, because this is a
    /// *directory listing* — hwmon numbers are assigned in probe order and are
    /// not stable across boots, so there is no fixed path to read.
    ///
    /// Run once, when the first watcher arrives — not at the deferred stage,
    /// because a shell nobody has opened the dashboard on should spawn nothing
    /// at all. What it finds is then read directly on every sample, which costs
    /// no process after that.
    function sensorProbeCommand(): var {
        return ["sh", "-c",
                "for d in /sys/class/hwmon/hwmon*; do "
              + "[ -r \"$d/name\" ] || continue; "
              + "n=$(cat \"$d/name\"); "
              + "for f in \"$d\"/temp*_input; do "
              + "[ -r \"$f\" ] && printf '%s\\t%s\\n' \"$n\" \"$f\"; "
              + "done; done"];
    }

    /// Which of those is the one worth showing.
    ///
    /// A desktop has half a dozen — the NVMe controller, the chipset, the
    /// wireless card — and the one a person means by "the temperature" is the
    /// CPU package. The order below is that preference: Intel's driver, then
    /// AMD's two, then the ACPI thermal zone every machine has as a last
    /// resort. Anything else is taken only if nothing preferred is present, so
    /// a machine this table has never heard of still gets a reading.
    function pickSensor(text: string): string {
        const preferred = ["coretemp", "k10temp", "zenpower", "cpu_thermal", "acpitz"];
        const found = {};
        let fallback = "";

        for (const line of String(text ?? "").split("\n")) {
            const parts = line.split("\t");
            if (parts.length < 2)
                continue;
            const name = parts[0].trim();
            const path = parts[1].trim();
            if (name === "" || path === "")
                continue;
            if (found[name] === undefined)
                found[name] = path;
            if (fallback === "")
                fallback = path;
        }

        for (const name of preferred)
            if (found[name] !== undefined)
                return found[name];
        return fallback;
    }

    /// Degrees Celsius out of a `temp*_input`. The file is millidegrees by the
    /// hwmon sysfs contract; a driver that ignores that and writes plain
    /// degrees would otherwise be reported as a 45,000° processor, so a small
    /// number is taken as it stands.
    function temperature(text: string): real {
        const value = Number(String(text ?? "").trim());
        if (isNaN(value) || value === 0)
            return NaN;
        return Math.abs(value) >= 1000 ? value / 1000 : value;
    }

    // --- history --------------------------------------------------------------

    /// One sample appended, oldest dropped past the cap.
    ///
    /// A new array every time, deliberately: the sparkline redraws on identity
    /// change, and mutating the array in place would leave it showing the
    /// history it was given at construction forever.
    function push(history: var, value: real, cap: int): var {
        const out = Array.isArray(history) ? history.slice() : [];
        out.push(isNaN(value) ? NaN : Math.max(0, Math.min(1, value)));
        const limit = Math.max(1, cap);
        return out.length > limit ? out.slice(out.length - limit) : out;
    }

    // --- words ----------------------------------------------------------------

    function percent(fraction: real): string {
        return isNaN(fraction) ? "—" : Math.round(fraction * 100) + "%";
    }

    /// Kilobytes as the unit a person would say it in. GiB and not GB, because
    /// this is memory read out of the kernel in kibibytes and converting to
    /// decimal gigabytes would make a 16 GiB machine report 17.2.
    function sizeLabel(kb: real): string {
        const value = Number(kb);
        if (isNaN(value))
            return "";
        if (value >= 1024 * 1024)
            return (value / (1024 * 1024)).toFixed(1) + " GiB";
        if (value >= 1024)
            return Math.round(value / 1024) + " MiB";
        return Math.round(value) + " KiB";
    }

    function temperatureLabel(celsius: real): string {
        return isNaN(celsius) ? "—" : Math.round(celsius) + "°C";
    }

    /// A temperature as a fraction of the range worth drawing. 30° is a cold
    /// idle machine and 95° is thermal throttling on every consumer part, so
    /// that is the span the sparkline uses — the alternative, 0–100, spends
    /// half its height on temperatures no running computer reaches.
    function temperatureFraction(celsius: real): real {
        if (isNaN(celsius))
            return NaN;
        return Math.max(0, Math.min(1, (celsius - 30) / 65));
    }

    // --- the rows -------------------------------------------------------------

    /// The card's four rows, built from one sample and the history behind it.
    ///
    /// Here rather than in the card because *which* rows exist and what each
    /// one says are the same decision as the parsing above — and because the
    /// row a machine cannot answer (no thermal sensor, which is most virtual
    /// machines) has to be dropped rather than drawn as a dash. A card whose
    /// row count depends on the hardware is the point.
    function rows(sample: var, history: var): var {
        const reading = sample || ({});
        const past = history || ({});
        const out = [];

        for (const key of root.readouts) {
            const fraction = key === "temperature"
                           ? root.temperatureFraction(reading.temperature)
                           : Number(reading[key]);
            // Absent rather than empty: a sensor this machine does not have is
            // not a row with nothing in it.
            if (fraction === undefined || fraction === null || isNaN(fraction))
                continue;

            out.push({
                key: key,
                label: root.labels[key],
                icon: root.icons[key],
                fraction: fraction,
                value: key === "temperature"
                       ? root.temperatureLabel(reading.temperature)
                       : root.percent(fraction),
                detail: root.detail(key, reading),
                history: Array.isArray(past[key]) ? past[key] : []
            });
        }
        return out;
    }

    /// The second line of a row: what the percentage is a percentage *of*.
    /// Only where there is one — a processor at 40% is not 40% of anything a
    /// number would help with.
    function detail(key: string, reading: var): string {
        const value = reading || ({});
        if (key === "memory" && value.memoryUsedKb !== undefined)
            return root.sizeLabel(value.memoryUsedKb) + " of " + root.sizeLabel(value.memoryTotalKb);
        if (key === "disk" && value.diskUsedKb !== undefined)
            return root.sizeLabel(value.diskUsedKb) + " of " + root.sizeLabel(value.diskTotalKb);
        return "";
    }

    /// The bar module's readout — the same sampler, one line wide (#9's
    /// optional system-monitor module). CPU and RAM only: a disk that moves
    /// twice a day and a temperature nobody can act on are not worth the bar's
    /// horizontal space, and the card is one click away.
    function barLabel(sample: var): string {
        const reading = sample || ({});
        const cpu = Number(reading.cpu);
        const memory = Number(reading.memory);
        if (isNaN(cpu) && isNaN(memory))
            return "";
        return "CPU " + root.percent(cpu) + "  RAM " + root.percent(memory);
    }

    // --- the log lines --------------------------------------------------------
    //
    // #81: a lifecycle nothing logs is a lifecycle with two candidate causes.
    // Sampling starting and stopping is exactly that shape — the acceptance
    // criterion "sampling verifiably stops when the dashboard is closed" is
    // checked by reading these out of the log (`tools/drawer-harness.sh`).

    function watching(watchers: int, intervalMs: int): string {
        return "sampling every " + intervalMs + "ms for " + watchers + " watcher(s)";
    }

    function idle(): string {
        return "sampling stopped — nothing is watching";
    }

    function summary(sample: var): string {
        const reading = sample || ({});
        return "cpu " + root.percent(Number(reading.cpu))
             + ", memory " + root.percent(Number(reading.memory))
             + ", disk " + root.percent(Number(reading.disk))
             + ", temp " + root.temperatureLabel(Number(reading.temperature));
    }
}
