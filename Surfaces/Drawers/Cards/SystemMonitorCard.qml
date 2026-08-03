// What the machine is doing, four rows of it (#50).
//
// CPU, memory, disk and temperature: a glyph, a name, a minute of history as a
// sparkline, and the number now. Every value comes from
// Services/System/SystemStats.qml and every decision about it — which rows exist
// on this hardware, what each is called, what the number is a percentage of —
// from Services/System/SystemStatsPolicy.qml next door, where `tests/` reaches
// them.
//
// ## The card is what starts the sampling
//
// `SystemStats.watch()` on arrival, `SystemStats.release()` on the way out, and
// the sampler's timer runs only while somebody holds a subscription. That is
// #50's "sampling verifiably stops when the dashboard is closed", and it is
// verifiable because both edges are logged (`tools/drawer-harness.sh` asserts on
// them). The drawer destroys its slot on close
// (Surfaces/Drawers/DrawerSlot.qml), so the release is the panel going away
// rather than something this file has to notice.
//
// A bar configured with the optional system-monitor module holds a subscription
// of its own all session, so opening the dashboard over it does not start a
// second timer — the count is what makes that true.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets
// Its own directory, explicitly: this file is loaded by URL, and a file
// Quickshell serves through its interceptor gets no implicit sibling
// resolution — without this line `CardFrame` is "not a type" (#73).
import qs.Surfaces.Drawers.Cards
import qs.Services.System

CardFrame {
    id: card

    /// The dashboard's pose, or null for the live shell. `facts.system` is
    /// `{ sample, history }` — the sampler's own two values rather than the
    /// finished rows, so a posed capture goes through the same policy the live
    /// card does and a change to the row rules cannot pass a capture while
    /// failing the shell.
    property var facts: null

    readonly property bool posed: card.facts !== null && card.facts.system !== undefined

    readonly property SystemStatsPolicy policy: SystemStatsPolicy {}

    readonly property var rows: card.posed
                                ? card.policy.rows(card.facts.system.sample,
                                                   card.facts.system.history)
                                : SystemStats.rows

    title: "System"

    Repeater {
        model: card.rows

        RowLayout {
            id: row

            required property var modelData

            Layout.fillWidth: true
            spacing: Theme.space2

            Icon {
                Layout.alignment: Qt.AlignVCenter
                name: row.modelData.icon
                size: 16
                color: Theme.textMuted
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2

                    Text {
                        text: row.modelData.label
                        color: Theme.textSecondary
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(10.5)
                    }

                    Text {
                        Layout.fillWidth: true
                        // What the percentage is of, where there is such a
                        // thing — a processor at 40% is not 40% of a number
                        // anyone wants written down.
                        visible: text !== ""
                        text: row.modelData.detail
                        color: Theme.textMuted
                        elide: Text.ElideRight
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(9.5)
                    }

                    Item { Layout.fillWidth: row.modelData.detail === "" }

                    // Monospaced, so a row does not shift sideways as its value
                    // goes from 9% to 10% — the one thing that makes a live
                    // readout hard to read is the readout moving.
                    Text {
                        text: row.modelData.value
                        color: Theme.textPrimary
                        font.family: Theme.fontMono
                        font.pointSize: Theme.pt(10.5)
                    }
                }

                Sparkline {
                    Layout.fillWidth: true
                    implicitHeight: 18
                    values: row.modelData.history
                    slots: card.policy.historyLength
                    color: Theme.accentDeep
                }
            }
        }
    }

    // What a machine with no readings at all looks like — the first tick of a
    // freshly-opened card, before /proc has been read once. A line rather than
    // an empty card, for #81's reason: a blank rectangle has two causes and
    // this is the harmless one.
    Text {
        Layout.fillWidth: true
        visible: card.rows.length === 0
        text: "Reading the machine…"
        color: Theme.textMuted
        font.family: Theme.fontUi
        font.pointSize: Theme.pt(10.5)
    }

    // --- the subscription -----------------------------------------------------

    Component.onCompleted: {
        if (!card.posed)
            SystemStats.watch();
        Logger.log("dashboard", "system monitor " + card.rows.length + " row(s)");
    }

    Component.onDestruction: if (!card.posed) SystemStats.release();
}
