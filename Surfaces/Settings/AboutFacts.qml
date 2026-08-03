// What the About tab says (#55): the version this build is, who is credited
// for what, and whether this version's changelog has been read.
//
// The one tab with no config section, so this file is where its content lives
// instead. Pure QtQuick — no Quickshell import — so `tests/` can reach it, and
// so the version string has exactly one declaration in the repo rather than
// being a literal inside a `Text`.
//
// ## Why the version is here and not in a manifest
//
// There is no package to read one out of: forest-shell is a Quickshell config
// directory, not a built artefact, and `shell.qml` is the entry point rather
// than a spec file. A version therefore has to be *stated* by some file, and
// the honest place is the one file whose whole job is answering "what is this
// and what version of it".
//
// ## Why the changelog flag is a version and not a boolean
//
// `state.json` carries `seen.changelogVersion` (Core/StateSchema.qml). A
// boolean would have to be cleared by whatever ships the next version, which is
// a write nobody performs on a config directory the user pulled with git — so
// the flag records *which* version was read, and any other value, including the
// empty default, is unread. Upgrading announces itself with nothing written.
import QtQuick

QtObject {
    id: facts

    /// This build. Pre-1.0 on purpose: the map (#1) puts v1 at the end of the
    /// build plan, and a shell that called itself 1.0 before its own plan said
    /// so would be the version number lying about the thing it exists to
    /// describe.
    readonly property string version: "0.1.0"

    /// The name under the version — what this is, in one line, for someone who
    /// opened the tab to find out.
    readonly property string tagline: "A Wayland desktop shell for Hyprland, written in Quickshell."

    /// What this shell is built out of. Every entry is a thing that had to be
    /// chosen and could have been chosen differently, with somewhere to go and
    /// read about it — a credits list of things nobody can look up is a list
    /// nobody reads twice.
    readonly property var credits: [
        { name: "Quickshell",
          what: "The QML shell toolkit everything here is written against",
          url: "https://quickshell.org" },
        { name: "Hyprland",
          what: "The compositor this shell targets",
          url: "https://hypr.land" },
        { name: "Lucide",
          what: "Every glyph in the shell, vendored at a pinned version",
          url: "https://lucide.dev" },
        { name: "Open-Meteo",
          what: "The weather, keyless and without an account",
          url: "https://open-meteo.com" },
        { name: "Qt",
          what: "QtQuick, the scenegraph, and the layout engine under all of it",
          url: "https://www.qt.io" }
    ]

    /// Whether the changelog for *this* version has been read, given what
    /// `state.json` remembers. Equality and not a comparison: versions are not
    /// ordered here, and a state file that has run ahead of the build — a
    /// downgrade — reads as unread rather than as read, because what it
    /// recorded was a different set of notes.
    function changelogSeen(seenVersion: string): bool {
        return seenVersion === facts.version;
    }

    /// The row's line. Naming the version rather than saying "yes" answers the
    /// question the row is actually about after an upgrade: not *whether* notes
    /// were read but *which*.
    function seenLabel(seenVersion: string): string {
        return seenVersion === "" ? "Not read yet" : "Read for " + seenVersion;
    }
}
