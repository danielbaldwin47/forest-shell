// The bar itself: the Standard-14 module inventory from the feature inventory
// (#9), laid out left / centre / right, rendered in the design-system tokens.
//
// Data is live where it is cheap (workspaces, active window, clock, battery)
// and mocked where it is not (tray, media, network state) — the question this
// prototype answers is about surface and proportion, not plumbing.
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

Item {
    id: bar

    /// Wallpaper source and the bar's offset within it, so the fog-band
    /// variant can blur exactly the pixels it covers.
    property url backdropSource: ""
    property real backdropWidth: width
    property real backdropHeight: height
    property real backdropOffsetY: 0

    // --- live-ish data ------------------------------------------------------
    property string clockText: ""
    property int batteryPct: 0
    property string activeTitle: {
        if (Vars.mock) return "nvim   ~/repos/forest-shell/Surfaces/Bar/Bar.qml";
        const tl = ToplevelManager.activeToplevel;
        return tl && tl.title ? tl.title : "";
    }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            bar.clockText = Qt.formatDateTime(new Date(), "ddd d MMM   HH:mm");
            batFile.reload();
        }
    }
    FileView {
        id: batFile
        path: "/sys/class/power_supply/BAT0/capacity"
        onLoaded: bar.batteryPct = parseInt(text()) || 0
    }

    // --- fog band: the wallpaper behind the bar, blurred + desaturated -------
    Item {
        id: fogBand
        anchors.fill: parent
        visible: Vars.barBlur
        clip: true

        Item {
            id: fogSource
            anchors.fill: parent
            visible: false
            Image {
                width: bar.backdropWidth
                height: bar.backdropHeight
                y: -bar.backdropOffsetY
                anchors.horizontalCenter: parent.horizontalCenter
                source: bar.backdropSource
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(bar.backdropWidth * 2, bar.backdropHeight * 2)
            }
        }

        MultiEffect {
            anchors.fill: parent
            source: fogSource
            blurEnabled: true
            blur: Vars.barBlurAmount
            blurMax: 48
            saturation: Vars.barSaturation
        }

        // The pale mist wash — depth through haze, not through shadow.
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(190 / 255, 206 / 255, 209 / 255, Vars.fogWash)
        }
    }

    // --- surface ------------------------------------------------------------
    Rectangle {
        id: surface
        anchors.fill: parent
        radius: Vars.floating ? Vars.floatRadius : 0
        opacity: Vars.barOpacity
        color: Theme.surface

        // "barely-perceptible top-edge lightening" — the vertical luminance
        // gradient of every pin, compressed into 32px.
        Rectangle {
            anchors.fill: parent
            radius: surface.radius
            visible: Vars.topLight
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(Theme.surface, 1.0 + Vars.topLightAmount * 4) }
                GradientStop { position: 0.55; color: "transparent" }
            }
        }

        // 2–4% monochrome noise kills banding in the gradient (brief §3.5).
        Image {
            anchors.fill: parent
            visible: Vars.grain
            opacity: Vars.grainAmount
            source: "gen/noise.png"
            fillMode: Image.Tile
        }

        Rectangle {
            visible: Vars.bottomHairline && !Vars.floating
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Theme.borderSubtle
        }
    }

    // --- module clusters ----------------------------------------------------
    RowLayout {
        id: left
        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Vars.padH }
        spacing: Vars.moduleGap

        BarButton { icon: "trees"; tooltip: "Launcher" }
        Ridgeline { Layout.alignment: Qt.AlignVCenter }
        Text {
            Layout.maximumWidth: 260
            text: bar.activeTitle
            elide: Text.ElideRight
            color: Theme.textMuted
            font { family: Theme.fontUi; pixelSize: 12; weight: 400 }
            visible: text !== ""
        }
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: Vars.moduleGap * 1.5

        Text {
            text: bar.clockText
            color: Theme.textSecondary
            font { family: Theme.fontUi; pixelSize: 12; weight: 450 }
        }
        // Media mini — an MPRIS pill, mocked.
        RowLayout {
            spacing: Theme.space2
            Icon { name: "music"; size: 14; color: Theme.textMuted }
            Text {
                text: "Bon Iver — Holocene"
                color: Theme.textMuted
                font { family: Theme.fontUi; pixelSize: 12; weight: 400 }
            }
        }
    }

    RowLayout {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: Vars.padH }
        spacing: Vars.moduleGap

        // System tray — mocked with three plausible clients.
        RowLayout {
            spacing: Theme.space2
            Icon { name: "message-circle"; size: 15; color: Theme.textMuted }
            Icon { name: "cloud"; size: 15; color: Theme.textMuted }
            Icon { name: "monitor"; size: 15; color: Theme.textMuted }
        }

        // Status cluster — network + bluetooth + volume + mic as one quiet group.
        RowLayout {
            spacing: Theme.space2
            Icon { name: "wifi"; size: 15; color: Theme.textSecondary }
            Icon { name: "bluetooth"; size: 15; color: Theme.textMuted }
            Icon { name: "volume-2"; size: 15; color: Theme.textSecondary }
            Icon { name: "mic"; size: 15; color: Theme.textMuted }
        }

        RowLayout {
            spacing: Theme.space1
            Icon { name: "battery-medium"; size: 15; color: Theme.textSecondary }
            Text {
                text: bar.batteryPct + "%"
                color: Theme.textSecondary
                font { family: Theme.fontUi; pixelSize: 12; weight: 400 }
            }
        }

        Text {
            text: "US"
            color: Theme.textMuted
            // Spec says 10.5px caps at +0.08em; font.pixelSize is an int, so the
            // caps label needs pointSize (or 11px) in the real shell — noted.
            font { family: Theme.fontUi; pixelSize: 11; weight: 500; letterSpacing: 0.08 * 11; capitalization: Font.AllUppercase }
        }

        BarButton { icon: "bell"; tooltip: "Notifications" }
        BarButton { icon: "sliders-horizontal"; tooltip: "Control centre" }
    }
}
