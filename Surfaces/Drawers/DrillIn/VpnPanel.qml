// The VPN detail view (#45): every tunnel NetworkManager knows about, by name.
//
// The tile above answers "am I tunnelled" and acts on whichever tunnel that
// means. This is the other half — *which* one — and it is the only one of the
// five panels with a subprocess behind it: `Quickshell.Networking` is a real
// NetworkManager client, but it exposes devices and access points rather than
// connection profiles, so a tunnel is invisible to it and `nmcli` is the
// fallback (Services/Networking/Vpn.qml).
//
// That is also why this panel refreshes on open. There is no polling anywhere in
// the VPN facade — a subprocess on a timer for a value that changes a few times
// a day is a wakeup nobody is paying for (#22 §5) — so a tunnel brought up in a
// terminal would otherwise not be noticed until the next press. Opening the
// panel is the moment somebody is looking, which is exactly when the list should
// be true.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Widgets
import qs.Services.Networking
import qs.Surfaces.Drawers

DrillInPanel {
    id: panel

    name: "vpn"

    note: Vpn.rows.length === 0
        ? "No VPN connections configured. Add one in NetworkManager." : ""

    onBackRequested: ControlCenterActions.back("back")

    // The panel is created when the drill-in opens and destroyed when it
    // closes, so this runs once per visit — which is the cadence the facade's
    // header asks for.
    Component.onCompleted: Vpn.refresh()

    Repeater {
        model: Vpn.rows

        DrillInRow {
            id: tunnelRow

            required property var modelData

            glyph: Vpn.policy.rowIcon(tunnelRow.modelData)
            label: tunnelRow.modelData.name
            detail: Vpn.policy.rowDetail(tunnelRow.modelData)
            active: tunnelRow.modelData.up

            onActivated: ControlCenterActions.tunnel(tunnelRow.modelData.name)
        }
    }
}
