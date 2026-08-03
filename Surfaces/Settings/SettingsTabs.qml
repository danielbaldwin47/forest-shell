// The settings window's tab list (#54, #55) — the navigation skeleton as data.
//
// Ten tabs, and they are the config sections: `settings.json` mirrors this list
// 1:1 (#21), About excepted because there is nothing to configure about a
// version number. That mapping is the whole reason hand-editing the file and
// using the window are the same mental model, so it is enforced by a test
// (`tests/tst_settingstabs.qml`) rather than left as a comment — a section added
// without a tab is a setting the GUI cannot reach, and a tab without a section
// is a tab with nothing in it.
//
// `built` is honest about what has been shipped: #54 built the frame and the
// first four tabs, #55 the other six, so every tab is built today. The flag
// stays rather than being deleted with the last `false`, because what it buys
// is the state on the way there — an unbuilt tab is navigable and says so,
// which is a better answer than hiding it, and an eleventh tab landing
// half-done should reach the same page rather than an empty one.
//
// Pure data, no Quickshell imports, so tests/ can reach it. It carries no
// components either: the window maps an id to its page, because a page imports
// Quickshell and this file must not.
import QtQuick

QtObject {
    id: registry

    readonly property var tabs: [
        { id: "appearance", title: "Appearance", icon: "palette",
          section: "appearance", built: true },
        { id: "bar", title: "Bar", icon: "panel-top",
          section: "bar", built: true },
        { id: "launcher", title: "Launcher", icon: "search",
          section: "launcher", built: true },
        { id: "controlCenter", title: "Control Center", icon: "sliders-horizontal",
          section: "controlCenter", built: true },
        { id: "dashboard", title: "Dashboard", icon: "layout-dashboard",
          section: "dashboard", built: true },
        { id: "notifications", title: "Notifications", icon: "bell",
          section: "notifications", built: true },
        { id: "weatherTime", title: "Weather & Time", icon: "cloud-sun",
          section: "weatherTime", built: true },
        { id: "wallpaper", title: "Wallpaper", icon: "image",
          section: "wallpaper", built: true },
        { id: "system", title: "System", icon: "monitor-cog",
          section: "system", built: true },
        // The one tab with no config section: version, credits, changelog.
        { id: "about", title: "About", icon: "info",
          section: "", built: true }
    ]

    /// The tab an id names, or null. Used to validate what arrives from outside
    /// the window — the state file's last-open tab, and the id a launcher action
    /// or the control centre's gear passes to `SettingsWindow.show()`.
    function find(id: string): var {
        for (const tab of tabs)
            if (tab.id === id)
                return tab;
        return null;
    }

    /// Where the window opens when nothing says otherwise. First rather than
    /// named, so the order is stated once, above.
    readonly property string firstTab: tabs[0].id

    /// The tab to open for `id`, falling back to the first. Every entry point
    /// goes through this: a stale id in the state file, or a page name typed
    /// into `qs ipc call settings showTab`, must open the window rather than
    /// leaving it blank.
    function resolve(id: string): string {
        return find(id) ? id : firstTab;
    }

    /// The tab an arrow key from `id` lands on: `delta` is -1 for Up and +1 for
    /// Down (#77). Clamped at both ends rather than wrapping, so walking off the
    /// bottom of the rail stays on About instead of jumping back to Appearance.
    ///
    /// Every tab is a candidate, built or not — an unbuilt tab is navigable by
    /// pointer and says what it will hold, and a rail the keyboard walks a
    /// different list of than the mouse does would be a worse surprise than
    /// landing on a page that explains itself.
    function neighbour(id: string, delta: int): string {
        const index = tabs.findIndex(tab => tab.id === resolve(id));
        const next = index + delta;
        return next < 0 || next >= tabs.length ? tabs[index].id : tabs[next].id;
    }
}
