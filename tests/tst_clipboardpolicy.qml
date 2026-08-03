// The clipboard provider's decisions (#53).
//
// Three groups matter more than the rest. The parse, because the format is
// another project's output and a line this file misreads is a row that pastes
// the wrong thing. The argvs, because one of them is the only `sh -c` in this
// shell and the id has to be an *argument* to it rather than syntax in it. And
// the silences, because an absent `cliphist`, a stopped watcher and a genuinely
// empty history produce byte-identical output — nothing — and only the exit
// status and the probe tell them apart. That last one is the ticket's own
// instruction: "a missing cliphist that degrades into a silently empty history
// is the #78 shape".
import QtQuick
import QtTest
import "../Services/Launcher"

TestCase {
    id: testCase
    name: "ClipboardPolicy"

    ClipboardPolicy { id: policy }

    // --- one line at a time --------------------------------------------------

    function test_a_line_is_an_id_a_tab_and_a_preview() {
        const entry = policy.entryOf("42\thello world");
        verify(entry !== null);
        compare(entry.id, "42");
        compare(entry.preview, "hello world");
        verify(!entry.image);
    }

    function test_only_the_first_tab_splits() {
        // A copied line of TSV. Splitting on every tab would turn one entry
        // into three and lose two thirds of the preview.
        const entry = policy.entryOf("7\tname\tvalue\tunit");
        verify(entry !== null);
        compare(entry.id, "7");
        compare(entry.preview, "name\tvalue\tunit");
    }

    function test_a_line_that_is_not_an_entry_is_dropped() {
        compare(policy.entryOf(""), null);
        compare(policy.entryOf("no tab here"), null);
        compare(policy.entryOf("\tno id"), null);
        // Not a decimal id: nothing downstream could decode it, and it would
        // reach an argv.
        compare(policy.entryOf("12a\tsomething"), null);
    }

    function test_an_id_is_digits_and_nothing_else() {
        verify(policy.validId("1"));
        verify(policy.validId("948231"));
        verify(!policy.validId(""));
        verify(!policy.validId("12 34"));
        // The shapes that matter, because `copyArgv()` puts this near a shell.
        verify(!policy.validId("1; rm -rf ~"));
        verify(!policy.validId("$(id)"));
        verify(!policy.validId("../../etc/passwd"));
    }

    // --- images --------------------------------------------------------------

    function test_the_binary_marker_is_an_image() {
        const entry = policy.entryOf("99\t[[ binary data 39 KiB png 1920x1080 ]]");
        verify(entry !== null);
        verify(entry.image);
        compare(entry.format, "png");
        compare(entry.size, "39 KiB");
        compare(entry.dimensions, "1920x1080");
    }

    function test_the_marker_is_read_by_shape_not_by_position() {
        // The same three facts in another order — an upstream that reorders its
        // preview must not turn every image into a text row, because a text row
        // re-copies with the wrong MIME type and pastes nothing.
        const entry = policy.binaryOf("[[ binary data jpeg 800x600 1.2 MiB ]]");
        verify(entry !== null);
        compare(entry.format, "jpeg");
        compare(entry.dimensions, "800x600");
        compare(entry.size, "1.2 MiB");
    }

    function test_an_unreadable_marker_is_still_an_image() {
        // Degrade to a picture with nothing known about it, never to text.
        const entry = policy.entryOf("5\t[[ binary data something new ]]");
        verify(entry !== null);
        verify(entry.image);
        compare(entry.format, "");
        compare(entry.dimensions, "");
    }

    function test_text_that_merely_mentions_binary_data_is_text() {
        const entry = policy.entryOf("6\tthe binary data was 39 KiB png");
        verify(entry !== null);
        verify(!entry.image);
    }

    // --- the list ------------------------------------------------------------

    function test_parse_keeps_cliphists_own_order() {
        const list = policy.parse("3\tthird\n2\tsecond\n1\tfirst\n");
        compare(list.length, 3);
        compare(list[0].id, "3");
        compare(list[2].preview, "first");
    }

    function test_parse_drops_what_it_cannot_read() {
        const list = policy.parse("1\tone\n\n\ngarbage\n2\ttwo\n");
        compare(list.length, 2);
        compare(list[0].id, "1");
        compare(list[1].id, "2");
    }

    function test_dedupe_keeps_the_most_recent_of_a_repeat() {
        // Trailing whitespace is the pair this exists for: two rows that look
        // identical on screen, and only one of them is the one you meant.
        const list = policy.dedupe(policy.parse("9\tsudo pacman -Syu  \n8\tsudo pacman -Syu\n7\tls\n"));
        compare(list.length, 2);
        compare(list[0].id, "9");
        compare(list[1].id, "7");
    }

    function test_dedupe_never_collapses_two_images() {
        // Two screenshots of the same size are two different pictures, and the
        // marker is not a description of either of them.
        const list = policy.dedupe(policy.parse(
            "2\t[[ binary data 39 KiB png 1920x1080 ]]\n"
            + "1\t[[ binary data 39 KiB png 1920x1080 ]]\n"));
        compare(list.length, 2);
    }

    // --- matching ------------------------------------------------------------

    function fixture() {
        return policy.parse("4\tgit rebase --continue\n"
                            + "3\t[[ binary data 39 KiB png 1920x1080 ]]\n"
                            + "2\thttps://example.invalid/thing\n"
                            + "1\tgit push --force-with-lease\n");
    }

    function test_a_bare_prefix_browses_the_front_of_the_history() {
        const rows = policy.search(testCase.fixture(), "");
        compare(rows.length, 4);
        compare(rows[0].id, "4");
    }

    function test_the_browse_list_is_capped() {
        const many = [];
        for (let i = 0; i < 40; i++)
            many.push({ id: String(i), preview: "line " + i, image: false });
        compare(policy.search(many, "").length, policy.browseLimit);
    }

    function test_a_query_filters_the_history() {
        const rows = policy.search(testCase.fixture(), "git");
        compare(rows.length, 2);
        verify(rows.every(row => row.preview.indexOf("git") === 0));
    }

    function test_a_query_that_matches_nothing_returns_nothing() {
        compare(policy.search(testCase.fixture(), "zzzz").length, 0);
    }

    function test_an_image_is_matched_on_what_it_is() {
        // "png" should find the screenshot; the marker's own boilerplate should
        // not make every image match every query.
        const byFormat = policy.search(testCase.fixture(), "png");
        compare(byFormat.length, 1);
        compare(byFormat[0].id, "3");
        compare(policy.search(testCase.fixture(), "1920x1080").length, 1);
        compare(policy.search(testCase.fixture(), "binary").length, 0);
    }

    function test_matching_is_substring_and_not_subsequence() {
        // The measurement behind the deviation from `LauncherPolicy.score()`.
        // A subsequence matcher finds p·n·g inside
        // `https://example.invalid/thing` — so a search for screenshots would
        // return a URL. Over content this long, "the letters are in there
        // somewhere" is not a match anyone meant.
        compare(policy.scoreEntry("png", policy.entryOf("2\thttps://example.invalid/thing")), -1);
    }

    function test_every_term_has_to_appear() {
        const rows = policy.search(testCase.fixture(), "git lease");
        compare(rows.length, 1);
        compare(rows[0].id, "1");
        // The point of AND: a query narrows as it is typed.
        compare(policy.search(testCase.fixture(), "git zzz").length, 0);
    }

    function test_an_entry_that_starts_with_the_query_ranks_first() {
        const rows = policy.search(policy.parse("2\tsee the git log\n1\tgit log\n"), "git");
        compare(rows[0].id, "1");
    }

    function test_ties_break_on_recency() {
        const rows = policy.search(policy.parse("2\tsame\n1\tsame\n"), "same");
        compare(rows.length, 2);
        compare(rows[0].id, "2");
    }

    // --- the rows ------------------------------------------------------------

    function test_a_text_row_shows_its_preview() {
        const row = policy.row(policy.entryOf("4\tgit rebase --continue"), "");
        compare(row.provider, "clipboard");
        compare(row.id, "clipboard:4");
        compare(row.title, "git rebase --continue");
        compare(row.category, "Clipboard");
        compare(row.entryId, "4");
        compare(row.icon, "clipboard-list");
        compare(row.iconSource, "");
    }

    function test_a_row_never_carries_the_text_to_copy() {
        // The preview is truncated and flattened. Copying it would paste a
        // mangled prefix and report success — #78, once per paste. Enter has to
        // decode, so `copy` is empty by construction.
        const row = policy.row(policy.entryOf("4\tgit rebase --continue"), "");
        compare(row.copy, "");
    }

    function test_an_image_row_says_what_it_is() {
        const row = policy.row(policy.entryOf("3\t[[ binary data 39 KiB png 1920x1080 ]]"), "");
        compare(row.title, "Image 1920×1080");
        compare(row.subtitle, "PNG · 39 KiB");
        compare(row.icon, "image");
    }

    function test_a_decoded_thumbnail_replaces_the_icon() {
        const row = policy.row(policy.entryOf("3\t[[ binary data 39 KiB png 1920x1080 ]]"),
                               "/cache/3.png");
        compare(row.iconSource, "/cache/3.png");
        // Both would draw. The icon is the placeholder the decode replaces.
        compare(row.icon, "");
    }

    function test_rows_fill_thumbnails_in_by_id() {
        const rows = policy.rows(testCase.fixture(), "", { "3": "/cache/3.png" });
        compare(rows.length, 4);
        compare(rows[1].iconSource, "/cache/3.png");
        compare(rows[0].iconSource, "");
    }

    // --- what to run ---------------------------------------------------------

    function test_the_listing_is_also_the_probe() {
        const argv = policy.listArgv();
        compare(argv.length, 2);
        compare(argv[0], "cliphist");
        compare(argv[1], "list");
    }

    function test_decode_takes_the_id_as_one_argument() {
        const argv = policy.decodeArgv("42");
        compare(argv.length, 3);
        compare(argv[2], "42");
    }

    function test_the_copy_shell_takes_positional_arguments() {
        // The one `sh -c` in this shell. The script body is a constant and the
        // id is `$1`: a value to sh, where interpolation would be syntax.
        const argv = policy.copyArgv("42", "png");
        compare(argv[0], "sh");
        compare(argv[1], "-c");
        verify(argv[2].indexOf("$1") >= 0);
        verify(argv[2].indexOf("42") < 0);
        compare(argv[3], "sh");
        compare(argv[4], "42");
        compare(argv[5], "image/png");
    }

    function test_the_thumbnail_shell_takes_positional_arguments_too() {
        const argv = policy.thumbnailArgv("42", "/cache/42.png");
        compare(argv[0], "sh");
        verify(argv[2].indexOf("$1") >= 0);
        verify(argv[2].indexOf("$2") >= 0);
        verify(argv[2].indexOf("/cache") < 0);
        compare(argv[4], "42");
        compare(argv[5], "/cache/42.png");
    }

    function test_the_mime_type_follows_the_format() {
        compare(policy.mimeOf("png"), "image/png");
        compare(policy.mimeOf("jpeg"), "image/jpeg");
        compare(policy.mimeOf("jpg"), "image/jpeg");
        compare(policy.mimeOf("gif"), "image/gif");
        // An unread marker falls back to PNG rather than to octet-stream, which
        // most applications will not accept as an offer at all.
        compare(policy.mimeOf(""), "image/png");
    }

    // --- thumbnails ----------------------------------------------------------

    function test_only_images_get_a_thumbnail_path() {
        compare(policy.thumbnailPath("/cache", policy.entryOf("4\ttext")), "");
        compare(policy.thumbnailPath("/cache",
                                     policy.entryOf("3\t[[ binary data 39 KiB png 1920x1080 ]]")),
                "/cache/3.png");
    }

    function test_a_format_free_image_still_gets_a_path() {
        compare(policy.thumbnailPath("/cache", policy.entryOf("5\t[[ binary data unknown ]]")),
                "/cache/5.bin");
    }

    function test_the_queue_is_images_without_pictures_capped() {
        const many = [];
        for (let i = 0; i < 40; i++)
            many.push({ id: String(i), preview: "", image: true, format: "png" });
        compare(policy.thumbnailQueue(many, {}).length, policy.thumbnailLimit);
        compare(policy.thumbnailQueue(testCase.fixture(), {}).length, 1);
        // Already decoded: nothing to do.
        compare(policy.thumbnailQueue(testCase.fixture(), { "3": "/cache/3.png" }).length, 0);
    }

    // --- the silences --------------------------------------------------------
    //
    // The group the ticket's maintenance pass is about. Every one of these
    // states produces zero rows and empty stdout; only the probe and the exit
    // status tell them apart.

    function test_a_store_that_was_never_written_is_not_a_failure() {
        // Measured against cliphist 1:0.7.0, and it cost this file a rewrite:
        // `cliphist list` exits **1** when nothing has ever been stored, because
        // the database is created by the first `store`. The first version read
        // that exit code as an absent binary and told a fresh machine "cliphist
        // is not installed" — the wrong sentence in the most expensive
        // direction, sending someone to install what they already have.
        verify(policy.emptyStore("opening db: please store something first"));
        verify(!policy.accepted(1));
    }

    function test_anything_else_that_fails_is_a_failure() {
        // Narrow on purpose. A permission on the store, or a database written
        // by a version that does not read back, must not be quietly called
        // empty — and if upstream rewords its own sentence, a fresh machine
        // gets the honest "could not read its history" instead.
        verify(!policy.emptyStore("opening db: permission denied"));
        verify(!policy.emptyStore(""));
    }

    function test_a_missing_cliphist_outranks_everything() {
        const note = policy.silence("", { available: false, probed: true,
                                          pending: false, count: 0 });
        verify(note !== null);
        verify(note.text.indexOf("not installed") >= 0);
        verify(note.text.indexOf("wl-clipboard") >= 0);
    }

    function test_a_listing_in_flight_says_so() {
        const note = policy.silence("", { available: true, probed: false,
                                          pending: true, count: 0 });
        compare(note.icon, "loader");
    }

    function test_an_empty_history_names_the_watcher() {
        // The state a machine with cliphist installed and no watcher running
        // sits in forever. "Empty" alone would be true and useless.
        const note = policy.silence("", { available: true, probed: true,
                                          pending: false, count: 0 });
        verify(note.text.indexOf("wl-paste") >= 0);
        verify(note.text.indexOf("--watch") >= 0);
    }

    function test_a_broken_listing_never_reads_as_an_empty_history() {
        // The rung between "not installed" and "nothing copied yet". Both of
        // those are wrong for a store cliphist can see and cannot read, and the
        // second one is wrong in a way that would send the user to check a
        // watcher that is running perfectly well.
        const note = policy.silence("", { available: true, probed: true,
                                          pending: false, failed: true,
                                          exitCode: 13, count: 0 });
        verify(note.text.indexOf("could not read") >= 0);
        verify(note.text.indexOf("13") >= 0);
        verify(note.text.indexOf("wl-paste") < 0);
    }

    function test_a_query_that_matched_nothing_is_its_own_answer() {
        const note = policy.silence("zzz", { available: true, probed: true,
                                             pending: false, count: 12 });
        verify(note.text.indexOf("zzz") >= 0);
    }

    function test_a_history_with_rows_in_it_is_silent() {
        compare(policy.silence("", { available: true, probed: true,
                                     pending: false, count: 12 }), null);
    }

    function test_a_refresh_over_a_full_history_does_not_blank_it() {
        // Pending with entries already known: the list is on screen and the
        // right thing to show is the list, not a spinner over it.
        compare(policy.silence("", { available: true, probed: true,
                                     pending: true, count: 12 }), null);
    }

    // --- the setup -----------------------------------------------------------

    function test_both_watchers_are_documented() {
        // One untyped watcher stores text and silently drops every image, which
        // is a clipboard history that works until the first screenshot. Both
        // acceptance criteria in #53 name images.
        compare(policy.autostart.length, 2);
        verify(policy.autostart[0].indexOf("--type text") >= 0);
        verify(policy.autostart[1].indexOf("--type image") >= 0);
        verify(policy.autostart.every(line => line.indexOf("cliphist store") >= 0));
    }

    function test_both_watchers_ship_in_an_installable_config() {
        // #140: documented in three places and installed by none of them. A
        // user who follows integration/README.md end to end got a `;` provider
        // that is empty forever, with nothing on the machine to say why — the
        // watcher lines existed only as prose in Services/README.md and as data
        // here. So the assertion is not "the lines are written down somewhere"
        // but "the file the integration guide tells you to source contains
        // them, verbatim, uncommented".
        const conf = testCase.readConf("../integration/hyprland/forest-autostart.conf");
        verify(conf !== null, "no autostart config at integration/hyprland/forest-autostart.conf");

        const live = conf.split("\n").map(line => line.trim())
                         .filter(line => line.length > 0 && line[0] !== "#");
        for (const line of policy.autostart)
            verify(live.indexOf(line) >= 0, "not shipped: " + line);
    }

    /// The file at `path` relative to this test, or `null` when there is none.
    /// Qt gates file:// reads behind QML_XHR_ALLOW_FILE_READ, which tests/run.sh
    /// sets; a missing file comes back status 0 rather than 404.
    function readConf(path: string): var {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(path), false);
        xhr.send();
        if (xhr.status !== 200 && xhr.status !== 0)
            return null;
        const text = String(xhr.responseText ?? "");
        return text.length > 0 ? text : null;
    }

    // --- what the log says ---------------------------------------------------

    function test_the_listing_logs_its_count() {
        compare(policy.listed(0), "0 clipboard entries listed");
        compare(policy.listed(1), "1 clipboard entry listed");
    }

    function test_a_copy_logs_which_entry_and_what_kind() {
        const text = policy.copied(policy.entryOf("4\thello"));
        verify(text.indexOf("4") >= 0);
        verify(text.indexOf("text") >= 0);
        const image = policy.copied(policy.entryOf("3\t[[ binary data 39 KiB png 1920x1080 ]]"));
        verify(image.indexOf("image/png") >= 0);
    }
}
