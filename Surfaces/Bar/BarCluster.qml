// One of the bar's three clusters (#35): the modules named for it, in the
// order they were named, along whichever axis the bar runs.
//
// Both positioners exist and one of them is empty. It reads odd next to a
// Loader that swaps between a Row and a Column, and it is the version that
// cannot destroy and rebuild every module in the cluster when the axis
// changes — which is what a Loader swap would do, and what would make a
// vertical bar a rewrite rather than a setting (#35).
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: cluster

    required property var moduleIds
    required property var barScreen
    required property bool vertical

    // Required rather than defaulted to 14: the shipped value is the schema's
    // (`bar.moduleGap`), and restating it here would give it two homes.
    required property int spacing

    implicitWidth: cluster.vertical ? column.implicitWidth : row.implicitWidth
    implicitHeight: cluster.vertical ? column.implicitHeight : row.implicitHeight

    Row {
        id: row

        anchors.centerIn: parent
        height: cluster.height
        visible: !cluster.vertical
        spacing: cluster.spacing

        Repeater {
            model: cluster.vertical ? [] : cluster.moduleIds

            delegate: BarSlot {
                required property string modelData

                moduleId: modelData
                barScreen: cluster.barScreen
                vertical: false
                // The module gets the full cross-axis run and centres its own
                // content in it, so a 14px ridge and a 17px clock still sit on
                // one line.
                height: row.height
            }
        }
    }

    Column {
        id: column

        anchors.centerIn: parent
        width: cluster.width
        visible: cluster.vertical
        spacing: cluster.spacing

        Repeater {
            model: cluster.vertical ? cluster.moduleIds : []

            delegate: BarSlot {
                required property string modelData

                moduleId: modelData
                barScreen: cluster.barScreen
                vertical: true
                width: column.width
            }
        }
    }
}
