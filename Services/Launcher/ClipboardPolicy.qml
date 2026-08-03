// The clipboard provider's decisions (#53) — what `cliphist list` said, which
// of it a query matches, what Enter has to run to put an entry back on the
// selection, and what to say when there is no history to show.
//
// `cliphist` keeps the history and `wl-clipboard` fills it; this file runs
// neither. It parses one text format, ranks against it, builds three argvs and
// turns an exit code into one of four sentences. Services/Launcher/Clipboard.qml
// owns the `Process`es, and nothing here needs Quickshell, so `tests/` can reach
// the whole decision — the split CalculatorPolicy.qml makes next door, for the
// same reason.
//
// ## Native-first loses here, knowingly
//
// Quickshell reads and writes the current selection (`Quickshell.clipboardText`)
// and has no history at all: the Wayland data-device protocol hands out the
// *current* offer and nothing before it, so a shell that wanted history would
// have to hold every selection it ever saw in its own memory, for the length of
// the session, and lose it on restart. `cliphist` is a database and a watcher
// that already does this, and #9 took the trade explicitly. The cost is two
// binaries that must be on the machine and one watcher that must be running,
// which is why `missing()` and `idle()` below are two different sentences.
//
// ## Why the exit code is the only thing trusted
//
// The ticket's maintenance pass named the shape to avoid: "a missing cliphist
// that degrades into a silently empty history is the #78 shape". An empty
// history and an absent `cliphist` produce *the same stdout* — nothing at all —
// so output can never be the test. Measured against cliphist 1:0.7.0 and
// Quickshell 0.3.0, the four outcomes are told apart like this:
//
//   history full        started → exited(0), lines on stdout
//   history emptied     started → exited(0), nothing on stdout
//   store never written started → exited(1), `opening db: please store
//                       something first` on stderr, nothing on stdout
//   not installed       neither signal — only `running` going false
//
// The bottom row is why `started` is tracked at all, and it is the same
// measurement CalculatorPolicy.qml's header records: a spawn that never happened
// produces no exit code to key off, so the absence of the signal *is* the
// signal.
//
// The third row is the one that cost this file a rewrite, and it is worth the
// space. `cliphist list` **exits 1** on a machine where nothing has ever been
// stored — the database file does not exist yet, and cliphist treats that as an
// error rather than as an empty result. The first version here keyed
// `available` off the exit code, the way the calculator legitimately can, and so
// a fresh install with `cliphist` present and a watcher not yet started was told
// *"cliphist is not installed"*. That is the wrong sentence in the most
// expensive possible direction: it sends someone to install a package they
// already have, past the actual problem. Found by running it
// (tools/launcher-harness.sh), not by reading it.
//
// So the two questions are separated. **Whether the tool exists** is answered by
// `started`, and by nothing else. **Whether the listing worked** is answered by
// the exit code, and a non-zero one is read against `emptyStore()` below before
// it is called a failure.
//
// The second row is this provider's own, and survives the rewrite: an emptied
// history is a perfectly good answer that must not read as a failure, but it is
// also what a machine with a watcher that was never started looks like, forever
// — so the sentence names the watcher.
import QtQuick

QtObject {
    id: policy

    /// The three binaries, named once each. They appear in argvs, in probes and
    /// in the sentences a user reads when one is missing, and a shell that
    /// spells its dependency two ways in three places sends people to install
    /// the wrong one.
    readonly property string tool: "cliphist"
    readonly property string copier: "wl-copy"
    readonly property string watcher: "wl-paste"

    /// The Hyprland lines that fill the history. Data rather than prose, so the
    /// sentence the launcher shows when the history is empty and the lines in
    /// Services/README.md cannot drift apart, and so a test can assert on them.
    ///
    /// The file that actually installs them is
    /// `integration/hyprland/forest-autostart.conf`; being data here is not the
    /// same as being installed anywhere, which is the whole of #140.
    ///
    /// Two lines and not one: `wl-paste --watch` serves a single MIME family per
    /// invocation, so a single untyped watcher stores text and silently drops
    /// every image — which would be a clipboard history that works until the
    /// first screenshot, then quietly does not. Both acceptance criteria in #53
    /// name images, so both watchers are the documented setup.
    readonly property var autostart: [
        "exec-once = " + policy.watcher + " --type text --watch " + policy.tool + " store",
        "exec-once = " + policy.watcher + " --type image --watch " + policy.tool + " store"
    ]

    // --- what came back ------------------------------------------------------

    /// One line of `cliphist list`, as an entry, or `null` when the line is not
    /// one. The format is `<id>\t<preview>`: a decimal id, a tab, and one line
    /// of preview with the entry's own newlines already collapsed by cliphist.
    ///
    /// The tab is the split and the *first* tab is the only one that counts —
    /// a copied line of TSV contains its own tabs, and splitting on all of them
    /// would turn one entry into several and lose the rest of the preview.
    function entryOf(line: string): var {
        const text = String(line ?? "");
        const tab = text.indexOf("\t");
        if (tab <= 0)
            return null;

        const id = text.slice(0, tab);
        if (!policy.validId(id))
            return null;

        const preview = text.slice(tab + 1);
        const binary = policy.binaryOf(preview);
        return {
            id: id,
            preview: preview,
            image: binary !== null,
            format: binary ? binary.format : "",
            size: binary ? binary.size : "",
            dimensions: binary ? binary.dimensions : ""
        };
    }

    /// Whether an id is one this provider will put in an argv. Decimal digits,
    /// nothing else, and non-empty.
    ///
    /// This is a guard and not a parse. Every argv below is built from an id
    /// that came off `cliphist list`, so it is cliphist's own output rather than
    /// user input — but `copyArgv()` is the one place in this shell that hands a
    /// string to `sh -c`, and a value that reaches a shell should be checked
    /// where it is cheap to check rather than trusted because of where it came
    /// from. See `copyArgv()` for why a shell is involved at all.
    function validId(id: string): bool {
        return /^[0-9]+$/.test(String(id ?? ""));
    }

    /// The binary-data marker cliphist writes in place of a preview it cannot
    /// print, taken apart — or `null` for an ordinary text entry.
    ///
    /// The format upstream produces is `[[ binary data 39 KiB png 1920x1080 ]]`,
    /// and this reads it *loosely*: the marker is matched exactly, and the three
    /// facts inside it are picked out by shape rather than by position. That is
    /// deliberate. The marker is another project's output and its field order
    /// has changed before; a strict parse that returned `null` on an unfamiliar
    /// variant would classify an image as text, and a text row for an image
    /// re-copies as `application/octet-stream` and pastes nothing. A loose parse
    /// degrades to an image with no dimensions on it, which is a worse row and a
    /// working one.
    function binaryOf(preview: string): var {
        const text = String(preview ?? "").trim();
        if (!/^\[\[\s*binary data\b.*\]\]$/.test(text))
            return null;

        const body = text.replace(/^\[\[\s*binary data\s*/, "").replace(/\s*\]\]$/, "");
        const size = body.match(/\b\d+(?:\.\d+)?\s*(?:B|[KMG]i?B)\b/i);
        const dimensions = body.match(/\b\d+x\d+\b/);
        const format = body.match(/\b(png|jpe?g|gif|bmp|webp|tiff?|svg)\b/i);

        return {
            size: size ? size[0] : "",
            dimensions: dimensions ? dimensions[0] : "",
            format: format ? format[0].toLowerCase() : ""
        };
    }

    /// Every entry `cliphist list` reported, newest first — its own order, kept.
    ///
    /// Unparseable lines are dropped rather than shown. A line with no tab in it
    /// is not an entry cliphist can decode either, so a row for one would be a
    /// row that pastes nothing.
    function parse(stdout: string): var {
        const out = [];
        for (const line of String(stdout ?? "").split("\n")) {
            const entry = policy.entryOf(line);
            if (entry)
                out.push(entry);
        }
        return out;
    }

    /// The same list with repeats taken out, keeping the first — which is the
    /// most recent, because cliphist lists newest first.
    ///
    /// cliphist de-duplicates on store, so this is not that. What it catches is
    /// the pair that differs only in trailing whitespace: a line yanked from an
    /// editor and the same line copied from a terminal are two rows that look
    /// identical on screen and one of them is not the one you meant to press
    /// Enter on.
    ///
    /// Images are exempt. Two screenshots of the same size are two different
    /// pictures, and the only thing this file knows about either of them is a
    /// preview that says `[[ binary data 39 KiB png 1920x1080 ]]` for both —
    /// so de-duplicating them would throw away an entry on the strength of a
    /// string that was never a description of the content.
    function dedupe(entries: var): var {
        const seen = {};
        const out = [];
        for (const entry of entries ?? []) {
            if (entry.image) {
                out.push(entry);
                continue;
            }
            const key = String(entry.preview ?? "").trim();
            if (seen[key] === true)
                continue;
            seen[key] = true;
            out.push(entry);
        }
        return out;
    }

    // --- matching ------------------------------------------------------------

    // The one provider that does *not* borrow `LauncherPolicy.score()`, and the
    // deviation is deliberate — EmojiPolicy.qml borrows it and says why, so this
    // is the file that owes the argument for not.
    //
    // The fuzzy scorer matches a subsequence: every character of the needle, in
    // order, anywhere. That is right for a *name*, which is short and which the
    // user is aiming at from memory. A clipboard entry is not a name — it is
    // whatever prose, URL or command was copied, and over a haystack that long a
    // subsequence finds almost anything. Measured on the fixture in
    // tests/tst_clipboardpolicy.qml: `png` scores a hit against
    // `https://example.invalid/thing` (p·n·g, in order, three words apart), so a
    // search for screenshots returns a URL. EmojiPolicy hit the same wall from
    // the other side — `lol` scoring 8.6 against "loudly crying face" — and
    // solved it with exact rungs above the fuzzy ones, which works when there is
    // a canonical name to be exact *about*. Here there is not.
    //
    // So: substring, every term, case-insensitive. That is what "find the thing
    // I copied that had `--force-with-lease` in it" means, and it is what every
    // other tool that searches content rather than names does.

    /// How many rows a bare `;` shows. The emoji provider's number and its
    /// reason (#11 §6): these rows are being *browsed* rather than recognised —
    /// you do not know which of the last forty copies you want until you see it
    /// — but a launcher that opens onto the whole history is a database viewer.
    readonly property int browseLimit: 12

    /// The matches for a query, ranked, out of a list that is already deduped.
    ///
    /// An image entry is matched on its *format*, not on its marker: typing
    /// `png` should find screenshots, and typing `binary` should not find
    /// everything. The preview of a text entry is matched whole.
    ///
    /// Ties break on the list's own order, which is recency, so the most
    /// recently copied of two equal matches is the one nearest the top — and so
    /// the list is stable under a keystroke that does not change any score.
    function search(entries: var, query: string): var {
        const list = entries ?? [];
        const want = String(query ?? "").trim();

        if (want.length === 0)
            return list.slice(0, policy.browseLimit);

        const scored = [];
        for (let i = 0; i < list.length; i++) {
            const hit = policy.scoreEntry(want, list[i]);
            if (hit < 0)
                continue;
            scored.push({ entry: list[i], hit: hit, order: i });
        }

        scored.sort((a, b) => b.hit - a.hit || a.order - b.order);
        return scored.map(row => row.entry);
    }

    /// What a query is matched against. Text is matched on its preview; an
    /// image is matched on the words that describe it, so `png`, `1920x1080`
    /// and `image` each reach one and the marker's own boilerplate — `binary
    /// data` — reaches none, because a word that appears in every image is a
    /// word that filters nothing.
    function haystack(entry: var): string {
        if (!entry)
            return "";
        if (entry.image !== true)
            return String(entry.preview ?? "");
        return ["image", entry.format, entry.dimensions]
               .filter(part => String(part ?? "") !== "")
               .join(" ");
    }

    /// How well one entry matches. Every whitespace-separated term must appear
    /// in it, so `git lease` finds the one command with both words and the
    /// query narrows as it is typed rather than widening.
    ///
    /// Longer terms are worth more, an entry that *starts* with the query is
    /// worth more still, and a long entry is penalised slightly — the same
    /// three instincts `LauncherPolicy.score()` has, kept so that ranking feels
    /// the same even though matching cannot be.
    function scoreEntry(needle: string, entry: var): real {
        if (!entry)
            return -1;
        const want = String(needle ?? "").trim().toLowerCase();
        if (want.length === 0)
            return 0;

        const hay = policy.haystack(entry).toLowerCase();
        if (hay.length === 0)
            return -1;

        let total = 0;
        let earliest = -1;
        for (const term of want.split(/\s+/)) {
            if (term.length === 0)
                continue;
            const at = hay.indexOf(term);
            if (at < 0)
                return -1;
            total += term.length;
            if (earliest < 0 || at < earliest)
                earliest = at;
        }

        if (earliest === 0)
            total += 4;
        return total - hay.length * 0.02 - Math.max(0, earliest) * 0.01;
    }

    // --- the rows ------------------------------------------------------------

    /// One entry as a row.
    ///
    /// `copy` is empty and stays empty, which is the one place this provider
    /// departs from the emoji and calculator rows. What `cliphist list` returns
    /// is a *preview*: one line, truncated, with the newlines flattened out. A
    /// row that carried it as its `copy` would put a mangled prefix of the entry
    /// on the clipboard and report a successful copy — the #78 shape again, in
    /// miniature and per paste. The full entry only exists behind
    /// `cliphist decode`, so Enter here runs something, and
    /// Services/Launcher/Providers.qml routes it to Clipboard.qml rather than to
    /// its own `copy()`.
    ///
    /// `entryId` carries the cliphist id, the way it carries a desktop-entry id
    /// for the apps provider: it is the provider's own name for the thing, and
    /// the field is documented in LauncherPolicy.qml as exactly that.
    ///
    /// `thumbnail` is a decoded image on disk, or "". It arrives after the row
    /// does — see Clipboard.qml — so a row is built without one and rebuilt with
    /// it, rather than the list waiting for every picture before it shows
    /// anything.
    function row(entry: var, thumbnail: string): var {
        if (!entry)
            return null;
        const image = entry.image === true;
        const path = String(thumbnail ?? "");
        return {
            provider: "clipboard",
            id: "clipboard:" + entry.id,
            title: image ? policy.imageTitle(entry) : String(entry.preview ?? ""),
            subtitle: image ? policy.imageSubtitle(entry) : "",
            // No thumbnail yet, or an entry that will never have one: the icon
            // slot says which kind of thing this is rather than sitting empty
            // while the decode runs.
            icon: path === "" ? (image ? "image" : "clipboard-list") : "",
            glyph: "",
            iconSource: path,
            category: "Clipboard",
            copy: "",
            entryId: String(entry.id ?? ""),
            run: null
        };
    }

    /// Every row for a query, thumbnails filled in from a map the surface's
    /// provider keeps. `thumbnails` is `{ [id]: path }` and a missing key is
    /// simply no picture yet.
    function rows(entries: var, query: string, thumbnails: var): var {
        const map = thumbnails ?? {};
        return policy.search(entries, query)
                     .map(entry => policy.row(entry, String(map[entry.id] ?? "")));
    }

    /// What an image row's title says. The dimensions and not the byte count,
    /// because "1920x1080" is how you recognise the screenshot you took and
    /// "39 KiB" is not.
    function imageTitle(entry: var): string {
        const dimensions = String((entry ?? {}).dimensions ?? "");
        return dimensions === "" ? "Image" : "Image " + dimensions.replace("x", "×");
    }

    function imageSubtitle(entry: var): string {
        return [String((entry ?? {}).format ?? "").toUpperCase(),
                String((entry ?? {}).size ?? "")]
               .filter(part => part !== "")
               .join(" · ");
    }

    // --- what to run ---------------------------------------------------------

    /// The listing. Also the probe — see Clipboard.qml's header: the question
    /// "is cliphist installed" and the question "what is in the history" have
    /// the same answer and the same exit code, so asking them with two processes
    /// would be one spawn spent proving what the other one already showed.
    function listArgv(): var {
        return [policy.tool, "list"];
    }

    /// The full entry behind an id, on stdout.
    function decodeArgv(id: string): var {
        return [policy.tool, "decode", String(id ?? "")];
    }

    /// What Enter runs for an *image* entry: decode it and hand the bytes to
    /// `wl-copy` with the MIME type on them.
    ///
    /// This is the one place the shell uses a shell. Everything else here is an
    /// argv, for the reason CalculatorPolicy.qml gives — but a pipe is not
    /// something an argv can express, and the alternative is carrying a PNG
    /// through `StdioCollector`, which is a QML string: the bytes would be
    /// decoded as UTF-8 and re-encoded on the way out, and what reached the
    /// clipboard would not be the image.
    ///
    /// So the shell is real and the interpolation is not: the id and the type go
    /// in as **positional arguments**, and the script body is a constant. That
    /// is the same discipline `argv()` keeps for a typed sum — `$1` is a value
    /// to `sh`, where `" + id + "` would be syntax.
    ///
    /// Text does not come through here at all. It goes through
    /// `Quickshell.clipboardText`, which is the compositor's own selection and
    /// costs no process — the argument Providers.qml makes about not spawning a
    /// copier that has to stay alive to serve what it copied.
    function copyArgv(id: string, format: string): var {
        return ["sh", "-c",
                policy.tool + " decode \"$1\" | " + policy.copier + " --type \"$2\"",
                "sh", String(id ?? ""), policy.mimeOf(format)];
    }

    /// Decode an entry to a file — how a thumbnail gets on disk. A shell for
    /// the redirection, and the same positional-argument rule as above.
    ///
    /// The `mkdir` is here rather than in a one-shot at startup because the
    /// cache directory is not the shell's to keep: `rm -rf` of a cache is a
    /// supported thing for a user to do, and a provider that created the
    /// directory once at boot would draw blank rows for the rest of the session
    /// afterwards.
    function thumbnailArgv(id: string, path: string): var {
        return ["sh", "-c",
                "mkdir -p \"$(dirname \"$2\")\" && " + policy.tool + " decode \"$1\" > \"$2\"",
                "sh", String(id ?? ""), String(path ?? "")];
    }

    /// The MIME type for a format cliphist named. Falls back to PNG rather than
    /// to `application/octet-stream`: an image whose marker this file could not
    /// read is still far more likely to be a screenshot than to be arbitrary
    /// bytes, and an offer typed `application/octet-stream` is one most
    /// applications will not take at all.
    function mimeOf(format: string): string {
        const name = String(format ?? "").toLowerCase();
        if (name === "jpg" || name === "jpeg")
            return "image/jpeg";
        if (name === "gif")
            return "image/gif";
        if (name === "bmp")
            return "image/bmp";
        if (name === "webp")
            return "image/webp";
        if (name === "tif" || name === "tiff")
            return "image/tiff";
        if (name === "svg")
            return "image/svg+xml";
        return "image/png";
    }

    // --- thumbnails ----------------------------------------------------------

    /// How many pictures are decoded for one query. The list shows twelve rows
    /// at most and a decode is a process, so this is the same number: a query
    /// that spawned one process per entry in a two-hundred-entry history would
    /// be a keystroke that forks two hundred times.
    readonly property int thumbnailLimit: 12

    /// Where a decoded image lives. Under the cache directory, named by the id,
    /// so that a second look at the same entry costs no second decode and a
    /// `rm -rf` of the cache costs nothing at all.
    ///
    /// The extension is cliphist's own word for the format, which is what makes
    /// the file loadable: `Image` picks its reader by content, but a file whose
    /// name says nothing is one no other tool can open when a bug has to be
    /// looked at by hand.
    function thumbnailPath(cacheDir: string, entry: var): string {
        if (!entry || entry.image !== true || !policy.validId(entry.id))
            return "";
        const format = String(entry.format ?? "");
        return String(cacheDir ?? "") + "/" + entry.id
             + (format === "" ? ".bin" : "." + format);
    }

    /// Which of a query's rows are worth decoding: the image ones, capped, and
    /// only those without a picture already.
    function thumbnailQueue(entries: var, thumbnails: var): var {
        const map = thumbnails ?? {};
        const out = [];
        for (const entry of entries ?? []) {
            if (entry.image !== true || String(map[entry.id] ?? "") !== "")
                continue;
            out.push(entry);
            if (out.length >= policy.thumbnailLimit)
                break;
        }
        return out;
    }

    // --- reading the reply ---------------------------------------------------

    function accepted(exitCode: int): bool {
        return exitCode === 0;
    }

    /// Whether a *failed* listing failed only because nothing has ever been
    /// stored. cliphist's database is created by the first `store`, and `list`
    /// against a database that does not exist yet exits 1 rather than printing
    /// nothing — see the header, and note that this is the state every machine
    /// is in until the watcher stores its first copy.
    ///
    /// Matched on cliphist's own sentence, which is the fragile part and is
    /// deliberately narrow: anything else that fails is a *failure*, and gets a
    /// sentence naming the exit code rather than being quietly called empty. If
    /// upstream rewords this, a fresh machine reads "could not read its history
    /// — exit 1" instead of "nothing copied yet". That is a worse message and an
    /// honest one, which is the right way round for a guess about another
    /// project's strings to fail.
    function emptyStore(stderr: string): bool {
        return /store something first/i.test(String(stderr ?? ""));
    }

    // --- the silences --------------------------------------------------------
    //
    // Four, and they are four different pieces of news — the argument
    // LauncherPolicy.empty() makes, and this provider is the one where getting
    // it wrong is invisible: a missing binary, a stopped watcher and an empty
    // history all produce no rows and no error.

    /// What the clipboard says instead of a list, or `null` when it has rows.
    ///
    /// `state` is the provider's own:
    /// `{ available, probed, pending, failed, count }`. The order is the order
    /// of certainty — a missing binary is a fact about the machine and outranks
    /// anything about this particular query, and a listing that came back broken
    /// outranks the conclusion anyone would otherwise draw from its empty
    /// result.
    function silence(query: string, state: var): var {
        const it = state ?? {};

        if (it.probed === true && it.available === false)
            return { icon: "circle-slash", text: policy.missing() };
        if (it.pending === true && !(Number(it.count ?? 0) > 0))
            return { icon: "loader", text: "Reading clipboard history…" };
        if (it.failed === true)
            return { icon: "circle-slash", text: policy.unreadable(Number(it.exitCode ?? 0)) };
        if (!(Number(it.count ?? 0) > 0))
            return { icon: "clipboard-list", text: policy.idle() };
        if (String(query ?? "").trim().length > 0)
            return { icon: "circle-slash",
                     text: "Nothing in the clipboard matches \"" + String(query).trim() + "\"" };
        return null;
    }

    /// The sentence for a machine with no `cliphist` on it. Names both packages,
    /// because installing one without the other produces a history that stays
    /// empty forever and no error anywhere — `cliphist` is the store and
    /// `wl-clipboard` is what fills it.
    function missing(): string {
        return policy.tool + " is not installed (packages: " + policy.tool
             + ", wl-clipboard)";
    }

    /// `cliphist` ran and could not read its history — a permission on the
    /// store, a database written by a version that does not read back, a disk
    /// with nothing left on it. Names the exit code because there is nothing
    /// else to say: the only thing known here is that the tool is present and
    /// refused, which is already the useful half of the news.
    function unreadable(exitCode: int): string {
        return policy.tool + " could not read its history — exit " + exitCode;
    }

    /// `cliphist` answered, and had nothing. A fresh boot with nothing copied
    /// yet looks exactly like a machine whose watcher was never started, and the
    /// second one never fixes itself — so the sentence names the watcher rather
    /// than saying "empty" and leaving the user to guess which it is.
    function idle(): string {
        return "No clipboard history yet — is `" + policy.watcher + " --watch "
             + policy.tool + " store` running?";
    }

    // --- what the log says ---------------------------------------------------
    //
    // The wording is the contract: tools/launcher-harness.sh greps for exactly
    // these (#81).

    /// The history was read, and how much of it there was. Logged on every
    /// listing and not only on a change, because "the list came back empty" is
    /// the answer this provider is most often wrong about and the only record
    /// that it was asked at all.
    function listed(count: int): string {
        return count + " clipboard " + (count === 1 ? "entry" : "entries") + " listed";
    }

    /// An entry went back on the selection. Names the id *and* what it was, for
    /// #81's reason: a line saying `copied` and nothing else cannot be told from
    /// the copy before it.
    function copied(entry: var): string {
        if (!entry)
            return "nothing to copy";
        return "clipboard entry " + entry.id + " copied ("
             + (entry.image === true ? policy.mimeOf(entry.format)
                                     : "text, " + String(entry.preview ?? "").length + " chars")
             + ")";
    }

    /// A decode that came back non-zero. The entry was in the list a moment ago,
    /// so this is the history having moved under the launcher — cliphist wipes
    /// and the ring buffer rolling over are both real.
    function decodeFailed(id: string, exitCode: int): string {
        return policy.tool + " could not decode entry " + id + " — exit " + exitCode;
    }

    /// The listing itself came back non-zero. Distinct from `absent()`: the
    /// binary ran, so this is cliphist's own database refusing — a permission
    /// on the store, or a version that does not know the subcommand.
    function listFailed(exitCode: int): string {
        return policy.tool + " list failed — exit " + exitCode;
    }

    /// An image copy that came back non-zero. 127 is called out by name because
    /// it is the one this pipe produces on a machine that has `cliphist` and not
    /// `wl-clipboard` — the half-installed case `missing()` names both packages
    /// to prevent, seen from the other end.
    function copyFailed(id: string, exitCode: int): string {
        const line = "could not copy entry " + id + " — exit " + exitCode;
        return exitCode === 127 ? line + " (is " + policy.copier + " installed?)" : line;
    }

    /// The spawn that never happened. A warning and not a log line: every `;`
    /// from here on is a silence, and this is the only place the reason is
    /// written down.
    function absent(): string {
        return "no " + policy.tool + " on PATH — the clipboard provider is inert";
    }

    /// A thumbnail landed. The path and not just the id, because the next
    /// question after "why is this row blank" is always "is the file there".
    function thumbnailed(id: string, path: string): string {
        return "thumbnail for entry " + id + " at " + path;
    }
}
