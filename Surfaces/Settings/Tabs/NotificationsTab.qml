// Notifications — the per-app rules editor (#54, for #42/#43).
//
// Three states per app: **normal**, **silent** (history only, no popup) and
// **blocked** (nothing at all). The rules live in settings and are enforced by
// the notification server, which is the reason they are here and not on the
// notification card — a rule is a standing decision about an app, not something
// you set while dismissing a toast.
//
// #43 lists every app that has *ever* notified. That list comes from the
// notification service's history, which does not exist yet (#42), so until it
// does the tab shows the apps that already have a rule and lets one be named
// outright. `knownApps` below is the single seam that turns into a live list —
// one binding, no other change here.
//
// Do-not-disturb is deliberately absent: it is situational rather than setup, so
// it lives in the state file and belongs to the control centre, not to a config
// tab (#21).
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets
import qs.Surfaces.Settings.Controls

TabPage {
    id: page

    title: "Notifications"
    section: "notifications"
    blurb: "Which apps may interrupt you. Silent still keeps the notification in history; "
           + "blocked drops it entirely."

    SectionHeader { text: "Per-app rules" }

    SectionNote {
        visible: page.apps.length === 0
        note: "No rules yet. Every app is normal until told otherwise — name one below to "
              + "change that. Once the notification service lands, every app that has ever "
              + "notified will be listed here without being named."
    }

    Repeater {
        model: page.apps

        NotificationRuleRow {
            required property string modelData

            app: modelData
            // A row that is only here because it was typed in has nothing in the
            // file behind it, so it offers removal rather than a reset.
            dismissable: page.named.indexOf(modelData) >= 0
            onDismissed: page.forget(modelData)
        }
    }

    // --- naming an app -------------------------------------------------------

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space2
        spacing: Theme.space3

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 30
            radius: Theme.radiusSm
            color: Theme.bgSunken
            border.width: Theme.hairline
            border.color: appField.activeFocus ? Theme.borderStrong : Theme.borderSubtle

            TextInput {
                id: appField

                anchors.fill: parent
                anchors.leftMargin: Theme.space3
                anchors.rightMargin: Theme.space3
                verticalAlignment: TextInput.AlignVCenter
                clip: true

                color: Theme.textPrimary
                selectionColor: Theme.accentDeep
                selectedTextColor: Theme.textPrimary
                font.family: Theme.fontMono
                font.pointSize: Theme.pt(11.5)

                onAccepted: page.nameApp(text)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: appField.text === ""
                    // The desktop entry name, which is what a notification
                    // carries as its app id.
                    text: "app id, e.g. org.mozilla.firefox"
                    color: Theme.textMuted
                    font.family: appField.font.family
                    font.pointSize: appField.font.pointSize
                }
            }
        }

        Rectangle {
            implicitWidth: addRow.implicitWidth + Theme.space4 * 2
            implicitHeight: 30
            radius: Theme.radiusSm
            opacity: appField.text.trim() === "" ? 0.4 : 1
            color: addHover.hovered ? Theme.surfaceOverlay : Theme.surfaceRaised
            border.width: Theme.hairline
            border.color: Theme.borderSubtle

            RowLayout {
                id: addRow

                anchors.centerIn: parent
                spacing: Theme.space2

                Icon { name: "plus"; size: 13; color: Theme.textSecondary }

                Text {
                    text: "Add app"
                    color: Theme.textSecondary
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(11.5)
                }
            }

            HoverHandler {
                id: addHover
                enabled: appField.text.trim() !== ""
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                enabled: appField.text.trim() !== ""
                onTapped: page.nameApp(appField.text)
            }
        }
    }

    // --- what is listed ------------------------------------------------------

    /// Apps named in this window that have no rule written yet. Not persisted:
    /// an app the user named and then left at normal is not a setting, and
    /// writing it would put noise in a file meant to be read.
    property var named: []

    /// Apps the notification service has seen. Empty until #42 lands; this is
    /// the seam that becomes `Notifications.knownApps`.
    readonly property var knownApps: []

    /// Everything to show a row for, in one sorted list so the order does not
    /// jump as rules are set and cleared.
    readonly property var apps: {
        const rules = Object.keys(Config.values.notifications.apps);
        const all = rules.concat(page.knownApps).concat(page.named);
        return all.filter((app, i) => all.indexOf(app) === i).sort();
    }

    function nameApp(text: string): void {
        const app = text.trim();
        if (app === "" || page.apps.indexOf(app) >= 0) {
            appField.text = "";
            return;
        }
        page.named = page.named.concat([app]);
        appField.text = "";
    }

    function forget(app: string): void {
        page.named = page.named.filter(entry => entry !== app);
    }
}
