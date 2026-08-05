// The control tile's chevron must not also throw the tile's switch (#183).
//
// Reported as: press the arrow in the corner of the Wi-Fi tile and the network
// panel opens *and* Wi-Fi turns off. Same for Bluetooth, same for VPN — the
// three tiles that are a switch and a door at once
// (tests/tst_drillinpolicy.qml).
//
// ## Why this is at this seam at all
//
// Surfaces/Drawers/ControlTile.qml imports `qs.Core` and `qs.Widgets`, so
// qmltestrunner cannot load it — the tile itself is on the far side of the line
// CLAUDE.md draws. What *is* reachable here is the thing the bug actually was:
// a Qt input-routing rule, which QtQuick and QtTest can both provide without
// Quickshell anywhere near them. So this file does the same two things
// tests/tst_measure_blur.py does for the blur harness — it reproduces the
// mechanism the fix rests on, and then checks that the shipped file still
// carries the fix.
//
// 1. The mechanism, on a replica of the tile's nesting: a body handler on the
//    card and a door handler on a 24px `Item` in the corner. At the default
//    `TapHandler.DragThreshold` a handler takes only a *passive* grab, and a
//    passive grab is not exclusive — so a press in the corner reaches the door
//    handler and the ancestor body handler alike and both emit `tapped`. That
//    is #183, and it is pinned here rather than described, because "the child
//    handler takes the press" was the assumption the tile shipped on and it was
//    wrong.
//
// 2. The fix, on the same replica: `ReleaseWithinBounds` takes an exclusive grab
//    on press, which cancels the body's passive grab, so the corner means the
//    door and nothing else — while a press anywhere else on the card still means
//    the switch.
//
// 3. That ControlTile.qml still says so. A replica alone would stay green with
//    the property deleted from the shipped tile, which is the one regression
//    worth catching; reading a checked-in file to check it still contains the
//    line the shell depends on is the seam-1 shape #140 already established
//    (tests/RepoFile.qml, which tests/tst_clipboardpolicy.qml reads the
//    autostart conf with).
//
// Point 1 is a characterization test of Qt rather than of this shell: if some
// later Qt stops letting two handlers claim the same press, it goes red while
// the shell is perfectly correct. That is the point — the fix is a workaround
// for a routing rule, and the day the rule changes is the day to re-read it.
//
// What no seam checks: that the chevron is where a finger lands. That is a
// picture (seam 3) and a live press (a real session) — this file only decides
// where a press that *does* land on it goes.
import QtQuick
import QtTest

TestCase {
    id: root

    name: "ControlTileDoor"
    when: windowShown
    visible: true
    width: 200
    height: 120

    // The tile's own numbers at the time of writing — a 24px door inset from the
    // top-right corner by `Theme.space1`, which is 4. Nothing here depends on
    // them staying that: all they have to do is put one click inside the corner
    // target and one well clear of it. The tile's real geometry is seam 3's
    // (tools/capture-harness.sh --surface controlcenter).
    readonly property int doorSize: 24
    readonly property int doorMargin: 4

    property int switchTaps: 0
    property int doorTaps: 0

    /// The gesture policy under test, so one replica can answer both "what did
    /// the tile do before #183" and "what does it do now".
    property int doorPolicy: TapHandler.DragThreshold

    Rectangle {
        id: tile

        anchors.fill: parent

        // Surfaces/Drawers/ControlTile.qml's body handler: the whole card is the
        // switch.
        TapHandler {
            onTapped: root.switchTaps++
        }

        // ...and its door, declared after the body and inside it, which is the
        // nesting that caused the bug.
        Item {
            id: door

            anchors {
                top: parent.top
                right: parent.right
                margins: root.doorMargin
            }
            implicitWidth: root.doorSize
            implicitHeight: root.doorSize

            TapHandler {
                gesturePolicy: root.doorPolicy
                onTapped: root.doorTaps++
            }
        }
    }

    function init() {
        root.switchTaps = 0;
        root.doorTaps = 0;
    }

    /// The middle of the chevron's hit target.
    function clickDoor() {
        mouseClick(tile, root.width - root.doorMargin - root.doorSize / 2, root.doorMargin + root.doorSize / 2);
    }

    /// Well clear of it — the bottom-left of the card, where the label sits.
    function clickBody() {
        mouseClick(tile, 20, root.height - 20);
    }

    // --- 1. the bug ----------------------------------------------------------

    function test_the_default_policy_fires_both_handlers() {
        root.doorPolicy = TapHandler.DragThreshold;
        clickDoor();
        compare(root.doorTaps, 1, "the door did not open");
        compare(root.switchTaps, 1, "#183 was not a passive grab after all — re-read the fix");
    }

    // --- 2. the fix ----------------------------------------------------------

    function test_an_exclusive_grab_keeps_the_press_on_the_door() {
        root.doorPolicy = TapHandler.ReleaseWithinBounds;
        clickDoor();
        compare(root.doorTaps, 1, "the door did not open");
        compare(root.switchTaps, 0, "the chevron threw the tile's switch (#183)");
    }

    function test_the_body_is_still_the_switch() {
        root.doorPolicy = TapHandler.ReleaseWithinBounds;
        clickBody();
        compare(root.switchTaps, 1, "the card no longer toggles");
        compare(root.doorTaps, 0, "a press on the card opened the panel");
    }

    // --- 3. the shipped tile -------------------------------------------------

    function test_the_tile_ships_the_exclusive_grab() {
        const source = repo.read("../Surfaces/Drawers/ControlTile.qml");
        verify(source !== null, "no tile at Surfaces/Drawers/ControlTile.qml");

        // Bounded to the door's own handler rather than "somewhere below
        // `id: door`": the property is only the fix while it is on the handler
        // that opens the panel, and a loose search would stay green if it drifted
        // onto some later one.
        const doorAt = source.indexOf("id: door");
        verify(doorAt >= 0, "ControlTile.qml no longer declares `id: door`");

        const drillAt = source.indexOf("onTapped: tile.drillRequested()", doorAt);
        verify(drillAt >= 0, "the door no longer opens the panel");

        const handler = source.slice(doorAt, drillAt);
        verify(/gesturePolicy\s*:\s*TapHandler\.ReleaseWithinBounds/.test(handler),
               "the door's TapHandler dropped its gesturePolicy — #183 is back");
    }

    RepoFile { id: repo }
}
