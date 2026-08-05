// Reads a checked-in file, for the tests that assert on one.
//
// Most of this seam decides things about values a policy object returns. A few
// decide things about a *file* instead — "does the config the integration guide
// tells you to source still contain the lines the shell documents" (#140), "does
// the shipped tile still carry the property that keeps its chevron off the
// switch" (#183). CLAUDE.md sanctions that: it is still a decision, and
// tests/run.sh sets `QML_XHR_ALLOW_FILE_READ` for it.
//
// It lives in its own component because the second caller arrived (#183) and the
// alternative was a second byte-identical copy of the same eight lines.
//
// Paths are relative to `tests/`, because that is where this file is and
// `Qt.resolvedUrl` resolves against the component, not the caller.
import QtQml

QtObject {
    /// The text of the file at `path`, or `null` when there is none. Qt gates
    /// file:// reads behind QML_XHR_ALLOW_FILE_READ, which tests/run.sh sets; a
    /// missing file comes back status 0 rather than 404, which is why an empty
    /// read is `null` too.
    function read(path: string): var {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(path), false);
        xhr.send();
        if (xhr.status !== 200 && xhr.status !== 0)
            return null;
        const text = String(xhr.responseText ?? "");
        return text.length > 0 ? text : null;
    }
}
