// What the wallpaper picker decides (#45): which files are wallpapers, what
// order they are shown in, which one carries the tick, and when a press is
// worth a config write.
//
// The picture — thumbnails, the grid, the decode — is the surface's, and
// whether the pick survives a restart is seam 2's: it is a config write and a
// reload, and tools/drawer-harness.sh drives both against a scratch
// XDG_CONFIG_HOME.
import QtQuick
import QtTest
import "../Surfaces/Background"

TestCase {
    name: "WallpaperPolicy"

    WallpaperPolicy { id: policy }

    function paths(rows) {
        return rows.map(row => row.path);
    }

    function names(rows) {
        return rows.map(row => row.name);
    }

    function files(list) {
        return list.map(path => ({ path: path }));
    }

    // --- what counts as a wallpaper ------------------------------------------

    function test_the_raster_formats_are_wallpapers() {
        verify(policy.isImage("a.jpg"));
        verify(policy.isImage("a.jpeg"));
        verify(policy.isImage("a.png"));
        verify(policy.isImage("a.webp"));
        verify(policy.isImage("a.JPG"));      // the extension is not case
    }

    function test_svg_and_gif_are_not() {
        // An SVG scaled to a 4K output is a decode that misses the first-frame
        // budget; an animated GIF is a repaint per frame forever against an
        // idle budget of one a minute.
        verify(!policy.isImage("a.svg"));
        verify(!policy.isImage("a.gif"));
    }

    function test_a_file_with_no_extension_is_not_a_wallpaper() {
        verify(!policy.isImage("README"));
        verify(!policy.isImage(".hidden"));
        verify(!policy.isImage(""));
        verify(!policy.isImage(null));
    }

    function test_a_folder_of_mixed_files_yields_only_the_images() {
        const rows = policy.entries(files([
            "/w/notes.txt", "/w/forest.jpg", "/w/logo.svg", "/w/dawn.png"
        ]), "");
        compare(paths(rows), ["/w/dawn.png", "/w/forest.jpg"]);
    }

    // --- the order -----------------------------------------------------------

    function test_the_grid_is_alphabetical_by_the_name_under_the_thumbnail() {
        // Not by modification time, which is the other plausible ordering: a
        // folder of wallpapers is scrolled through looking for the one you
        // remember, and the one you remember is found by name.
        compare(names(policy.entries(files([
            "/w/zurich.jpg", "/w/Alps.png", "/w/beach.jpg"
        ]), "")), ["Alps", "beach", "zurich"]);
    }

    function test_the_name_drops_the_folder_and_the_extension() {
        // The extension is the one part of a filename nobody chose.
        compare(policy.displayName("/home/me/Pictures/forest-at-dawn.jpg"),
                "forest-at-dawn");
        compare(policy.displayName("plain.png"), "plain");
        compare(policy.displayName("/w/no-extension"), "no-extension");
    }

    // --- the tick ------------------------------------------------------------

    function test_the_current_wallpaper_is_marked() {
        const rows = policy.entries(files(["/w/a.jpg", "/w/b.jpg"]), "/w/b.jpg");
        compare(rows.filter(row => row.current).map(row => row.path), ["/w/b.jpg"]);
    }

    function test_a_file_url_and_a_plain_path_are_the_same_wallpaper() {
        // settings.json may hold either, and the tick has to appear whichever.
        const rows = policy.entries(files(["/w/a.jpg"]), "file:///w/a.jpg");
        compare(rows[0].current, true);
    }

    function test_a_percent_encoded_url_still_matches_its_file() {
        const rows = policy.entries(files(["/w/two words.jpg"]),
                                    "file:///w/two%20words.jpg");
        compare(rows[0].current, true);
    }

    function test_a_doubled_slash_is_the_same_path() {
        compare(policy.entries(files(["/w/a.jpg"]), "/w//a.jpg")[0].current, true);
    }

    function test_nothing_is_ticked_when_no_wallpaper_is_set() {
        // The normal state of a fresh install, and of a machine whose wallpaper
        // lives outside the picker's folder — neither is an error.
        const rows = policy.entries(files(["/w/a.jpg"]), "");
        compare(rows[0].current, false);
        compare(policy.entries(files(["/w/a.jpg"]), null)[0].current, false);
    }

    // --- #75: the signature --------------------------------------------------

    function test_the_signature_moves_when_the_tick_does() {
        // A thumbnail is an `Image` with a decode behind it, so a rebuilt
        // delegate is a whole folder decoded again — the most expensive rebuild
        // in the shell.
        const before = policy.entries(files(["/w/a.jpg", "/w/b.jpg"]), "/w/a.jpg");
        const after = policy.entries(files(["/w/a.jpg", "/w/b.jpg"]), "/w/b.jpg");
        verify(policy.signature(before) !== policy.signature(after));
    }

    function test_listing_the_same_folder_twice_is_the_same_signature() {
        const once = policy.entries(files(["/w/b.jpg", "/w/a.jpg"]), "/w/a.jpg");
        const twice = policy.entries(files(["/w/a.jpg", "/w/b.jpg"]), "/w/a.jpg");
        compare(policy.signature(once), policy.signature(twice));
    }

    // --- when a press is worth a write ---------------------------------------

    function test_pressing_the_wallpaper_already_set_writes_nothing() {
        // Every write is a file rewritten and a reload of every surface bound
        // to it.
        verify(!policy.changed("/w/a.jpg", "/w/a.jpg"));
        verify(!policy.changed("/w/a.jpg", "file:///w/a.jpg"));
    }

    function test_pressing_a_different_wallpaper_is_a_write() {
        verify(policy.changed("/w/a.jpg", "/w/b.jpg"));
        verify(policy.changed("", "/w/b.jpg"));
    }

    function test_pressing_nothing_is_never_a_write() {
        verify(!policy.changed("/w/a.jpg", ""));
        verify(!policy.changed("/w/a.jpg", null));
    }

    // --- the words -----------------------------------------------------------

    function test_the_empty_state_names_the_folder_and_how_to_change_it() {
        // Both, and neither is guessable: a picker that says "no wallpapers" is
        // one nobody can fix, and one that says where it looked but not how to
        // look elsewhere is one they can only fix by moving their files.
        verify(policy.emptyLine("/home/me/Walls").indexOf("/home/me/Walls") >= 0);
        verify(policy.emptyLine("/home/me/Walls").indexOf("wallpaper.folder") >= 0);
        verify(policy.emptyLine("").indexOf(policy.defaultFolder) >= 0);
    }

    function test_the_default_folder_is_written_the_way_settings_travel() {
        // settings.json moves between machines; a home directory does not.
        compare(policy.defaultFolder.startsWith("~/"), true);
    }
}
