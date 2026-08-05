// The dashboard (#49) — the shared drawer window's fifth and last tenant.
//
// A header and a stack of cards, hanging from the top edge under the bar's
// clock, which is the thing that opens it (#27's "each drawer is anchored to
// what opened it"; the clock is in the centre cluster, so this is the one
// drawer anchored to the middle of the bar rather than to a corner).
//
// ## Registry-driven, like the bar
//
// There is no hardcoded card list here: `dashboard.cards` in settings.json is
// one list of names, Surfaces/Drawers/DashboardRegistry.qml is the only thing
// that knows which names exist, and the column below is a `Repeater` over the
// resolved result. Adding, removing and reordering cards is editing an array,
// and it takes effect on save with no reload — the resolution is a binding on
// `Config.values`.
//
// The cards are loaded **by URL** out of `Cards/`, which is why this file
// imports that directory even though it names no type from it: Quickshell turns
// a directory into a `qs.` module only when it walks an import naming it, and a
// directory reached exclusively by `Qt.resolvedUrl` never becomes one — a card
// loaded that way would then fail to find its own siblings (#73, and
// Surfaces/Bar/BarContent.qml says it at length).
//
// ## What this file decides, which is as little as possible
//
// The month grid is Surfaces/Drawers/CalendarPolicy.qml, the media card's
// arithmetic is Services/Media/MprisPolicy.qml and which cards exist is the
// registry — all three on the QtQuick-only side of the line where `tests/`
// reaches them. What is left here is a header, a column and `facts`.
//
// ## `facts`, and why a dashboard needs posing
//
// The same concession Surfaces/Drawers/ControlCenter.qml makes, for the same
// reason: a capture of this panel would otherwise be a picture of whatever is
// playing on the machine that ran it, on whatever day it ran — and neither is a
// thing a seam-3 check can assert on. Assigning `facts` replaces the binding
// below; the shell never does, tools/capture-harness.sh always does.
//
//     facts: ({ now: new Date(2026, 7, 1, 19, 26),
//               profile: { name: "Daniel", avatar: "" },
//               media: { showing: true, title: …, art: …, length: 214, … } })
//
// A card reads the key it is about and nothing else, and a `facts` with only
// some of them posed leaves the rest live.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets as QsWidgets
import qs.Core
import qs.Widgets
// Nothing below names a type from `Cards/`, and the import still has to be here
// — see the header.
import qs.Surfaces.Drawers.Cards

FocusScope {
    id: root

    /// Raised when the dashboard wants the drawer gone.
    signal closeRequested(string reason)

    readonly property DashboardRegistry registry: DashboardRegistry {}

    /// The pose, or null for the live shell. See the header.
    property var facts: null

    /// A component dimension, not a token (#8): seven day cells wide enough to
    /// hold two digits with air around them, and narrow enough that the panel
    /// reads as a column hanging off the clock rather than as a window.
    readonly property int panelWidth: 380

    /// Never taller than the screen it hangs on, less its margins.
    readonly property int maxPanelHeight: Math.max(240, root.height - Theme.space4 * 2)

    /// The measurement region for tools/capture-harness.sh, and nothing in the
    /// shell reads it. One and not three, unlike the control centre's: every
    /// text in this panel is drawn on the same two fills, so the panel's own
    /// average is a number about a pairing that exists.
    readonly property alias panelItem: panel

    /// The cards on screen, in order. Unknown and repeated names are dropped as
    /// this is resolved, with a warning naming each one, so a typo costs one
    /// card instead of the dashboard.
    ///
    /// **Written rather than bound**, which is #75's rule and the one thing
    /// about this panel that is not obvious: Core/SpecFile.qml replaces
    /// `Config.values` whole on every reload and every `set()`, so a binding
    /// here would hand the `Repeater` below a new array identity when *any* key
    /// in settings.json changed. A `Repeater` does not diff a JS array, so the
    /// bar's blur toggle would destroy and rebuild every card — the calendar
    /// would snap back from the month you paged to, and the media card would
    /// remount mid-track.
    ///
    /// So the resolution is a binding and the assignment is not: `configured`
    /// changes with the file, and `cards` changes only when the dashboard
    /// actually differs (DashboardRegistry.same).
    property var cards: []

    readonly property var configured: root.registry.resolve(Config.values.dashboard.cards)

    onConfiguredChanged: {
        if (!root.registry.same(root.cards, root.configured))
            root.cards = root.configured;
    }

    /// The clock this panel reads. One tick a minute, shell-wide (Core/Time.qml)
    /// — and the format is nobody's here either: Core/TimeFormat.qml resolves
    /// it once for every surface that draws a clock (#93).
    readonly property date now: root.facts && root.facts.now ? root.facts.now : Time.now

    readonly property var profile: root.facts && root.facts.profile
                                 ? root.facts.profile
                                 : Config.values.dashboard.profile

    /// What the header calls you. The configured name, or the login name, or
    /// nothing — and nothing is a header that is a clock, rather than a header
    /// with a hole in it.
    readonly property string userName: root.profile.name !== ""
                                     ? root.profile.name
                                     : (Quickshell.env("USER") ?? "")

    focus: true

    Rectangle {
        id: panel

        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            margins: Theme.space4
        }

        readonly property int padding: Theme.space3

        width: root.panelWidth
        // Sized *from* the column rather than anchored to it, for the reason
        // Surfaces/Drawers/ControlCenter.qml documents: an `anchors.fill`
        // between a layout and its container is a height cycle, and Qt breaks it
        // by zeroing the layout — which draws the panel as its header alone with
        // everything stacked at x=0.
        height: Math.min(column.implicitHeight + panel.padding * 2, root.maxPanelHeight)

        color: Theme.surface
        radius: Theme.radiusLg
        border.width: Theme.hairline
        border.color: Theme.borderSubtle

        // First child: the card's own controls are hit-tested before it. See
        // Surfaces/Drawers/PressCatcher.qml (#193).
        PressCatcher {}

        // The stack is allowed to be longer than the screen — five cards on a
        // laptop will be — and what must not happen is the panel growing past
        // the display it hangs on. So the body scrolls inside the height it is
        // given, the way the control centre's detail views do.
        Flickable {
            id: body

            x: panel.padding
            y: panel.padding
            width: panel.width - panel.padding * 2
            height: panel.height - panel.padding * 2

            contentWidth: width
            contentHeight: column.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            interactive: contentHeight > height

            ColumnLayout {
                id: column

                width: body.width
                spacing: Theme.space3

                // --- the header ---------------------------------------------
                //
                // The date and the time, and who this machine belongs to. Not a
                // card and not in the registry: it is what the panel *is* —
                // a dashboard whose header could be removed from a config would
                // be a panel that could be configured into a blank rectangle.

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space3

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: Qt.formatDateTime(root.now, TimeFormat.time)
                            color: Theme.textPrimary
                            // The display serif, which the brief allows "clock
                            // only, once, never twice" — this and the bar's
                            // clock are the same object seen at two sizes, and
                            // they are never both on screen at rest.
                            font.family: Theme.fontDisplay
                            font.weight: Theme.weightDisplay
                            font.pointSize: Theme.pt(30)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: Qt.formatDate(root.now, TimeFormat.date)
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(11.5)
                        }
                    }

                    // The face, with the name under it. Together in one column
                    // rather than spread across the header, because they are one
                    // thing — a name floating on the other side of a panel from
                    // the picture it belongs to reads as a second heading.
                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Theme.space1

                        QsWidgets.ClippingRectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 44
                            implicitHeight: 44
                            radius: width / 2
                            color: Theme.surfaceOverlay

                            // The monogram under the picture, so a machine with
                            // no account picture — which is most of them — gets
                            // a considered circle rather than a missing image.
                            Text {
                                anchors.centerIn: parent
                                visible: avatar.status !== Image.Ready
                                text: root.userName.substring(0, 1).toUpperCase()
                                color: Theme.textSecondary
                                font.family: Theme.fontDisplay
                                font.weight: Theme.weightDisplay
                                font.pointSize: Theme.pt(18)
                            }

                            Image {
                                id: avatar

                                anchors.fill: parent
                                // Empty is not a URL: an unset key would
                                // otherwise resolve against the config directory
                                // and log a failed load on every open.
                                source: root.profile.avatar !== ""
                                        ? Qt.resolvedUrl(root.profile.avatar) : ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 88
                                sourceSize.height: 88
                                asynchronous: true
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: 120
                            visible: root.userName !== ""
                            text: root.userName
                            color: Theme.textMuted
                            elide: Text.ElideRight
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(10.5)
                        }
                    }
                }

                // --- the cards ------------------------------------------------

                Repeater {
                    model: root.cards

                    Loader {
                        id: cardLoader

                        required property string modelData

                        Layout.fillWidth: true

                        // A card that hides itself must take its gap with it —
                        // the media card is absent with nothing playing — and
                        // `shown` is asked of the item rather than `visible`
                        // for the reason Cards/MediaCard.qml documents.
                        visible: cardLoader.item !== null
                                 && cardLoader.item.shown !== false

                        // Synchronous: the panel is sized from this column, and
                        // a card arriving a frame later would show as the whole
                        // dashboard resizing after it opened.
                        asynchronous: false
                        source: Qt.resolvedUrl(
                            "Cards/" + root.registry.cards[cardLoader.modelData].file)

                        // The pose, pushed rather than bound: a card loaded from
                        // a URL cannot see this file's ids, and a `facts` the
                        // harness assigns after construction still has to reach
                        // it.
                        function pose(): void {
                            if (cardLoader.item !== null && "facts" in cardLoader.item)
                                cardLoader.item.facts = root.facts;
                        }

                        onLoaded: cardLoader.pose()

                        onStatusChanged: if (cardLoader.status === Loader.Error)
                            Logger.warn("dashboard",
                                        "card failed to load: " + cardLoader.modelData)

                        Connections {
                            target: root
                            function onFactsChanged() { cardLoader.pose(); }
                        }
                    }
                }
            }
        }
    }

    // The first resolution, and the panel's own line — the evidence a harness
    // reads that the stack was assembled from the config rather than drawn
    // empty (#81).
    //
    // The assignment is here as well as in the handler above because a property
    // that evaluates its initial binding before anything is listening has
    // already had its one change signal: a panel built with `cards` still empty
    // is a dashboard that draws nothing at all.
    Component.onCompleted: {
        if (!root.registry.same(root.cards, root.configured))
            root.cards = root.configured;

        Logger.log("dashboard", root.cards.length + " card(s): "
                   + (root.cards.length > 0 ? root.cards.join(", ") : "none"));
    }
}
