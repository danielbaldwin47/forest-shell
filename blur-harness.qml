// A shell root that is the bar and a way to push layer rules at it (#78).
//
// The bar's blur is a Hyprland layer rule, so nothing about it is visible from
// `tests/`: the facade that pushes it imports Quickshell, and whether the
// compositor accepted the rule is the compositor's answer rather than a
// decision the shell makes. What *is* a decision — how a rule is spelled, and
// what counts as it having been taken — lives in
// Services/Compositor/LayerRulePolicy.qml with its own unit tests. This is the
// other half: the wiring, against a real compositor.
//
// tools/blur-harness.sh brings up a nested Hyprland, runs this in it, and reads
// the log. Everything under test — Bar.qml's rule, the facade's Process, the
// reply handling — is the real code, unmodified.
//
// A second entry point at the repo root rather than a file under `tools/`, for
// lock-harness.qml's reason: Quickshell takes the entry point's directory as
// the config root, and only from here does `qs.Surfaces.Bar` resolve to the
// real bar.
//
//   qs-upstream -p blur-harness.qml   # inside the nested display
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Services.Compositor
import qs.Surfaces.Bar

ShellRoot {
    id: harness

    Component.onCompleted: Logger.log("harness", "blur harness ready");

    // The real bar, which pushes its own rule at the deferred stage.
    Bar {}

    IpcHandler {
        target: "layerrule"

        /// Push a rule by hand — the seam the shell itself uses, so a rule
        /// Hyprland refuses can be sent deliberately and the warning read.
        function push(rule: string, namespace: string): bool {
            Compositor.setLayerRule(rule, namespace);
            return true;
        }

        /// Flip `bar.surface.blur`, exactly as the settings window does:
        /// `bar.surface` is one grouped key, so the knob is a read-modify-write
        /// of the group and never a bare `{ blur: … }`, which would drop every
        /// other knob in it (Surfaces/Settings/Controls/ConfigBinding.qml).
        ///
        /// This is a real write to settings.json — the harness script gives the
        /// shell its own XDG_CONFIG_HOME so it is never the real one.
        function blur(on: bool): bool {
            const group = Object.assign({}, Config.get("bar.surface") ?? {});
            group.blur = on;
            return Config.set("bar.surface", group);
        }

        /// Whether the facade found a compositor at all. A harness asserting on
        /// layer rules against an inert facade would pass by never trying.
        function available(): bool {
            return Compositor.available;
        }
    }
}
