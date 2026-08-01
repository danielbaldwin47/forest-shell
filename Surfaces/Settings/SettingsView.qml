// The settings window (#54): a floating toplevel with the ten-tab rail.
//
// A `FloatingWindow` and not a layer-shell surface, deliberately — this is an
// ordinary window, so placement, movement, resizing, tiling and the close
// button are the compositor's job and the shell writes none of it. That is also
// what makes it behave like every other application window on the desktop,
// which is the correct expectation for a settings dialog.
//
// One page is instantiated at a time. Ten tabs' worth of controls is a lot of
// bindings to hold live for a window that is usually closed, and the pages are
// pure views over `Config` — leaving a tab and coming back rebuilds it from the
// file, which is the same thing it showed.
//
// The rail is the navigation *skeleton*: all ten tabs are here from the first
// release, and the six #55 has not built yet open a page that says so and lists
// what the section already holds. Hiding them would make the window's shape a
// surprise later.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Core
import qs.Widgets
import qs.Surfaces.Settings.Controls
import qs.Surfaces.Settings.Tabs

FloatingWindow {
    id: window

    /// The tab on screen. Seeded from the state file and written back on every
    /// change, so the window reopens where it was left (#54).
    property string currentTab: tabs.resolve(ShellState.values.settings.lastTab)

    /// The window was closed from outside the shell — the compositor's close
    /// button or a window-manager kill. Whoever opened the window owns tearing
    /// it down; this only reports it.
    signal closeRequested()

    title: "forest-shell — settings"
    // Stated rather than assumed: the window exists only while it is open, so
    // it is mapped as soon as it is built, and the assignment the compositor
    // makes when the close button is hit is what `wasShown` below reads.
    visible: true
    implicitWidth: 900
    implicitHeight: 660
    minimumSize: Qt.size(720, 480)
    color: Theme.bgBase

    // A window that has been shown and is now not is a window that was closed.
    // The flag is what keeps the not-yet-mapped state — visible is false for a
    // moment after construction — from reading as a close.
    property bool wasShown: false
    onVisibleChanged: {
        if (window.visible)
            window.wasShown = true;
        else if (window.wasShown)
            window.closeRequested();
    }

    SettingsTabs { id: tabs }

    function selectTab(id: string): void {
        const resolved = tabs.resolve(id);
        if (window.currentTab === resolved)
            return;

        // Assigned, not bound: the binding above is the *initial* value from the
        // state file, and clicking a tab replaces it. The write below is what
        // makes the choice survive, and it is state rather than config because
        // which tab you had open is not part of your setup (#21).
        window.currentTab = resolved;
        ShellState.set("settings.lastTab", resolved);
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // --- the rail --------------------------------------------------------

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 196
            color: Theme.bgSunken

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: Theme.space5
                anchors.bottomMargin: Theme.space4
                spacing: Theme.space1

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.space5
                    Layout.rightMargin: Theme.space5
                    Layout.bottomMargin: Theme.space4
                    spacing: Theme.space3

                    Icon { name: "trees"; size: 18; color: Theme.accentPrimary }

                    Text {
                        Layout.fillWidth: true
                        text: "forest-shell"
                        color: Theme.textPrimary
                        font.family: Theme.fontDisplay
                        font.weight: Theme.weightDisplay
                        font.pointSize: Theme.pt(16)
                        elide: Text.ElideRight
                    }
                }

                Repeater {
                    model: tabs.tabs

                    Rectangle {
                        id: railItem

                        required property var modelData

                        readonly property bool selected: window.currentTab === railItem.modelData.id

                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.space2
                        Layout.rightMargin: Theme.space2
                        implicitHeight: 34
                        radius: Theme.radiusSm

                        // Selection is the launcher's idiom, and the shell has
                        // exactly one: a wash of the deep accent plus a rail of
                        // the interactive one down the leading edge.
                        color: railItem.selected
                            ? Qt.rgba(Theme.accentDeep.r, Theme.accentDeep.g,
                                      Theme.accentDeep.b, 0.18)
                            : (railHover.hovered ? Theme.surfaceOverlay : "transparent")

                        FogColorBehavior on color {}

                        Rectangle {
                            width: Theme.rail
                            height: parent.height - Theme.space2 * 2
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Theme.radiusFull
                            color: Theme.accentPrimary
                            visible: railItem.selected
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space4
                            anchors.rightMargin: Theme.space3
                            spacing: Theme.space3

                            Icon {
                                name: railItem.modelData.icon
                                size: 15
                                color: railItem.selected ? Theme.textPrimary : Theme.textMuted
                            }

                            Text {
                                Layout.fillWidth: true
                                text: railItem.modelData.title
                                color: railItem.selected ? Theme.textPrimary : Theme.textSecondary
                                font.family: Theme.fontUi
                                font.pointSize: Theme.pt(12.5)
                                font.weight: railItem.selected ? Theme.weightMedium
                                                               : Theme.weightRegular
                                elide: Text.ElideRight
                            }

                            // A tab whose controls are not built. Marked rather
                            // than hidden — the window's shape is honest from
                            // the first release.
                            Rectangle {
                                visible: !railItem.modelData.built
                                implicitWidth: 5
                                implicitHeight: 5
                                radius: Theme.radiusFull
                                color: Theme.accentStone
                            }
                        }

                        HoverHandler { id: railHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: window.selectTab(railItem.modelData.id) }
                    }
                }

                Item { Layout.fillHeight: true }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.space5
                    Layout.rightMargin: Theme.space5
                    text: "settings.json is the source of truth — hand edits land here live"
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(10.5)
                    lineHeight: Theme.lineHeightBody
                    lineHeightMode: Text.ProportionalHeight
                    wrapMode: Text.WordWrap
                }
            }
        }

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Theme.hairline
            color: Theme.borderSubtle
        }

        // --- the page --------------------------------------------------------

        Loader {
            id: page

            Layout.fillWidth: true
            Layout.fillHeight: true

            // Gated on the config being read, like every other surface (#12 §4)
            // — a settings window that flashes defaults and then snaps to the
            // real values is the worst place in the shell for that to happen.
            active: Config.ready
            sourceComponent: window.pageFor(window.currentTab)
        }
    }

    // Which page an id opens. Held here rather than in the tab registry because
    // the registry is pure data that tests load, and a page imports Quickshell.
    //
    // `built` is asked first so that "which tabs are implemented" is answered in
    // one place: the registry marks the rail with the same flag, and a page
    // added here without flipping it — or the reverse — would show a built tab
    // with a placeholder in it, or a placeholder with no dot beside it.
    function pageFor(id: string): Component {
        if (!(tabs.find(id)?.built ?? false))
            return placeholderPage;

        switch (id) {
        case "appearance": return appearancePage;
        case "bar": return barPage;
        case "launcher": return launcherPage;
        case "notifications": return notificationsPage;
        default: return placeholderPage;
        }
    }

    Component { id: appearancePage; AppearanceTab {} }
    Component { id: barPage; BarTab {} }
    Component { id: launcherPage; LauncherTab {} }
    Component { id: notificationsPage; NotificationsTab {} }

    Component {
        id: placeholderPage

        PlaceholderTab {
            readonly property var tab: tabs.find(window.currentTab)

            title: tab?.title ?? ""
            section: tab?.section ?? ""
        }
    }
}
