// Dashboard — the card registry, the sampler's two knobs, and the header (#55,
// for #49, #50).
//
// `dashboard.cards` is one ordered list rather than a switch per card, the same
// shape the bar's clusters and the control centre's grid have: presence is
// enablement, and the order *is* the layout — the dashboard is a column, so the
// list reads top to bottom exactly as the panel does.
//
// The pool is what Surfaces/Drawers/DashboardRegistry.qml can draw, which is
// deliberately not the same set as what the config may carry: a card written by
// a newer shell survives a round trip through this one and shows up in the list
// under its own id, unlabelled, rather than being stripped on the first save.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Surfaces.Drawers
import qs.Surfaces.Settings.Controls

TabPage {
    id: page

    title: "Dashboard"
    section: "dashboard"
    blurb: "The panel behind the bar's clock: a header, then the cards below in the order "
           + "they are listed here."

    SectionHeader { text: "Cards" }

    SectionNote {
        note: "Top to bottom. A card that is in no list is off, so removing one parks it "
              + "in the pool below. The header is not a card — it is what the panel is."
    }

    OrderedList {
        path: "dashboard.cards"
        pool: page.pool
        mono: false
        labelFor: id => page.registry.cards[id]?.label ?? id
        emptyNote: "no cards — the panel is its header alone"
    }

    SectionHeader { text: "System monitor" }

    SectionNote {
        note: "The card's own knobs rather than the machine's: the sampler exists for this "
              + "card and reads nothing at all while the card is off."
    }

    SettingRow {
        label: "Sample interval"
        hint: "Seconds. One is the readable maximum — a sparkline updating faster than "
              + "that is a shimmer rather than a reading — and ten is a monitor that has "
              + "become a summary."
        binding: intervalBinding

        ConfigBinding { id: intervalBinding; path: "dashboard.systemMonitor.intervalSeconds" }

        SettingSlider { binding: intervalBinding; from: 1; to: 10 }
    }

    SettingRow {
        label: "Disk"
        hint: "Which filesystem the disk row is about. One and not all of them: a machine "
              + "with fifteen mounts would need the card to choose anyway. A path that is "
              + "not a mount point drops the row rather than showing a wrong number."
        binding: diskBinding

        ConfigBinding { id: diskBinding; path: "dashboard.systemMonitor.diskPath" }

        SettingText {
            binding: diskBinding
            placeholder: "/"
            validate: text => text === "" || text.startsWith("/") || text.startsWith("~")
        }
    }

    SectionHeader { text: "Header" }

    SectionNote {
        note: "Both blank mean *work it out*: the shell knows the login name and where a "
              + "desktop keeps a face. They are settings because neither guess is always "
              + "right — a login name is not a name, and an account picture is a "
              + "per-machine file this config travels away from."
    }

    SettingRow {
        label: "Name"
        hint: "What the header calls you."
        binding: nameBinding

        ConfigBinding { id: nameBinding; path: "dashboard.profile.name" }

        SettingText { binding: nameBinding; placeholder: "the login name" }
    }

    SettingRow {
        label: "Avatar"
        hint: "A path to a picture. `~/` is expanded."
        binding: avatarBinding

        ConfigBinding { id: avatarBinding; path: "dashboard.profile.avatar" }

        SettingText {
            binding: avatarBinding
            placeholder: "~/.face"
            validate: text => text === "" || text.startsWith("/") || text.startsWith("~")
        }
    }

    // --- what the registry can draw ------------------------------------------

    readonly property DashboardRegistry registry: DashboardRegistry {}

    /// Every card the *schema* names that is not currently placed. The schema's
    /// vocabulary and not the registry's, because those two are allowed to
    /// differ in one direction and have: a name may be offered here before the
    /// file that draws it exists, which is how #50's two data cards survived a
    /// version that could not render them.
    readonly property var pool: {
        const placed = Config.values.dashboard.cards;
        return Config.schema.dashboardCards.filter(id => placed.indexOf(id) < 0);
    }
}
