pragma Singleton

// matugen, the optional dependency (#59): whether it is installed, and one
// palette per run of it.
//
// Split from Services/Theming/Theming.qml because the two answer to different
// things. Theming decides *whether* a wallpaper is allowed to say anything and
// writes the answer down; this one owns a subprocess — which is to say it owns
// the three failures a subprocess has and no pure function does: the binary is
// not installed, the binary ran and exited non-zero, and the binary answered
// after the question changed.
//
// Every decision about what the output *means* is in
// Services/Theming/MatugenPolicy.qml where tests/ can reach it. What is left
// here is spawning, exit status, and the one piece of state a surface needs:
// `available`.
//
// ## Why availability is a property and not a check
//
// The settings window greys the mode out when matugen is missing, and it has to
// do that before anyone clicks it — a mode that accepts the click and then does
// nothing is the "no errors, no hint" failure the ticket names. So the probe
// runs once at startup and the answer sits here as a property the window binds
// to. `probed` is separate from `available` for the same reason a spinner is:
// the probe is asynchronous and "not yet" is not "no".
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core

Singleton {
    id: root

    readonly property MatugenPolicy policy: MatugenPolicy {}

    /// Whether the binary answered a `--version`. False until proven otherwise:
    /// the mode is the thing being gated, and gating it open on a machine that
    /// turns out not to have matugen is worse than gating it shut for the few
    /// milliseconds the probe takes.
    property bool available: false

    /// Whether the probe has finished. A surface that shows a hint wants to
    /// know the difference between "no" and "not yet".
    property bool probed: false

    /// What a run produced. Signals rather than properties, and nothing is kept:
    /// the palette belongs in `appearance.dynamic` the moment it exists, which
    /// is Theming's job and not this one's, and a copy held here would be a
    /// second answer to "what is the shell wearing" that could disagree with the
    /// file every consumer actually reads.
    signal generated(palette: var, lifted: int)
    signal failed(reason: string)

    /// Generate from `image`. Silently does nothing when matugen is not
    /// installed: the mode is unreachable in the settings window in that case,
    /// so arriving here means a hand-edited config, and a config file that
    /// names a mode this machine cannot serve should leave the shipped palette
    /// standing rather than throw.
    function run(image: string, darkMode: bool, templates: bool): void {
        if (!root.available || image === "")
            return;

        // A wallpaper change while a run is out. The in-flight one is finishing
        // for a wallpaper nobody is looking at any more, so the answer is
        // recorded as stale and the new one starts the moment it exits —
        // Services/Launcher/Calculator.qml's argument about a sum whose
        // question moved, and the same shape.
        runner.wanted = { image: image, darkMode: darkMode, templates: templates };
        if (runner.running)
            return;

        runner.asked = runner.wanted;
        runner.started = false;
        runner.command = root.policy.argv(image, darkMode, templates);
        runner.running = true;
    }

    Process {
        id: runner

        /// What this run is answering, and what the next one should. Both are
        /// `{ image, darkMode, templates }`.
        property var asked: null
        property var wanted: null

        /// Whether the process ever got as far as existing — the one case with
        /// no exit code to read.
        property bool started: false

        stdout: StdioCollector { id: out }
        // Collected, not discarded: an exit code says a run failed and matugen's
        // stderr says why, specifically enough to act on. Without it the log
        // line is a number and the only way to read the sentence is to run the
        // command again by hand.
        stderr: StdioCollector { id: err }

        onStarted: runner.started = true

        onExited: (exitCode, exitStatus) => {
            const result = root.policy.outcome(exitCode, out.text,
                                               runner.asked.darkMode, err.text);
            if (result.ok) {
                Logger.log("theming", root.policy.generatedLine(
                    result.palette.accentPrimary, result.lifted,
                    runner.asked.darkMode));
                root.generated(result.palette, result.lifted);
            } else {
                // Not cleared. A failed generation is a failed generation and
                // not a statement about the wallpaper (#78), so what is on
                // screen stays on screen — dropping back to the shipped forest
                // on a transient failure would repaint the whole shell to
                // report an error a log line already reports.
                Logger.warn("theming", root.policy.failedLine(result.error));
                root.failed(result.error);
            }

            if (runner.wanted && (runner.wanted.image !== runner.asked.image
                    || runner.wanted.darkMode !== runner.asked.darkMode
                    || runner.wanted.templates !== runner.asked.templates))
                root.run(runner.wanted.image, runner.wanted.darkMode,
                         runner.wanted.templates);
        }

        onRunningChanged: {
            // False without ever having started: the binary went away between
            // the probe and now. The one path with no exit code, and the reason
            // this handler exists.
            if (runner.running || runner.started)
                return;
            root.available = false;
            Logger.warn("theming", root.policy.absentLine());
            root.failed("matugen not installed");
        }
    }

    // --- is it even installed -------------------------------------------------

    Process {
        id: probe

        command: root.policy.probeArgv()
        // A Process does nothing until it is told to run.
        running: true

        property bool started: false

        stdout: StdioCollector { id: probeOut }

        onStarted: probe.started = true

        onExited: (exitCode, exitStatus) => {
            root.probed = true;
            root.available = exitCode === 0;
            if (root.available)
                Logger.log("theming", root.policy.foundLine(probeOut.text));
            else
                Logger.warn("theming", root.policy.absentLine());
        }

        onRunningChanged: {
            if (probe.running || probe.started)
                return;
            root.probed = true;
            root.available = false;
            Logger.warn("theming", root.policy.absentLine());
        }
    }
}
