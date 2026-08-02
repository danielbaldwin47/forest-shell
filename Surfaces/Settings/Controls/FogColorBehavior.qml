// The design system's colour transition, as a type (#8, #27, #54).
//
//     FogColorBehavior on color {}
//
// Every colour change in the settings window is the same one — fog moves, it
// doesn't snap, and an in-place change inside a visible surface is the 140ms
// step. Written out per control it was eight identical five-line blocks, which
// is eight places for the curve to drift away from the one the design system
// has.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Behavior {
    ColorAnimation {
        // A crossfade, so `reducedEffects` keeps it — and 140 is already the
        // step the ladder collapses to, so the call is here for the rule
        // rather than for the number (#69).
        duration: Theme.duration(Theme.motionFast)
        easing.type: Easing.Bezier
        easing.bezierCurve: Theme.fogEase
    }
}
