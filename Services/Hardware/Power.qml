pragma Singleton

// The power facade (#36, #12 §3): battery charge, and whether the machine is
// running on it.
//
//     Power.hasBattery      // false on a desktop — the module hides itself
//     Power.percent         // 0-100
//     Power.state           // "charging" | "discharging" | "full" | …
//     Power.onMains
//     Power.timeRemaining   // "3h 20m", or "" while UPower has no estimate
//
// Native (#4 §2.6): `Quickshell.Services.UPower` is a real UPower client, so
// nothing here polls /sys and nothing shells out. `UPower.displayDevice` is
// UPower's own aggregate — which matters on the T480, a laptop with *two*
// batteries whose individual percentages are not what anybody wants on a bar.
//
// Power profiles (`PowerProfiles`, also native) belong to the control centre
// (#44), not here: nothing on the bar shows them, and a facade that exposes
// what nothing reads is a facade nobody maintains.
//
// Every decision — the glyph ladder, the thresholds, how a duration is written
// — is in Services/Hardware/PowerPolicy.qml, which imports nothing but QtQuick
// so tests/ can reach it. This file is the wiring.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Core

Singleton {
    id: root

    // Held as its own property rather than declared inline — see Core/Config.qml.
    readonly property PowerPolicy policy: PowerPolicy {}

    /// UPower's own aggregate device. Present on every machine — including one
    /// with no battery, where it answers nothing — but null for the moment
    /// before UPower replies, which is why every read below goes through the
    /// optional chain rather than assuming it.
    readonly property UPowerDevice device: UPower.displayDevice

    /// Whether there is a battery to draw at all. `displayDevice` exists on
    /// every machine, including towers, where it reports nothing — a module
    /// that rendered it unconditionally would show 0% forever on a desktop.
    ///
    /// The answer arrives late: UPower's first reply lands about a second after
    /// the service is constructed (measured), so this is a binding and never a
    /// value read once at startup.
    readonly property bool hasBattery: root.policy.hasBattery(root.device?.isPresent ?? false,
                                                              root.device?.isLaptopBattery ?? false)

    /// The 0-1 fraction UPower reports (`energy / energyCapacity`).
    readonly property real fraction: root.device?.percentage ?? 0
    readonly property int percent: root.policy.percent(root.fraction)
    readonly property string label: root.policy.label(root.fraction)

    /// The raw `UPowerDeviceState`, named by the policy everywhere else.
    readonly property int deviceState: root.device?.state ?? 0

    readonly property string state: root.policy.stateName(root.deviceState)
    readonly property bool onMains: root.policy.onMains(root.deviceState)
    readonly property bool low: root.policy.low(root.fraction)
    readonly property bool critical: root.policy.critical(root.fraction)

    readonly property string icon: root.policy.icon(root.fraction, root.deviceState)
    readonly property string emphasis: root.policy.emphasis(root.fraction, root.deviceState)

    /// Time to empty while discharging, time to full while charging, and an
    /// empty string whenever UPower has no estimate — a fresh boot, or a rate
    /// that has not settled.
    readonly property string timeRemaining: root.policy.timeRemaining(
        root.onMains ? (root.device?.timeToFull ?? 0) : (root.device?.timeToEmpty ?? 0))

    // A line per state change worth asserting on (#81) — and per whole percent
    // rather than per fraction, which drifts continuously while discharging and
    // would otherwise write a line a second all night.
    onPercentChanged: Logger.log("power", "battery " + root.percent + "% (" + root.state + ")")
    onStateChanged: Logger.log("power", "battery " + root.state
        + (root.timeRemaining ? ", " + root.timeRemaining + " left" : ""))

    Component.onCompleted: Logger.log("power", "upower facade ready")
}
