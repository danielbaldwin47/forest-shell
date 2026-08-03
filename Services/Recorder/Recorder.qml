pragma Singleton

// Screen recording (#52) — start, stop, and fall back when the GPU cannot.
//
//     Recorder.start("ipc")          record the focused monitor
//     Recorder.startRegion("ipc")    put the picker up, record what it hands back
//     Recorder.stop("ipc")           SIGINT, flush, done
//     Recorder.toggle("keybind")     whichever of the two applies
//
// Every *decision* is RecorderPolicy.qml next door, where `tests/` can reach it
// (CLAUDE.md, seam 1) — both argvs, which engine runs, whether a dead engine is
// worth retrying, the four states. What is here is the three things that need a
// subprocess or a compositor: the two probes, the encoder itself, and the
// elapsed clock the bar and the control centre bind to.
//
// ## The fallback is the whole point of the ticket, and it has two shapes
//
// `gpu-screen-recorder` can be absent, and it can be present and unable to
// initialise — the T480's VAAPI driver is a separate package from the tool. The
// first shape has no exit code at all to read (a `Process` whose binary does not
// exist emits no `exited` in Quickshell 0.3.0, only `running` going false —
// #40), and the second exits non-zero in about 200ms. `RecorderPolicy.
// shouldFallback` takes both facts and answers once; this file's job is to feed
// it honestly and to retry exactly one hop, so a broken machine records in
// software rather than not at all.
//
// ## A region comes from the picker, not from slurp
//
// #51 already owns a freeze-and-drag on a layer surface with window snapping.
// Asking `slurp` for the same rectangle would be a second selection UI with
// different keys and no snapping, so the picker grew a mode instead: it hands a
// rectangle back rather than photographing it (`Screenshot.pickRegion`), and
// this is its only consumer.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Services.Compositor
import qs.Services.Screenshot

Singleton {
    id: root

    readonly property RecorderPolicy policy: RecorderPolicy {}

    /// This service's settings, walked once — the same reason
    /// Services/Screenshot/Screenshot.qml walks its own.
    readonly property var settings: Config.values.system?.recording ?? ({})

    // --- what the surfaces bind to -------------------------------------------

    /// One of `idle`, `starting`, `recording`, `stopping`. Only `advance()`
    /// writes it, so every transition goes through the policy's table.
    property string state: root.policy.idle

    /// Whether the shell should show itself as recording — true from the press
    /// rather than from the encoder's first frame, so the bar dot answers the
    /// keybind immediately. See `RecorderPolicy.isActive`.
    readonly property bool active: root.policy.isActive(root.state)

    /// Milliseconds since the encoder was asked to start. Ticks once a second
    /// while recording and stops dead at idle, so nothing is running when
    /// nothing is recording.
    property int elapsedMs: 0

    /// The file the current — or last — recording is written to.
    property string lastFile: ""

    /// Which encoder this shell would use, or `""` when neither is installed.
    /// The control-centre tile reads it to say "GPU" or "Software" before the
    /// press, which is a question nothing else in the shell can answer.
    readonly property string engine:
        root.policy.engineFor(root.settings.engine, root.available)

    readonly property bool canRecord: root.engine !== ""

    /// engine name → on PATH. Filled by the two probes below.
    property var available: ({})

    /// Whether this machine can hand an encoder a working SIGINT — see
    /// `RecorderPolicy.signalReset` for why that is a question at all. False
    /// until the probe answers, which is the safe direction: a recording
    /// started before it lands runs bare and stops via the watchdog, rather
    /// than being spawned behind a prefix that turns out not to exist.
    property bool canResetSignals: false

    // --- starting ------------------------------------------------------------

    /// Record the focused monitor, whole.
    function start(reason: string): bool {
        return root.begin(null, reason);
    }

    /// Put the picker up and record whatever rectangle comes back. Returns
    /// whether the picker opened, not whether a recording started — the
    /// rectangle arrives later, or never if the user presses Escape.
    function startRegion(reason: string): bool {
        return root.startRegionAfter(reason, 0);
    }

    /// The same, with the picker's freeze held back for `settleMs` — the
    /// launcher's fade, passed in by the caller for the reason
    /// `Screenshot.openAfter` explains.
    function startRegionAfter(reason: string, settleMs: int): bool {
        if (!root.guardStart())
            return false;
        return Screenshot.pickRegion("recorder: " + reason, settleMs);
    }

    /// The checks both entry points share, so the refusals cannot drift apart.
    function guardStart(): bool {
        if (!root.policy.canStart(root.state)) {
            // Two different refusals, because they resolve differently: one
            // waits for the user, the other for the muxer.
            Logger.log("recorder", root.state === root.policy.stopping
                                   ? root.policy.stillStopping()
                                   : root.policy.alreadyRecording());
            return false;
        }
        if (!root.canRecord) {
            Logger.warn("recorder", root.policy.noEngine());
            return false;
        }
        return true;
    }

    /// The real start. `region` is null for a whole-screen capture.
    function begin(region: var, reason: string): bool {
        if (!root.guardStart())
            return false;

        const monitor = Compositor.monitorSnapshot;
        if (!monitor) {
            Logger.warn("recorder", root.policy.noMonitor());
            return false;
        }

        let wanted = null;
        if (region) {
            if (!root.policy.isRegion(region)) {
                Logger.warn("recorder", root.policy.tooSmall(region));
                return false;
            }
            // Odd sides are not a soft failure on a hardware encoder — see
            // `RecorderPolicy.evenSides`. Trimmed here and said out loud,
            // because an unexplained missing pixel row is worse than a line.
            wanted = root.policy.evenSides(region);
            if (wanted.width !== root.policy.rect(region).width
                || wanted.height !== root.policy.rect(region).height)
                Logger.log("recorder", root.policy.evened(region, wanted));
        }

        const dir = root.policy.directory(root.settings.directory, Paths.home);
        const container = root.policy.container(root.settings.container);

        root.pending = {
            file: root.policy.path(dir, root.policy.filename(new Date(), container)),
            output: String(monitor.name ?? ""),
            region: wanted,
            framerate: root.settings.framerate,
            audio: root.settings.audio,
            quality: root.settings.quality,
            container: container
        };
        root.attempt = root.engine;
        root.lastFile = root.pending.file;
        root.advance("start");

        // The directory is made before the encoder runs rather than beside it:
        // both tools create their output file at start and neither creates the
        // directory, so a missing one is an immediate non-zero exit that
        // `shouldFallback` would read as a broken GPU encoder.
        seed.command = ["sh", "-c", "mkdir -p \"$1\"", "sh", dir];
        seed.running = true;
        return true;
    }

    // --- stopping ------------------------------------------------------------

    /// Stop, and keep the file. SIGINT rather than SIGTERM — see
    /// RecorderPolicy's header for what SIGTERM leaves on disk.
    function stop(reason: string): bool {
        if (!root.policy.canStop(root.state)) {
            Logger.log("recorder", root.policy.notRecording());
            return false;
        }

        root.advance("stop");
        Logger.log("recorder", root.policy.signalledStop());

        // Stopping something that has not spawned yet: there is no process to
        // signal, so the state is unwound here rather than waiting for an exit
        // that will never come.
        if (!encoder.running) {
            seed.running = false;
            root.finish(0, false);
            return true;
        }

        encoder.signal(root.policy.stopSignal);
        muxWatchdog.restart();
        return true;
    }

    function toggle(reason: string): bool {
        return root.policy.canStop(root.state) ? root.stop(reason) : root.start(reason);
    }

    // --- internals -----------------------------------------------------------

    /// The run in flight, as `argv()` wants it. Held rather than recomputed, so
    /// a fallback retry records the same rectangle to the same file with the
    /// other engine.
    property var pending: null

    /// The engine this attempt is using, which is not always `engine`: after a
    /// fallback it is the one after it.
    property string attempt: ""

    /// When the encoder was spawned, for the elapsed clock and — more sharply —
    /// for `shouldFallback`, which needs to tell "died during init" from "ran
    /// for twenty minutes and then died".
    property double startedAt: 0

    function advance(event: string): void {
        root.state = root.policy.nextState(root.state, event);
    }

    /// Everything that has to happen once the encoder is gone, however it went.
    function finish(code: int, report: bool): void {
        clock.stop();
        muxWatchdog.stop();
        root.advance("exited");
        root.pending = null;
        root.attempt = "";
        if (report)
            Logger.log("recorder", root.policy.stopped(root.lastFile, root.elapsedMs));
        root.elapsedMs = 0;
    }

    Process {
        id: seed

        onExited: code => {
            if (!root.policy.isActive(root.state))
                return;
            if (code !== 0) {
                Logger.warn("recorder", root.policy.directoryFailed(code));
                root.finish(code, false);
                return;
            }
            root.spawn();
        }
    }

    /// Run `attempt` against `pending`. Called for the first attempt and again
    /// for the one fallback hop.
    function spawn(): void {
        if (!root.pending || root.attempt === "")
            return;

        if (root.policy.audioIsNarrowed(root.attempt, root.settings.audio))
            Logger.log("recorder",
                       root.policy.audioNarrowed(root.policy.audio(root.settings.audio)));

        Logger.log("recorder", root.policy.startingWith(root.attempt, root.pending.file,
                                                        root.pending.region));

        encoder.started = false;
        root.startedAt = Date.now();
        // Assigned, never bound: settings hot-reload, and a binding that
        // re-evaluated mid-recording would kill the encoder and truncate the
        // file (#78).
        encoder.command = root.policy.launchArgv(root.attempt, root.pending,
                                                 root.canResetSignals);
        encoder.running = true;
    }

    Process {
        id: encoder

        property bool started: false

        onStarted: {
            encoder.started = true;
            root.advance("started");
            root.elapsedMs = 0;
            clock.start();
            Logger.log("recorder", root.policy.encodingStarted(root.attempt));
        }

        onExited: code => root.settle(code, encoder.started);

        onRunningChanged: {
            // False without ever having started is the missing-binary case, and
            // the only one with no exit code to read (#40). `onExited` does not
            // fire for it, so the same settlement is reached from here.
            if (encoder.running || encoder.started)
                return;
            root.settle(0, false);
        }
    }

    /// What to do with an encoder that is no longer running: retry on the other
    /// engine, or report and go idle. The one place the fallback happens.
    function settle(code: int, started: bool): void {
        if (root.state === root.policy.idle)
            return;

        const elapsed = Math.max(0, Date.now() - root.startedAt);
        const stopping = root.state === root.policy.stopping;
        const from = root.attempt;

        // A recording the user stopped is never retried, whatever it exited
        // with: the file is written and a second engine would start over it.
        if (!stopping && root.policy.shouldFallback(from, started, code, elapsed)) {
            const next = root.policy.fallbackFor(from);
            if (root.available[next] === true) {
                Logger.warn("recorder",
                            root.policy.fellBack(from, next,
                                                 root.policy.fallbackReason(started, code)));
                clock.stop();
                root.attempt = next;
                root.state = root.policy.starting;
                root.spawn();
                return;
            }
            Logger.warn("recorder", root.policy.fellBack(from, next,
                                                         root.policy.fallbackReason(started, code)));
            Logger.warn("recorder", root.policy.noEngine());
            root.finish(code, false);
            return;
        }

        if (!stopping && (!started || code !== 0)) {
            // Ran and broke, or the last engine could not start either. Not
            // retried — see `shouldFallback` — so this is the whole report.
            Logger.warn("recorder", started ? root.policy.failed(from, code)
                                            : root.policy.noEngine());
            root.finish(code, false);
            return;
        }

        root.finish(code, true);
    }

    // The elapsed clock. One second, because it draws `M:SS`; running only
    // while something is recording, because a timer that ticks all session for
    // a readout nobody is looking at is the cost SystemMonitor.qml is careful
    // about.
    Timer {
        id: clock
        interval: 1000
        repeat: true
        onTriggered: root.elapsedMs = Math.max(0, Date.now() - root.startedAt)
    }

    // The deadline on the flush. A stopped encoder that never exits would leave
    // the state at `stopping` forever, and every later press would answer "not
    // recording" with nothing in the log saying why (#81).
    Timer {
        id: muxWatchdog
        interval: root.policy.stopTimeoutMs
        repeat: false
        onTriggered: {
            Logger.warn("recorder", root.policy.stopTimedOut());
            encoder.signal(9);
            root.finish(0, false);
        }
    }

    // --- the region picker's answer ------------------------------------------

    Connections {
        target: Screenshot

        function onRegionPicked(region, screen, scale) {
            root.begin({ x: region.x, y: region.y,
                         width: region.width, height: region.height }, "picker");
        }

        function onRegionCancelled() {
            Logger.log("recorder", root.policy.pickCancelled());
        }
    }

    // --- the probes ----------------------------------------------------------
    //
    // One `Process` each, never one reassigned: reassigning `command` on a
    // running Process kills the run in flight (#78). Absence of `started` is
    // the entire signal — a missing binary emits no `exited` at all (#40) — so
    // the flag a probe sets is not read from an exit code.

    Component {
        id: probeRunner
        Process {
            required property string engine
            property bool started: false
            onStarted: started = true
            onRunningChanged: {
                if (running)
                    return;
                root.mark(engine, started);
                destroy();
            }
        }
    }

    function mark(engine: string, present: bool): void {
        // A fresh object rather than a mutation: `available` is read by a
        // binding (`engine`), and mutating a JS object in place does not
        // re-evaluate it.
        const next = {};
        for (const key in root.available)
            next[key] = root.available[key];
        next[engine] = present;
        root.available = next;

        Logger.log("recorder", root.policy.probed(engine, present));
        if (!root.canRecord && Object.keys(next).length === root.policy.engines.length)
            Logger.warn("recorder", root.policy.noEngine());
    }

    /// The one probe that reads an exit code rather than just `started`: an
    /// `env` too old for `--default-signal` is present and exits 125, which is
    /// the opposite answer from `started` alone.
    Process {
        id: signalResetProbe
        property bool started: false
        command: root.policy.signalReset.concat(["true"])
        running: true
        onStarted: signalResetProbe.started = true
        onExited: code => {
            root.canResetSignals = signalResetProbe.started && code === 0;
            if (!root.canResetSignals)
                Logger.warn("recorder", root.policy.signalResetMissing());
        }
        onRunningChanged: {
            if (signalResetProbe.running || signalResetProbe.started)
                return;
            root.canResetSignals = false;
            Logger.warn("recorder", root.policy.signalResetMissing());
        }
    }

    function probe(): void {
        for (const engine of root.policy.engines) {
            const runner = probeRunner.createObject(root, {
                engine: engine,
                command: [engine, "--version"]
            });
            if (runner)
                runner.running = true;
        }
    }

    // --- the door from outside -----------------------------------------------

    // No `show`, `list` or `call` on this target: the `qs ipc` client parses
    // those as its own subcommands and exits 0 without calling anything (#77).
    IpcHandler {
        target: "recorder"

        function start(): bool {
            return root.start("ipc");
        }

        function stop(): bool {
            return root.stop("ipc");
        }

        function toggle(): bool {
            return root.toggle("ipc");
        }

        function isRecording(): bool {
            return root.active;
        }

        /// Record a rectangle without a drag — a keybind for a fixed region,
        /// and the door tools/recorder-harness.sh drives, because a harness
        /// cannot hold a mouse button down across two positions.
        function region(x: int, y: int, width: int, height: int): bool {
            return root.begin({ x: x, y: y, width: width, height: height }, "ipc region");
        }

        /// Put the picker up and record what it hands back.
        function pick(): bool {
            return root.startRegion("ipc");
        }

        /// What the last recording was written to — what a script chains off,
        /// and what the harness reads to find the file it should assert on.
        function last(): string {
            return root.lastFile;
        }

        /// Which encoder would run, or "" for none. The harness asserts the
        /// fallback engaged by reading this rather than by parsing the log.
        function using(): string {
            return root.attempt !== "" ? root.attempt : root.engine;
        }
    }

    Component.onCompleted: {
        root.probe();
        Logger.stage(root.policy.armed());
    }
}
