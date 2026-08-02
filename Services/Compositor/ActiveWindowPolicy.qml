// What the bar says about the focused window, as pure functions (#37).
//
// Small, and separate from the facade for the usual reason: the facade imports
// Quickshell and is therefore unreachable from tests/, while every rule below
// is a decision about text.
//
// The rule worth stating is the fallback. A window's title is set by the
// application and a fair number set it late, set it empty, or never set it at
// all — a freshly mapped terminal, a splash window, an X11 client mid-startup.
// The app id is always there, so a title-less window reads as its application
// rather than as an empty slot that looks like the module has crashed.
import QtQuick

QtObject {
    id: policy

    /// The bar's text for a focused window. `var` rather than `string`, because
    /// both arrive off a toplevel that may be null and a typed parameter would
    /// turn that into the word "undefined".
    function label(title: var, appId: var): string {
        const named = policy.clean(title);
        return named !== "" ? named : policy.clean(appId);
    }

    /// Whitespace-normalised: a title is whatever the application wrote, and
    /// some write tabs and newlines into it.
    function clean(text: var): string {
        if (text === undefined || text === null)
            return "";
        return String(text).replace(/\s+/g, " ").trim();
    }

    /// Whether the module is on the bar. An empty workspace has no focused
    /// window, and the module goes with it rather than showing a placeholder —
    /// "Desktop" would be a word this shell invented for a thing that is not
    /// there.
    function showing(label: var): bool {
        return policy.clean(label) !== "";
    }
}
