// What the bar says about the focused window (#37).
import QtQuick
import QtTest
import "../Services/Compositor"

TestCase {
    name: "ActiveWindowPolicy"

    ActiveWindowPolicy { id: policy }

    function test_the_title_is_what_is_shown() {
        compare(policy.label("shell.qml — forest-shell", "kitty"),
                "shell.qml — forest-shell");
    }

    function test_a_window_with_no_title_reads_as_its_application() {
        // A fair number of windows set their title late, empty, or never — a
        // freshly mapped terminal, a splash window, an X11 client mid-startup.
        // The app id is always there.
        compare(policy.label("", "org.mozilla.firefox"), "org.mozilla.firefox");
        compare(policy.label("   ", "kitty"), "kitty");
    }

    function test_no_focused_window_is_no_module() {
        // An empty workspace has no focused window, and the module goes with
        // it: "Desktop" would be a word this shell invented for a thing that is
        // not there.
        compare(policy.label("", ""), "");
        compare(policy.label(undefined, undefined), "");
        verify(!policy.showing(policy.label(undefined, undefined)));
        verify(policy.showing(policy.label("nvim", "kitty")));
    }

    function test_a_title_is_whatever_the_application_wrote() {
        compare(policy.label("  two\nlines\t ", "kitty"), "two lines");
    }
}
