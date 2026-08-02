// Which surfaces a button may ask for, and what the shell says when one is not
// there yet (#37).
//
// The bar's launcher and control-centre buttons are the first things in the
// shell that reach *across* to another surface, and both of those surfaces are
// unbuilt (#39, #44). This table is what they reach through: a name, the IPC
// target the surface will own, and the verb.
//
// **The target and verb are declared here rather than discovered**, for the
// reason #77 exists. `qs ipc call <target> show` is unreachable from the CLI —
// the client's parser takes `show` as its own subcommand, prints the target
// listing and exits 0 — and `list` and `call` collide the same way. A name that
// can never be typed is worse than no name, and the shell-switch contract
// already fixes the launcher's (`qs ipc call launcher toggle`, the Super+Space
// bind it generates). Writing both down here means the surfaces land against a
// name the bar is already using instead of inventing a second one.
//
// Imports nothing but QtQuick, so tests/ can reach it — including the check
// that nothing in the table is a name the CLI eats.
import QtQuick

QtObject {
    id: policy

    /// The `qs ipc` subcommands, which are therefore not available as function
    /// names on any target (#77, measured against this shell in
    /// tools/settings-harness.sh).
    readonly property var reservedVerbs: ["show", "list", "call"]

    /// name → `{ target, verb, label }`. `target` is lowercase and matches the
    /// surface's own name, which is the convention Surfaces/Settings/
    /// SettingsWindow.qml fixed for `settings`.
    ///
    /// `settings` is not here, and that is not an oversight: it is reached as a
    /// QML singleton by everything inside the shell (`SettingsWindow.toggle()`)
    /// because it already exists. This table is for surfaces that do not.
    readonly property var surfaces: ({
        launcher: {
            target: "launcher",
            // Fixed by the shell-switch contract — `templates/hyprland/
            // shell-binds.conf.template` generates `bind = SUPER, Space, exec,
            // <launcher_cmd>`, and ours is `qs ipc call launcher toggle`
            // (.wayfinder/research/shell-switch-integration.md §2.2).
            verb: "toggle",
            label: "Launcher"
        },
        controlcenter: {
            target: "controlcenter",
            verb: "toggle",
            label: "Control centre"
        }
    })

    function known(name: string): bool {
        return policy.surfaces[name] !== undefined;
    }

    /// Whether a verb can actually be called over IPC. Every entry above is
    /// checked against this in tests/, so a surface cannot ship a door nobody
    /// can open.
    function callable(verb: string): bool {
        return verb !== "" && policy.reservedVerbs.indexOf(verb) < 0;
    }

    /// How the surface is reached from outside the shell — the line to paste
    /// into a keybind, and what the log prints when the surface is missing so
    /// that "the button did nothing" comes with the thing to try by hand.
    function command(name: string): string {
        if (!policy.known(name))
            return "";
        const surface = policy.surfaces[name];
        return "qs ipc call " + surface.target + " " + surface.verb;
    }

    /// What the log says when a button is pressed and the surface behind it has
    /// not been built yet. A line rather than silence, because #81 was a
    /// lifecycle with no log line and one bug then had two candidate causes for
    /// a week — and because "nothing happened" is precisely what a broken
    /// button and an unbuilt surface look like from the outside.
    function absent(name: string): string {
        if (!policy.known(name))
            return policy.unknown(name);
        return "no " + policy.surfaces[name].label.toLowerCase()
            + " surface yet — ignoring " + policy.surfaces[name].verb
            + " (it will answer `" + policy.command(name) + "` when it lands)";
    }

    /// A name that is not in the table at all. That is a shell bug rather than
    /// a missing surface — a module asking for a surface nobody declared — so
    /// it says so instead of reading as "not built yet".
    function unknown(name: string): string {
        return "no such surface: " + name;
    }
}
