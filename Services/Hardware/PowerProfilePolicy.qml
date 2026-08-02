// What the power-profile tile decides (#44), as pure functions.
//
// power-profiles-daemon has a DBus interface and Quickshell has no client for
// it, so this shells out to `powerprofilesctl` — which means an exit status to
// check (#78) and a log line per press (#81), both of which are decided here
// and wired next door.
//
// The daemon is the authority on which profiles exist. A machine may offer two
// or four, and one of them may be a vendor name this shell has never seen, so
// the cycle walks the list the daemon printed rather than a list written here.
import QtQuick

QtObject {
    id: policy

    function listCommand(): var {
        return ["powerprofilesctl", "list"];
    }

    /// Empty argv for a profile the daemon never offered. The name only ever
    /// arrives from `next()` over the daemon's own list, so this is a guard
    /// against a bug upstream of it rather than against the user — and an empty
    /// argv reaching `Process` is a tile that spins forever.
    function setCommand(name: string): var {
        const trimmed = String(name ?? "").trim();
        return trimmed === "" ? [] : ["powerprofilesctl", "set", trimmed];
    }

    // --- reading the daemon --------------------------------------------------
    //
    // `powerprofilesctl list` prints a stanza per profile: the name at the left
    // margin with a trailing colon, its properties indented under it, and an
    // asterisk on the one that is running.
    //
    //     * balanced:
    //           CpuDriver:  amd_pstate_epp
    //
    //       performance:
    //           CpuDriver:  amd_pstate_epp
    //
    // The property lines are indented four and also end in a colon, so "ends in
    // a colon" is not enough to tell a profile from a `CpuDriver:` — the
    // indent is what separates them.

    readonly property var headingPattern: /^(\*| )\s{0,2}([A-Za-z0-9][\w.+-]*):\s*$/

    function parseList(reply: string): var {
        const out = [];
        for (const line of String(reply ?? "").split("\n")) {
            const match = policy.headingPattern.exec(line);
            if (match)
                out.push(match[2]);
        }
        return out;
    }

    /// The profile carrying the asterisk, or `""` on a machine where the daemon
    /// did not answer at all.
    function parseActive(reply: string): string {
        for (const line of String(reply ?? "").split("\n")) {
            const match = policy.headingPattern.exec(line);
            if (match && match[1] === "*")
                return match[2];
        }
        return "";
    }

    // --- one press -----------------------------------------------------------

    /// The profile after `current`, wrapping. `""` when there is nothing to
    /// move to — no daemon, or a daemon offering exactly one profile — which is
    /// what stops the tile from issuing a set that changes nothing.
    ///
    /// A `current` that is not in the list starts the cycle over rather than
    /// refusing: the daemon drops `performance` on some machines when the cable
    /// comes out, and the tile must not become a dead press because of it.
    function next(current: string, profiles: var): string {
        const all = profiles ?? [];
        if (all.length < 2)
            return "";
        const index = all.indexOf(current);
        return all[(index + 1) % all.length];
    }

    /// Whether a finished `powerprofilesctl` did what it was asked. The exit
    /// status is the whole answer here — unlike hyprctl, which answers `ok` to
    /// rules it has refused (#78).
    function accepted(exitCode: int): bool {
        return exitCode === 0;
    }

    // Both outcomes get a line and both name the profile: a state change with
    // no log line is one no harness can assert on (#81), and a failure logged
    // without what was attempted is one nobody can reproduce.
    function applied(name: string): string {
        return "profile " + name;
    }

    function complaint(name: string, exitCode: int, stderr: string): string {
        return "profile " + name + " refused — exit " + exitCode
            + (stderr ? ": " + String(stderr).trim() : "");
    }
}
