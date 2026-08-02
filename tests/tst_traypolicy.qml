// The tray's decisions (#37): what is shown, and what a click means.
import QtQuick
import QtTest
import "../Services/System"

TestCase {
    name: "TrayPolicy"

    TrayPolicy { id: policy }

    function test_everything_registered_is_shown() {
        // The SNI `Passive` status means "hide me if space is tight", and
        // honouring it loses icons from the many applications that report
        // Passive and never change it. A tray that silently drops an icon is
        // indistinguishable from a tray that is broken.
        verify(policy.showing(policy.passive));
        verify(policy.showing(policy.active));
        verify(policy.showing(policy.attention));
        verify(policy.showing("something a future spec adds"));
    }

    function test_attention_is_the_one_status_that_changes_the_icon() {
        verify(policy.attentive(policy.attention));
        verify(!policy.attentive(policy.active));
        verify(!policy.attentive(policy.passive));
        verify(!policy.attentive(undefined));
    }

    function test_a_left_click_activates_unless_the_app_says_it_cannot() {
        // `onlyMenu` is the application saying its Activate call does nothing —
        // a left click that made it would read as a dead icon.
        compare(policy.primaryAction(false, true), "activate");
        compare(policy.primaryAction(false, false), "activate");
        compare(policy.primaryAction(true, true), "menu");
    }

    function test_an_item_with_neither_an_action_nor_a_menu_says_so() {
        // Answered rather than swallowed, so the click is logged: an icon that
        // does nothing on click has two candidate causes otherwise (#81).
        compare(policy.primaryAction(true, false), "none");
        compare(policy.secondaryAction(false), "none");
    }

    function test_a_right_click_is_always_the_menu() {
        // Never a fallback to activating: right-click meaning two different
        // things depending on the app is worse than right-click doing nothing.
        compare(policy.secondaryAction(true), "menu");
    }
}
