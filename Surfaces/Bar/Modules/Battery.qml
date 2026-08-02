// The battery module (#9, #36): a glyph and a percentage.
//
// The number is shown and not just the glyph, unlike everything in the status
// cluster next door. A battery icon divides the range into four buckets, and
// the difference between 35% and 20% is the difference between finishing what
// you are doing and not — that is a number, and it is the only place on the bar
// where four pixels of glyph would be doing a number's job.
//
// It hides itself on a machine with no battery. `UPower.displayDevice` exists
// on a desktop too and answers 0%, so a module that trusted it would put a flat
// battery on every tower running this shell.
import QtQuick
import qs.Core
import qs.Services.Hardware
// Own directory, explicitly — `BarIndicator` is a sibling, and a file
// Quickshell loads by URL gets no implicit sibling resolution (see
// BarContent.qml).
import qs.Surfaces.Bar.Modules

BarIndicator {
    id: root

    visible: Power.hasBattery
    icon: Power.icon
    label: Power.label

    /// The one place the power policy's words become colours — and only the
    /// glyph's, never the number's: ember measures 3.45:1 over the bar's
    /// worst-case composite, which is legible as a mark and fails the bar's own
    /// 4.5:1 rule as text (#79). The percentage stays text-secondary at every
    /// level, which is BarIndicator's default.
    ///
    /// Warm is the shell's attention role and ember its urgent one (#8), and a
    /// battery is the archetypal user of both — but only while it is draining:
    /// the policy answers "quiet" for every level while the cable is in,
    /// because the one thing a flat battery is asking for is already happening.
    tint: {
        switch (Power.emphasis) {
        case "urgent": return Theme.accentEmber;
        case "attention": return Theme.accentWarm;
        }
        return Theme.textSecondary;
    }
}
