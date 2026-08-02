// Everything the volume and mic indicators decide, as pure functions (#36).
//
// Split out of Services/Media/Audio.qml for the reason Core/Tokens.qml is split
// out of Core/Theme.qml: this file imports nothing but QtQuick, so tests/ can
// reach it. What is left next door is the PipeWire wiring, which is not a
// decision at all.
import QtQuick

QtObject {
    id: policy

    /// One nudge of the volume, as a fraction. 5% is the smallest step that is
    /// audible on the T480's speakers; smaller ones read as a key that did
    /// nothing.
    readonly property real step: 0.05

    /// A volume the shell is willing to set. PipeWire will happily go above
    /// 1.0, and the amplification it does there is the distorted kind — so the
    /// ceiling is the device's own, and `percent` below agrees with it rather
    /// than reporting a number the setter would refuse.
    function clamp(volume: real): real {
        if (!isFinite(volume))
            return 0;
        return Math.max(0, Math.min(1, volume));
    }

    /// A volume as a whole percent, for a readout.
    function percent(volume: real): int {
        return Math.round(policy.clamp(volume) * 100);
    }

    /// The volume one step up (`direction` 1) or down (-1) from here.
    ///
    /// Snapped to the step grid rather than added to: a level nudged from 0.43
    /// otherwise spends the rest of the session three percent off every round
    /// number, and the readout never says a number anyone recognises.
    function stepped(volume: real, direction: int): real {
        const base = policy.clamp(volume) / policy.step;
        // The epsilon is for a level that is *already* on the grid: floating
        // point makes 0.45/0.05 land at 8.999999999999998 as readily as 9.
        const grid = direction > 0 ? Math.floor(base + 1e-9) : Math.ceil(base - 1e-9);
        const next = (grid + (direction > 0 ? 1 : -1)) * policy.step;
        return Math.round(policy.clamp(next) * 1000) / 1000;
    }

    /// The output glyph. Mute outranks the level — a mute drawn as "quiet"
    /// would be one nobody can find their way back from — and the level
    /// underneath is unchanged, so unmuting returns to it.
    function sinkIcon(volume: real, muted: bool): string {
        if (muted)
            return "volume-x";
        if (policy.clamp(volume) <= 0)
            return "volume";
        return policy.clamp(volume) >= 0.5 ? "volume-2" : "volume-1";
    }

    function sourceIcon(muted: bool): string {
        return muted ? "mic-off" : "mic";
    }

    /// Whether the mic belongs on the bar at all.
    ///
    /// The cluster is quiet by default (#9): a live mic is the normal state and
    /// says nothing; a muted one is the surprise — "why can nobody hear me" is
    /// the question this glyph exists to answer, and it is only ever asked in
    /// one direction.
    function showSource(muted: bool): bool {
        return muted === true;
    }

    // --- the drill-in's two lists (#45) --------------------------------------
    //
    // The output picker and the per-application mixer. Both arrive as plain rows
    // the facade assembles from PipeWire nodes, and both follow the ordering
    // rule Services/Networking/WifiPolicy.qml argues at length: only fields that
    // change when something *happens* decide where a row sits. A volume is the
    // most volatile value in the shell — it moves while the user is dragging the
    // very row it would reorder — so it decides nothing here.

    /// The output devices, in the order they are drawn: the current default
    /// first, then everything else alphabetically by the name PipeWire shows.
    ///
    /// The default is pinned to the top rather than left in place because it is
    /// the answer to the question the picker was opened with — "what am I
    /// playing through" — and a checked row six rows down answers it slowly.
    function sinks(nodes: var): var {
        const out = [];
        for (const node of nodes ?? []) {
            const id = String(node?.id ?? "");
            if (id === "")
                continue;
            out.push({
                id: id,
                name: policy.deviceName(node),
                isDefault: node?.isDefault === true,
                live: node?.live ?? null
            });
        }
        return out.sort((a, b) => {
            if (a.isDefault !== b.isDefault)
                return a.isDefault ? -1 : 1;
            const left = a.name.toLowerCase();
            const right = b.name.toLowerCase();
            return left < right ? -1 : left > right ? 1 : 0;
        });
    }

    /// What to call an output. PipeWire's `description` is the human one
    /// ("Built-in Audio Analogue Stereo"); `nickname` is shorter when it exists;
    /// `name` is the machine one (`alsa_output.pci-0000_00_1f.3.analog-stereo`)
    /// and is the last resort rather than the first.
    function deviceName(node: var): string {
        const facts = node ?? ({});
        return String(facts.description ?? "").trim()
            || String(facts.nickname ?? "").trim()
            || String(facts.name ?? "").trim()
            || "Unknown device";
    }

    /// The per-application mixer, alphabetical by application. One row per
    /// stream and not per application: Firefox playing two tabs is two streams
    /// to PipeWire and two volumes to set, and merging them would give a slider
    /// that moves one of the two.
    function streams(nodes: var): var {
        const out = [];
        for (const node of nodes ?? []) {
            const id = String(node?.id ?? "");
            if (id === "")
                continue;
            out.push({
                id: id,
                name: policy.streamName(node),
                subtitle: policy.streamSubtitle(node),
                icon: policy.streamIcon(node),
                live: node?.live ?? null
            });
        }
        return out.sort((a, b) => {
            const left = a.name.toLowerCase();
            const right = b.name.toLowerCase();
            if (left !== right)
                return left < right ? -1 : 1;
            // Two streams from one application keep PipeWire's order, which is
            // the order they started in — stable, and the only thing left that
            // tells them apart.
            return Number(a.id) - Number(b.id);
        });
    }

    /// Who is making the noise. `application.name` is what the toolkit set and
    /// is right almost always; the node's own description is the fallback for a
    /// stream created by something that set no properties at all.
    function streamName(node: var): string {
        const props = node?.properties ?? ({});
        return String(props["application.name"] ?? "").trim()
            || String(node?.description ?? "").trim()
            || String(node?.name ?? "").trim()
            || "Unknown application";
    }

    /// What it is playing, when the application says. Dropped when it is the
    /// same as the application's own name — "Firefox · Firefox" is a row that
    /// spent a line saying nothing.
    function streamSubtitle(node: var): string {
        const props = node?.properties ?? ({});
        const media = String(props["media.name"] ?? "").trim();
        return media.toLowerCase() === policy.streamName(node).toLowerCase() ? "" : media;
    }

    /// The glyph on a mixer row: the application's own desktop id, which
    /// Widgets/Icon.qml resolves against the icon theme, or the shell's own
    /// speaker glyph for a stream that names no application.
    function streamIcon(node: var): string {
        const props = node?.properties ?? ({});
        return String(props["application.icon_name"] ?? "").trim()
            || String(props["application.process.binary"] ?? "").trim()
            || "volume-2";
    }

    /// What both facades compare before republishing (#75). The volumes are
    /// deliberately absent: they move under the pointer, and a rebuilt delegate
    /// is a slider that loses the drag that is moving it.
    function sinkSignature(rows: var): string {
        return (rows ?? []).map(row => row.id + " " + row.name
                                + (row.isDefault ? "*" : "-")).join("");
    }

    function streamSignature(rows: var): string {
        return (rows ?? []).map(row => row.id + " " + row.name
                                + " " + row.subtitle).join("");
    }

    // --- what the log says ---------------------------------------------------

    function switched(name: string): string {
        return "output → " + name;
    }

    function streamMoved(name: string, percentValue: int): string {
        return "stream " + name + " " + policy.percent(percentValue / 100) + "%";
    }

    function streamRefused(id: string, reason: string): string {
        return "stream " + id + " unchanged — " + reason;
    }
}
