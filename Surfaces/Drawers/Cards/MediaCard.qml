// What is playing, in full (#49).
//
// The bar has a pill and the control centre has a strip; this is the whole
// player — cover art, two lines of text, three transport buttons and a track
// position you can drag. All three read the same facade
// (Services/Media/Mpris.qml), so which player they are about cannot disagree.
//
// ## The position, and what it costs
//
// MPRIS position does not push: upstream will not update it reactively "to avoid
// excessive property updates wasting CPU while position is not actively
// monitored", so a moving progress bar is a poll that some file has to own. This
// one owns it, and only while it is on screen and something is actually playing
// — the timer below is the shell's *only* per-second wakeup, it exists for as
// long as a drawer is open, and it stops when the drawer closes with the card in
// it. That is the whole reason the bar's pill has never shown elapsed time
// (#22 §5).
//
// A paused card still shows the right position: it asks once on arrival and once
// on every state change, which is a wakeup per press rather than per second.
//
// ## Absent rather than empty
//
// With nothing playing the card is not on the dashboard at all — no art
// placeholder, no greyed transport. A transport with no track is three buttons
// that do nothing, which is the furniture #9 keeps off the bar and has no more
// business here.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets as QsWidgets
import qs.Core
import qs.Widgets
// Its own directory, explicitly: this file is loaded by URL, and a file
// Quickshell serves through its interceptor gets no implicit sibling
// resolution — without this line `CardFrame` is "not a type" and the card
// drops out of the dashboard with one warning (#73).
import qs.Surfaces.Drawers.Cards
import qs.Services.Media

CardFrame {
    id: card

    /// The dashboard's pose, or null for the live shell. `facts.media` replaces
    /// the whole of `state` below, which is what lets seam 3 capture a card with
    /// cover art on a machine that is not playing anything
    /// (Surfaces/Drawers/Dashboard.qml holds the shape).
    property var facts: null

    readonly property bool posed: card.facts !== null && card.facts.media !== undefined

    /// Everything the card draws, in one object, so that the posed and the live
    /// case differ in one place rather than in fifteen bindings.
    readonly property var state: card.posed ? card.facts.media : ({
        showing: Mpris.showing,
        title: Mpris.trackTitle || Mpris.label,
        artist: Mpris.trackArtist,
        art: Mpris.artUrl,
        playing: Mpris.playing,
        canGoBack: Mpris.canGoBack,
        canToggle: Mpris.canToggle,
        canSkip: Mpris.canSkip,
        position: Mpris.position,
        length: Mpris.length,
        scrubbable: Mpris.scrubbable
    })

    readonly property real fraction: Mpris.policy.progress(card.state.position,
                                                           card.state.length)

    /// The whole card, gone when there is no player.
    ///
    /// `shown` and not `visible`, which is the card contract and not a synonym:
    /// the dashboard's loader reads this and takes the card's *gap* with it, and
    /// asking the item about `visible` instead deadlocks — Qt forces every child
    /// of an invisible item to read `visible: false`, so a loader that starts
    /// hidden would hide the card it then loaded, forever (measured on the bar,
    /// Surfaces/Bar/BarContent.qml).
    readonly property bool shown: card.state.showing === true

    // No caption: the track's own title is the heading.

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space3

        // --- the cover -------------------------------------------------------
        //
        // Clipped to the card's own radius rather than drawn square: album art
        // is the one arbitrary image the shell puts on screen, and a square of
        // someone else's artwork inside a rounded card is the corner that makes
        // the whole panel look unfinished.
        QsWidgets.ClippingRectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 64
            implicitHeight: 64
            radius: Theme.radiusSm
            color: Theme.surfaceOverlay

            // The placeholder under the art, which is what a track with no
            // cover — most podcasts, every local file nobody tagged — is left
            // with. A glyph and not an empty square: the square would read as
            // art that failed to load.
            Icon {
                anchors.centerIn: parent
                visible: cover.status !== Image.Ready
                name: "disc-3"
                size: 24
                color: Theme.textMuted
            }

            Image {
                id: cover

                anchors.fill: parent
                source: card.state.art ?? ""
                fillMode: Image.PreserveAspectCrop
                // Bounded, and bounded to what is drawn: cover art arrives at
                // whatever size the client cached it at, and an unbounded decode
                // of a 3000px sleeve is the wallpaper trap (#73) in a 64px box.
                sourceSize.width: 128
                sourceSize.height: 128
                asynchronous: true
                cache: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space1

            Text {
                Layout.fillWidth: true
                text: card.state.title ?? ""
                color: Theme.textPrimary
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(12)
                font.weight: Theme.weightMedium
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.state.artist ?? ""
                color: Theme.textMuted
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(10.5)
            }

            // --- the position ------------------------------------------------

            Item {
                id: scrubber

                Layout.fillWidth: true
                Layout.topMargin: Theme.space1
                implicitHeight: 14

                readonly property bool scrubbable: card.state.scrubbable === true

                // The whole row is the target, not the 4px bar inside it: a
                // 4px-tall drag target is one nobody hits.
                HoverHandler {
                    id: scrubHover
                    cursorShape: scrubber.scrubbable ? Qt.PointingHandCursor
                                                     : Qt.ArrowCursor
                }

                TapHandler {
                    enabled: scrubber.scrubbable
                    onTapped: point => card.seek(point.position.x / scrubber.width)
                }

                // Dragged rather than only tapped, because a position is
                // something you *look for* — the release is the seek, so the
                // player is asked once at the end rather than on every frame of
                // the drag.
                DragHandler {
                    id: scrubDrag

                    enabled: scrubber.scrubbable
                    target: null
                    yAxis.enabled: false

                    onActiveChanged: if (!active)
                        card.seek(centroid.position.x / scrubber.width)
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: height / 2
                    color: Theme.surfaceOverlay

                    Rectangle {
                        width: parent.width * (scrubDrag.active
                                               ? Math.max(0, Math.min(1, scrubDrag.centroid.position.x
                                                                         / scrubber.width))
                                               : card.fraction)
                        height: parent.height
                        radius: parent.radius
                        // Lit while the pointer is on it, so a bar that can be
                        // dragged says so before it is dragged — and one that
                        // cannot stays quiet.
                        color: scrubber.scrubbable && (scrubHover.hovered || scrubDrag.active)
                               ? Theme.accentPrimary : Theme.accentDeep
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                Text {
                    text: Mpris.policy.clock(card.state.position)
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pointSize: Theme.pt(10)
                }

                Item { Layout.fillWidth: true }

                Text {
                    // Absent rather than `0:00` when the player will not say how
                    // long the track is: a live stream has no end, and a zero
                    // there would be a claim that it does.
                    visible: Number(card.state.length) > 0
                    text: Mpris.policy.clock(card.state.length)
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pointSize: Theme.pt(10)
                }
            }
        }
    }

    // --- the transport --------------------------------------------------------

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space1
        spacing: Theme.space4

        Item { Layout.fillWidth: true }

        TransportButton {
            glyph: "skip-back"
            dimmed: card.state.canGoBack !== true
            onPressed: Mpris.previous()
        }

        TransportButton {
            glyph: card.state.playing === true ? "pause" : "play"
            size: 22
            dimmed: card.state.canToggle !== true
            onPressed: Mpris.togglePlaying()
        }

        TransportButton {
            glyph: "skip-forward"
            dimmed: card.state.canSkip !== true
            onPressed: Mpris.next()
        }

        Item { Layout.fillWidth: true }
    }

    /// Ask the player to move. Posed, it does nothing at all — a capture must
    /// not reach the session's real player, which is the same hazard
    /// tools/drawer-harness.sh handles by restoring the host's radios.
    function seek(fraction: real): void {
        if (!card.posed)
            Mpris.seekToFraction(fraction);
    }

    // --- keeping the position honest -----------------------------------------

    Timer {
        // The shell's one per-second wakeup, and every condition on it is load
        // bearing: nothing polls for a card that is not on screen, for a posed
        // capture, for a paused player, or for a track with no length to be a
        // fraction of.
        interval: 1000
        repeat: true
        running: card.visible && !card.posed
                 && card.state.playing === true && Number(card.state.length) > 0
        onTriggered: Mpris.refresh()
    }

    // The two moments a poll cannot cover: the card arriving over a player that
    // is already halfway through a track, and a press that moves the position
    // without any time passing.
    Component.onCompleted: {
        if (!card.posed)
            Mpris.refresh();
        Logger.log("dashboard", "media "
                   + (card.shown ? card.state.title : "no player"));
    }

    Connections {
        target: card.posed ? null : Mpris
        function onPlayingChanged() { Mpris.refresh(); }
        function onChosenIdChanged() { Mpris.refresh(); }
    }

    // A transport button. Local rather than in Widgets/, for the reason the
    // control centre's is: the shell's icon buttons are each shaped by their own
    // surface, and this one is bigger than the strip's because the card is
    // something you reach for rather than glance at.
    component TransportButton: Item {
        id: button

        required property string glyph
        property int size: 18
        property bool dimmed: false

        signal pressed

        implicitWidth: 34
        implicitHeight: 34

        HoverHandler {
            id: buttonHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: button.pressed()
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: buttonHover.hovered ? Theme.surfaceOverlay : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: Theme.duration(Theme.motionFast)
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.fogEase
                }
            }
        }

        Icon {
            anchors.centerIn: parent
            name: button.glyph
            size: button.size
            // Dimmed rather than hidden: a player that will not skip is worth
            // showing as a player that will not skip.
            color: button.dimmed ? Theme.textMuted
                 : buttonHover.hovered ? Theme.accentPrimary : Theme.textSecondary
        }
    }
}
