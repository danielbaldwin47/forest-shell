pragma Singleton

// The VPN facade (#44, #12 §3).
//
//     Vpn.available   // does this machine have a tunnel configured at all
//     Vpn.on          // is one up
//     Vpn.name        // which
//     Vpn.toggle()    // one press of the control-centre tile
//     Vpn.rows        // the drill-in's list (#45), one row per profile
//     Vpn.pressTunnel(name)
//
// The one part of the network facade that shells out. `Quickshell.Networking`
// is a real NetworkManager client — the reason Services/Networking/Networking
// .qml polls nothing — but it exposes devices and access points rather than
// connection profiles, so a tunnel is invisible to it. `nmcli` is the fallback,
// which brings an exit status to check (#78) and a log line per press (#81),
// both decided in Services/Networking/VpnPolicy.qml.
//
// **No polling.** The list is read at the deferred stage and after every press
// the shell makes. A tunnel brought up in a terminal is not noticed until the
// next press — the trade the idle budget (#22 §5) asks for, and the same one
// Services/Hardware/PowerProfiles.qml makes: a subprocess on a timer for a
// value that changes a few times a day is a wakeup nobody is paying for.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core

Singleton {
    id: root

    readonly property VpnPolicy policy: VpnPolicy {}

    /// Every tunnel NetworkManager knows about, `[{ name, up }]`, in its order.
    property var tunnels: []

    readonly property bool available: root.policy.available(root.tunnels)

    /// The tunnel that is up, or `""`.
    readonly property string name: root.policy.active(root.tunnels)
    readonly property bool on: root.name !== ""

    /// One press of the tile: down whatever is up, or up the first one
    /// configured. Which tunnel out of several is the drill-in's question
    /// (`pressTunnel` below) — the tile answers "am I tunnelled", which is what
    /// a control centre is opened for.
    function toggle(): void {
        const target = root.policy.target(root.tunnels);
        if (target === "") {
            Logger.warn("vpn", "no connection configured");
            return;
        }
        root.setTunnel(target, root.policy.wanted(root.tunnels));
    }

    // --- the drill-in's list (#45) -------------------------------------------
    //
    // The tile answers "am I tunnelled" and acts on whichever tunnel that means.
    // These are the other half: *which* one, by name.

    /// Every tunnel as a row, ordered for drawing. Republished on every refresh
    /// rather than filtered through a signature the way the three live lists
    /// are: there is no polling here at all (see the header), so this array is
    /// rebuilt a handful of times a session and never on its own.
    readonly property var rows: root.policy.rows(root.tunnels)

    /// Bring one tunnel up or down by name. Unlike `toggle`, which acts on the
    /// machine's state, this acts on the row: pressing a second tunnel while a
    /// first is up means bring this one up, not take that one down —
    /// NetworkManager will hold several at once and it is not this shell's
    /// business to decide it should not.
    function setTunnel(name: string, up: bool): void {
        const target = String(name ?? "").trim();
        if (target === "") {
            Logger.warn("vpn", "no connection named");
            return;
        }
        if (apply.running) {
            // Handing a running `Process` a new command kills it
            // (Services/Compositor/Compositor.qml), and bringing a tunnel up
            // takes long enough that a second press is easy to make.
            Logger.warn("vpn", "busy — press ignored");
            return;
        }

        apply.target = target;
        apply.up = up;
        apply.command = up ? root.policy.upCommand(target)
                           : root.policy.downCommand(target);
        apply.running = true;
    }

    /// One press on a row, routed by what the row is now — the same table the
    /// panel uses, so the IPC door does what a finger does.
    function pressTunnel(name: string): void {
        for (const row of root.rows)
            if (row.name === name) {
                root.setTunnel(name, root.policy.rowAction(row) === "up");
                return;
            }
        Logger.warn("vpn", "no connection called " + name);
    }

    function refresh(): void {
        if (list.running)
            return;
        list.command = root.policy.listCommand();
        list.running = true;
    }

    Process {
        id: list

        stdout: StdioCollector { id: listOut }

        onExited: (exitCode, exitStatus) => {
            root.tunnels = root.policy.accepted(exitCode)
                         ? root.policy.parse(listOut.text) : [];
            // A machine with no tunnel is a normal machine and gets a log line
            // rather than a warning: this line is why the tile is not on it.
            Logger.log("vpn", root.available
                ? root.tunnels.length + " connection(s)"
                  + (root.on ? " — " + root.name + " up" : "")
                : "no vpn connections — facade inert");
        }
    }

    Process {
        id: apply

        /// What is in flight, kept for the log line: the reply arrives after
        /// the call and says nothing about which press it is answering.
        property string target: ""
        property bool up: false

        stderr: StdioCollector { id: applyErr }

        onExited: (exitCode, exitStatus) => {
            if (root.policy.accepted(exitCode))
                Logger.log("vpn", root.policy.applied(apply.target, apply.up));
            else
                Logger.warn("vpn", root.policy.complaint(apply.target, apply.up,
                                                         exitCode, applyErr.text));
            // Either way: NetworkManager is the authority on what is up, and a
            // tunnel that failed halfway is exactly the case where the shell's
            // guess and the truth part company.
            root.refresh();
        }
    }

    // Deferred, not immediate: a subprocess spawn during the first frames is
    // the startup budget #22 §5 measures, and nothing on screen needs a tunnel
    // list before the drawer is opened.
    Connections {
        target: Startup
        function onDeferredStage() { root.refresh(); }
    }

    Component.onCompleted: if (Startup.deferredRan) root.refresh();
}
