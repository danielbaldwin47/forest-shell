// Defaults-under-user-settings merge and safe JSON parsing. The config engine
// (#33) replaces the Config stub around this, but the merge rule — nested
// sections merge, leaves replace, unknown keys survive — is settled here.
import QtQuick
import QtTest
import "../Core"

TestCase {
    name: "JsonMerge"

    JsonMerge { id: json }

    function test_merge_leaves_defaults_alone() {
        const merged = json.merge({ a: 1, b: "two" }, {});
        compare(merged.a, 1);
        compare(merged.b, "two");
    }

    function test_merge_overrides_leaf() {
        compare(json.merge({ a: 1 }, { a: 2 }).a, 2);
    }

    function test_merge_is_deep() {
        const merged = json.merge(
            { background: { wallpaper: "", fillMode: "crop" } },
            { background: { wallpaper: "/tmp/w.jpg" } });
        compare(merged.background.wallpaper, "/tmp/w.jpg");
        compare(merged.background.fillMode, "crop");
    }

    function test_merge_preserves_unknown_keys() {
        const merged = json.merge({ a: 1 }, { futureKey: { deep: true } });
        compare(merged.futureKey.deep, true);
    }

    function test_merge_replaces_arrays_wholesale() {
        const merged = json.merge({ list: [1, 2, 3] }, { list: [9] });
        compare(merged.list.length, 1);
        compare(merged.list[0], 9);
    }

    function test_merge_does_not_mutate_defaults() {
        const defaults = { section: { key: "default" } };
        json.merge(defaults, { section: { key: "user" } });
        compare(defaults.section.key, "default");
    }

    function test_merge_does_not_share_arrays_with_defaults() {
        // A shared array reference would let one consumer's push() rewrite the
        // defaults for every later reload.
        const defaults = { list: [1, 2] };
        const merged = json.merge(defaults, {});
        merged.list.push(3);
        compare(defaults.list.length, 2);
    }

    function test_merge_does_not_share_objects_inside_arrays() {
        const overrides = { rules: [{ app: "vivaldi" }] };
        const merged = json.merge({}, overrides);
        merged.rules[0].app = "firefox";
        compare(overrides.rules[0].app, "vivaldi");
    }

    function test_merge_null_override_replaces() {
        const merged = json.merge({ a: { b: 1 } }, { a: null });
        compare(merged.a, null);
    }

    function test_parse_ok() {
        const result = json.parse('{"a": 1}');
        compare(result.ok, true);
        compare(result.value.a, 1);
    }

    function test_parse_invalid_json_reports_error() {
        const result = json.parse("{not json");
        compare(result.ok, false);
        verify(result.error.length > 0);
        compare(result.value, null);
    }

    function test_parse_non_object_rejected() {
        // A settings file must be an object; a bare array or number is a
        // corrupt file, not a valid config.
        compare(json.parse("[1, 2]").ok, false);
        compare(json.parse("42").ok, false);
    }

    function test_parse_empty_text_is_empty_object() {
        const result = json.parse("");
        compare(result.ok, true);
        compare(Object.keys(result.value).length, 0);
    }
}
