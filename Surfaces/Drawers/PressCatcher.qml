// Makes a drawer's own card solid to the pointer (#193).
//
// Reported as: press the control centre anywhere that is not a button — the
// padding, the header, the gap between two tiles — and the whole drawer closes,
// exactly as if you had pressed the fog outside it. It was never only the
// control centre; all five drawers had it, for one shared reason.
//
// ## The reason
//
// Surfaces/Drawers/DrawerWindow.qml catches a press on the fog with a
// full-screen `MouseArea` and calls `Drawers.close("clicked away")`. The tenant
// is a *sibling* of that catcher, declared after it, so it stacks above — which
// would be enough if anything in the tenant accepted a press. Nothing does. A
// card is a `Rectangle` and a `Rectangle` is invisible to hit-testing; the
// tenant root is a `FocusScope`, which accepts keys and not clicks. So a press
// on the card fell through to the catcher underneath and was read as a press on
// the fog.
//
// The controls were never the problem, and it is worth being exact about that
// because the obvious guess is wrong. Almost every control inside a drawer is a
// `TapHandler` (ControlTile, RoundIconButton, ControlSlider, DrillInRow…), and
// #183 established that such a handler takes only a *passive* grab, which is why
// a chevron and the tile under it both fired. The tempting inference is that a
// passive grab lets the press carry on down to the fog catcher as well — so that
// even pressing a button would dismiss the drawer. It does not:
// tests/tst_drawercardpress.qml measures a press on a `TapHandler`'s item and
// the `MouseArea` beneath it never sees it. #183's rule is about one handler not
// excluding *another handler*; it says nothing about item-level delivery, which
// stops at the handler.
//
// So the bug was always exactly what the ticket described — *miss* a button and
// the drawer closes. The padding, the header, the gaps between tiles: the parts
// of the card with nothing on them. That is a smaller bug than "every press
// falls through", and this is a correspondingly small fix: it gives the card the
// one thing its bare areas lacked, and leaves every control alone.
//
// ## Why it lives here and not in DrawerWindow
//
// The fix could have been geometric — teach the fog catcher the card's bounds
// and ignore a press inside them. That means mapping a rectangle through the
// slot's entry scale (Surfaces/Drawers/DrawerSlot.qml animates `body.scale`, and
// about a different `transformOrigin` per tenant), and re-deriving by hand what
// Qt's hit-testing already knows. Item-level input is the mechanism that
// actually stops a click, so the card claims its own presses and the fog keeps
// meaning what it says: everything this catcher does not cover.
//
// One file rather than five identical `MouseArea` blocks, because the reason is
// one reason and this is where it is written down.
//
// ## Using it
//
// First child of the card, before its content:
//
//     Rectangle {
//         id: panel
//         PressCatcher {}
//         ColumnLayout { ... }
//     }
//
// First, so that it is *below* the card's own controls in stacking order and
// they are hit-tested before it — it is the backstop for presses that miss
// everything, not a lid over the buttons. `anchors.fill` is on this side of the
// line so a call site cannot forget it.
//
// It handles nothing on purpose. An empty `MouseArea` still accepts the press
// for its `acceptedButtons`, and accepting is the whole job; `hoverEnabled` stays
// false so it does not eat hovers, and it leaves `wheel` alone so a card with a
// list in it (the notification centre) still scrolls.
import QtQuick

MouseArea {
    anchors.fill: parent

    // Every button, not just the left one. The fog catcher only closes on a left
    // click today, so this is wider than the bug strictly needs — but "a press on
    // the card is not a press on the fog" is the rule, and it should not quietly
    // stop being true the day the catcher grows a right-click.
    acceptedButtons: Qt.AllButtons
}
