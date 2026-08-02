#!/usr/bin/env python3
"""A tray icon and a media player that do not exist, for #37.

    tools/fake-dbus-clients.py tray      # one StatusNotifierItem, with a menu
    tools/fake-dbus-clients.py mpris     # one MPRIS player, playing
    tools/fake-dbus-clients.py both

The tray and the media pill are the two modules whose *contents* come from
other applications, so a session with none of either exercises exactly the half
of them that is the shell's own layout code. This registers the missing half:
a real StatusNotifierItem on the session bus and a real
`org.mpris.MediaPlayer2` name, both minimal, both gone when the process is
killed.

Run by tools/services-harness.sh, which starts it before the shell so the items
are already on the bus when the tray host registers — that ordering is the
thing the harness is checking. It talks to the **session** bus, which is shared
with the desktop running the test: the item appears in whatever else is
watching for a minute and then goes away.

Nothing here asserts. It prints the names it took, so the harness can wait for
them, and then sits in a main loop.
"""
import os
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

TRAY_TITLE = "forest-shell test item"
TRACK_TITLE = "Test Track"
TRACK_ARTIST = "Forest Shell"


class Properties(dbus.service.Object):
    """A DBus object with a `org.freedesktop.DBus.Properties` implementation.

    dbus-python does not provide one, and both specs below are read entirely
    through it — a tray item that answers no properties registers fine and then
    shows up as a blank square.
    """

    def __init__(self, bus, path, tables):
        super().__init__(bus, path)
        self.tables = tables

    @dbus.service.method("org.freedesktop.DBus.Properties",
                         in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self.tables.get(interface, {}).get(name, "")

    @dbus.service.method("org.freedesktop.DBus.Properties",
                         in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return self.tables.get(interface, {})

    @dbus.service.signal("org.freedesktop.DBus.Properties", signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass


class TrayItem(Properties):
    """The smallest StatusNotifierItem that renders: an id, a status and an
    icon name from the system theme."""

    def __init__(self, bus):
        super().__init__(bus, "/StatusNotifierItem", {
            "org.kde.StatusNotifierItem": {
                "Category": "ApplicationStatus",
                "Id": "forest-shell-test",
                "Title": TRAY_TITLE,
                "Status": "Active",
                "IconName": "dialog-information",
                "ItemIsMenu": False,
            },
        })

    @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
    def Activate(self, x, y):
        print("activated", flush=True)

    @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
    def SecondaryActivate(self, x, y):
        print("secondary-activated", flush=True)

    @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ib")
    def Scroll(self, delta, orientation):
        print("scrolled", delta, flush=True)


class MprisPlayer(Properties):
    """An MPRIS player that is playing something, and can be paused."""

    def __init__(self, bus):
        self.state = "Playing"
        super().__init__(bus, "/org/mpris/MediaPlayer2", {
            "org.mpris.MediaPlayer2": {
                "Identity": "Forest Test Player",
                "CanQuit": False,
                "CanRaise": False,
                "HasTrackList": False,
            },
            "org.mpris.MediaPlayer2.Player": {},
        })
        self.refresh()

    def refresh(self):
        self.tables["org.mpris.MediaPlayer2.Player"] = {
            "PlaybackStatus": self.state,
            "CanControl": True,
            "CanPlay": True,
            "CanPause": True,
            "CanGoNext": True,
            "CanGoPrevious": True,
            "CanSeek": False,
            "Metadata": dbus.Dictionary({
                "mpris:trackid": dbus.ObjectPath("/org/forest/track/1"),
                "xesam:title": TRACK_TITLE,
                "xesam:artist": dbus.Array([TRACK_ARTIST], signature="s"),
            }, signature="sv"),
        }

    def announce(self):
        self.refresh()
        self.PropertiesChanged("org.mpris.MediaPlayer2.Player",
                               self.tables["org.mpris.MediaPlayer2.Player"], [])

    @dbus.service.method("org.mpris.MediaPlayer2.Player")
    def PlayPause(self):
        self.state = "Paused" if self.state == "Playing" else "Playing"
        self.announce()
        print("playback", self.state, flush=True)

    @dbus.service.method("org.mpris.MediaPlayer2.Player")
    def Play(self):
        self.state = "Playing"
        self.announce()

    @dbus.service.method("org.mpris.MediaPlayer2.Player")
    def Pause(self):
        self.state = "Paused"
        self.announce()

    @dbus.service.method("org.mpris.MediaPlayer2.Player")
    def Next(self):
        print("next", flush=True)

    @dbus.service.method("org.mpris.MediaPlayer2.Player")
    def Previous(self):
        print("previous", flush=True)


def main(argv):
    what = argv[1] if len(argv) > 1 else "both"
    if what not in ("tray", "mpris", "both"):
        print(__doc__)
        return 2

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    held = []

    if what in ("tray", "both"):
        name = "org.kde.StatusNotifierItem-%d-1" % os.getpid()
        held.append(dbus.service.BusName(name, bus))
        TrayItem(bus)
        # The watcher is what tells every host about the item. Without this
        # call the name sits on the bus and no tray ever hears about it.
        try:
            watcher = bus.get_object("org.kde.StatusNotifierWatcher",
                                     "/StatusNotifierWatcher")
            watcher.RegisterStatusNotifierItem(
                name, dbus_interface="org.kde.StatusNotifierWatcher")
            print("tray", name, flush=True)
        except dbus.DBusException as error:
            # No watcher yet: the shell under test registers one when it starts,
            # so try again until it does.
            print("tray-waiting", error.get_dbus_name(), flush=True)
            GLib.timeout_add_seconds(1, lambda: retry_register(bus, name))

    if what in ("mpris", "both"):
        name = "org.mpris.MediaPlayer2.foresttest"
        held.append(dbus.service.BusName(name, bus))
        MprisPlayer(bus)
        print("mpris", name, flush=True)

    GLib.MainLoop().run()
    return 0


def retry_register(bus, name):
    try:
        watcher = bus.get_object("org.kde.StatusNotifierWatcher",
                                 "/StatusNotifierWatcher")
        watcher.RegisterStatusNotifierItem(
            name, dbus_interface="org.kde.StatusNotifierWatcher")
        print("tray", name, flush=True)
        return False
    except dbus.DBusException:
        return True


if __name__ == "__main__":
    sys.exit(main(sys.argv))
