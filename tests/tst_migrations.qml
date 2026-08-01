// The migration runner (#12 §5, #21, #33).
//
// Migrations run on the *raw* parsed JSON, before the spec table ever sees it:
// a typed adapter drops the keys it does not know, and a rename migration's
// whole job is to read exactly those.
import QtQuick
import QtTest
import "../Core"

TestCase {
    name: "Migrations"

    Migrations { id: migrations }
    SettingsSchema { id: settings }
    SpecStore { id: store }

    // Guarded the way a real migration is: a step that finds nothing to do
    // leaves the file alone rather than writing a key full of `undefined`.
    readonly property var registry: [
        {
            to: 2,
            describe: "a → b",
            migrate: function (raw) {
                if (raw.a === undefined)
                    return raw;
                raw.b = raw.a;
                delete raw.a;
                return raw;
            }
        },
        {
            to: 3,
            describe: "b doubled",
            migrate: function (raw) {
                if (typeof raw.b === "number")
                    raw.b = raw.b * 2;
                return raw;
            }
        }
    ]

    function run(raw, latest) {
        return migrations.run(raw, registry, "version", latest === undefined ? 3 : latest);
    }

    // --- version reading -----------------------------------------------------

    function test_missing_version_reads_as_the_oldest() {
        // A hand-written file with no version stamp is a v1 file.
        compare(migrations.versionOf({}, "version", 1), 1);
        compare(migrations.versionOf({ version: 4 }, "version", 1), 4);
        compare(migrations.versionOf({ version: "nonsense" }, "version", 1), 1);
    }

    // --- the run -------------------------------------------------------------

    function test_runs_every_step_above_the_files_version() {
        const result = run({ version: 1, a: 5 });
        compare(result.raw.b, 10);
        compare(result.raw.a, undefined);
        compare(result.from, 1);
        compare(result.to, 3);
        compare(result.applied.length, 2);
    }

    function test_skips_steps_at_or_below_the_files_version() {
        const result = run({ version: 2, b: 5 });
        compare(result.raw.b, 10);
        compare(result.applied.length, 1);
    }

    function test_stamps_the_version_even_when_nothing_changed() {
        // An unversioned file that nothing applies to still gets its anchor.
        const result = run({ version: 3, b: 5 });
        compare(result.raw.version, 3);
        compare(result.applied.length, 0);
        compare(result.rewritten, false);
    }

    function test_reports_whether_a_step_actually_rewrote_anything() {
        // This is what decides whether a backup is worth keeping: a file that
        // only lacked its stamp is stamped, not backed up.
        verify(run({ version: 1, a: 5 }).rewritten);
        verify(!run({ version: 1 }).rewritten);
    }

    function test_never_downgrades_a_file_from_a_newer_shell() {
        // Older forest-shell reading a newer file: run nothing, keep the
        // version, and let the sparse write preserve the unknown keys.
        const result = run({ version: 9, futureKey: 1 });
        compare(result.to, 9);
        compare(result.applied.length, 0);
        compare(result.raw.futureKey, 1);
    }

    function test_does_not_mutate_the_file_it_was_given() {
        const raw = { version: 1, a: 5 };
        run(raw);
        compare(raw.a, 5);
    }

    function test_applies_steps_in_version_order() {
        const backwards = [registry[1], registry[0]];
        const result = migrations.run({ version: 1, a: 5 }, backwards, "version", 3);
        compare(result.raw.b, 10);
    }

    // --- the real settings migration ----------------------------------------

    function test_v2_moves_the_wallpaper_out_of_the_background_section() {
        // The skeleton (#32) shipped `background.wallpaper`; the section list
        // resolved in #21 puts it in `wallpaper.path`.
        const result = migrations.run({ background: { wallpaper: "/a.jpg" } },
                                      settings.migrations, settings.versionKey, settings.version);
        compare(result.from, 1);
        compare(result.to, settings.version);
        compare(result.raw.wallpaper.path, "/a.jpg");
        compare(result.raw.background, undefined);
        verify(result.rewritten);
    }

    function test_v2_leaves_an_already_migrated_file_alone() {
        const raw = { settingsVersion: settings.version, wallpaper: { path: "/a.jpg" } };
        const result = migrations.run(raw, settings.migrations, settings.versionKey, settings.version);
        compare(result.raw.wallpaper.path, "/a.jpg");
        compare(result.rewritten, false);
    }

    function test_v2_keeps_an_unrelated_background_key() {
        const result = migrations.run({ background: { wallpaper: "/a.jpg", futureKey: 1 } },
                                      settings.migrations, settings.versionKey, settings.version);
        compare(result.raw.background.futureKey, 1);
        compare(result.raw.background.wallpaper, undefined);
    }

    function test_v2_output_resolves_through_the_settings_spec() {
        const result = migrations.run({ background: { wallpaper: "/a.jpg" } },
                                      settings.migrations, settings.versionKey, settings.version);
        compare(store.resolve(settings.spec, result.raw).values.wallpaper.path, "/a.jpg");
    }
}
