// The weather, current and for the next few days (#50).
//
// A reading and a strip: what it is doing now, big, with the sky's own glyph
// beside it, and one column per day under it. Everything it draws comes from
// Services/Weather/Weather.qml, and every word and glyph in it is chosen by
// Services/Weather/WeatherPolicy.qml — this file has no opinion about what code
// 61 means.
//
// ## The card takes a subscription
//
// `Weather.watch()` on arrival and `Weather.release()` on the way out. That
// pair is what makes the acceptance criterion "no network cost at shell
// startup" true beyond the deferred stage: the service fetches when a card
// appears over a stale reading, refreshes on a timer only while one is on
// screen, and does nothing at all the rest of the day. The drawer destroys its
// slot on close (Surfaces/Drawers/DrawerSlot.qml), so the release is the panel
// going away.
//
// ## Four states, not two
//
// A card that has never been configured, one whose lookup failed, one still
// waiting and one with a reading are four different things to say, and saying
// three of them as an empty card would be the #81 shape in a surface: a blank
// rectangle with two candidate causes. The unconfigured case in particular is
// the *common* one on a fresh install, and it is the only one the user can fix
// — so it names the key.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets
// Its own directory, explicitly: this file is loaded by URL, and a file
// Quickshell serves through its interceptor gets no implicit sibling
// resolution — without this line `CardFrame` is "not a type" (#73).
import qs.Surfaces.Drawers.Cards
import qs.Services.Weather

CardFrame {
    id: card

    /// The dashboard's pose, or null for the live shell. `facts.weather`
    /// replaces the whole of `state` below, which is what lets seam 3 capture a
    /// forecast on a machine with no network (Surfaces/Drawers/Dashboard.qml
    /// holds the shape).
    property var facts: null

    readonly property bool posed: card.facts !== null && card.facts.weather !== undefined

    readonly property WeatherPolicy policy: WeatherPolicy {}

    /// Everything the card draws, in one object, so the posed and the live case
    /// differ in one place rather than in a dozen bindings.
    ///
    /// `units` is in here with the rest, and it has to be: read from `Config`
    /// beside a posed reading it would put "12 mph" under a metric pose on an
    /// imperial machine, which is a capture that changes with the settings of
    /// whoever took it.
    readonly property var state: card.posed ? card.facts.weather : ({
        status: Weather.status,
        label: Weather.label,
        message: Weather.message,
        current: Weather.current,
        days: Weather.days,
        units: Weather.units
    })

    readonly property bool hasReading: card.state.current !== null
                                    && card.state.current !== undefined

    title: "Weather"

    // --- the reading ----------------------------------------------------------

    RowLayout {
        Layout.fillWidth: true
        visible: card.hasReading
        spacing: Theme.space3

        Icon {
            Layout.alignment: Qt.AlignVCenter
            name: card.hasReading
                  ? card.policy.conditionIcon(card.state.current.code,
                                              card.state.current.day)
                  : "cloud-off"
            size: 40
            color: Theme.textSecondary
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                Text {
                    text: card.hasReading
                          ? card.policy.temperature(card.state.current.temperature) : ""
                    color: Theme.textPrimary
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(24)
                    font.weight: Theme.weightMedium
                }

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBaseline
                    text: card.hasReading
                          ? card.policy.conditionLabel(card.state.current.code) : ""
                    color: Theme.textSecondary
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(11.5)
                }
            }

            Text {
                Layout.fillWidth: true
                text: card.state.label ?? ""
                color: Theme.textMuted
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(10.5)
            }

            // Feels-like, humidity and wind on one line — which parts are on it
            // is Services/Weather/WeatherPolicy.qml's, like every other word on
            // this card.
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.policy.detailLine(card.state.current, card.state.units)
                color: Theme.textMuted
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(10)
            }
        }
    }

    // --- the strip ------------------------------------------------------------
    //
    // One column per day, sharing the width evenly. `Layout.fillWidth` on each
    // and not a fixed column width: the panel is 380px and the strip is
    // configurable between one and seven days (`weatherTime.weather.days`),
    // which is the #80 overflow shape if a column ever sets its own size.
    //
    // Nothing inside a column uses `Layout.alignment`, and that is the whole
    // reason the strip is as wide as the card. A layout item with an alignment
    // set is one the layout may not stretch, so its maximum width becomes its
    // implicit width — and a column of four aligned labels caps the *column*,
    // which caps the row above it. Measured: the strip sat at 109px inside a
    // 356px card, four day-columns packed against its left edge. Centring is
    // done by the text instead (`horizontalAlignment`), and the glyph by an
    // item that fills and centres its own child.

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space1
        visible: card.hasReading && card.state.days !== undefined
                 && card.state.days.length > 0
        spacing: Theme.space2

        Repeater {
            model: card.state.days ?? []

            ColumnLayout {
                id: day

                required property var modelData

                Layout.fillWidth: true
                spacing: Theme.space1

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: card.policy.dayLabel(day.modelData.date,
                                               card.policy.isoDate(card.now))
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(10)
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 18

                    Icon {
                        anchors.centerIn: parent
                        // Daily rows are a whole day, so the night glyphs never
                        // apply to them.
                        name: card.policy.conditionIcon(day.modelData.code, true)
                        size: 18
                        color: Theme.textSecondary
                    }
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: card.policy.temperature(day.modelData.high)
                    color: Theme.textPrimary
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(10.5)
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: card.policy.temperature(day.modelData.low)
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(10)
                }
            }
        }
    }

    /// Which day is "Today" in the strip. Posed with the dashboard's own clock
    /// so a capture names the same day the calendar card above it draws.
    readonly property date now: card.facts && card.facts.now ? card.facts.now : Time.now

    // --- the other three states -----------------------------------------------

    RowLayout {
        Layout.fillWidth: true
        visible: !card.hasReading
        spacing: Theme.space3

        Icon {
            Layout.alignment: Qt.AlignVCenter
            name: card.policy.emptyIcon(card.state.status)
            size: 24
            color: Theme.textMuted
        }

        Text {
            Layout.fillWidth: true
            text: card.policy.emptyMessage(card.state.status, card.state.message)
            color: Theme.textMuted
            wrapMode: Text.WordWrap
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(10.5)
        }
    }

    // --- the subscription -----------------------------------------------------
    //
    // Posed, the card does not touch the service at all: a capture must not put
    // a request on the wire, which is the same hazard the media card's `seek`
    // guards against.

    Component.onCompleted: {
        if (!card.posed)
            Weather.watch();
        Logger.log("dashboard", "weather " + (card.hasReading
                   ? card.policy.summary(card.state.label,
                                         { current: card.state.current,
                                           days: card.state.days ?? [] })
                   : card.state.status));
    }

    Component.onDestruction: if (!card.posed) Weather.release();
}
