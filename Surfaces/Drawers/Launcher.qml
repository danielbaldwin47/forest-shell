// The launcher (#39) — a clearing: fog, sky, and one card at the horizon.
//
// The shape is #11's, decided against 46 captures: a 720px column centred on
// the screen with its field at 32% of the height, results below it, and one
// card (radius 16, `surface` at 90%) holding both. The card is not decoration —
// it is the reason the scrim can stay pale. A 10% mist *lightens* the surface
// light text sits on, so text directly on fog measures 1.96:1 over a bright
// wallpaper; the card insulates its contents completely, and the measurement is
// identical with the compositor's blur on or off (#11 §1, §3).
//
// Three things this file does differently from the prototype it comes from, all
// because the prototype measured them going wrong:
//
//   - **The legend is inside the card.** On bare scrim it was the one piece of
//     UI that failed contrast on every wallpaper, and no veil setting fixes it
//     — every rung *up* the veil made it worse, because a pale wash raises the
//     luminance under light text (#11 §3). It sits on the card at full-opacity
//     `textSecondary` instead, which is what #27's legend-in-card fix asks for.
//   - **Subtitles and category labels are `textSecondary`, not `textMuted`.**
//     Measured on this exact card, `textMuted` comes in at 4.26–4.43:1 — under
//     the shell's 4.5 floor. #11 offered two fixes: take the card to ~94% or
//     move those two roles up. The card opacity is in the spec and the roles
//     are not, so the roles moved.
//   - **The row list is a fixed number of delegates**, indexed into the ranked
//     array, rather than a `Repeater` whose model is reassigned per keystroke.
//     That reassignment is the #75 shape, and "60 Hz while filtering" is
//     exactly the criterion it fails: every keystroke would destroy and rebuild
//     every delegate. Here the delegates are built once at the fold count and
//     only their bindings change.
//
// Unselected rows sit in the haze — icon desaturated, dimmed, title dropped a
// role — and the selected row comes forward at full saturation. That is #11 §4:
// the brief's "the selected icon warms to amber" cannot apply to apps, whose
// icons are full-colour PNGs, so atmospheric perspective carries selection
// instead. Amber survives where it can, on the Lucide glyph of a provider that
// has one.
//
// What is here needs Quickshell — the desktop-entry model, the icon lookup, the
// launch. Which provider a query is in, what matches, in what order, and where
// the list stops are decisions, and they are in
// Services/Launcher/LauncherPolicy.qml where `tests/` can reach them — under
// Services/ rather than beside this file because Apps.qml needs them too, and
// a policy under Surfaces/ would have the service importing the surface.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Core
import qs.Widgets
import qs.Services.Launcher

FocusScope {
    id: root

    /// Raised when the launcher wants the drawer gone — after something is
    /// launched, because a launcher that stays up over the window it just
    /// opened is asking to be dismissed by hand every time.
    signal closeRequested(string reason)

    readonly property LauncherPolicy policy: LauncherPolicy {}
    readonly property var providerSettings: Config.values.launcher.providers

    /// What has been typed, prefix and all. The field owns the text; this is
    /// the alias everything else reads, so the routing is asked once.
    property string query: ""

    readonly property var provider: root.policy.route(root.query, root.providerSettings)
    readonly property string body: root.policy.bodyOf(root.query, root.providerSettings)
    readonly property var emptyAnswer: Providers.silence(root.query, root.providerSettings,
                                                         Apps.indexed)

    /// Every match, and the slice of it that fits. Both, because the label at
    /// the fold is a count of the difference.
    ///
    /// Through the dispatcher rather than through `Apps` by name (#40): which
    /// provider answers is the dispatcher's question, and the delegate below
    /// renders whatever shape comes back because every provider hands over the
    /// same one.
    readonly property var matches: Providers.rows(root.query, root.providerSettings)
    readonly property int maxRows: root.policy.fold(root.height, root.chrome)
    readonly property var rows: root.matches.slice(0, root.maxRows)
    readonly property string hiddenLabel: root.policy.hidden(root.matches.length,
                                                             root.rows.length)

    /// Whether the panel is a conversation rather than a list (#41). Read off
    /// the routing table and not off a provider id — the surface knowing any
    /// provider by name is what the dispatcher exists to prevent.
    readonly property bool conversing: root.policy.converses(root.query,
                                                             root.providerSettings)

    /// Whether there is a transcript to draw. A question appears in it the
    /// instant it is sent, so this turns true on the same frame as Enter and
    /// the empty state does not flash under the first answer.
    readonly property bool transcribing: root.conversing && Claude.turns.count > 0

    /// What the field says when it is empty. A conversation already underway
    /// is answering rather than asking, and the prototype's finding is that
    /// the field should say so (#11 §7, sheet 5).
    readonly property string placeholder: root.transcribing ? "Reply…"
                                                            : root.provider.placeholder

    /// The model the chip names. While a turn is in flight it is the one
    /// actually answering; otherwise it previews what the query as typed would
    /// use, so `?sonnet` changes the chip as the word is completed rather than
    /// after the answer comes back.
    /// How wide prose is allowed to get inside the column. The column stays
    /// 720 — the field, the rule and the legend are all measured off it — but
    /// the prototype measured 720 at 14.5px as ~105 characters a line, which
    /// is past the width prose stays readable at. Named once here because
    /// three places need it and three literals is how they drift apart.
    readonly property real proseWidth: 600

    readonly property string modelInUse:
        Claude.streaming
        ? Claude.model
        : Claude.policy.modelFor(Claude.policy.split(root.body).model,
                                 Config.values.launcher.claude)

    /// Everything between the horizon and the bottom of the screen that is not
    /// a row: the gap under the rule, then below the last row the overflow
    /// label and its gap, the rule above the legend, the legend itself, the
    /// card's own bottom padding, and the margin that keeps the card off the
    /// bottom edge. Stated here because the surface is what knows how tall its
    /// own footer is; `fold()` takes it as an argument for that reason.
    ///
    /// The `Theme.space4` above the rows is the one that was missing first
    /// time, and it is the whole gap between "the list stops at the fold" and
    /// "the list stops 27px past the bottom of a 1366x768 screen at scale 1.5"
    /// — which is #11 §6's original defect, reintroduced by arithmetic. Any
    /// edit here wants a capture at a short size, not a re-read.
    ///
    /// The `RECENT` band is deliberately *not* counted. It appears only when
    /// the query is empty, and an empty query is already capped at
    /// `recentsLimit` — six rows, fewer than the fold on any screen this
    /// renders on. Charging every screen a row for a band that only shows when
    /// the fold is not the binding constraint is how the launcher lost a row
    /// it did not need to.
    readonly property real chrome: Theme.space4
                                   + Theme.space2 + 16 + Theme.space3 + Theme.hairline
                                   + 18 + Theme.space5 + Theme.space6

    /// The row the keyboard is on. Reset by every change to the query, because
    /// a selection held across a filter is pointing at a different app.
    property int selected: 0
    onQueryChanged: {
        root.selected = 0;
        // The calculator cannot answer from the query alone — it has to spawn
        // something. Pushed here, once per change, rather than started from
        // inside the `matches` binding: see `Providers.prime()`.
        Providers.prime(root.query, root.providerSettings);
    }

    focus: true

    // --- what Enter does -----------------------------------------------------

    function activate(): void {
        // A conversational provider has no rows to activate — the query itself
        // is what Enter sends, and the launcher stays open for the answer.
        //
        // The field is cleared back to its prefix rather than emptied: an
        // empty string routes to the apps provider, so clearing it outright
        // would drop the user out of the conversation they are in the middle
        // of on the frame their question was sent.
        if (root.conversing) {
            Providers.submit(root.query, root.providerSettings);
            field.text = root.provider.prefix;
            return;
        }

        const row = root.rows[root.selected];
        if (!row) {
            Logger.log("launcher", root.policy.launchedNothing(root.query));
            return;
        }

        // #39 closed the drawer *first*, so it was on its way out while the
        // process started. That order cannot survive three verbs: `activate()`
        // returns false for a row that turned out to be stale — an app
        // uninstalled between the keystroke and the Enter, a descriptor with no
        // case — and a launcher that vanished without doing anything is worse
        // than one that stayed put and said so.
        //
        // Nothing is lost by the swap, because every verb behind it is
        // non-blocking: `DesktopEntry.execute()` hands off to the compositor, a
        // clipboard write is a property assignment, and `SettingsWindow.show()`
        // activates a `LazyLoader`. The close still happens in the same frame.
        //
        // The reason travels with it — `launched`, `emoji`, `actions` — because
        // a drawer that closed after a copy and one that closed after a launch
        // look identical afterwards (#81).
        if (Providers.activate(row))
            root.closeRequested(row.provider === "apps" ? "launched" : row.provider);
    }

    function move(delta: int): void {
        // In a conversation there is no selection to move, so the arrows do
        // the other obvious thing and scroll what has been said.
        if (root.transcribing) {
            transcriptView.contentY = Math.max(
                0, Math.min(transcriptView.contentHeight - transcriptView.height,
                            transcriptView.contentY + delta * root.policy.rowHeight));
            return;
        }
        if (root.rows.length === 0)
            return;
        root.selected = Math.max(0, Math.min(root.rows.length - 1,
                                             root.selected + delta));
    }

    /// Who is speaking, as the caps micro-label the rest of the shell already
    /// uses for a band heading. An inline component because the transcript
    /// needs it in two places — the finished turns and the one still being
    /// written — and the third copy is where the two stop agreeing about
    /// tracking.
    component TurnLabel: Text {
        required property string speaker

        text: speaker === "you" ? "YOU" : "CLAUDE"
        // The one colour decision in the transcript: the reader's own turns
        // recede and Claude's come forward, which is what makes a wall of
        // prose scannable without a rule between every pair.
        color: speaker === "you" ? Theme.textSecondary : Theme.accentPrimary
        font.family: Theme.fontUi
        font.pointSize: Theme.pt(Theme.capsSize)
        font.weight: Theme.weightMedium
        font.letterSpacing: Theme.tracking(Theme.capsSize, Theme.capsTrackingEm)
    }

    // --- the god ray ---------------------------------------------------------
    //
    // One soft top-lit wash over the whole clearing (brief §3.6). Rung 2 of the
    // ladder: decoration that exists only to look like something, and the one
    // thing in this surface that `reducedEffects` removes outright rather than
    // shortening.

    Rectangle {
        anchors.fill: parent
        visible: Theme.drawDecoration
        opacity: 0.5
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(0.85, 0.93, 0.92, 0.05) }
            GradientStop { position: 0.45; color: Qt.rgba(0.85, 0.93, 0.92, 0.012) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // --- the column ----------------------------------------------------------

    Item {
        id: column

        width: root.policy.column(root.width, Theme.space10)
        x: Math.round((root.width - width) / 2)
        y: 0
        height: root.height

        readonly property real horizonY: Math.round(root.height * root.policy.horizonFraction)

        // The card. Holds the field, the results and the legend — everything
        // with text on it, which is the whole of why it is here.
        Rectangle {
            id: card

            x: -Theme.space5
            y: column.horizonY - fieldArea.height - Theme.space5
            width: column.width + Theme.space5 * 2

            // Measured off the footer's own bottom edge rather than summed
            // from the parts. Adding the pieces up is how the first version
            // was written and it was short by the two gaps between them — the
            // legend then hung 8px below the card it is supposed to be sitting
            // on, which is the whole point of having moved it there (#11 §3).
            // Nothing here is circular: the footer is positioned off the
            // results, and the results off the horizon.
            height: footer.y + footer.height + Theme.space5 - card.y

            // 90% — the measured value, and the reason the two text roles above
            // moved up rather than this number moving.
            color: Qt.alpha(Theme.surface, 0.90)
            radius: Theme.radiusLg
            border.width: Theme.hairline
            border.color: Theme.borderSubtle

            // Top-lit: a 4–6% lightness delta down the surface (brief §3.2).
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                visible: Theme.drawDecoration
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.05) }
                    GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.012) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        // --- the field -------------------------------------------------------

        Item {
            id: fieldArea

            width: column.width
            height: 46
            y: column.horizonY - height

            Row {
                id: fieldRow

                anchors.fill: parent
                spacing: Theme.space3

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !chip.visible
                    name: "search"
                    size: 18
                    color: Theme.textSecondary
                }

                // The prefix stops being punctuation the moment it resolves,
                // and says which room you are in (#11 §7).
                Rectangle {
                    id: chip

                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.provider.prefix !== ""
                    height: 24
                    width: chipRow.width + Theme.space3 * 2
                    radius: Theme.radiusSm
                    color: Qt.alpha(Theme.accentDeep, 0.22)

                    Row {
                        id: chipRow

                        anchors.centerIn: parent
                        spacing: Theme.space2

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: root.provider.icon
                            size: 13
                            color: Theme.accentPrimary
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.provider.name
                            color: Theme.accentPrimary
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(12)
                            font.weight: Theme.weightMedium
                        }
                    }
                }

                Item {
                    width: fieldRow.width - x - (modelChip.visible
                                                 ? modelChip.width + Theme.space3 : 0)
                    height: fieldArea.height

                    // The real thing, not the prototype's painted stand-in: it
                    // has to take a keystroke. The drawer window holds
                    // `WlrKeyboardFocus.Exclusive` while a drawer is open, so
                    // this is where the keyboard lands.
                    TextInput {
                        id: field

                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width

                        focus: true
                        color: Theme.textPrimary
                        selectionColor: Qt.alpha(Theme.accentDeep, 0.5)
                        selectedTextColor: Theme.textPrimary
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(23)
                        font.weight: Theme.weightRegular
                        font.letterSpacing: -0.2

                        // The whole query, prefix included — what is typed is
                        // what is here, and the routing is derived rather than
                        // the text being split into two fields.
                        //
                        // Bound both ways on purpose. Typing writes back the
                        // same string the binding would produce, so it settles
                        // in one pass rather than looping; what the binding
                        // buys is that setting `query` from outside actually
                        // reaches the field. Without it, capture-harness.qml
                        // can pose the routing and the results but the field
                        // still shows its placeholder — a picture of a state
                        // the shell cannot be in.
                        text: root.query
                        onTextChanged: root.query = text

                        // Escape belongs to the drawer window's outer
                        // FocusScope, so every drawer dismisses the same way
                        // (DrawerWindow.qml) — and it still does here. The one
                        // thing taken out of its path is an answer arriving:
                        // a run that is streaming is the only state in this
                        // surface where Escape has something nearer to hand to
                        // mean, and it is the ticket's "hung request must be
                        // cancellable". With nothing streaming the key is left
                        // unaccepted and dismisses as before.
                        Keys.onEscapePressed: event => {
                            event.accepted = Providers.cancel(root.query,
                                                              root.providerSettings);
                        }

                        Keys.onUpPressed: root.move(-1)
                        Keys.onDownPressed: root.move(1)
                        Keys.onReturnPressed: root.activate()
                        Keys.onEnterPressed: root.activate()

                        // A caret of its own: 2px teal, the one interactive
                        // colour, rather than the platform's thin default.
                        cursorDelegate: Rectangle {
                            width: 2
                            radius: 1
                            color: Theme.accentPrimary
                            opacity: 0.9
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: field.x + 12
                        visible: field.text.length === 0
                        text: root.placeholder
                        color: Theme.textSecondary
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(23)
                        font.weight: Theme.weightRegular
                        font.letterSpacing: -0.2
                    }
                }

                // Which model is answering. Mono and warm, at the far end of
                // the field — the prototype's sheet 5, and it earns its place
                // because `?sonnet …` changes it per question: a chip that
                // only ever said the configured default would be decoration.
                Rectangle {
                    id: modelChip

                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.conversing
                    height: 20
                    width: modelText.width + Theme.space3 * 2
                    radius: Theme.radiusSm
                    color: Qt.alpha(Theme.accentWarm, 0.16)

                    Text {
                        id: modelText

                        anchors.centerIn: parent
                        text: root.modelInUse
                        color: Theme.accentWarm
                        font.family: Theme.fontMono
                        font.pointSize: Theme.pt(11.5)
                    }
                }
            }
        }

        // The rule under the field. With the card, this is an internal divider
        // rather than the horizon it was in the prototype — #11's own note that
        // the metaphor weakened once the field moved onto a surface.
        Rectangle {
            width: column.width
            y: column.horizonY
            height: Theme.hairline
            color: Qt.alpha(Theme.borderSubtle, 0.9)
        }

        // --- the results -----------------------------------------------------

        Item {
            id: results

            y: column.horizonY + Theme.space4
            width: column.width

            // The empty state is a row too. Leaving it out of the height is
            // how the first version was written, and the card then closed
            // above it — "Calculate lands with #40" was drawn straight through
            // the legend, which is the one arrangement of this surface that no
            // unit test can see and the capture shows at a glance.
            height: root.transcribing
                    ? transcriptView.height
                    : root.rows.length === 0
                      ? emptyState.height
                      : rowsColumn.y + rowsColumn.height
                        + (overflow.visible ? Theme.space2 + overflow.height : 0)

            Text {
                id: sectionLabel

                visible: root.query.length === 0 && root.rows.length > 0
                         && !root.transcribing
                text: "RECENT"
                color: Theme.textSecondary
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(Theme.capsSize)
                font.weight: Theme.weightMedium
                font.letterSpacing: Theme.tracking(Theme.capsSize, Theme.capsTrackingEm)
                y: 2
            }

            Column {
                id: rowsColumn

                visible: !root.transcribing
                width: results.width
                y: sectionLabel.visible ? sectionLabel.height + Theme.space3 : 0

                // The fold count, not the row array — see the header. The
                // delegates are built once and survive every keystroke; only
                // what they are bound to changes.
                Repeater {
                    model: root.maxRows

                    Item {
                        id: row

                        required property int index

                        readonly property var entry: root.rows[row.index] ?? null
                        readonly property bool active: row.index === root.selected

                        width: rowsColumn.width
                        height: row.entry ? root.policy.rowHeight : 0
                        visible: row.entry !== null

                        // Selection: a low-opacity lake fill and a 2px teal
                        // rail. A fill, so it fades — no gate, and the duration
                        // is the in-place step (Core/EffectsPolicy.qml).
                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: -Theme.space3
                            anchors.rightMargin: -Theme.space3
                            radius: Theme.radiusSm
                            color: row.active ? Qt.alpha(Theme.accentDeep, 0.18)
                                              : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.duration(Theme.motionFast)
                                    easing.type: Easing.Bezier
                                    easing.bezierCurve: Theme.fogEase
                                }
                            }
                        }

                        Rectangle {
                            visible: row.active
                            x: -Theme.space3
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.rail
                            height: parent.height - Theme.space3
                            radius: 1
                            color: Theme.accentPrimary
                        }

                        Row {
                            anchors.fill: parent
                            spacing: Theme.space3

                            // The icon slot, and exactly one of three things is
                            // in it: a real application icon, an emoji, or a
                            // Lucide glyph. Three items rather than a `Loader`
                            // per row, for the reason the delegates themselves
                            // are fixed — a component swapped per keystroke is
                            // the #75 cost, and two hidden `Item`s are cheaper
                            // than one created one.
                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22

                                Image {
                                    id: appIcon

                                    anchors.fill: parent
                                    visible: false
                                    cache: true
                                    source: row.entry ? (row.entry.iconSource ?? "") : ""
                                    sourceSize: Qt.size(44, 44)
                                    fillMode: Image.PreserveAspectFit
                                }

                                // An emoji is drawn as text, at the size the
                                // application icons are, so a `:` list scans
                                // down the same column as an app list rather
                                // than stepping in and out.
                                Text {
                                    anchors.centerIn: parent
                                    visible: text.length > 0
                                    text: row.entry ? (row.entry.glyph ?? "") : ""
                                    font.family: Theme.fontUi
                                    font.pointSize: Theme.pt(16)
                                    // Not dimmed when unselected the way the
                                    // app icons are: the haze is a desaturation
                                    // pass, and desaturating the thing the user
                                    // is choosing *by its colour* is the one
                                    // place #11 §4's atmospheric perspective
                                    // would work against the row.
                                    opacity: 1.0
                                }

                                // Unselected rows sit in the haze (#11 §4).
                                // Under `reducedEffects` the haze goes: rung 2
                                // is decoration, and a desaturation pass is
                                // exactly that — selection still reads from the
                                // fill and the rail.
                                MultiEffect {
                                    anchors.fill: parent
                                    source: appIcon
                                    visible: appIcon.status === Image.Ready
                                    saturation: row.active || !Theme.drawDecoration ? 0.0 : -0.65
                                    brightness: row.active || !Theme.drawDecoration ? 0.0 : 0.06
                                    opacity: row.active || !Theme.drawDecoration ? 1.0 : 0.72
                                }

                                // The Lucide glyph: a provider's own icon on a
                                // calculator or action row, and the affordance
                                // for an app whose icon the theme has nothing
                                // for. Rendering nothing would leave the title
                                // hanging off a gap.
                                //
                                // It does *not* warm to amber when selected,
                                // even though it is a Lucide glyph and #11 §4
                                // lets those warm. The rule that beats it is
                                // the one in the same section: on an app row
                                // the icon stands for an application, "real app
                                // icons are never tinted amber", and a list
                                // where the selected row is sometimes amber and
                                // sometimes not — depending on whether the icon
                                // theme happened to have that app — is the
                                // encoding coming apart. The `/` and `=` rows
                                // are held to the same rule rather than given
                                // their own, because a launcher whose selection
                                // colour depends on which provider you are in
                                // teaches the encoding twice.
                                Icon {
                                    anchors.centerIn: parent
                                    visible: appIcon.status !== Image.Ready
                                             && (row.entry?.glyph ?? "") === ""
                                    name: row.entry && row.entry.icon !== ""
                                          ? row.entry.icon : "box"
                                    size: 19
                                    color: row.active ? Theme.textPrimary : Theme.textSecondary
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 22 - categoryLabel.width - Theme.space3 * 2
                                spacing: 1

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: row.entry ? row.entry.title : ""
                                    color: row.active ? Theme.textPrimary : Theme.textSecondary
                                    font.family: Theme.fontUi
                                    font.pointSize: Theme.pt(14.5)
                                    font.weight: row.active ? Theme.weightMedium
                                                            : Theme.weightRegular
                                }

                                // `textSecondary`, not `textMuted` — see the
                                // header. The subtitle is the only line of a
                                // row that ever measured under the floor.
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                    text: row.entry ? row.entry.subtitle : ""
                                    color: Theme.textSecondary
                                    font.family: Theme.fontUi
                                    font.pointSize: Theme.pt(12)
                                }
                            }

                            // On every row, which is #11 §7's decision — the
                            // quieter selected-only variant was the one it
                            // turned down.
                            //
                            // Off the *row* rather than off the routed
                            // provider (#40). They agree today — one query is
                            // in one provider — and they will not the first
                            // time a query returns rows from two, which is
                            // what the `?` provider's "the app I meant, and
                            // the answer" shape wants (#41). A label derived
                            // from the route would then say the same word on
                            // every row of a mixed list.
                            Text {
                                id: categoryLabel

                                anchors.verticalCenter: parent.verticalCenter
                                text: row.entry ? String(row.entry.category).toUpperCase() : ""
                                color: Theme.textSecondary
                                font.family: Theme.fontUi
                                font.pointSize: Theme.pt(Theme.capsSize)
                                font.weight: Theme.weightMedium
                                font.letterSpacing: Theme.tracking(Theme.capsSize,
                                                                   Theme.capsTrackingEm)
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: row.entry !== null
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selected = row.index
                            onClicked: {
                                root.selected = row.index;
                                root.activate();
                            }
                        }
                    }
                }
            }

            // Where the list stops, and how much it hid — rather than running
            // off the bottom of the screen behind the legend (#11 §6).
            // --- the conversation --------------------------------------------
            //
            // The transcript replaces the list in the same column, keeping the
            // field, the rule and the horizon exactly where they were (#11 §7,
            // sheet 5). What it does *not* keep is the 720px measure: at
            // 14.5px that is about 105 characters a line, which the prototype
            // measured as too wide to read prose in. The column stays; the
            // text inside it is capped.

            Flickable {
                id: transcriptView

                visible: root.transcribing
                width: results.width
                // The same vertical budget the row list would have had, so a
                // conversation stops where a list stops and the card closes in
                // the same place either way.
                height: Math.min(contentHeight, root.maxRows * root.policy.rowHeight)
                contentWidth: width
                contentHeight: turnsColumn.height
                clip: true
                interactive: true
                boundsBehavior: Flickable.StopAtBounds

                // Follow the answer as it is written, but only from the
                // bottom: a user who has scrolled up to re-read something is
                // not asking to be dragged back down every token.
                readonly property bool atBottom:
                    contentY >= contentHeight - height - root.policy.rowHeight
                onContentHeightChanged: {
                    if (atBottom)
                        contentY = Math.max(0, contentHeight - height);
                }

                Column {
                    id: turnsColumn

                    width: transcriptView.width
                    spacing: Theme.space4

                    Repeater {
                        // A model, appended to — not reassigned. Reassignment
                        // rebuilds every delegate in the list, which here is
                        // every bubble in the conversation, and it would
                        // happen on every token (#75). The turn still being
                        // written is the item below this one instead.
                        model: Claude.turns

                        Column {
                            id: turn

                            required property string speaker
                            required property string text
                            required property string note

                            width: turnsColumn.width
                            spacing: Theme.space2

                            TurnLabel {
                                speaker: turn.speaker
                            }

                            Text {
                                width: Math.min(root.proseWidth, turnsColumn.width)
                                text: turn.text
                                color: Theme.textPrimary
                                wrapMode: Text.Wrap
                                font.family: Theme.fontUi
                                font.pointSize: Theme.pt(14.5)
                            }

                            // The denial chip, under the turn it belongs to.
                            // A tool refused three answers ago is not news
                            // about this one, which is the whole reason it
                            // travels with the turn rather than sitting in one
                            // place at the bottom of the panel.
                            Row {
                                visible: turn.note !== ""
                                spacing: Theme.space2

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "shield-alert"
                                    size: 13
                                    color: Theme.accentWarm
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: turn.note
                                    color: Theme.accentWarm
                                    font.family: Theme.fontUi
                                    font.pointSize: Theme.pt(11.5)
                                }
                            }
                        }
                    }

                    // The turn being written. One `Text` bound to a string
                    // that is appended to, so a token is a re-layout of this
                    // item and nothing else.
                    Column {
                        visible: Claude.streaming || Claude.answer !== ""
                                 || Claude.failure !== ""
                        width: turnsColumn.width
                        spacing: Theme.space2

                        TurnLabel {
                            speaker: "claude"
                        }

                        Row {
                            spacing: 2

                            Text {
                                id: liveAnswer

                                width: Math.min(root.proseWidth, turnsColumn.width)
                                    - (caret.visible ? caret.width + 2 : 0)
                                text: Claude.answer
                                color: Theme.textPrimary
                                wrapMode: Text.Wrap
                                font.family: Theme.fontUi
                                font.pointSize: Theme.pt(14.5)
                            }

                            // A block, not a text cursor: the prototype
                            // measured 7×15 as the one that reads as "still
                            // writing" rather than as "the field is here".
                            Rectangle {
                                id: caret

                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 3
                                visible: Claude.streaming
                                width: 7
                                height: 15
                                color: Theme.accentPrimary

                                // Rung 3 of the ladder: reduced, the caret
                                // stops blinking and stays solid. It is still
                                // doing its job — "an answer is being written"
                                // is carried by the block being there at all,
                                // and the blink is the part that moves.
                                SequentialAnimation on opacity {
                                    running: caret.visible && Theme.duration(450) > 0
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.2; duration: Theme.duration(450) }
                                    NumberAnimation { to: 1.0; duration: Theme.duration(450) }
                                }
                            }
                        }

                        // What it is doing while there is nothing to read yet
                        // — "using WebSearch…", "retrying 2/10…". A transient
                        // and not an answer, so it goes under the caret and
                        // disappears the moment text starts.
                        Text {
                            visible: Claude.status !== "" && Claude.answer === ""
                            text: Claude.status
                            color: Theme.textSecondary
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(11.5)
                        }

                        Row {
                            visible: Claude.failure !== ""
                            spacing: Theme.space2

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "circle-slash"
                                size: 14
                                color: Theme.accentEmber
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(root.proseWidth - 40, turnsColumn.width)
                                text: Claude.failure
                                color: Theme.accentEmber
                                wrapMode: Text.Wrap
                                font.family: Theme.fontUi
                                font.pointSize: Theme.pt(12.5)
                            }
                        }
                    }
                }
            }

            Text {
                id: overflow

                visible: root.hiddenLabel !== "" && !root.transcribing
                y: rowsColumn.y + rowsColumn.height + Theme.space2
                text: root.hiddenLabel
                color: Theme.textSecondary
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(11.5)
            }

            // --- nothing to show ---------------------------------------------

            Item {
                id: emptyState

                visible: root.rows.length === 0 && !root.transcribing
                width: results.width
                height: root.policy.rowHeight

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space3

                    // One answer, not two cascades: the icon and the line come
                    // out of the same policy call, so they cannot drift into
                    // saying different things about the same silence.
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.emptyAnswer.icon
                        size: 17
                        color: Theme.textSecondary
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.emptyAnswer.text
                        color: Theme.textSecondary
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(14.5)
                    }
                }
            }
        }

        // --- the legend ------------------------------------------------------
        //
        // Inside the card, at full-opacity `textSecondary`. On bare scrim this
        // measured 1.96:1 and no veil setting improved it (#11 §3); it is the
        // one piece of the prototype's layout this file moves.

        Item {
            id: footer

            y: results.y + results.height + Theme.space3
            width: column.width
            height: rule.height + Theme.space3 + legendRow.height

            Rectangle {
                id: rule

                width: parent.width
                height: Theme.hairline
                color: Qt.alpha(Theme.borderSubtle, 0.9)
            }

            // The band the legend text sits in, as its own item so that
            // capture-harness.qml can name it: #39's contrast criterion is
            // about *this* strip, and a region that included the hairline
            // above it would be measuring a 1px rule into the background it is
            // sampling.
            Item {
                id: legendBand

                y: rule.height + Theme.space3
                width: parent.width
                height: 18

            Row {
                id: legendRow

                spacing: Theme.space4
                height: parent.height

                Repeater {
                    // The providers the user has left on. Rebuilt only when a
                    // setting changes, which is not a per-keystroke path.
                    model: root.policy.legend(root.providerSettings)

                    Row {
                        id: legendEntry

                        required property var modelData

                        readonly property bool current:
                            root.provider.prefix === legendEntry.modelData.prefix

                        spacing: Theme.space2
                        height: legendRow.height

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: legendEntry.modelData.prefix
                            color: legendEntry.current ? Theme.accentPrimary
                                                       : Theme.textSecondary
                            font.family: Theme.fontMono
                            font.pointSize: Theme.pt(11.5)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: legendEntry.modelData.name.toLowerCase()
                            color: legendEntry.current ? Theme.textPrimary
                                                       : Theme.textSecondary
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(11.5)
                        }
                    }
                }
            }

            Row {
                anchors.right: parent.right
                spacing: Theme.space4
                height: parent.height

                Row {
                    spacing: Theme.space2

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "corner-down-left"
                        size: 12
                        color: Theme.textSecondary
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "open"
                        color: Theme.textSecondary
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(11.5)
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "esc  dismiss"
                    color: Theme.textSecondary
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(11.5)
                }
            }
            }
        }
    }

    // --- what the capture measures -------------------------------------------
    //
    // #39's contrast criterion is about two fills: the card every row's text
    // sits on, and the legend strip at the bottom of it. Named here so that
    // capture-harness.qml reports the geometry it actually rendered rather than
    // the script recomputing it from tokens and drifting.

    readonly property alias cardItem: card
    readonly property alias legendItem: legendBand

    // The field is the launcher: it is created already shown, so it takes focus
    // on arrival rather than waiting for a click that a full-screen drawer
    // never gets.
    Component.onCompleted: field.forceActiveFocus()
}
