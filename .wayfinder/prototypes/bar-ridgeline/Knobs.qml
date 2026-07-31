// Live tuning surface — a plain floating window, deliberately unstyled so it
// never competes with the thing being judged. Drag a slider, watch the bar.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "."

FloatingWindow {
    id: win
    title: "forest-shell bar prototype — knobs"
    implicitWidth: 420
    implicitHeight: 720
    color: "#1a1a1a"

    component Row_: RowLayout {
        property string label
        property string value
        Layout.fillWidth: true
        Label { text: parent.label; color: "#ddd"; Layout.preferredWidth: 130; font.pixelSize: 12 }
        Label { text: parent.value; color: "#8ab"; Layout.preferredWidth: 44; font.pixelSize: 12 }
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 12
        contentWidth: availableWidth

        ColumnLayout {
            width: win.width - 40
            spacing: 6

            Label { text: "BAR"; color: "#7d8f86"; font.pixelSize: 11; font.letterSpacing: 1 }

            Row_ {
                label: "height"; value: Vars.barHeight
                Slider { Layout.fillWidth: true; from: 22; to: 52; stepSize: 1; value: Vars.barHeight
                         onMoved: Vars.barHeight = value }
            }
            Row_ {
                label: "inner padding"; value: Vars.padH
                Slider { Layout.fillWidth: true; from: 0; to: 32; stepSize: 2; value: Vars.padH
                         onMoved: Vars.padH = value }
            }
            Row_ {
                label: "module gap"; value: Vars.moduleGap
                Slider { Layout.fillWidth: true; from: 4; to: 32; stepSize: 1; value: Vars.moduleGap
                         onMoved: Vars.moduleGap = value }
            }
            Row_ {
                label: "opacity"; value: Vars.barOpacity.toFixed(2)
                Slider { Layout.fillWidth: true; from: 0.5; to: 1.0; value: Vars.barOpacity
                         onMoved: Vars.barOpacity = value }
            }
            RowLayout {
                CheckBox { text: "floating"; checked: Vars.floating; onToggled: Vars.floating = checked
                           contentItem: Label { text: parent.text; color: "#ddd"; leftPadding: 24; font.pixelSize: 12 } }
                CheckBox { text: "hairline"; checked: Vars.bottomHairline; onToggled: Vars.bottomHairline = checked
                           contentItem: Label { text: parent.text; color: "#ddd"; leftPadding: 24; font.pixelSize: 12 } }
            }
            RowLayout {
                CheckBox { text: "top light"; checked: Vars.topLight; onToggled: Vars.topLight = checked
                           contentItem: Label { text: parent.text; color: "#ddd"; leftPadding: 24; font.pixelSize: 12 } }
                CheckBox { text: "grain"; checked: Vars.grain; onToggled: Vars.grain = checked
                           contentItem: Label { text: parent.text; color: "#ddd"; leftPadding: 24; font.pixelSize: 12 } }
            }
            RowLayout {
                CheckBox { text: "fog band (blur wallpaper)"; checked: Vars.barBlur; onToggled: Vars.barBlur = checked
                           contentItem: Label { text: parent.text; color: "#ddd"; leftPadding: 24; font.pixelSize: 12 } }
            }
            Row_ {
                label: "blur"; value: Vars.barBlurAmount.toFixed(2)
                Slider { Layout.fillWidth: true; from: 0.0; to: 1.0; value: Vars.barBlurAmount
                         onMoved: Vars.barBlurAmount = value }
            }
            Row_ {
                label: "fog wash"; value: Vars.fogWash.toFixed(2)
                Slider { Layout.fillWidth: true; from: 0.0; to: 0.4; value: Vars.fogWash
                         onMoved: Vars.fogWash = value }
            }
            Row_ {
                label: "float margin H"; value: Vars.floatMarginH
                Slider { Layout.fillWidth: true; from: 0; to: 40; stepSize: 2; value: Vars.floatMarginH
                         onMoved: Vars.floatMarginH = value }
            }
            Row_ {
                label: "float margin V"; value: Vars.floatMarginV
                Slider { Layout.fillWidth: true; from: 0; to: 24; stepSize: 1; value: Vars.floatMarginV
                         onMoved: Vars.floatMarginV = value }
            }
            Row_ {
                label: "float radius"; value: Vars.floatRadius
                Slider { Layout.fillWidth: true; from: 0; to: 20; stepSize: 1; value: Vars.floatRadius
                         onMoved: Vars.floatRadius = value }
            }

            Label { text: "RIDGELINE"; color: "#7d8f86"; font.pixelSize: 11; font.letterSpacing: 1
                    Layout.topMargin: 10 }

            RowLayout {
                Label { text: "shape"; color: "#ddd"; Layout.preferredWidth: 130; font.pixelSize: 12 }
                ComboBox {
                    Layout.fillWidth: true
                    model: ["strata", "peaks", "pills"]
                    currentIndex: model.indexOf(Vars.ridgeShape)
                    onActivated: Vars.ridgeShape = model[currentIndex]
                }
            }
            Row_ {
                label: "unit width"; value: Vars.ridgeUnitWidth
                Slider { Layout.fillWidth: true; from: 4; to: 28; stepSize: 1; value: Vars.ridgeUnitWidth
                         onMoved: Vars.ridgeUnitWidth = value }
            }
            Row_ {
                label: "gap"; value: Vars.ridgeGap
                Slider { Layout.fillWidth: true; from: 0; to: 16; stepSize: 1; value: Vars.ridgeGap
                         onMoved: Vars.ridgeGap = value }
            }
            Row_ {
                label: "active height"; value: Vars.ridgeActiveH
                Slider { Layout.fillWidth: true; from: 4; to: 28; stepSize: 1; value: Vars.ridgeActiveH
                         onMoved: Vars.ridgeActiveH = value }
            }
            Row_ {
                label: "occupied height"; value: Vars.ridgeOccupiedH
                Slider { Layout.fillWidth: true; from: 2; to: 24; stepSize: 1; value: Vars.ridgeOccupiedH
                         onMoved: Vars.ridgeOccupiedH = value }
            }
            Row_ {
                label: "empty height"; value: Vars.ridgeEmptyH
                Slider { Layout.fillWidth: true; from: 0; to: 12; stepSize: 1; value: Vars.ridgeEmptyH
                         onMoved: Vars.ridgeEmptyH = value }
            }
            Row_ {
                label: "height falloff"; value: Vars.ridgeFalloff
                Slider { Layout.fillWidth: true; from: 0; to: 6; stepSize: 1; value: Vars.ridgeFalloff
                         onMoved: Vars.ridgeFalloff = value }
            }
            Row_ {
                label: "occupied haze"; value: Vars.ridgeOccupiedOpacity.toFixed(2)
                Slider { Layout.fillWidth: true; from: 0.1; to: 1.0; value: Vars.ridgeOccupiedOpacity
                         onMoved: Vars.ridgeOccupiedOpacity = value }
            }
            Row_ {
                label: "empty haze"; value: Vars.ridgeEmptyOpacity.toFixed(2)
                Slider { Layout.fillWidth: true; from: 0.0; to: 0.8; value: Vars.ridgeEmptyOpacity
                         onMoved: Vars.ridgeEmptyOpacity = value }
            }
            Row_ {
                label: "haze falloff"; value: Vars.ridgeOpacityFalloff.toFixed(2)
                Slider { Layout.fillWidth: true; from: 0.0; to: 0.4; value: Vars.ridgeOpacityFalloff
                         onMoved: Vars.ridgeOpacityFalloff = value }
            }
            RowLayout {
                CheckBox { text: "amber active"; checked: Vars.ridgeAmberActive; onToggled: Vars.ridgeAmberActive = checked
                           contentItem: Label { text: parent.text; color: "#ddd"; leftPadding: 24; font.pixelSize: 12 } }
                CheckBox { text: "number"; checked: Vars.ridgeShowNumber; onToggled: Vars.ridgeShowNumber = checked
                           contentItem: Label { text: parent.text; color: "#ddd"; leftPadding: 24; font.pixelSize: 12 } }
                CheckBox { text: "horizon"; checked: Vars.ridgeHorizon; onToggled: Vars.ridgeHorizon = checked
                           contentItem: Label { text: parent.text; color: "#ddd"; leftPadding: 24; font.pixelSize: 12 } }
            }

            Label { text: "CONTEXT"; color: "#7d8f86"; font.pixelSize: 11; font.letterSpacing: 1
                    Layout.topMargin: 10 }

            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: "wallpaper →"
                    onClicked: Vars.wallpaper = win.nextWallpaper()
                }
                CheckBox { text: "backdrop"; checked: Vars.showBackdrop; onToggled: Vars.showBackdrop = checked
                           contentItem: Label { text: parent.text; color: "#ddd"; leftPadding: 24; font.pixelSize: 12 } }
                Button { text: "print config"; onClicked: Vars.dump() }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: "#888"
                font.pixelSize: 11
                text: Vars.wallpaper.split("/").pop()
            }
        }
    }

    property var wallpapers: [
        "/home/daniel/Pictures/wallpaper/forest-landscape.jpg",
        "/home/daniel/Pictures/wallpaper/mountain-lake.jpg",
        "/home/daniel/Pictures/wallpaper/deer_in_pine_forest.jpg",
        "/home/daniel/Pictures/wallpaper/sunset-in-thick-forest.jpg",
        "/home/daniel/Pictures/wallpaper/mountain-snow-minima.jpg",
        "/home/daniel/Pictures/wallpaper/natures-mountain-waters.jpg",
    ]
    property int wpIndex: 0
    function nextWallpaper(): string {
        wpIndex = (wpIndex + 1) % wallpapers.length;
        return wallpapers[wpIndex];
    }
}
