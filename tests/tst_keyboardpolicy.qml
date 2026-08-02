// The keyboard-layout module's decisions (#37): reading `hyprctl devices`, and
// the rule that one layout is no module.
import QtQuick
import QtTest
import "../Services/Compositor"

TestCase {
    name: "KeyboardPolicy"

    KeyboardPolicy { id: policy }

    /// A reply in the shape `hyprctl devices -j` really answers with — captured
    /// from the machine this is built on, trimmed to the fields read.
    function devices(keyboards) {
        return JSON.stringify({ mice: [], keyboards: keyboards, tablets: [], touch: [] });
    }

    function test_the_main_keyboard_is_the_one_that_counts() {
        // Every client that makes a virtual keyboard adds an entry. Only one
        // of them is the device Hyprland switches layouts on.
        const reply = devices([
            { name: "virtual-keyboard-1", layout: "us", active_layout_index: 0, main: false },
            { name: "at-translated-set-2-keyboard", layout: "us,de",
              active_layout_index: 1, main: true }
        ]);
        const read = policy.read(reply);
        compare(read.device, "at-translated-set-2-keyboard");
        compare(read.layouts, ["us", "de"]);
        compare(read.active, 1);
        compare(policy.label(read.layouts, read.active), "DE");
    }

    function test_a_reply_that_flags_no_main_keyboard_still_answers() {
        // Hiding the layout because a flag was missing would hide something the
        // user can see changing.
        const read = policy.read(devices([
            { name: "usb-keyboard", layout: "gb", active_layout_index: 0 }
        ]));
        compare(read.device, "usb-keyboard");
        compare(read.layouts, ["gb"]);
    }

    function test_one_layout_is_no_module() {
        // The ticket's own acceptance criterion, and #9's quiet-bar rule: a
        // machine with one layout can never be in the wrong one.
        verify(!policy.showing(["us"]));
        verify(!policy.showing([]));
        verify(policy.showing(["us", "de"]));
        verify(policy.showing(["us", "de", "fr"]));
    }

    function test_the_layout_field_is_a_string_and_not_a_list() {
        compare(policy.layouts("us,de,fr"), ["us", "de", "fr"]);
        // A trailing comma in a hand-written hyprland.conf is not a layout.
        compare(policy.layouts("us, de,"), ["us", "de"]);
        compare(policy.layouts(""), []);
        compare(policy.layouts(undefined), []);
    }

    function test_a_reply_the_shell_cannot_read_is_no_keyboard() {
        // Rather than a guess: a bar claiming a layout is active when the shell
        // has no idea which one is would be worse than a bar with no module.
        for (const bad of ["", "not json", "{}", '{"keyboards":"nope"}']) {
            const read = policy.read(bad);
            compare(read.layouts, []);
            compare(read.device, "");
            verify(!policy.showing(read.layouts));
        }
    }

    function test_an_index_the_reply_cannot_justify_reads_as_the_first() {
        // Which layout is live is a smaller thing to be wrong about than
        // whether there are any.
        const read = policy.read(devices([
            { name: "k", layout: "us,de", active_layout_index: 7, main: true }
        ]));
        compare(read.active, 0);
        compare(policy.label(read.layouts, read.active), "US");
        compare(policy.label(read.layouts, 9), "");
    }

    function test_the_switch_is_a_hyprctl_command_and_not_a_dispatcher() {
        // Measured against Hyprland 0.56.1 in tools/services-harness.sh:
        // `hyprctl dispatch switchxkblayout current next` answers "Invalid
        // dispatcher" and changes nothing, while the command form answers
        // "ok". The first version of this shipped as a dispatch.
        //
        // `next` rather than an index: Hyprland owns the cycle, and an index
        // computed here would disagree the moment a layout is added to the
        // compositor config without the shell being told.
        compare(policy.cycleCommand("at-translated-set-2-keyboard"),
                ["hyprctl", "switchxkblayout", "at-translated-set-2-keyboard", "next"]);
    }

    function test_a_refusal_is_read_out_of_the_reply_and_not_the_exit_code() {
        // hyprctl exits 0 when it refuses (#78), so the reply text is the only
        // evidence a switch happened.
        verify(policy.switched(0, "ok\n"));
        verify(!policy.switched(0, "Invalid dispatcher"));
        verify(!policy.switched(1, "ok"));
        verify(!policy.switched(0, ""));
    }

    function test_a_layout_switch_is_what_prompts_a_re_read() {
        verify(policy.layoutEvents.indexOf("activelayout") >= 0);
        // Window events are not layout events — a bar that re-ran a subprocess
        // on every focus change would be the polling this shell does not do.
        verify(policy.layoutEvents.indexOf("activewindow") < 0);
    }
}
