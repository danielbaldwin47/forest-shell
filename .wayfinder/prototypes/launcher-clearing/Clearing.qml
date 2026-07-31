// "Launcher as a clearing" (brief §6.5): full-screen fog, a hairline horizon
// for the search field, results below it like a forest floor under open sky.
//
// Every contested choice is a knob so two screenshots can differ by exactly one
// thing. Nothing here is production code — it fakes its providers from fixtures
// and answers a design question, not a functional one.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io

FocusScope {
    id: root

    // --- knobs under test -------------------------------------------------
    property string fieldStyle: "horizon"   // "horizon" | "boxed"
    property string panelStyle: "strata"    // "none" | "strata" | "card"
    property bool showCategory: true        // category label on every row
    property bool rowHaze: true             // unselected rows sit in the fog
    property bool godRay: true              // one soft directional wash (brief §3.6)
    property bool showLegend: true          // provider legend + key hints
    property real horizonFraction: 0.32     // where the rule sits, 0..1 of height

    // --- state ------------------------------------------------------------
    property string query: ""
    property int selected: 0
    property int columnWidth: Math.min(720, root.width - Theme.space10 * 2)

    readonly property string prefix: query.length > 0 && "=;:/?".indexOf(query[0]) >= 0 ? query[0] : ""
    readonly property string body: prefix ? query.slice(1).replace(/^ /, "") : query
    readonly property var provider: providers[prefix]
    readonly property bool chatting: prefix === "?" && claudeTurns.length > 0

    readonly property var providers: ({
        "": { name: "Apps", icon: "layout-grid" },
        "=": { name: "Calculate", icon: "calculator" },
        ";": { name: "Clipboard", icon: "clipboard-list" },
        ":": { name: "Emoji", icon: "smile" },
        "/": { name: "Actions", icon: "command" },
        "?": { name: "Ask Claude", icon: "sparkles" }
    })

    /// Row height and how many of them fit between the horizon and the legend.
    /// A launcher that lets its list run off the bottom of the screen is not a
    /// clearing, it is a leak — so the list is capped and says how many it hid.
    readonly property int rowHeight: 46
    readonly property int maxRows: Math.max(3, Math.floor(
        (root.height * (1 - root.horizonFraction) - Theme.space8 - Theme.space6 * 2) / rowHeight))

    /// Rows currently on screen — recomputed on every keystroke.
    readonly property var allRows: buildRows(prefix, body)
    readonly property var rows: allRows.slice(0, maxRows)
    readonly property int hiddenRows: allRows.length - rows.length

    /// Fake transcript for the Ask Claude mode. Set by the scene script.
    property var claudeTurns: []
    property string claudeStreaming: ""
    property string claudeModel: "haiku"

    // --- fixtures ---------------------------------------------------------
    FileView {
        id: appsFile
        path: Qt.resolvedUrl("fixtures/apps.json").toString().replace("file://", "")
        blockLoading: true
    }
    readonly property var apps: {
        try { return JSON.parse(appsFile.text()).apps; } catch (e) { return []; }
    }

    readonly property var clipboardFixture: [
        { title: "https://github.com/danielbaldwin47/forest-shell/issues/11", sub: "2 minutes ago", icon: "clipboard" },
        { title: "layerrule = blur, forest-shell:launcher", sub: "11 minutes ago", icon: "clipboard" },
        { title: "#6fbec4", sub: "34 minutes ago", icon: "palette" },
        { title: "cubic-bezier(0.22, 1, 0.36, 1)", sub: "1 hour ago", icon: "clipboard" },
        { title: "Screenshot_2026-07-31_14-02.png", sub: "2 hours ago · image", icon: "clipboard" }
    ]
    readonly property var emojiFixture: [
        { glyph: "🌲", title: "evergreen tree", sub: "tree, forest, conifer" },
        { glyph: "🏔️", title: "snow-capped mountain", sub: "mountain, peak, alpine" },
        { glyph: "🌫️", title: "fog", sub: "mist, haze, weather" },
        { glyph: "🔥", title: "fire", sub: "campfire, flame, hot" },
        { glyph: "🪵", title: "wood", sub: "log, timber, cabin" }
    ]
    readonly property var actionsFixture: [
        { title: "Toggle dark mode", sub: "Appearance", icon: "moon" },
        { title: "Change wallpaper…", sub: "Appearance", icon: "monitor" },
        { title: "Open settings", sub: "Shell", icon: "settings-2" },
        { title: "Lock session", sub: "Session", icon: "lock" },
        { title: "Switch shell…", sub: "shell-switch", icon: "package" },
        { title: "Power menu", sub: "Session", icon: "power" }
    ]

    // --- row building -----------------------------------------------------
    function fuzzy(needle, hay) {
        // Subsequence match, scored: earlier and tighter is better. Stands in
        // for whatever the real launcher ends up using — the point here is that
        // the rows look plausible, not that the ranking is final.
        needle = needle.toLowerCase();
        hay = hay.toLowerCase();
        if (!needle) return 0;
        var hi = 0, score = 0, lastHit = -1;
        for (var i = 0; i < needle.length; i++) {
            hi = hay.indexOf(needle[i], hi);
            if (hi < 0) return -1;
            score += (lastHit >= 0 && hi === lastHit + 1) ? 3 : 1;
            if (hi === 0) score += 4;
            lastHit = hi;
            hi++;
        }
        return score - hay.length * 0.02;
    }

    function buildRows(pfx, text) {
        var out = [];
        var i;
        if (pfx === "=") {
            var expr = text || "0";
            var value = "";
            try { value = String(eval(expr.replace(/[^0-9+\-*/(). %]/g, ""))); } catch (e) { value = "—"; }
            if (text.length)
                out.push({ kind: "calc", title: value, sub: expr, icon: "equal", category: "Calculator" });
            return out;
        }
        if (pfx === ";") {
            for (i = 0; i < clipboardFixture.length; i++) {
                var c = clipboardFixture[i];
                if (fuzzy(text, c.title) >= 0)
                    out.push({ kind: "clip", title: c.title, sub: c.sub, icon: c.icon, category: "Clipboard" });
            }
            return out;
        }
        if (pfx === ":") {
            for (i = 0; i < emojiFixture.length; i++) {
                var e = emojiFixture[i];
                if (fuzzy(text, e.title + " " + e.sub) >= 0)
                    out.push({ kind: "emoji", glyph: e.glyph, title: e.title, sub: e.sub, category: "Emoji" });
            }
            return out;
        }
        if (pfx === "/") {
            for (i = 0; i < actionsFixture.length; i++) {
                var a = actionsFixture[i];
                if (fuzzy(text, a.title) >= 0)
                    out.push({ kind: "action", title: a.title, sub: a.sub, icon: a.icon, category: "Action" });
            }
            return out;
        }
        if (pfx === "?") return [];

        // apps
        var scored = [];
        for (i = 0; i < apps.length; i++) {
            var s = text ? fuzzy(text, apps[i].name) : 0;
            if (s >= 0) scored.push({ s: s, a: apps[i], i: i });
        }
        scored.sort(function (x, y) { return y.s - x.s || x.i - y.i; });
        var limit = text ? scored.length : 6;   // no query = a short recents list
        for (i = 0; i < Math.min(limit, scored.length); i++)
            out.push({ kind: "app", title: scored[i].a.name, sub: scored[i].a.subtitle,
                       appIcon: scored[i].a.icon, category: "App" });
        return out;
    }

    onQueryChanged: selected = 0

    // --- god ray: one soft directional wash, upper-left (brief §3.6) -------
    Rectangle {
        visible: root.godRay
        anchors.fill: parent
        opacity: 0.5
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(0.85, 0.93, 0.92, 0.05) }
            GradientStop { position: 0.45; color: Qt.rgba(0.85, 0.93, 0.92, 0.012) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // --- the column -------------------------------------------------------
    Item {
        id: column
        width: root.columnWidth
        x: (root.width - width) / 2
        y: 0
        height: root.height

        readonly property real horizonY: Math.round(root.height * root.horizonFraction)

        // Card variant: one raised surface holding field + results.
        Rectangle {
            visible: root.panelStyle === "card"
            x: -Theme.space5
            y: column.horizonY - fieldArea.height - Theme.space5
            width: parent.width + Theme.space5 * 2
            height: fieldArea.height + Theme.space5 * 2 + resultsArea.height
            radius: Theme.radiusLarge
            color: Qt.rgba(0.078, 0.106, 0.090, 0.90)   // surface @ 90%
            border.width: 1
            border.color: Qt.alpha(Theme.borderSubtle, 0.9)

            // top-lit: 4–6% lightness delta down the surface (brief §3.2)
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.05) }
                    GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.012) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        // --- search field -------------------------------------------------
        Item {
            id: fieldArea
            width: parent.width
            height: 46
            y: column.horizonY - height

            // Boxed variant, for the comparison the brief's claim invites.
            Rectangle {
                visible: root.fieldStyle === "boxed"
                anchors.fill: parent
                anchors.topMargin: -2
                radius: Theme.radiusMedium
                color: Qt.rgba(0.11, 0.149, 0.129, 0.75)
                border.width: 1
                border.color: Theme.borderSubtle
            }

            Row {
                id: fieldRow
                anchors.left: parent.left
                anchors.leftMargin: root.fieldStyle === "boxed" ? Theme.space4 : 0
                anchors.right: parent.right
                anchors.rightMargin: root.fieldStyle === "boxed" ? Theme.space4 : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space3

                Icon {
                    name: "search"
                    size: 18
                    color: Theme.textMuted
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !providerChip.visible
                }

                // Provider chip — the prefix stops being punctuation the moment
                // it resolves, so the user is told which room they're in.
                Rectangle {
                    id: providerChip
                    visible: root.prefix !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    height: 24
                    width: chipRow.width + Theme.space3 * 2
                    radius: Theme.radiusSmall
                    color: Qt.alpha(Theme.accentDeep, 0.22)

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: Theme.space2
                        Icon {
                            name: root.provider ? root.provider.icon : "search"
                            size: 13
                            color: Theme.accentPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: root.provider ? root.provider.name : ""
                            color: Theme.accentPrimary
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(12)
                            font.weight: Theme.weightMedium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                Item {
                    width: fieldRow.width - x - (modelChip.visible ? modelChip.width + Theme.space3 : 0)
                    height: fieldArea.height
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        id: queryText
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.chatting ? "" : root.body
                        color: Theme.textPrimary
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(23)
                        font.weight: Theme.weightRegular
                        font.letterSpacing: -0.2
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        // clears the caret, which sits at x=0 on an empty field
                        x: 12
                        visible: root.body.length === 0 && !root.chatting
                        text: root.prefix === "" ? "Search"
                            : root.prefix === "=" ? "12 * 60 * 24"
                            : root.prefix === ";" ? "Search clipboard"
                            : root.prefix === ":" ? "Search emoji"
                            : root.prefix === "/" ? "Run an action"
                            : "Ask anything"
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(23)
                        font.weight: Theme.weightRegular
                        font.letterSpacing: -0.2
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 12
                        visible: root.chatting
                        text: "Reply…"
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(23)
                    }

                    // Caret: 2px teal, the one interactive colour.
                    Rectangle {
                        x: root.chatting ? 0 : queryText.width + (root.body.length > 0 ? 3 : 0)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: 26
                        radius: 1
                        color: Theme.accentPrimary
                        opacity: 0.9
                    }
                }

                // Ask Claude carries its model inline — `?haiku …` overrides it.
                Rectangle {
                    id: modelChip
                    visible: root.prefix === "?"
                    anchors.verticalCenter: parent.verticalCenter
                    height: 22
                    width: modelText.width + Theme.space3 * 2
                    radius: Theme.radiusSmall
                    color: Qt.alpha(Theme.accentWarm, 0.14)
                    Text {
                        id: modelText
                        anchors.centerIn: parent
                        text: root.claudeModel
                        color: Theme.accentWarm
                        font.family: Theme.fontMono
                        font.pointSize: Theme.pt(11.5)
                    }
                }
            }
        }

        // --- the horizon --------------------------------------------------
        // A rule, not a box: brightest at the middle, dissolving into mist at
        // both ends, the way a ridgeline does.
        Rectangle {
            visible: root.fieldStyle === "horizon"
            y: column.horizonY
            width: parent.width
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.12; color: Qt.alpha(Theme.borderStrong, 0.55) }
                GradientStop { position: 0.5; color: Qt.alpha(Theme.accentPrimary, 0.42) }
                GradientStop { position: 0.88; color: Qt.alpha(Theme.borderStrong, 0.55) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // --- results ------------------------------------------------------
        Item {
            id: resultsArea
            y: column.horizonY + Theme.space4
            width: parent.width
            height: root.chatting ? transcript.height
                  : rowsColumn.y + rowsColumn.height + (overflowLabel.visible ? overflowLabel.height + Theme.space2 : 0)

            // Sky-to-floor: the results plate is lit from the top.
            Rectangle {
                visible: root.panelStyle === "strata" && (root.chatting || root.rows.length > 0)
                anchors.fill: parent
                anchors.margins: -Theme.space2
                radius: Theme.radiusMedium
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0.11, 0.149, 0.129, 0.42) }
                    GradientStop { position: 1.0; color: Qt.rgba(0.043, 0.063, 0.051, 0.22) }
                }
            }

            Text {
                id: sectionLabel
                visible: root.query.length === 0 && root.rows.length > 0
                text: "RECENT"
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(10.5)
                font.weight: Theme.weightMedium
                font.letterSpacing: 0.84    // +0.08em
                y: 2
            }

            Column {
                id: rowsColumn
                width: parent.width
                y: sectionLabel.visible ? sectionLabel.height + Theme.space3 : 0
                visible: !root.chatting

                Repeater {
                    model: root.rows
                    delegate: Item {
                        required property int index
                        required property var modelData
                        readonly property bool isSelected: index === root.selected

                        width: rowsColumn.width
                        height: root.rowHeight

                        // Selection: low-opacity lake fill + a 2px teal rail.
                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: -Theme.space3
                            anchors.rightMargin: -Theme.space3
                            radius: Theme.radiusSmall
                            visible: parent.isSelected
                            color: Qt.alpha(Theme.accentDeep, 0.18)
                        }
                        Rectangle {
                            visible: parent.isSelected
                            x: -Theme.space3
                            width: 2
                            height: parent.height - Theme.space3
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 1
                            color: Theme.accentPrimary
                        }

                        // hairline between strata — no card borders anywhere
                        Rectangle {
                            visible: index > 0 && !parent.isSelected
                            width: parent.width
                            height: 1
                            color: Qt.alpha(Theme.borderSubtle, 0.55)
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.space3

                            Item {
                                width: 22
                                height: 22
                                anchors.verticalCenter: parent.verticalCenter

                                // Real app icons are full-colour, so the brief's
                                // "selected row's icon warms to amber" can't
                                // apply to them. Atmospheric perspective can:
                                // unselected icons sit back in the haze.
                                Image {
                                    id: appIconImage
                                    anchors.fill: parent
                                    visible: false
                                    source: modelData.appIcon ? "image://icon/" + modelData.appIcon : ""
                                    sourceSize: Qt.size(44, 44)
                                    fillMode: Image.PreserveAspectFit
                                }
                                MultiEffect {
                                    anchors.fill: parent
                                    source: appIconImage
                                    visible: modelData.appIcon !== undefined && appIconImage.status === Image.Ready
                                    saturation: (isSelected || !root.rowHaze) ? 0.0 : -0.65
                                    brightness: (isSelected || !root.rowHaze) ? 0.0 : 0.06
                                    opacity: (isSelected || !root.rowHaze) ? 1.0 : 0.72
                                }
                                Icon {
                                    anchors.centerIn: parent
                                    visible: modelData.icon !== undefined
                                    name: modelData.icon || ""
                                    size: 19
                                    // The one amber element on screen.
                                    color: isSelected ? Theme.accentWarm : Theme.textMuted
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: modelData.glyph !== undefined
                                    text: modelData.glyph || ""
                                    font.pointSize: Theme.pt(19)
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 22 - (categoryLabel.visible ? categoryLabel.width : 0) - Theme.space3 * 2
                                spacing: 1

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: modelData.title
                                    color: isSelected ? Theme.textPrimary
                                         : root.rowHaze ? Theme.textSecondary : Theme.textPrimary
                                    font.family: modelData.kind === "calc" ? Theme.fontMono : Theme.fontUi
                                    font.pointSize: Theme.pt(modelData.kind === "calc" ? 20 : 14.5)
                                    font.weight: isSelected ? Theme.weightMedium : Theme.weightRegular
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                    text: modelData.sub || ""
                                    color: Theme.textMuted
                                    opacity: isSelected ? 1.0 : (root.rowHaze ? 0.75 : 1.0)
                                    font.family: Theme.fontUi
                                    font.pointSize: Theme.pt(12)
                                }
                            }

                            Text {
                                id: categoryLabel
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.showCategory || isSelected
                                text: (modelData.category || "").toUpperCase()
                                color: Theme.textMuted
                                opacity: isSelected ? 0.9 : 0.45
                                font.family: Theme.fontUi
                                font.pointSize: Theme.pt(10.5)
                                font.weight: Theme.weightMedium
                                font.letterSpacing: 0.84
                            }
                        }
                    }
                }
            }

            // The list stops at the fold and says so, rather than running off
            // the bottom of the screen behind the legend.
            Text {
                id: overflowLabel
                visible: root.hiddenRows > 0 && !root.chatting
                y: rowsColumn.y + rowsColumn.height + Theme.space2
                text: root.hiddenRows + " more"
                color: Theme.textMuted
                opacity: 0.55
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(11.5)
            }

            // --- nothing found ---------------------------------------------
            Item {
                visible: root.rows.length === 0 && !root.chatting && root.query.length > 0
                width: parent.width
                height: 46
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space3
                    Icon { name: "circle-slash"; size: 17; color: Theme.textMuted; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "No matches"
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(14.5)
                    }
                }
            }

            // --- Ask Claude: the panel becomes a transcript -----------------
            Column {
                id: transcript
                visible: root.chatting
                width: parent.width
                spacing: Theme.space5

                Repeater {
                    model: root.claudeTurns
                    delegate: Column {
                        required property var modelData
                        width: transcript.width
                        spacing: Theme.space2

                        Text {
                            text: modelData.role === "user" ? "YOU" : "CLAUDE"
                            color: modelData.role === "user" ? Theme.textMuted : Theme.accentPrimary
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(10.5)
                            font.weight: Theme.weightMedium
                            font.letterSpacing: 0.84
                        }
                        Text {
                            width: transcript.width
                            wrapMode: Text.WordWrap
                            text: modelData.text
                            color: modelData.role === "user" ? Theme.textSecondary : Theme.textPrimary
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(14.5)
                            lineHeight: 1.55
                            lineHeightMode: Text.ProportionalHeight
                        }
                    }
                }

                Row {
                    visible: root.claudeStreaming.length > 0
                    spacing: Theme.space2
                    Text {
                        text: root.claudeStreaming
                        color: Theme.textPrimary
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(14.5)
                    }
                    Rectangle {
                        width: 7; height: 15; radius: 1
                        color: Theme.accentPrimary
                        opacity: 0.8
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // --- footer: provider legend + key hints ---------------------------
        Item {
            visible: root.showLegend
            width: parent.width
            height: 18
            y: root.height - Theme.space8

            Row {
                spacing: Theme.space4
                anchors.left: parent.left
                Repeater {
                    model: [
                        { k: "=", v: "calc" }, { k: ";", v: "clipboard" }, { k: ":", v: "emoji" },
                        { k: "/", v: "actions" }, { k: "?", v: "ask claude" }
                    ]
                    delegate: Row {
                        required property var modelData
                        spacing: Theme.space2
                        Text {
                            text: modelData.k
                            color: root.prefix === modelData.k ? Theme.accentPrimary : Theme.textMuted
                            font.family: Theme.fontMono
                            font.pointSize: Theme.pt(11.5)
                            opacity: root.prefix === modelData.k ? 1.0 : 0.75
                        }
                        Text {
                            text: modelData.v
                            color: root.prefix === modelData.k ? Theme.textSecondary : Theme.textMuted
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(11.5)
                            opacity: root.prefix === modelData.k ? 1.0 : 0.55
                        }
                    }
                }
            }

            Row {
                spacing: Theme.space4
                anchors.right: parent.right
                Row {
                    spacing: Theme.space2
                    Icon { name: "corner-down-left"; size: 12; color: Theme.textMuted; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "open"; color: Theme.textMuted; opacity: 0.6; font.family: Theme.fontUi; font.pointSize: Theme.pt(11.5); anchors.verticalCenter: parent.verticalCenter }
                }
                Row {
                    spacing: Theme.space2
                    Icon { name: "arrow-up"; size: 12; color: Theme.textMuted; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                    Icon { name: "arrow-down"; size: 12; color: Theme.textMuted; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "move"; color: Theme.textMuted; opacity: 0.6; font.family: Theme.fontUi; font.pointSize: Theme.pt(11.5); anchors.verticalCenter: parent.verticalCenter }
                }
                Text { text: "esc  dismiss"; color: Theme.textMuted; opacity: 0.6; font.family: Theme.fontUi; font.pointSize: Theme.pt(11.5) }
            }
        }
    }
}
