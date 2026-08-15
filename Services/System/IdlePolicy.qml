// Everything the idle ladder decides, as pure functions (#48; the ladder itself
// is #30's resolution).
//
// Four stages — dim, lock, DPMS off, suspend — each a timeout in minutes with an
// AC and a battery column, each individually toggleable. This file answers the
// four questions that follow from that, and nothing else:
//
//   - which stages are armed right now, and at how many seconds
//     (`ladder()` — the power source, the per-stage toggle, and Keep Awake all
//     land in one place, so a monitor cannot be enabled for a reason nobody
//     wrote down);
//   - how long DPMS waits *while locked*, which is not the same number
//     (#30: 30 s, because a locked screen has nothing on it worth keeping lit);
//   - whether suspend may proceed (`suspendBlocked()` — the PipeWire gate, and
//     it is on this stage only: music keeps playing while the screen dims,
//     locks and blanks);
//   - whether the session must be locked before it sleeps (`mustLockFirst()`,
//     which is `true` whenever it is not already locked, and is the reason the
//     ticket's fourth acceptance criterion is a decision rather than a hope).
//
// What is deliberately *not* here: `respectInhibitors` as a setting. #30 puts it
// on all four stages, and a config that could turn it off would be a config that
// makes a film stop halfway. It is the constant below.
//
// Imports nothing but QtQuick so `tests/` can reach it (CLAUDE.md, seam 1);
// Services/System/Idle.qml is the half that needs Quickshell, and
// Services/System/LogindBridge.qml is the half that needs subprocesses.
import QtQuick

QtObject {
    id: policy

    /// The four stages, in the order #30 lists them — which is also the order
    /// their default timeouts put them in, though nothing here depends on that:
    /// a hand-edited file may lock before it dims, and the correct response is
    /// to lock before dimming rather than to argue with the file.
    readonly property var stages: ["dim", "lock", "dpms", "suspend"]

    /// On every stage, always. A video player and a browser both take
    /// `zwp_idle_inhibit_manager_v1` themselves, and honouring it is what makes
    /// "the film does not stop" true without the shell knowing what a film is
    /// (#30 §"Inhibitor policy").
    readonly property bool respectInhibitors: true

    /// How long the delay inhibitor may be held while waiting for the lock to
    /// come up, in ms. logind's own `InhibitDelayMaxSec` defaults to 5 s and it
    /// does not ask twice — past that it sleeps whether or not the lock is up —
    /// so the shell gives up first and says so, rather than being overruled
    /// silently.
    readonly property int lockConfirmTimeoutMs: 4000

    // --- what is armed --------------------------------------------------------

    /// One stage's sub-object from `system.idle`, or an empty one. Reached
    /// through this rather than indexed directly, because every caller here is
    /// reading a hand-editable file (#21) and a missing section must read as
    /// "the defaults" and not as a crash inside a binding.
    function stage(settings: var, id: string): var {
        const table = settings ?? {};
        const entry = table[id];
        return (entry !== null && typeof entry === "object") ? entry : ({});
    }

    /// The configured timeout for a stage on this power source, in minutes.
    /// Zero means "not on this source" — which is how AC suspend is off while
    /// battery suspend is on, without a second toggle to keep in agreement with
    /// the first.
    function minutes(settings: var, id: string, onBattery: bool): real {
        const entry = policy.stage(settings, id);
        const value = Number(onBattery ? entry.battery : entry.ac);
        return isFinite(value) && value > 0 ? value : 0;
    }

    function seconds(settings: var, id: string, onBattery: bool): real {
        return Math.round(policy.minutes(settings, id, onBattery) * 60);
    }

    /// Why a stage is not armed, or `""` if it is.
    ///
    /// A string rather than a bool because every one of these reasons ends up in
    /// the log: "the ladder did not fire" has four causes, and a harness that
    /// cannot tell them apart is the #81 failure again one feature along.
    function off(settings: var, id: string, onBattery: bool, frozen: bool): string {
        if (frozen === true)
            return "keep awake";
        if (policy.stage(settings, id).enabled === false)
            return "turned off";
        if (policy.minutes(settings, id, onBattery) <= 0)
            return onBattery ? "no timeout on battery" : "no timeout on ac";
        return "";
    }

    /// The whole ladder as it stands right now: one row per stage, in `stages`
    /// order, each carrying its timeout and either its armed state or the reason
    /// it is not. This is what the four monitors bind to and what the startup
    /// line is written from, so the log and the behaviour cannot disagree.
    function ladder(settings: var, onBattery: bool, frozen: bool): var {
        const rows = [];
        for (const id of policy.stages) {
            const reason = policy.off(settings, id, onBattery, frozen);
            rows.push({
                id: id,
                enabled: reason === "",
                minutes: policy.minutes(settings, id, onBattery),
                seconds: policy.seconds(settings, id, onBattery),
                off: reason
            });
        }
        return rows;
    }

    function row(settings: var, id: string, onBattery: bool, frozen: bool): var {
        for (const entry of policy.ladder(settings, onBattery, frozen))
            if (entry.id === id)
                return entry;
        return null;
    }

    // --- the two stages that are not just a timeout ---------------------------

    /// How long DPMS waits, which is the one stage whose timeout depends on
    /// something other than the power source: a locked screen is showing a clock
    /// nobody is reading, so #30 tightens it to 30 s while locked.
    ///
    /// The floor is a floor and not a replacement — a machine configured to
    /// blank after 20 s unlocked does not get *slower* the moment it locks.
    function dpmsSeconds(settings: var, onBattery: bool, locked: bool): real {
        const configured = policy.seconds(settings, "dpms", onBattery);
        if (locked !== true)
            return configured;

        const entry = policy.stage(settings, "dpms");
        const whileLocked = Number(entry.lockedSeconds);
        if (!isFinite(whileLocked) || whileLocked <= 0)
            return configured;
        return configured > 0 ? Math.min(configured, whileLocked) : whileLocked;
    }

    /// What the screen dims *to*, as a percent.
    function dimLevel(settings: var): int {
        const value = Number(policy.stage(settings, "dim").level);
        if (!isFinite(value))
            return 10;
        return Math.max(1, Math.min(100, Math.round(value)));
    }

    /// What the dim remembers, so the wake can put it back (#208).
    ///
    /// Two numbers, because the panel has two truths at the moment a rung
    /// fires. `reading` is the panel as sysfs says it is *now* — a fresh read,
    /// not the facade's cached percent, which is the whole of #208: sysfs
    /// announces nothing, so anything outside the shell may have moved the
    /// panel since the last read and the remembered level would be a number
    /// nobody had checked. `aiming` is the level a queued or running write is
    /// on its way to, or -1 for none.
    ///
    /// When a write is in flight the reading is worth nothing — `actual_bright-
    /// ness` is between the two levels and is neither of them — so the choice
    /// is to wait for it to settle or to take the level it aims at. This repo
    /// takes the aim: it is a level somebody just chose, so it is exactly what
    /// a restore owes them, and waiting would mean a timer or a subscription
    /// armed at the moment a rung fires, which is the cost #186 measured and
    /// refused (a permanent backlight poll: 5.57 context switches/s against a
    /// budget of 5).
    /// Both arguments are `var` rather than `int` deliberately: an `int`
    /// parameter coerces a missing or unreadable number to 0, which reads here
    /// as "aiming at zero" rather than as "nothing in flight".
    function capturedLevel(reading: var, aiming: var): int {
        const aim = Number(aiming);
        const value = isFinite(aim) && aim >= 0 ? aim : Number(reading);
        if (!isFinite(value))
            return 1;
        return Math.max(1, Math.min(100, Math.round(value)));
    }

    /// Whether a captured level would restore the screen no brighter than the
    /// dim left it — which is not a level to restore *to*, it is a capture that
    /// has already gone wrong. #208 was reported as exactly this shape: a wake
    /// that left the screen darker than it went idle. The level is still put
    /// back — the remembered level is the contract — but the log says so.
    function captureSuspect(captured: int, dimLevel: int): bool {
        return Number(captured) <= Number(dimLevel);
    }

    function suspectCapture(captured: int, dimLevel: int): string {
        return "dim captured " + captured + "%, no brighter than the dim's own "
             + dimLevel + "% — the restore will not undo this dim";
    }

    /// A configured command as argv. Split here rather than handed to `sh -c`:
    /// the config holds a command, and routing it through a shell brings that
    /// shell's quoting, globbing and word-splitting along with it for no gain —
    /// the same argument Surfaces/Drawers/SessionPolicy.qml makes for the
    /// session commands, and Services/Compositor/LayerRulePolicy.qml for layer
    /// rules.
    ///
    /// An empty command is an empty argv, which every caller here refuses with a
    /// line naming the key: "not on this machine" is a thing a config should be
    /// able to say, and a `Process` handed nothing is a stage that reports
    /// success and does nothing.
    function argv(command: string): var {
        const trimmed = String(command ?? "").trim();
        return trimmed === "" ? [] : trimmed.split(/\s+/);
    }

    /// The PipeWire gate, and it is on this stage alone (#30): a machine playing
    /// music through headphones must not suspend under the person listening to
    /// it, and the same machine dimming, locking and blanking is exactly right.
    ///
    /// "Playing" is a live link to the sink rather than the existence of a
    /// stream — see `Services/Media/AudioPolicy.qml`, which owns that reading.
    function suspendBlocked(audioPlaying: bool): bool {
        return audioPlaying === true;
    }

    /// Whether the session has to be locked before this sleep. The whole of the
    /// ticket's fourth acceptance criterion: there is no path to suspend that
    /// skips the lock, so the only question left is whether it is up already.
    function mustLockFirst(locked: bool): bool {
        return locked !== true;
    }

    // --- what a harness reads -------------------------------------------------
    //
    // A line per stage transition and per inhibitor acquire/release, with the
    // reason in it — the maintenance pass on #48 asks for exactly this by name,
    // and #81 is why: "suspend never lands on an unlocked session" is only
    // assertable if the log says when the lock went up and when the sleep lock
    // was let go.

    /// The startup line: the ladder as configured, in one line, so a harness can
    /// prove the file was read without waiting for a stage to fire.
    function ladderLine(rows: var, onBattery: bool): string {
        const parts = [];
        for (const entry of rows)
            parts.push(entry.enabled ? entry.id + " " + entry.seconds + "s"
                                     : entry.id + " off (" + entry.off + ")");
        return "ladder on " + (onBattery ? "battery" : "ac") + ": " + parts.join(", ");
    }

    function armed(id: string, seconds: real): string {
        return id + " armed at " + Math.round(seconds) + "s";
    }

    function disarmed(id: string, why: string): string {
        return id + " disarmed (" + why + ")";
    }

    function reached(id: string, detail: string): string {
        return "idle: " + id + (detail ? " — " + detail : "");
    }

    function woke(id: string, detail: string): string {
        return "activity: " + id + (detail ? " — " + detail : "");
    }

    function blocked(id: string, why: string): string {
        return id + " held off — " + why;
    }

    function frozenLine(on: bool): string {
        return on ? "ladder frozen — keep awake is on"
                  : "ladder released — keep awake is off";
    }

    // --- the logind bridge's lines -------------------------------------------

    function inhibitorHeld(what: string): string {
        return "sleep inhibitor held (" + what + ")";
    }

    /// A delay lock that failed to take must not read as one that is held (#78).
    function inhibitorRefused(detail: string): string {
        return "no sleep inhibitor — a suspend may not wait for the lock ("
            + detail + ")";
    }

    function inhibitorReleased(why: string): string {
        return "sleep inhibitor released (" + why + ")";
    }

    function sleeping(locked: bool): string {
        return locked ? "sleep requested — already locked"
                      : "sleep requested — locking first";
    }

    function lockConfirmed(ms: real): string {
        return "lock confirmed after " + Math.round(ms) + "ms — releasing the sleep inhibitor";
    }

    function lockUnconfirmed(ms: real): string {
        return "the compositor did not confirm the lock within " + Math.round(ms)
            + "ms — sleeping anyway, logind will not wait longer";
    }

    /// What a line from the helper means, or `""` for one that means nothing.
    /// The helper's whole protocol, in one place: it emits one bare word per
    /// event and this is what the shell does with each.
    function event(line: string): string {
        const text = String(line ?? "").trim();
        switch (text) {
        case "lock":
        case "unlock":
        case "sleep":
        case "resume":
            return text;
        }
        return "";
    }

    function bridgeLine(event: string): string {
        switch (event) {
        case "lock": return "logind asked for the lock";
        case "unlock": return "logind asked for an unlock — refused, PAM owns the way out";
        case "sleep": return "logind is preparing to sleep";
        case "resume": return "logind resumed the session";
        }
        return "";
    }

    function bridgeRefused(detail: string): string {
        return "no logind bridge — `loginctl lock-session` and lock-before-sleep "
            + "are both unavailable (" + detail + ")";
    }
}
