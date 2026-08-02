// A shell root that is *only* the system services, plus a way to drive them
// from a script (#36).
//
// The five services this loads are the half of the ticket no unit test can
// reach: `tests/` cannot import Quickshell at all, so PipeWire, NetworkManager,
// BlueZ, UPower and one subprocess are invisible from there. What is checkable
// without hardware — which glyph, what a step is, how a reply parses — lives in
// the `*Policy.qml` files next to each service and is checked there. This is
// the other seam: the real singletons, constructed the way the shell constructs
// them, driven over IPC, asserted on through the log (tools/services-harness.sh).
//
// This is a harness, not a shell: shell.qml never loads it, and the
// `servicetest` target exists nowhere else. Everything under test is the real
// code, unmodified.
//
// A second entry point at the repo root rather than a file under `tools/`, for
// gallery.qml's reason: Quickshell takes the entry point's directory as the
// config root, and only from here does `qs.Services.…` resolve at all.
//
//   qs-upstream -p services-harness.qml   # inside the nested display
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Services.Media
import qs.Services.Networking
import qs.Services.Hardware

ShellRoot {
    id: harness

    Component.onCompleted: {
        // The same call shell.qml makes off the first painted frame — naming
        // the singletons is what constructs them, and constructing them is what
        // starts the DBus and PipeWire clients underneath (#12 §4).
        ServiceInit.initDeferred();
        Logger.log("harness", "services harness ready");
    }

    IpcHandler {
        target: "servicetest"

        /// Everything a script needs to assert on, in one round trip.
        ///
        /// Reported rather than checked here: a harness that decided what was
        /// correct would be a second implementation of the policies, and the
        /// two would drift.
        function snapshot(): string {
            return JSON.stringify({
                audio: {
                    ready: Audio.ready,
                    hasSink: Audio.hasSink,
                    percent: Audio.percent,
                    muted: Audio.muted,
                    sourceMuted: Audio.sourceMuted,
                    icon: Audio.icon
                },
                network: {
                    available: Networking.available,
                    wifiEnabled: Networking.wifiEnabled,
                    connected: Networking.connected,
                    devices: Networking.devices.length,
                    icon: Networking.icon,
                    label: Networking.label
                },
                bluetooth: {
                    present: Bluetooth.present,
                    enabled: Bluetooth.enabled,
                    connected: Bluetooth.connectedCount,
                    icon: Bluetooth.icon
                },
                power: {
                    hasBattery: Power.hasBattery,
                    percent: Power.percent,
                    state: Power.state,
                    onMains: Power.onMains,
                    icon: Power.icon,
                    timeRemaining: Power.timeRemaining
                },
                backlight: {
                    available: Backlight.available,
                    device: Backlight.device,
                    max: Backlight.max,
                    percent: Backlight.percent
                }
            });
        }

        /// Set the output volume, as the bar's wheel does. A percent rather
        /// than a fraction, so a shell script can spell it.
        function volume(percent: int): bool {
            Audio.setVolume(percent / 100);
            return true;
        }

        function micMute(muted: bool): bool {
            Audio.setSourceMuted(muted);
            return true;
        }

        /// Set the panel, as the brightness module's wheel does.
        ///
        /// This really does move the backlight of the machine running the test
        /// — a nested compositor is nested, but the hardware underneath it is
        /// the same hardware. The script restores what it found.
        function brightness(percent: int): bool {
            Backlight.setPercent(percent);
            return true;
        }

        function nudgeBrightness(direction: int): bool {
            Backlight.step(direction);
            return true;
        }
    }
}
