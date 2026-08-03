// What a settings field accepts before the config engine sees it (#55).
//
// These are the warnings, not the enforcement — Core/Coerce.qml is the last
// word and clamps whatever arrives, including from a hand-edit that never
// passed a field. So the interesting cases here are the two directions of being
// wrong: refusing a value the file would have honoured, and passing one the
// coercer would quietly turn into something else.
import QtQuick
import QtTest
import "../Surfaces/Settings/Controls"

TestCase {
    name: "FieldPolicy"

    FieldPolicy { id: policy }

    function test_a_path_is_absolute_or_from_home() {
        verify(policy.looksLikePath("/etc/foo"));
        verify(policy.looksLikePath("~/Pictures/Wallpapers"));
        // A path with a space in it is fine: nothing on these keys goes through
        // a shell, so there is nothing to quote against.
        verify(policy.looksLikePath("~/My Pictures/a wallpaper.png"));
    }

    function test_empty_is_a_path_because_empty_means_something() {
        // Blank is "work it out" on the screenshot directory and "not set" on
        // the wallpaper. Refusing it would make those keys unclearable.
        verify(policy.looksLikePath(""));
    }

    function test_a_relative_path_is_the_one_form_that_cannot_be_honoured() {
        // There is no agreed base for it — the shell's working directory is
        // whatever the compositor launched it from.
        verify(!policy.looksLikePath("Pictures/wall.png"));
        verify(!policy.looksLikePath("./wall.png"));
    }

    function test_a_time_is_anchored_at_both_ends() {
        verify(policy.isClockTime("20:00"));
        verify(policy.isClockTime("07:30"));
        verify(policy.isClockTime("23:59"));
        verify(policy.isClockTime("00:00"));
    }

    function test_a_time_that_is_nearly_a_time_is_refused() {
        // Unanchored, every one of these passes — and a night-light schedule
        // that silently never started is what the warning exists for.
        verify(!policy.isClockTime("19:00 ish"));
        verify(!policy.isClockTime("x20:00"));
        verify(!policy.isClockTime("24:00"));
        verify(!policy.isClockTime("7:30"));
        verify(!policy.isClockTime(""));
    }

    function test_idle_minutes_are_fractional_and_may_be_zero() {
        // #30's dim rung is 2.5 minutes, and 0 is "off on this power source"
        // rather than "fire immediately".
        verify(policy.isMinutes("2.5"));
        verify(policy.isMinutes("0"));
        verify(policy.isMinutes("600"));
    }

    function test_blank_minutes_are_refused_and_zero_is_not() {
        // The one input that would land on the *default* rather than on what
        // was typed — 0 and blank are different acts and only one is legible.
        verify(!policy.isMinutes(""));
        verify(!policy.isMinutes("   "));
        verify(!policy.isMinutes("soon"));
        verify(!policy.isMinutes("-1"));
        verify(!policy.isMinutes("601"));
    }

    function test_the_pool_is_the_vocabulary_less_what_is_placed() {
        compare(policy.pool(["a", "b", "c"], ["b"]), ["a", "c"]);
        compare(policy.pool(["a", "b"], []), ["a", "b"]);
        compare(policy.pool(["a", "b"], ["a", "b"]), []);
    }

    function test_the_pool_survives_a_config_that_has_not_arrived_yet() {
        // `Config.values` is replaced wholesale on every reload, so a binding
        // can evaluate against an undefined list for a frame.
        compare(policy.pool(["a"], undefined), ["a"]);
        compare(policy.pool(undefined, ["a"]), []);
    }

    function test_the_pool_greys_what_the_renderer_cannot_draw() {
        // #72: the vocabulary runs ahead of the registry on purpose, so the
        // pool offers ids that would do nothing when added. The distinction
        // comes from the renderer's own table — pass a registry map, get back
        // the ids it has no entry for.
        compare(policy.unsupported(["clock", "aquarium"], { clock: { file: "Clock.qml" } }),
                ["aquarium"]);
        compare(policy.unsupported(["clock"], { clock: { file: "Clock.qml" } }), []);
    }

    function test_nothing_is_greyed_before_the_registry_arrives() {
        // Same frame-zero problem the pool has. Claiming every module is
        // missing would grey the whole pool on the way in.
        compare(policy.unsupported(["clock"], undefined), []);
        compare(policy.unsupported(["clock"], null), []);
        compare(policy.unsupported(undefined, {}), []);
    }

    function test_options_take_the_list_from_the_schema_and_the_words_here() {
        const options = policy.options(["auto", "wf-recorder"],
                                       { auto: "Auto", "wf-recorder": "Software" });
        compare(options.length, 2);
        compare(options[0].value, "auto");
        compare(options[0].label, "Auto");
        compare(options[1].label, "Software");
    }

    function test_a_value_with_no_label_shows_under_its_own_id() {
        // A vocabulary that grows leaves an ugly chip rather than an option the
        // user cannot reach — the failure mode of the hand-written option lists
        // this function replaced.
        const options = policy.options(["auto", "brand-new"], { auto: "Auto" });
        compare(options[1].value, "brand-new");
        compare(options[1].label, "brand-new");
    }
}
