// Calendar — the Google account the calendar syncs with (#calendar).
//
// Three controls, and deliberately only three: whether to sync at all, which
// calendar of the account, and how often a background round runs. Everything
// else about the connection is not a setting. The client credentials live in
// `~/.config/forest-shell/google-oauth.json` and the token in
// `~/.local/share/forest-shell/calendar/google-token.json`, both 0600 and both
// written by `tools/gcal-sync.py`; a settings file is hand-edited, copied
// between machines and pasted into bug reports, so a refresh token must never
// be one of the things in it.
//
// The switch is honest about what it does *not* do: turning it on does not
// connect an account. Connecting is `qs ipc call calendar syncConnect`, which
// spawns the helper's consent flow — a browser window and a loopback listener,
// neither of which a settings row can host. The note under the switch says so,
// because a toggle that silently does nothing is the worse answer.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Surfaces.Settings.Controls

TabPage {
    id: page

    title: "Calendar"
    section: "calendar"
    blurb: "The Google account the calendar reads from and writes back to. Off until an "
           + "account is connected, and no request is made at all while it is off."

    FieldPolicy { id: fields }

    SectionHeader { text: "Google" }

    SectionNote {
        note: "Sync is **off** until this is switched on *and* an account is connected. "
              + "Connecting runs a consent flow in a browser — `qs ipc call calendar "
              + "syncConnect` — because it needs a loopback listener a settings row "
              + "cannot host. Credentials and tokens are written to files of their own, "
              + "never into settings.json."
    }

    SettingRow {
        label: "Sync with Google"
        hint: "Every trigger reads this first, so a shell with it off spawns no helper and "
              + "makes no request. Switching it off leaves the events already pulled in "
              + "place — they are yours now, and nothing deletes them."
        binding: enabledBinding

        ConfigBinding { id: enabledBinding; path: "calendar.google.enabled" }

        SettingSwitch { binding: enabledBinding }
    }

    SettingRow {
        label: "Calendar"
        hint: "`primary` is the calendar the account is named after. A shared or secondary "
              + "one is its address — `…@group.calendar.google.com` — which is what "
              + "`tools/gcal-sync.py calendars` prints."
        binding: calendarBinding

        ConfigBinding { id: calendarBinding; path: "calendar.google.calendarId" }

        SettingText { binding: calendarBinding; placeholder: "primary" }
    }

    SettingRow {
        label: "Round interval"
        hint: "Minutes between background rounds. The two triggers that matter while "
              + "someone is watching — opening the window, and making an edit — sync "
              + "straight away, so this is the interval of a shell nobody is touching."
        binding: intervalBinding

        ConfigBinding { id: intervalBinding; path: "calendar.google.intervalMin" }

        SettingSlider { binding: intervalBinding; from: 1; to: 240 }
    }
}
