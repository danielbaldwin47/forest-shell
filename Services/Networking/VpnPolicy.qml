// What the VPN tile decides (#44), as pure functions.
//
// `Quickshell.Networking` is a real NetworkManager client — the whole reason
// Services/Networking/Networking.qml polls nothing — but it exposes devices and
// access points, not connection profiles, so there is no VPN on it. This is the
// one part of the network facade with a subprocess and a parser behind it.
//
// `nmcli -t` is the machine-readable form: one connection per line,
// colon-separated, with a literal colon inside a value backslash-escaped. The
// name is the only field that can contain one, and it is the first field — so
// the parse works from the *right*, where the two fixed-shape fields are.
import QtQuick

QtObject {
    id: policy

    /// NetworkManager's two tunnel types. A WireGuard profile is typed
    /// `wireguard` rather than `vpn`, and a shell matching only the latter
    /// would show no tile at all on a machine whose only tunnel is one.
    readonly property var tunnelTypes: ["vpn", "wireguard"]

    function listCommand(): var {
        return ["nmcli", "-t", "-f", "NAME,TYPE,STATE", "connection", "show"];
    }

    function upCommand(name: var): var {
        const trimmed = String(name ?? "").trim();
        return trimmed === "" ? [] : ["nmcli", "connection", "up", "id", trimmed];
    }

    function downCommand(name: var): var {
        const trimmed = String(name ?? "").trim();
        return trimmed === "" ? [] : ["nmcli", "connection", "down", "id", trimmed];
    }

    // --- reading the listing -------------------------------------------------

    /// The tunnels, as `[{ name, up }]`, in NetworkManager's own order.
    function parse(reply: string): var {
        const out = [];
        for (const line of String(reply ?? "").split("\n")) {
            const row = policy.parseRow(line);
            if (row !== null)
                out.push(row);
        }
        return out;
    }

    /// One line, or `null` for anything that is not a tunnel — which includes
    /// wifi and ethernet (Networking.qml already speaks for those) and nmcli's
    /// own prose when NetworkManager is not running.
    function parseRow(line: string): var {
        const fields = String(line ?? "").split(":");
        if (fields.length < 3)
            return null;

        // From the right: state last, type before it. Everything before those
        // is the name, which is where an escaped colon put an extra field.
        const state = fields[fields.length - 1];
        const type = fields[fields.length - 2];
        if (policy.tunnelTypes.indexOf(type) < 0)
            return null;

        const name = fields.slice(0, fields.length - 2).join(":")
                           .split("\\:").join(":");
        return name === "" ? null
             : { name: name, up: state.trim() === "activated" };
    }

    // --- which one a press moves ---------------------------------------------

    /// The tunnel that is up, or `""`. One, not a list: NetworkManager will
    /// hold several at once and the tile speaks for the state of the machine
    /// rather than for a particular profile — a picker for the rest is the
    /// drill-in this ticket stubs.
    function active(tunnels: var): string {
        for (const tunnel of tunnels ?? [])
            if (tunnel.up === true)
                return tunnel.name;
        return "";
    }

    /// Which tunnel one press acts on: whichever is up, or the first configured
    /// when none is.
    function target(tunnels: var): string {
        const up = policy.active(tunnels);
        if (up !== "")
            return up;
        const all = tunnels ?? [];
        return all.length > 0 ? all[0].name : "";
    }

    /// What that press is asking for — up when nothing is, down when something
    /// is.
    function wanted(tunnels: var): bool {
        return policy.active(tunnels) === "";
    }

    /// Whether this machine has a tunnel at all. No tunnel is no tile
    /// (Surfaces/Drawers/ControlCenterPolicy.qml), rather than a control that
    /// does nothing when pressed.
    function available(tunnels: var): bool {
        return (tunnels ?? []).length > 0;
    }

    /// Whether a finished `nmcli` did what it was asked. The exit status is the
    /// whole answer — nmcli exits non-zero and explains itself, unlike hyprctl
    /// (#78).
    function accepted(exitCode: int): bool {
        return exitCode === 0;
    }

    // Both outcomes get a line and both name the tunnel: a state change with no
    // log line is one no harness can assert on (#81).
    function applied(name: string, up: bool): string {
        return "vpn " + name + (up ? " up" : " down");
    }

    function complaint(name: string, up: bool, exitCode: int, stderr: string): string {
        return policy.applied(name, up) + " refused — exit " + exitCode
            + (stderr ? ": " + String(stderr).trim() : "");
    }
}
