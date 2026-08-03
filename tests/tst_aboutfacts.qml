// What the About tab says (#55): the version, who is credited for what, and
// the one piece of state the tab can act on — whether this version's changelog
// has been read.
//
// The tab itself is a picture and belongs to seam 3. What is here is the part
// that is a decision: the changelog-seen flag is a version string rather than a
// boolean, so "has this been read" is a comparison, and a shell that ships a
// new version must read as unseen without anything writing to the file.
import QtQuick
import QtTest
import "../Surfaces/Settings"

TestCase {
    name: "AboutFacts"

    AboutFacts { id: about }

    function test_the_shell_states_one_version() {
        // Not empty, and not a placeholder: the About tab is where a bug report
        // gets its version number from, and "unknown" is the answer that makes
        // a report unactionable.
        verify(about.version !== "");
        verify(/^\d+\.\d+\.\d+/.test(about.version), about.version + " is not a version");
    }

    function test_every_credit_names_a_thing_and_where_to_find_it() {
        verify(about.credits.length > 0);
        for (const credit of about.credits) {
            verify(credit.name !== undefined && credit.name !== "", "a credit has no name");
            verify(credit.what !== undefined && credit.what !== "",
                   credit.name + " is credited for nothing");
            verify(credit.url !== undefined && credit.url.startsWith("http"),
                   credit.name + " has no link");
        }
    }

    function test_a_fresh_install_has_read_nothing() {
        // The default is `""`, which is not any version, so the first run of
        // any build is unseen. That is the point of storing a version rather
        // than a flag: nothing has to be reset on upgrade.
        verify(!about.changelogSeen(""));
    }

    function test_the_version_that_was_read_is_the_one_that_counts() {
        verify(about.changelogSeen(about.version));
        verify(!about.changelogSeen("0.0.1"));
    }

    function test_a_newer_version_in_the_state_file_still_reads_as_seen() {
        // Downgrading is not the case this flag exists for, and a shell that
        // re-announced an older changelog because the state file had run ahead
        // would be announcing news the user has already had. Any non-empty
        // string that is not *this* version is unseen — except the equality
        // above — so this is stated rather than assumed.
        verify(!about.changelogSeen("99.0.0"));
    }

    function test_the_row_says_which_version_was_read() {
        // The tab's line. Seen names the version, because "yes" answers a
        // question nobody asked; unseen says so plainly.
        compare(about.seenLabel(about.version), "Read for " + about.version);
        compare(about.seenLabel(""), "Not read yet");
        compare(about.seenLabel("0.0.1"), "Read for 0.0.1");
    }
}
