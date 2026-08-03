// The optional system-monitor readout (#9, #50): CPU and RAM on the bar.
//
// Off by default, like every optional module — a module that is off is one no
// cluster names (Surfaces/Bar/BarRegistry.qml). It exists for the machine whose
// owner wants the two numbers in front of them all day, and it rides on exactly
// the same sampler as the dashboard's card: putting this on the bar takes a
// subscription for the session, so the timer that was running only while the
// drawer was open now runs all the time. That is the cost the user opted into by
// asking for a live readout, and it is why this module is not on by default.
//
// Two numbers and not four: a disk that moves twice a day and a temperature
// nobody can act on are not worth the bar's horizontal space, and the card is
// one click away. `SystemStatsPolicy.barLabel` is the one that decides that.
import QtQuick
import qs.Core
import qs.Services.System
// Own directory, explicitly — `BarIndicator` is a sibling, and a file
// Quickshell loads by URL gets no implicit sibling resolution (see
// BarContent.qml).
import qs.Surfaces.Bar.Modules

BarIndicator {
    id: root

    icon: "activity"

    label: SystemStats.barLabel

    /// Absent until the first sample lands, rather than present and empty. The
    /// module is on the bar for a second before /proc has been read twice, and
    /// a lone glyph appearing and then growing a number reads as the bar
    /// reflowing.
    shown: root.label !== ""

    Component.onCompleted: {
        SystemStats.watch();
        Logger.log("bar", "system monitor module sampling for the session");
    }

    Component.onDestruction: SystemStats.release()
}
