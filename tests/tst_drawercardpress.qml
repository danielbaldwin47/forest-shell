// A press on a drawer's own card must not dismiss the drawer (#193).
//
// Reported as: click inside the control centre but miss a button — the padding,
// the header, the gap between two tiles — and the whole drawer closes, as if you
// had clicked the fog outside it. It was never only the control centre; all five
// drawers shared one cause, which Surfaces/Drawers/PressCatcher.qml sets out.
//
// ## Why this is at this seam at all
//
// The same argument tests/tst_controltiledoor.qml makes for #183, which is this
// file's model. Surfaces/Drawers/DrawerWindow.qml imports `Quickshell`, so
// qmltestrunner cannot load it — the window is on the far side of the line
// CLAUDE.md draws. What *is* reachable is the thing the bug actually was: a Qt
// hit-testing rule about which item accepts a press, which QtQuick and QtTest
// provide with Quickshell nowhere near them. So this file does the same three
// things:
//
// 1. The mechanism, on a replica of the window's nesting: a full-screen fog
//    catcher, and above it a `FocusScope` holding a card with a `TapHandler`
//    button on it. With nothing on the card accepting presses, a press on the
//    card's padding falls through to the fog catcher and reads as "clicked
//    away". A press on the *button* does not, and that half is measured here
//    rather than assumed: #183 showed a TapHandler takes only a passive grab,
//    and the tempting inference is that the press therefore carries on down to
//    the catcher as well — which would make every press in a drawer a dismiss.
//    It does not. A passive grab is about one handler not excluding another;
//    item-level delivery stops at the handler's item either way. The first
//    draft of this fix inferred otherwise and this file is what caught it, so
//    the wrong half is pinned next to the right one.
//
// 2. The fix, on the same replica: an enabled `MouseArea` filling the card,
//    declared before the card's content. It accepts the press, the fog catcher
//    never sees it, and the button still taps.
//
// 3. That the shipped files still say so. A replica alone would stay green with
//    `PressCatcher {}` deleted from all five tenants, which is the one
//    regression worth catching; reading a checked-in file to check it still
//    carries the line the shell depends on is the seam-1 shape #140 established
//    (tests/RepoFile.qml) and #183 reused.
//
// Point 1 is a characterization test of Qt rather than of this shell: if some
// later Qt stops delivering a press to a `MouseArea` under an item whose handler
// already took a passive grab, it goes red while the shell is perfectly correct.
// That is the point — the fix rests on a routing rule, and the day the rule
// changes is the day to re-read it.
//
// What no seam checks yet: that this holds through a real pointer on a real
// layer surface. That is seam 2, and it needs the virtual-pointer tool
// (`nested_click`) that #187 is adding on a parallel branch; it is not in this
// branch's lineage. Nor does anything here check where the card *is* — that is a
// picture (seam 3) and a live press. This file only decides where a press that
// does land on the card goes.
import QtQuick
import QtTest

TestCase {
    id: root

    name: "DrawerCardPress"
    when: windowShown
    visible: true
    width: 320
    height: 240

    // The replica's own numbers. Nothing here depends on them staying that: all
    // they have to do is put one press on the button, one on the card but well
    // clear of the button, and one on the fog well clear of the card. The real
    // geometry of each drawer is seam 3's.
    readonly property int cardW: 160
    readonly property int cardH: 100
    readonly property int buttonSize: 32

    /// Whether the card claims its own presses — the whole of the fix, held as a
    /// property so one replica answers both "what did a drawer do before #193"
    /// and "what does it do now".
    property bool guarded: true

    property int fogCloses: 0
    property int cardPresses: 0
    property int buttonTaps: 0
    property real sliderValue: -1

    // --- the replica ---------------------------------------------------------
    //
    // Surfaces/Drawers/DrawerWindow.qml's own nesting: the fog catcher first,
    // then the key scope as a *sibling declared after it*, so the tenant stacks
    // above the catcher. That stacking was never the problem — nothing in the
    // tenant accepted a press, so being on top bought it nothing.

    MouseArea {
        id: fog

        anchors.fill: parent
        onClicked: root.fogCloses++
    }

    FocusScope {
        id: keys

        anchors.fill: parent

        // Surfaces/Drawers/DrawerSlot.qml: an Item filling the window, with the
        // tenant's card centred in it. The slot is screen-sized, which is why
        // the catcher could not simply be put on the slot.
        Item {
            id: slot

            anchors.fill: parent

            Rectangle {
                id: card

                anchors.centerIn: parent
                width: root.cardW
                height: root.cardH

                // The fix. `enabled: false` is the shell before #193: a
                // MouseArea that does not accept is exactly as transparent to a
                // press as the bare Rectangle that used to be here.
                MouseArea {
                    anchors.fill: parent
                    enabled: root.guarded
                    acceptedButtons: Qt.AllButtons
                    onPressed: root.cardPresses++
                }

                // A tile, declared after the catcher and so hit-tested before
                // it. A TapHandler, because that is what almost every control
                // inside a drawer actually is.
                Item {
                    id: button

                    anchors.centerIn: parent
                    width: root.buttonSize
                    height: root.buttonSize

                    TapHandler {
                        onTapped: root.buttonTaps++
                    }
                }

                // A slider track. Surfaces/Drawers/ControlSlider.qml is the one
                // control that is item-level input rather than a handler, and it
                // is the one the ticket asks about by name: a drag that starts
                // here and wanders off the track before release must still move
                // the value and must not dismiss.
                MouseArea {
                    id: track

                    x: 10
                    y: parent.height - 26
                    width: 60
                    height: 16

                    onPressed: mouse => root.sliderValue = mouse.x
                    onPositionChanged: mouse => root.sliderValue = mouse.x
                }
            }
        }
    }

    function init() {
        root.fogCloses = 0;
        root.cardPresses = 0;
        root.buttonTaps = 0;
        root.sliderValue = -1;
        root.guarded = true;
    }

    /// The middle of the tile.
    function clickButton() {
        mouseClick(root, root.width / 2, root.height / 2);
    }

    /// On the card and well clear of the tile — the padding, where a miss lands.
    function clickCardPadding() {
        mouseClick(root, root.width / 2 - root.cardW / 2 + 8, root.height / 2 - root.cardH / 2 + 8);
    }

    /// The fog, well outside the card.
    function clickFog() {
        mouseClick(root, 6, 6);
    }

    // Absolute points, so a drag can be spelled out press-move-release. The card
    // is centred, so it spans 80..240 by 70..170; the track sits at its
    // bottom-left and the tile in its middle.
    readonly property point atTrack: Qt.point(120, 152)
    readonly property point atCardBackground: Qt.point(220, 100)
    readonly property point atFog: Qt.point(6, 6)

    // --- 2b. the ticket's two drag criteria ----------------------------------
    //
    // "Because the press decides, a press that starts on the card and releases
    // over the fog does not dismiss, and a drag that starts on a slider track
    // and wanders off it before release does not dismiss either." Both fall out
    // of the mouse grab rather than needing their own logic — whichever item
    // accepts the press keeps the move and the release — but they are the two
    // criteria a future refactor to a release-decided or geometry-decided
    // dismiss would silently break, so they are pinned rather than reasoned.

    function test_a_drag_off_the_slider_track_moves_it_and_does_not_dismiss() {
        mousePress(root, root.atTrack.x, root.atTrack.y);
        mouseMove(root, root.atCardBackground.x, root.atCardBackground.y);
        mouseRelease(root, root.atCardBackground.x, root.atCardBackground.y);

        // Positive guard: the drag really did drive the track. Without it the
        // dismiss assertion would also pass if the press had missed everything.
        verify(root.sliderValue >= 0, "the press missed the track — the replica's geometry is wrong");
        compare(root.fogCloses, 0, "a drag off a slider track dismissed the drawer (#193)");
    }

    function test_a_press_on_the_card_released_over_the_fog_does_not_dismiss() {
        mousePress(root, root.atCardBackground.x, root.atCardBackground.y);
        mouseMove(root, root.atFog.x, root.atFog.y);
        mouseRelease(root, root.atFog.x, root.atFog.y);

        compare(root.cardPresses, 1, "the press missed the card — the replica's geometry is wrong");
        compare(root.fogCloses, 0,
                "a press that began on the card dismissed on release over the fog (#193): "
                + "the press is supposed to decide");
    }

    // --- 1. the bug ----------------------------------------------------------

    function test_an_unguarded_card_falls_through_to_the_fog() {
        root.guarded = false;
        clickCardPadding();
        compare(root.fogCloses, 1, "#193 was not a fall-through after all — re-read the fix");
        compare(root.cardPresses, 0, "the disabled card catcher accepted a press");
    }

    /// The other half of the mechanism — see point 1 of the header for why the
    /// obvious inference from #183 is wrong and this is measured, not reasoned.
    function test_an_unguarded_button_does_not_fall_through_to_the_fog() {
        root.guarded = false;
        clickButton();
        // The positive guard: the press really did land on the tile. Without it
        // the line below would also pass if the click had missed everything.
        compare(root.buttonTaps, 1, "the press missed the tile — the replica's geometry is wrong");
        compare(root.fogCloses, 0,
                "a TapHandler no longer stops item-level delivery — re-read PressCatcher.qml, "
                + "the bug is now bigger than the card's bare areas");
    }

    // --- 2. the fix ----------------------------------------------------------

    function test_a_guarded_card_swallows_a_press_on_its_padding() {
        clickCardPadding();
        // Positive guard first: the catcher saw the press, so `fogCloses == 0`
        // below means "swallowed here" and not "missed the window entirely".
        compare(root.cardPresses, 1, "the press missed the card — the replica's geometry is wrong");
        compare(root.fogCloses, 0, "pressing the card's own padding dismissed the drawer (#193)");
    }

    function test_a_guarded_card_still_taps_its_buttons() {
        clickButton();
        compare(root.buttonTaps, 1, "the card catcher swallowed the tile's own press");
        // Zero, not one: the press stops at the tile's handler and never reaches
        // the catcher underneath — the same rule as the unguarded case above.
        // The catcher is a backstop for presses that miss, so a press that hits
        // is not its business.
        compare(root.cardPresses, 0, "the press reached past the tile's handler to the catcher");
        compare(root.fogCloses, 0, "pressing a tile dismissed the drawer (#193)");
    }

    function test_the_fog_still_dismisses() {
        clickFog();
        compare(root.fogCloses, 1, "the fix took the fog's own dismiss with it");
        compare(root.cardPresses, 0, "the card catcher reached outside the card");
    }

    // --- 3. the shipped files ------------------------------------------------

    RepoFile { id: repo }

    function test_the_catcher_is_a_mousearea_that_fills_its_card() {
        const source = repo.read("../Surfaces/Drawers/PressCatcher.qml");
        verify(source !== null, "no catcher at Surfaces/Drawers/PressCatcher.qml");

        // Both halves are load-bearing and neither is obvious from the call
        // sites, which are a bare `PressCatcher {}`: a root that is not a
        // MouseArea would accept nothing, and without the fill it would accept
        // nothing over a zero-sized area, which is the same bug with a longer
        // diff.
        verify(/^MouseArea\s*\{/m.test(source),
               "the catcher's root is no longer a MouseArea — it would accept nothing");
        verify(/anchors\.fill:\s*parent/.test(source),
               "the catcher no longer fills its card — a call site cannot supply this");
    }

    /// Every tenant, and the card it has to be inside. `Surfaces/Drawers/` holds
    /// exactly these five drawers; a sixth arriving without a catcher is a bug
    /// this file cannot see, which is what the seam-2 note in the header is for.
    readonly property var tenants: [
        { file: "ControlCenter.qml", card: "id: panel" },
        { file: "NotificationCenter.qml", card: "id: panel" },
        { file: "Dashboard.qml", card: "id: panel" },
        { file: "SessionMenu.qml", card: "id: card" },
        { file: "Launcher.qml", card: "id: card" }
    ]

    function test_every_drawer_ships_the_catcher_data() {
        return root.tenants;
    }

    /// The type names of a card's *direct* child objects, in declaration order.
    ///
    /// Bounded properly rather than by "PressCatcher appears somewhere after the
    /// card's id", which was this check's first draft and was worth almost
    /// nothing: it stayed green with the catcher inside a grandchild, after the
    /// card's closing brace, or — in Launcher.qml, where the field and results
    /// are siblings of the card — inside any of them. Both properties the fix
    /// rests on are about *this* list: that PressCatcher is in it (a child of the
    /// card, not of the screen-sized root, where it would swallow the fog's own
    /// dismiss) and that it is first (below the card's controls, not over them).
    ///
    /// Walks braces from the card's body, counting only depth-1 opens whose
    /// preceding token is capitalised — which is how a QML object declaration
    /// differs from a grouped property (`anchors {`) or an attached one
    /// (`Behavior on height {`). Comments are stripped first so a brace in prose
    /// cannot skew the depth.
    function cardChildTypes(source, cardMarker) {
        const clean = source.replace(/\/\/[^\n]*/g, "");
        const idAt = clean.indexOf(cardMarker);
        if (idAt < 0)
            return null;

        // The card's own opening brace is the last one before its `id:` line.
        const open = clean.lastIndexOf("{", idAt);
        if (open < 0)
            return null;

        const types = [];
        let depth = 0;
        for (let i = open; i < clean.length; i++) {
            const c = clean[i];
            if (c === "{") {
                if (depth === 1) {
                    const name = /([A-Za-z_]\w*)\s*$/.exec(clean.slice(0, i));
                    if (name !== null && /^[A-Z]/.test(name[1]))
                        types.push(name[1]);
                }
                depth++;
            } else if (c === "}") {
                depth--;
                if (depth === 0)
                    return types;
            }
        }
        return null;   // unbalanced — the file is not what this check assumes
    }

    function test_every_drawer_ships_the_catcher(row) {
        const source = repo.read("../Surfaces/Drawers/" + row.file);
        verify(source !== null, "no drawer at Surfaces/Drawers/" + row.file);
        verify(/\bPressCatcher\s*\{\s*\}/.test(source),
               row.file + " no longer instantiates PressCatcher — a press on its card dismisses it (#193)");

        const children = cardChildTypes(source, row.card);
        verify(children !== null,
               row.file + " no longer declares its card as `" + row.card + "` with a balanced body — re-read this check");
        verify(children.indexOf("PressCatcher") >= 0,
               row.file + " declares PressCatcher outside its card, where it does not guard it (#193). "
               + "The card's children are: " + children.join(", "));
        compare(children[0], "PressCatcher",
                row.file + " declares PressCatcher after `" + children[0] + "`, so it sits over that control "
                + "instead of under it and will swallow its presses (#193)");
    }
}
