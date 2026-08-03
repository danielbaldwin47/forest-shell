// The Bar tab against the `bar` section it edits (#72).
//
// The #35/#54 consolidation merged two bar sections into one and the tab did
// not catch up: `position`, `autoHide` and the three floating-geometry keys
// were in the file and reachable by hand-edit with no control anywhere in the
// GUI. The tabs↔sections test in tst_schemas.qml could not see it — it asks
// whether a *section* has a tab, and this section did.
//
// So the check is per leaf, and it runs against `Surfaces/Settings/Tabs/
// BarTabPolicy.qml` rather than against the tab: BarTab.qml imports qs.Core for
// `Config`, which qmltestrunner cannot load, and the policy object is the half
// of the tab that is a decision rather than a picture (CLAUDE.md seam 1). The
// row layout those controls arrive in is seam 3's business.
import QtQuick
import QtTest
import "../Core"
import "../Surfaces/Settings/Tabs"

TestCase {
    name: "BarTabPolicy"

    BarTabPolicy { id: policy }
    SettingsSchema { id: settings }
    SpecStore { id: store }

    function test_every_bar_leaf_has_a_control() {
        // The #72 criterion. A key added to the section fails here until the
        // tab grows a row for it — which is the point: a bar key the GUI
        // cannot reach is a key most users will never find.
        for (const path of store.leafPathsUnder(settings.spec, "bar"))
            verify(policy.covers.indexOf(path) >= 0, path + " has no control on the Bar tab");
    }

    function test_the_tab_claims_no_key_the_schema_does_not_have() {
        // The other direction, which catches a rename: a path left behind here
        // after the schema moved would make the check above pass by describing
        // a key that no longer exists.
        for (const path of policy.covers)
            verify(store.leafAt(settings.spec, path) !== null, path + " is not a leaf of the schema");
    }

    function test_the_tab_lists_each_key_once() {
        const seen = policy.covers.filter((path, i) => policy.covers.indexOf(path) !== i);
        compare(seen.length, 0, "listed twice: " + seen.join(", "));
    }

    function test_every_track_belongs_to_a_key_the_tab_covers() {
        // The two lists name the same keys from two directions, and this is
        // what keeps them one set: a track declared for a path the tab does not
        // put a row on is a range nothing reads.
        for (const path in policy.ranges)
            verify(policy.covers.indexOf(path) >= 0, path + " has a track but no row");
    }

    function test_every_slider_track_survives_its_own_coercer() {
        // The criterion that outlived #68: a slider must not offer a value the
        // file would then change. Both ends are checked, because a track is
        // only ever wrong at an end — a plain leaf keeps its bounds inside the
        // closure `Coerce.integer` returns, so round-tripping the end through
        // the coercer is the only way to ask what they are.
        for (const path in policy.ranges) {
            const track = policy.ranges[path];
            const leaf = store.leafAt(settings.spec, path);

            verify(track.from < track.to, path + " has an empty track");
            verify(store.equals(leaf.coerce(track.from), track.from),
                   path + " slider starts at a value the coercer would clamp");
            verify(store.equals(leaf.coerce(track.to), track.to),
                   path + " slider ends at a value the coercer would clamp");
        }
    }

    function test_every_track_holds_the_shipped_default() {
        // A track the default falls outside of is a tab that moves the value
        // the moment it draws the handle.
        for (const path in policy.ranges) {
            const track = policy.ranges[path];
            const def = store.leafAt(settings.spec, path).def;

            verify(def >= track.from && def <= track.to, path + " default is off its own track");
        }
    }

    function test_every_numeric_bar_leaf_is_on_a_declared_track() {
        // Without this a new numeric key could take a control whose range was
        // written inline in the tab, where nothing can check it.
        for (const path of store.leafPathsUnder(settings.spec, "bar")) {
            if (typeof store.leafAt(settings.spec, path).def !== "number")
                continue;
            verify(policy.ranges[path] !== undefined, path + " is a number with no declared track");
        }
    }

    function test_a_track_nobody_declared_is_a_build_error() {
        // Rather than a silent 0..1, which is `SettingSlider`'s fallback for a
        // leaf with no knob table and would put the handle somewhere the value
        // never goes.
        let threw = false;
        try {
            policy.from("bar.nosuchkey");
        } catch (error) {
            threw = true;
        }
        verify(threw, "an undeclared path returned a range");
    }

    function test_the_position_choice_offers_what_the_coercer_takes() {
        // The tab builds its choice from `Config.schema.barPositions`, which is
        // the same array `bar.position`'s `oneOf` is built from — this is the
        // assertion that keeps them one array and not two that look alike.
        const leaf = store.leafAt(settings.spec, "bar.position");

        verify(settings.barPositions.length > 1);
        for (const value of settings.barPositions)
            compare(leaf.coerce(value), value, value + " is offered but not accepted");
        verify(settings.barPositions.indexOf(leaf.def) >= 0, "the default is not on offer");
    }
}
