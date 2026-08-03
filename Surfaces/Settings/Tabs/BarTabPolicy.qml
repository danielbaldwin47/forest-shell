// What the Bar tab claims to edit, and on what track (#72).
//
// The tab itself imports `qs.Core` for `Config`, so it is on the far side of
// the seam-1 line (CLAUDE.md) and `tests/` cannot instantiate it. Two of #72's
// acceptance criteria are nevertheless *decisions* about the tab and belong at
// that seam:
//
//   - every leaf under `bar` in the schema has a control (the tabs↔sections
//     test only reaches section depth, and the merged section from #35/#54 had
//     five keys with no control at all);
//   - no slider offers a value the coercer would then clamp.
//
// So the two facts move here, where a pure-QML test can hold them against the
// schema, and the tab reads them back. `ranges` is load-bearing rather than a
// description: `SettingSlider` on a plain leaf has no knob table to take its
// bounds from and has to be told, and the tab is told from here, so a range in
// this file and the range on screen cannot be different numbers.
//
// `covers` is the weaker half, and honestly so: it is checked against the
// schema, not against the tab, so it catches the direction that matters — a
// key added to the section with no control — and not a control deleted while
// its path stayed here. Closing that direction would mean rendering the rows
// from a table, which would move every hint in the tab into data; the tab's
// prose is worth more than the second direction of that check.
//
// Pure QtQuick, no Quickshell, so tests/ can reach it — the arrangement
// `FieldPolicy.qml` and `LockPolicy.qml` have.
import QtQuick

QtObject {
    id: policy

    /// Every leaf path under `bar` the tab puts a control on. The test asserts
    /// this is exactly `SpecStore.leafPathsUnder(spec, "bar")` — so a key added
    /// to the section fails the suite until the tab grows a row for it.
    ///
    /// The two themed groups are one leaf each and are rendered knob by knob
    /// from the schema's own tables (`KnobRow`), which is why thirteen surface
    /// and ridgeline knobs are two entries here.
    readonly property var covers: [
        "bar.position",
        "bar.height",
        "bar.padding",
        "bar.moduleGap",
        "bar.floating",
        "bar.floatMarginH",
        "bar.floatMarginV",
        "bar.floatRadius",
        "bar.autoHide",
        "bar.modules.left",
        "bar.modules.center",
        "bar.modules.right",
        "bar.mediaMaxWidth",
        "bar.windowMaxWidth",
        "bar.surface",
        "bar.ridgeline"
    ]

    /// The track each numeric leaf gets, as the tab hands it to
    /// `SettingSlider`. Every one of these round-trips through its own leaf's
    /// coercer untouched, which is what the test checks — the failure it exists
    /// to stop is a slider whose end writes a value the file silently changes,
    /// so the handle sits somewhere the number never goes.
    ///
    /// Most are the coercer's own bounds. Three are narrower on purpose, and
    /// the reason is #10's prototype rather than safety: at 20px the bar's
    /// content has nowhere to sit and past 48 it has stopped being a strip, and
    /// padding and gap follow it. A hand-edit outside the track is still
    /// honoured — the coercer is the wider one, and this is a track, not a
    /// rule.
    readonly property var ranges: ({
        "bar.height": { from: 24, to: 48 },          // coercer 20..64
        "bar.padding": { from: 0, to: 32 },          // coercer 0..48
        "bar.moduleGap": { from: 0, to: 32 },        // coercer 0..48
        "bar.floatMarginH": { from: 0, to: 64 },
        "bar.floatMarginV": { from: 0, to: 64 },
        "bar.floatRadius": { from: 0, to: 32 },
        "bar.mediaMaxWidth": { from: 60, to: 600 },
        "bar.windowMaxWidth": { from: 60, to: 800 }
    })

    /// The low end of a leaf's track. Throws rather than defaulting on a path
    /// with no range: a slider silently landing on 0..1 is the bug this file
    /// exists to make impossible, and a missing entry is a typo at build time.
    function from(path: string): real {
        return policy.rangeFor(path).from;
    }

    function to(path: string): real {
        return policy.rangeFor(path).to;
    }

    function rangeFor(path: string): var {
        const range = policy.ranges[path];
        if (range === undefined)
            throw new Error("BarTabPolicy: no slider range declared for " + path);
        return range;
    }
}
