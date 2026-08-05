// The Bluetooth detail view (#45): what is paired, what is connected, and what
// the scan has turned up.
//
// Discovery is held by this panel for exactly as long as it is open, the same
// way the Wi-Fi panel holds the scanner and for the same reason — a discovering
// adapter is a radio kept awake against an idle budget of one wakeup a minute
// (#22 §5). The hold and the release are in
// Surfaces/Drawers/ControlCenterActions.qml's `setPanel`, which is the one place
// that can promise they come in pairs.
//
// ## One press pairs *and* connects
//
// Nobody who presses an unpaired headset wants to be paired to it and then have
// to press it again. BlueZ connects on its own after a successful pair for most
// device classes; the ones it does not are covered by the row then reading
// "Paired", which is the row you press to connect. That the two are one gesture
// is Services/Networking/BluetoothPolicy.qml's `deviceAction`, so the panel and
// the IPC door agree about it.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Widgets
import qs.Services.Networking
import qs.Surfaces.Drawers

DrillInPanel {
    id: panel

    name: "bluetooth"

    // What the radio is *doing*, not what was asked of it (#189). A panel that
    // holds a scan the adapter is not running said nothing at all before this,
    // which reads as a panel that never asked.
    activity: Bluetooth.policy.activity(Bluetooth.discoveryHolders > 0,
                                        Bluetooth.discovering)

    note: {
        if (!Bluetooth.present)
            return "No bluetooth adapter on this machine.";
        if (!Bluetooth.enabled)
            return "The radio is off. Turn it on from the tile and the scan starts.";
        return Bluetooth.deviceRows.length === 0
             ? "Nothing found yet. Put the device into pairing mode." : "";
    }

    onBackRequested: ControlCenterActions.back("back")

    Repeater {
        // Republished only when the shape of the list changes — never for a
        // battery percentage (#75, and the facade's own comment).
        model: Bluetooth.deviceRows

        DrillInRow {
            id: deviceRow

            required property var modelData

            glyph: Bluetooth.policy.deviceIcon(deviceRow.modelData.kind)
            label: deviceRow.modelData.name
            // Bound through the live handle for the battery, which moves on its
            // own: the row is not rebuilt for it, so the words have to come
            // from the object rather than from the snapshot beside it.
            //
            // `state` is read off the handle here and not off the snapshot for
            // the same reason (#189): a connect in flight is deliberately not in
            // the republish signature, since rebuilding every delegate on every
            // press is the cost the signature exists to avoid. The comparison is
            // spelled out in the binding rather than hidden in a function call so
            // that the read registers as a dependency of it.
            detail: Bluetooth.policy.deviceDetail({
                pairing: deviceRow.modelData.live
                         ? deviceRow.modelData.live.pairing : false,
                // The facade's own flag first, so the acknowledgement is on the
                // row on the frame of the press: `connect()` returns before
                // BlueZ moves `state`, and a row that only follows `state` is a
                // row that stays on "Paired" for the first moment of every
                // attempt — which is the moment the ticket is about.
                connecting: Bluetooth.connectingAddress === deviceRow.modelData.address
                            || (deviceRow.modelData.live
                                ? deviceRow.modelData.live.state === Bluetooth.connectingState
                                : false),
                failed: Bluetooth.failedAddress === deviceRow.modelData.address,
                connected: deviceRow.modelData.connected,
                paired: deviceRow.modelData.paired,
                batteryAvailable: deviceRow.modelData.live
                                  ? deviceRow.modelData.live.batteryAvailable : false,
                battery: deviceRow.modelData.live
                         ? deviceRow.modelData.live.battery : 0
            })
            active: deviceRow.modelData.connected

            onActivated: ControlCenterActions.device(deviceRow.modelData.address)
            // Unpair, on the rows where there is a pairing to undo.
            onSecondary: if (deviceRow.modelData.paired)
                ControlCenterActions.forgetDevice(deviceRow.modelData.address);

            // A paired device that is not connected still says so on the right:
            // the detail line is where the *state* is, and this is where "the
            // machine remembers this one" is, which is a different fact.
            Icon {
                visible: deviceRow.modelData.paired && !deviceRow.modelData.connected
                name: "link"
                size: 12
                color: Theme.textMuted
            }
        }
    }
}
