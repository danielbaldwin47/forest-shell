// Notifications — the per-app rules editor (#54, for #42/#43).
//
// Three states per app: **normal**, **silent** (history only, no popup) and
// **blocked** (nothing at all). The rules live in settings and are enforced by
// the notification server, which is the reason they are here and not on the
// notification card — a rule is a standing decision about an app, not something
// you set while dismissing a toast.
//
// #43 lists every app that has *ever* notified. That list is the notification
// service's history, read through `knownApps` below (#71) — live, so an app
// that notifies while this tab is open grows a row under it. An app can still
// be named outright, which is how a rule is set for something that has not
// notified yet, or has fallen off the end of `historyLimit`.
//
// Do-not-disturb is deliberately absent: it is situational rather than setup, so
// it lives in the state file and belongs to the control centre, not to a config
// tab (#21).
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets
import qs.Services.Notifications
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
        note: "No rules yet, and nothing has notified. Every app is normal until told "
              + "otherwise — apps appear here as they notify, or name one below to rule on "
              + "it before it does."
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

    /// Apps the notification service has seen (#71). One binding: every rule
    /// about what "seen" means is in NotificationPolicy, on the far side of the
    /// service, where a test can reach it.
    readonly property var knownApps: Notifications.knownApps

    /// Everything to show a row for, in one sorted list so the order does not
    /// jump as rules are set and cleared.
    readonly property var apps: {
        // Every source is folded the way a notification's own key is
        // (NotificationPolicy.appKey), and folded here rather than at each
        // source because only one of the three arrives folded already.
        // `notifications.apps` is hand-editable and `ruleFor` matches it
        // case-insensitively, so a `"Firefox": "silent"` in the file and a
        // `firefox` row in history are one app — two rows for it would be two
        // three-way controls fighting over one setting.
        const rules = Object.keys(Config.values.notifications.apps);
        const all = rules.concat(page.knownApps).concat(page.named)
                         .map(app => Notifications.policy.appKey(app, ""));
        return all.filter((app, i) => app !== "" && all.indexOf(app) === i).sort();
    }

    // The tab's answer to "why is that app not listed" (#71). An app that has
    // never notified, one that has fallen off the end of `historyLimit`, and a
    // history that never reached this binding all look the same on screen —
    // like an app that is simply absent.
    onAppsChanged: Logger.log("settings", "notifications tab: " + page.apps.length
                              + " app row(s), " + page.knownApps.length + " from history")

    function nameApp(text: string): void {
        // Through the same fold the list above uses, so that what is typed is
        // compared against the rows on screen as the same kind of thing.
        const app = Notifications.policy.appKey(text, "");
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
