// Every decision screen recording makes (#52), as pure functions.
//
// Recording is a long-lived subprocess with a settings-shaped command line and
// two encoders that do not agree on a single flag. What is *wrong* about a
// recording is almost never the `Process` — it is which argv reached the tool,
// which tool was picked, whether the fallback should have engaged, and where
// the file went. All of that is here, where `tests/` can pose it (CLAUDE.md,
// seam 1), and the service next door keeps only the subprocess and the state.
//
// ## Two encoders, and they are not interchangeable
//
// `gpu-screen-recorder` is the one the ticket wants: it encodes on the GPU
// (VAAPI on the T480's iGPU, NVENC/AMF on the desktop's dGPU) so a 60fps
// capture costs a few percent of one core instead of a whole CPU. It is also
// the one most likely to be absent, and the one that can *install fine and
// still fail*, because it needs a working VA-API driver underneath it and that
// is a property of the machine rather than of the package.
//
// `wf-recorder` is the fallback: present in more distributions, software
// encoding by default, and it takes a wlr screencopy frame like every other
// Wayland tool. It is slower and hotter and it is what you want when the
// alternative is no recording at all.
//
// They differ in every flag that matters:
//
//                     gpu-screen-recorder        wf-recorder
//   output file       -o FILE                    -f FILE
//   which monitor     -w NAME                    -o NAME
//   a region          -w region -region WxH+X+Y  -g "X,Y WxH"
//   framerate         -f N                       -r N
//   audio             -a DEVICE (repeatable)     --audio (one device)
//   container         -c mp4                     from the file extension
//   quality           -q very_high               no equivalent
//
// Note `-o` and `-f` mean *opposite things* to the two tools: `-f` is the
// framerate to one and the output file to the other. Building both argvs by
// hand in the service was how that gets crossed; building them here means
// `tests/` catches it.
//
// ## Stopping is a signal, and it must be SIGINT
//
// Neither tool has a stop command — you signal the process. It must be SIGINT
// (2) and not SIGTERM (15): both tools install a handler on SIGINT that stops
// the encoder, flushes the muxer and writes the container's index, and both
// die on SIGTERM without doing any of it. A recording stopped with SIGTERM
// leaves an mp4 with no moov atom, which is a file that exists, has the right
// size, and will not play — the worst of the three possible outcomes, because
// nothing about it looks like a failure until you try to watch it.
//
// Imports nothing but QtQuick, so `tests/` can reach it.
import QtQuick

QtObject {
    id: policy

    // --- the two engines -----------------------------------------------------

    readonly property string gsr: "gpu-screen-recorder"
    readonly property string wf: "wf-recorder"

    /// The engines in preference order. `auto` walks this; an explicit setting
    /// starts at its own choice and then walks the rest, because a machine
    /// configured for an engine it does not have should still record.
    readonly property var engines: [policy.gsr, policy.wf]

    /// Which encoder actually runs, given what is configured and what is
    /// installed.
    ///
    /// `available` maps engine name → bool, filled in by the service's probes.
    /// Returns `""` when neither is installed, which is the one case that is a
    /// refusal rather than a degraded run.
    ///
    /// An explicit engine that is missing does *not* refuse: it falls through
    /// to the other one and the caller logs that it did (`fellBack`). The
    /// setting is a preference about how to record, not a demand to fail.
    function engineFor(configured: var, available: var): string {
        const have = available ?? ({});
        const wanted = String(configured ?? "auto").trim();

        const order = wanted === "" || wanted === "auto"
            ? policy.engines
            : [wanted].concat(policy.engines.filter(e => e !== wanted));

        for (const engine of order) {
            if (have[engine] === true)
                return engine;
        }
        return "";
    }

    /// Whether a run that has just ended should be retried on the other engine.
    ///
    /// Two failures look identical from the outside and only one is worth a
    /// retry, so both facts are needed:
    ///
    ///   - `started` false — the binary is not on PATH. In Quickshell 0.3.0 a
    ///     `Process` whose command does not exist emits no `exited` at all, so
    ///     absence of `started` is the whole signal (#40, Services/README.md).
    ///   - a non-zero exit inside `initGraceMs` — it ran and could not
    ///     initialise. This is the VAAPI case: `gpu-screen-recorder` is
    ///     installed, the driver underneath it is not, and it exits in well
    ///     under a second having written nothing.
    ///
    /// A non-zero exit *after* the grace window is a recording that ran and
    /// then broke, and retrying that would silently start a second file
    /// minutes into the first one.
    ///
    /// The fallback is one hop, never a cycle: an engine that is already the
    /// last in `engines` has nothing to fall back to.
    function shouldFallback(engine: string, started: bool, code: int, elapsedMs: int): bool {
        if (policy.fallbackFor(engine) === "")
            return false;
        if (!started)
            return true;
        return code !== 0 && elapsedMs < policy.initGraceMs;
    }

    /// How long an engine gets to prove it initialised. Two and a half seconds:
    /// a VAAPI init failure lands in ~200ms, and the slowest healthy start
    /// measured — NVENC on a cold GPU — was under a second.
    readonly property int initGraceMs: 2500

    /// The engine after this one, or `""` at the end of the line.
    function fallbackFor(engine: string): string {
        const at = policy.engines.indexOf(String(engine ?? ""));
        if (at < 0 || at + 1 >= policy.engines.length)
            return "";
        return policy.engines[at + 1];
    }

    /// The signal that stops a recording *and keeps the file* — see the header.
    /// SIGINT, and the number rather than the name because `Process.signal()`
    /// takes an int.
    readonly property int stopSignal: 2

    /// The prefix every encoder is launched behind, and the reason it exists.
    ///
    /// **Quickshell spawns its children with SIGINT and SIGQUIT ignored.**
    /// Measured on 0.3.0 from inside a `Process`: the child's
    /// `/proc/self/status` reports `SigIgn: 0000000000000006`, which is bits 2
    /// and 3 — SIGINT and SIGQUIT. A disposition of *ignore* is inherited
    /// across `exec` (unlike a handler, which resets to default), and a process
    /// that starts with SIGINT ignored cannot install a handler for it at all:
    /// POSIX says a signal ignored on entry stays ignored, and both `bash` and
    /// libc's `signal()` honour that.
    ///
    /// So `Process.signal(2)` on a bare encoder is delivered and discarded.
    /// tools/recorder-harness.sh caught this as a stop that did nothing: the
    /// service logged that it had signalled, the encoder kept writing, and ten
    /// seconds later the mux watchdog killed it — which is exactly the
    /// truncated file this whole design is trying to avoid.
    ///
    /// SIGTERM is not the way out. Neither tool flushes its muxer on it — that
    /// is the header's whole argument — so switching signals would trade a
    /// recording that will not stop for one that will not play.
    ///
    /// `env --default-signal=INT` restores the default disposition and then
    /// `exec`s in place, so the process the shell holds a pid for is still the
    /// encoder and `signal()` still reaches the right process. It is coreutils
    /// 9.2 and newer; the service probes for it and says so when it is missing,
    /// because on an older machine the stop degrades to the watchdog.
    readonly property var signalReset: ["env", "--default-signal=INT"]

    /// The argv as it is actually spawned. Separate from `argv()` so the two
    /// questions stay separate: `argv()` is "what does this encoder want",
    /// this is "what does this machine need in front of it".
    function launchArgv(engine: string, opts: var, canReset: bool): var {
        const command = policy.argv(engine, opts);
        if (command.length === 0)
            return [];
        return canReset === true ? policy.signalReset.concat(command) : command;
    }

    /// How long a stopped encoder gets to flush and write its index before the
    /// shell stops waiting for it. Muxing an hour of 4K takes noticeably longer
    /// than muxing ten seconds, so this is generous; a recorder that misses it
    /// has hung, and the state must not stay `stopping` forever — that is the
    /// #81 shape, where every later press answers "already recording".
    readonly property int stopTimeoutMs: 10000

    // --- the command line ----------------------------------------------------

    /// The argv for an engine. `opts` is
    /// `{ file, output, region, framerate, audio, quality, container }`;
    /// `region` is null for a whole-screen capture.
    function argv(engine: string, opts: var): var {
        switch (String(engine ?? "")) {
        case policy.gsr: return policy.gsrArgv(opts ?? ({}));
        case policy.wf:  return policy.wfArgv(opts ?? ({}));
        }
        return [];
    }

    /// `gpu-screen-recorder -w <what> [-region WxH+X+Y] -f <fps> -q <quality>
    ///  -c <container> [-a <device>…] -o <file>`
    ///
    /// `-w region` is a literal window name and not a placeholder: the tool
    /// takes the word `region` where it would otherwise take a monitor name,
    /// and reads the rectangle out of `-region`. Getting that wrong records a
    /// monitor called "region", which does not exist, and the tool exits
    /// immediately — a fallback to `wf-recorder` on a machine whose GPU encoder
    /// was fine.
    function gsrArgv(opts: var): var {
        const it = opts ?? ({});
        const out = ["gpu-screen-recorder"];

        if (it.region) {
            out.push("-w", "region", "-region", policy.gsrRegion(it.region));
        } else {
            out.push("-w", String(it.output ?? "screen"));
        }

        out.push("-f", String(policy.framerate(it.framerate)));
        out.push("-q", policy.quality(it.quality));
        out.push("-c", policy.container(it.container));

        for (const device of policy.gsrAudio(it.audio))
            out.push("-a", device);

        out.push("-o", String(it.file ?? ""));
        return out;
    }

    /// `wf-recorder -o <monitor> [-g "X,Y WxH"] -r <fps> [--audio] -f <file>`
    ///
    /// No quality flag, deliberately: `wf-recorder` exposes codec parameters
    /// rather than presets, and mapping four preset words onto `-p crf=…`
    /// values would be inventing a policy the fallback path does not need. The
    /// fallback's job is to produce a playable file on a machine where the GPU
    /// encoder does not work, and it does that at its own defaults.
    ///
    /// `-g` is also given when recording a whole screen and there is a region,
    /// never both `-g` and a bare `-o`-only capture, because the geometry is
    /// already in the compositor's layout space (ScreenshotPolicy's header) and
    /// `wf-recorder` reads it in the same space `grim -g` does.
    function wfArgv(opts: var): var {
        const it = opts ?? ({});
        const out = ["wf-recorder", "-o", String(it.output ?? "")];

        if (it.region)
            out.push("-g", policy.wfRegion(it.region));

        out.push("-r", String(policy.framerate(it.framerate)));

        // One device or none. `wf-recorder` takes a single `--audio`, so the
        // four-way audio setting collapses to a boolean here and the log says
        // so — see `audioNarrowed()`.
        if (policy.wantsAudio(it.audio))
            out.push("--audio");

        // Last, and `-f` is the *file* to this tool. See the header table.
        out.push("-f", String(it.file ?? ""));
        return out;
    }

    /// `WxH+X+Y` — gpu-screen-recorder's geometry, which is the X11 form.
    function gsrRegion(rect: var): string {
        const it = policy.rect(rect);
        return it.width + "x" + it.height + "+" + it.x + "+" + it.y;
    }

    /// `X,Y WxH` — wf-recorder's geometry, which is grim's and slurp's form.
    function wfRegion(rect: var): string {
        const it = policy.rect(rect);
        return it.x + "," + it.y + " " + it.width + "x" + it.height;
    }

    /// A rectangle with integer sides, however it arrived. Both geometries are
    /// strings handed to another program, so a half-pixel from a pointer would
    /// become the literal text `640.5` on a command line and the tool would
    /// refuse to parse it.
    function rect(value: var): var {
        const it = value ?? ({});
        return {
            x: Math.round(Number(it.x) || 0),
            y: Math.round(Number(it.y) || 0),
            width: Math.max(0, Math.round(Number(it.width) || 0)),
            height: Math.max(0, Math.round(Number(it.height) || 0))
        };
    }

    /// Below this in either dimension, a region is not worth encoding — the
    /// same floor the picker uses to tell a drag from a click, and for the same
    /// reason. Both encoders additionally want *even* sides, which is the next
    /// function.
    readonly property int minSide: 8

    function isRegion(value: var): bool {
        const it = policy.rect(value);
        return it.width >= policy.minSide && it.height >= policy.minSide;
    }

    /// A region with even sides. Every hardware H.264/HEVC encoder in play here
    /// wants dimensions divisible by two — chroma is subsampled 2×2 — and an
    /// odd width is not a soft failure: `gpu-screen-recorder` exits during
    /// init, which `shouldFallback` would then read as a broken GPU encoder and
    /// answer by falling back to `wf-recorder`, which would fail identically.
    /// One odd pixel would look exactly like a missing VAAPI driver.
    ///
    /// Rounded *down*, so the region never grows past what was selected and off
    /// the edge of the screen it was clamped to.
    function evenSides(value: var): var {
        const it = policy.rect(value);
        return {
            x: it.x,
            y: it.y,
            width: it.width - (it.width % 2),
            height: it.height - (it.height % 2)
        };
    }

    // --- the settings, coerced for a command line ----------------------------

    function framerate(value: var): int {
        const n = Math.round(Number(value));
        if (!isFinite(n) || n < 1)
            return 60;
        return Math.min(240, n);
    }

    readonly property var qualities: ["medium", "high", "very_high", "ultra"]

    function quality(value: var): string {
        const set = String(value ?? "").trim();
        return policy.qualities.indexOf(set) >= 0 ? set : "very_high";
    }

    readonly property var containers: ["mp4", "mkv"]

    function container(value: var): string {
        const set = String(value ?? "").trim();
        return policy.containers.indexOf(set) >= 0 ? set : "mp4";
    }

    readonly property var audioSources: ["none", "desktop", "mic", "both"]

    function audio(value: var): string {
        const set = String(value ?? "").trim();
        return policy.audioSources.indexOf(set) >= 0 ? set : "desktop";
    }

    function wantsAudio(value: var): bool {
        return policy.audio(value) !== "none";
    }

    /// Whether an engine can honour the audio setting as written.
    ///
    /// `wf-recorder` takes one `--audio` and records the default device, so
    /// `desktop` lands exactly and `mic` and `both` do not — the user asked for
    /// the microphone and will get the speakers. That is a difference between
    /// the two engines that is inaudible until playback, so the caller says it
    /// out loud (`audioNarrowed`).
    function audioIsNarrowed(engine: string, value: var): bool {
        if (String(engine ?? "") !== policy.wf)
            return false;
        const set = policy.audio(value);
        return set === "mic" || set === "both";
    }

    /// The PulseAudio device names gpu-screen-recorder takes, one `-a` each.
    ///
    /// `default_output` and `default_input` are the tool's own aliases for
    /// whatever the sink and source currently are, which is what makes them the
    /// right answer here: a real device name baked into settings.json stops
    /// being real the first time a headset is plugged in.
    ///
    /// Separate flags rather than `-a a|b`: the pipe form merges both into one
    /// track, and separate tracks are what lets the desktop audio be muted in
    /// an editor without losing the commentary.
    function gsrAudio(value: var): var {
        switch (policy.audio(value)) {
        case "desktop": return ["default_output"];
        case "mic":     return ["default_input"];
        case "both":    return ["default_output", "default_input"];
        }
        return [];
    }

    // --- where it lands ------------------------------------------------------

    /// The directory recordings are written to.
    ///
    /// `~` is expanded here and not left to a shell, for the reason
    /// ScreenshotPolicy.directory gives: `Process` takes an argv, so a literal
    /// `~/Videos` would create a directory named `~`.
    function directory(configured: var, home: string): string {
        const set = String(configured ?? "").trim();
        if (set === "")
            return home + "/Videos/Recordings";
        if (set === "~")
            return home;
        if (set.startsWith("~/"))
            return home + set.slice(1);
        return set;
    }

    /// The timestamp in a file name — the same sortable, `:`-free and space-free
    /// form screenshots use, so the two directories sort the same way.
    function stamp(date: var): string {
        const d = date instanceof Date ? date : new Date();
        const pad = n => (n < 10 ? "0" : "") + n;
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
            + "T" + pad(d.getHours()) + "-" + pad(d.getMinutes()) + "-" + pad(d.getSeconds());
    }

    function filename(date: var, containerValue: var): string {
        return "forest-" + policy.stamp(date) + "." + policy.container(containerValue);
    }

    function path(dir: string, name: string): string {
        const base = String(dir ?? "");
        return (base.endsWith("/") ? base.slice(0, -1) : base) + "/" + name;
    }

    // --- what is on screen while it runs -------------------------------------

    /// Elapsed time, as the bar dot and the control-centre tile say it.
    ///
    /// `M:SS` under an hour and `H:MM:SS` over it, rather than always the long
    /// form: the bar is horizontal space and `0:07` is the answer for the first
    /// hour of every recording anyone makes.
    function formatDuration(ms: var): string {
        const total = Math.max(0, Math.floor(Number(ms) / 1000) || 0);
        const pad = n => (n < 10 ? "0" : "") + n;
        const seconds = total % 60;
        const minutes = Math.floor(total / 60) % 60;
        const hours = Math.floor(total / 3600);
        if (hours > 0)
            return hours + ":" + pad(minutes) + ":" + pad(seconds);
        return minutes + ":" + pad(seconds);
    }

    /// What the optional bar module shows. Empty while idle, because the module
    /// hides itself rather than sitting there as a dark dot claiming nothing —
    /// the same rule SystemMonitor.qml follows before its first sample.
    function barLabel(active: bool, ms: var): string {
        return active ? policy.formatDuration(ms) : "";
    }

    /// The control-centre tile's second line. It names the engine while idle,
    /// because "which encoder would this use" is the question the tile can
    /// answer before you press it and nothing else in the shell can; and the
    /// elapsed time while running, because that is the only question after.
    function tileDetail(active: bool, ms: var, engine: string, available: bool): string {
        if (active)
            return policy.formatDuration(ms);
        if (!available)
            return "No recorder";
        return String(engine ?? "") === policy.wf ? "Software" : "GPU";
    }

    // --- the state machine ---------------------------------------------------
    //
    // Four states, and the two transient ones are why: a recording that is
    // starting has a subprocess but no file yet, and one that is stopping has
    // been signalled but has not finished muxing. Collapsing either into a
    // boolean is how a second press lands in the gap and starts a second
    // encoder over the top of the first one's output file.

    readonly property string idle: "idle"
    readonly property string starting: "starting"
    readonly property string recording: "recording"
    readonly property string stopping: "stopping"

    /// Whether a press should be honoured, and what it means. One function
    /// rather than the caller testing the state twice, because "can I start"
    /// and "can I stop" are the same question asked from the two ends.
    function canStart(state: string): bool {
        return String(state ?? "") === policy.idle;
    }

    function canStop(state: string): bool {
        const at = String(state ?? "");
        return at === policy.recording || at === policy.starting;
    }

    /// Whether the shell should show itself as recording. `starting` counts:
    /// the dot appearing the instant the key is pressed is what tells the user
    /// the press landed, and a dot that waits for the encoder's first frame
    /// looks like a keybind that did not work.
    function isActive(state: string): bool {
        const at = String(state ?? "");
        return at === policy.starting || at === policy.recording;
    }

    /// The state after an event. Unknown pairs return the current state
    /// unchanged rather than throwing: an `exited` arriving in `idle` is a
    /// process that was already given up on, and it must not push the machine
    /// backwards.
    function nextState(current: string, event: string): string {
        const at = String(current ?? policy.idle);
        switch (String(event ?? "")) {
        case "start":
            return policy.canStart(at) ? policy.starting : at;
        case "started":
            return at === policy.starting ? policy.recording : at;
        case "stop":
            return policy.canStop(at) ? policy.stopping : at;
        case "exited":
            return policy.idle;
        }
        return at;
    }

    // --- what a harness reads ------------------------------------------------
    //
    // A line per state change with the reason in it (#81, and CLAUDE.md's
    // rule). "The recording did not start" has five causes — no encoder
    // installed, one already running, the directory could not be made, the
    // region was too small, or the encoder failed to initialise — and without
    // these they are one picture.

    function armed(): string {
        return "recorder armed (ipc target: recorder)";
    }

    function probed(engine: string, present: bool): string {
        return engine + (present ? " is available" : " is not installed");
    }

    function noEngine(): string {
        return "neither " + policy.gsr + " nor " + policy.wf
            + " is installed — nothing can record";
    }

    /// Both encoders are pointed at a monitor by name, so no focused output is
    /// a refusal rather than a default — guessing the first one would record
    /// the wrong screen on the desktop, silently.
    function noMonitor(): string {
        return "no focused monitor — nothing to record";
    }

    function startingWith(engine: string, file: string, region: var): string {
        const where = region
            ? (policy.rect(region).width + "x" + policy.rect(region).height + " region")
            : "the whole screen";
        return "recording " + where + " with " + engine + " to " + file;
    }

    function encodingStarted(engine: string): string {
        return engine + " started encoding";
    }

    function alreadyRecording(): string {
        return "already recording — ignoring start";
    }

    function notRecording(): string {
        return "not recording — ignoring stop";
    }

    /// A start that arrived while the last one was still flushing. Its own line
    /// rather than `alreadyRecording()`, because it is a different thing and
    /// resolves on its own: the encoder is writing the container's index and
    /// will be idle in a moment, whereas "already recording" means a press did
    /// nothing until the user stops the recording themselves.
    function stillStopping(): string {
        return "the last recording is still being written — ignoring start";
    }

    /// The one line that answers "why is this recording soft and hot": the GPU
    /// encoder was asked for and could not run. A `warn` at the call site, not
    /// a `log` — the recording succeeded, but on the wrong engine, and the
    /// machine's VAAPI is what wants looking at.
    function fellBack(from: string, to: string, why: string): string {
        return from + " " + why + " — falling back to " + to;
    }

    function fallbackReason(started: bool, code: int): string {
        return started ? ("failed to initialise (exit " + code + ")") : "is not installed";
    }

    function signalledStop(): string {
        return "stopping the recorder (SIGINT, so the container gets its index)";
    }

    function stopped(file: string, ms: var): string {
        return "recorded " + policy.formatDuration(ms) + " to " + file;
    }

    /// A non-zero exit *after* the grace window, which is a recording that ran
    /// and broke rather than one that could not start. Not retried — see
    /// `shouldFallback` — so this is the whole report.
    function failed(engine: string, code: int): string {
        return engine + " exited " + code + " mid-recording — the file may be truncated";
    }

    /// The one degraded start, and it is worth a `warn`: on this machine a
    /// recording can be started but not cleanly stopped, so the file that comes
    /// out the far end may be missing its index.
    function signalResetMissing(): string {
        return "env --default-signal=INT is unavailable (coreutils 9.2+) — the "
            + "encoder will inherit an ignored SIGINT, so stopping falls to the "
            + "watchdog and the file may be missing its index";
    }

    function stopTimedOut(): string {
        return "the recorder did not exit in " + policy.stopTimeoutMs
            + "ms — killing it, so the file may be missing its index";
    }

    function directoryFailed(code: int): string {
        return "could not make the recording directory (exit " + code
            + ") — not starting";
    }

    function tooSmall(region: var): string {
        const it = policy.rect(region);
        return "region " + it.width + "x" + it.height + " is under "
            + policy.minSide + "px — not recording it";
    }

    function evened(before: var, after: var): string {
        return "trimmed the region from " + policy.rect(before).width + "x"
            + policy.rect(before).height + " to " + policy.rect(after).width + "x"
            + policy.rect(after).height + " — encoders want even sides";
    }

    function pickCancelled(): string {
        return "region picker cancelled — nothing to record";
    }

    /// The four-way audio setting hitting a tool that has one switch. Said out
    /// loud because "I asked for microphone only and got desktop audio" is
    /// otherwise a silent difference between the two engines.
    function audioNarrowed(value: string): string {
        return policy.wf + " has one audio device — recording the default one rather than "
            + value;
    }
}
