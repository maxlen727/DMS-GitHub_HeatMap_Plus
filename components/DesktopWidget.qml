import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Desktop surface of the GitHub Heatmap composite plugin.
//
// IMPORTANT: this surface deliberately does NOT read `pluginData` (the
// property DesktopPluginComponent exposes), and does not go through this
// component's own `pluginService` property either. When a desktop widget is
// placed on the desktop it normally runs in "instance" mode
// (DesktopPluginWrapper assigns it an instanceId/instanceData so multiple
// placements can each have independent settings). In that mode, `pluginData`
// and this component's savePluginData/loadPluginData calls are transparently
// routed through an instance-scoped service that reads/writes
// instanceData.config first, falling back to the shared plugin settings only
// for keys that were never written into that instance's own config. The same
// applies to the plugin's settings panel (Settings.qml) when it's opened via
// the desktop widget's own settings dialog rather than Settings -> Plugins.
// That makes both of those paths unreliable for data that's meant to be one
// shared configuration - like the GitHub username, or the contribution data
// BarWidget.qml (a separate `widget` surface) fetches and caches.
//
// So instead, we read directly from SettingsData.getPluginSetting(pluginId,
// key, default) - the real shared, non-instance-scoped storage backing
// plugin_settings.json - and refresh on SettingsData.pluginSettingsChanged.
// BarWidget.qml and Settings.qml both write through the matching
// SettingsData.setPluginSetting(), so all three surfaces agree on one copy
// of the data regardless of which UI was used to open them.
//
// This widget does NOT perform its own network fetch; it only displays what
// BarWidget.qml already fetched and cached (a full year, see
// "cachedGridYear" - BarWidget.qml's own popout still only shows the most
// recent 8 weeks, but caches the full year specifically for this view).
// Purely informational - no click-to-refresh or click-to-open-profile
// interaction, by design.
DesktopPluginComponent {
    id: root

    // A single square plus its label header needs at least this much room;
    // below it we fall back to the single-day compact view.
    minWidth: 140
    minHeight: 90

    function readShared(key, defaultValue) {
        return SettingsData.getPluginSetting(root.pluginId, key, defaultValue)
    }

    // --- Settings (shared plugin_settings.json namespace with BarWidget.qml) ---
    // Initial values are placeholders only; refreshAll() (called from
    // Component.onCompleted below) immediately overwrites them via plain
    // assignment. We don't rely on these as live bindings because
    // SettingsData.getPluginSetting() is a plain function call the QML
    // binding engine can't track for automatic re-evaluation - that's why
    // refreshAll() exists and is invoked explicitly on every relevant signal.
    property string githubUsername: ""
    property bool followThemeColor: false
    property bool showDisplayName: false
    property real bgOpacity: 0.7
    property int squareSize: 11
    property int squareSpacing: 3

    // --- Data cached by the bar widget after each successful fetch ---
    property string totalContributions: "0"
    property string githubDisplayName: ""
    // Full year, 52 weeks x 7 days, oldest week first - see BarWidget.qml's
    // cachedGridYear write for how this is populated.
    property var rawGridData: []

    function refreshAll() {
        root.githubUsername = readShared("username", "")
        root.followThemeColor = readShared("followThemeColor", false)
        root.showDisplayName = readShared("showDisplayName", false)
        root.bgOpacity = (readShared("desktopBackgroundOpacity", 70)) / 100
        root.squareSize = readShared("desktopSquareSize", 11)
        root.squareSpacing = readShared("desktopSquareSpacing", 3)
        root.totalContributions = readShared("cachedTotal", "0")
        root.githubDisplayName = readShared("cachedDisplayName", "")

        const raw = readShared("cachedGridYear", "")
        if (!raw) {
            root.rawGridData = []
            return
        }
        try {
            root.rawGridData = JSON.parse(raw)
        } catch (e) {
            root.rawGridData = []
        }
    }

    Component.onCompleted: refreshAll()

    // BarWidget.qml and Settings.qml both write through
    // SettingsData.setPluginSetting() directly (see the comment in
    // Settings.qml for why), which updates SettingsData.pluginSettings and
    // triggers this auto-generated change signal. This is a global signal
    // (it doesn't tell us which pluginId changed), so we just
    // unconditionally re-read our own data on every firing - cheap, and
    // avoids missing an update.
    Connections {
        target: SettingsData
        function onPluginSettingsChanged() {
            root.refreshAll()
        }
    }

    // Colors are recomputed from level on every read (see levelToColor),
    // so a light/dark theme switch or an accent color change needs an
    // explicit recompute here too, same reasoning as the refresh above.
    Connections {
        target: Theme
        function onPrimaryChanged() { root.refreshAll() }
        function onSurfaceTextChanged() { root.refreshAll() }
    }

    readonly property var classicPalette: ["#202329", "#0e4429", "#006d32", "#26a641", "#39d353"]

    function levelToColor(level) {
        const lvl = Math.max(0, Math.min(4, Math.round(level || 0)))
        if (lvl === 0) {
            // No contributions: derive a faint tint from the theme's own text
            // color rather than a background-role variable, since some theme
            // presets give surfaceContainer values that read as inverted
            // (near-black in light mode, pale in dark mode) for this purpose.
            return Theme.withAlpha(Theme.surfaceText, 0.08)
        }
        if (!root.followThemeColor) {
            return root.classicPalette[lvl]
        }
        const steps = [0.25, 0.5, 0.75, 1.0]
        return Theme.withAlpha(Theme.primary, steps[lvl - 1])
    }

    // Full year (up to 52 weeks), recolored under this surface's own
    // followThemeColor setting.
    property var gridData: root.rawGridData.map(week =>
        week.map(day => Object.assign({}, day, {
            color: day.date === "--/--" ? root.levelToColor(0) : root.levelToColor(day.level)
        }))
    )

    Rectangle {
        id: cardBg
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainer, root.bgOpacity)
        border.color: Theme.withAlpha(Theme.outline, 0.3)
        border.width: 1

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            // The header (username + contribution count) needs roughly this
            // much vertical space. Below that, even the header itself won't
            // fit cleanly, so we drop to the "tiny" mode that skips it
            // entirely rather than letting it get clipped or squeezed.
            readonly property real headerMinHeight: Theme.fontSizeLarge + Theme.fontSizeSmall + Theme.spacingS

            // Three-tier degradation, evaluated against the *whole* widget's
            // available height (not just the heatmap sub-area), so the
            // header is only hidden when there truly isn't room for it:
            //   "grid"  - full calendar (year or however many recent weeks fit)
            //   "strip" - header stays, heatmap degrades to a single row of
            //             the most recent 7 days (like the DankBar pill)
            //   "tiny"  - not even the header fits; just a single colored
            //             square for today, no text
            //
            // Note on why this doesn't oscillate: the "tiny" check uses
            // root.widgetHeight (the fixed size DMS reports for the whole
            // placed widget) rather than any size derived from this
            // ColumnLayout's own children. That matters because the header
            // RowLayout below is hidden when displayMode is "tiny", which
            // would otherwise free up space for heatmapArea and could flip
            // the mode back and forth. Since "tiny" never depends on
            // heatmapArea's size, and the header is only ever hidden in
            // "tiny", the "grid"/"strip" branch (which does read
            // heatmapArea's size) only ever evaluates while the header is
            // visible and therefore stable.
            readonly property string displayMode: {
                if (root.widgetHeight < headerMinHeight + root.squareSize + Theme.spacingS) return "tiny"
                if (heatmapArea.oneWeekFitsHeight && heatmapArea.weeksThatFitWidth >= 2) return "grid"
                return "strip"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingXS
                visible: contentColumn.displayMode !== "tiny"

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: (root.showDisplayName && root.githubDisplayName) ? root.githubDisplayName : (root.githubUsername || "GitHub User")
                        font.bold: true
                        font.pixelSize: contentColumn.displayMode === "strip" ? Theme.fontSizeMedium : Theme.fontSizeLarge
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.totalContributions + " contributions"
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: Theme.primary
                        opacity: 0.85
                    }
                }
            }

            // --- Responsive heatmap area ---
            //
            // Squares are always rendered at a fixed size (root.squareSize),
            // never stretched to fill available space - that's what caused
            // squares to render as non-square rectangles whenever the widget
            // was resized to an aspect ratio that didn't match the grid's.
            //
            // Performance note: this Item always creates a FIXED 52*7 = 364
            // Rectangle delegates via Repeater, once, and never changes that
            // model count. Only their visible/x/y/color update as the widget
            // is resized. An earlier version instead changed the Repeater's
            // `model` count live (to however many weeks currently fit), which
            // meant every pixel of drag-resize could destroy and recreate
            // dozens of delegates in a tight loop - this is what caused the
            // runaway memory/CPU usage during resize. A resizeSettle Timer
            // also debounces the fit-calculation itself, so it only
            // recomputes ~10x/second while dragging instead of on every
            // single pixel change.
            Item {
                id: heatmapArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.gridData.length > 0

                readonly property int cell: root.squareSize + root.squareSpacing

                // Live (unthrottled) fit calculation.
                readonly property int liveWeeksThatFitWidth: cell > 0 ? Math.max(0, Math.floor((width + root.squareSpacing) / cell)) : 0
                readonly property bool liveOneWeekFitsHeight: cell > 0 ? (Math.floor((height + root.squareSpacing) / cell) >= 7) : false

                // Debounced copies actually used for rendering. Only these
                // (and things derived from them) drive what's visible, so a
                // resize drag re-lays-out visibility/position at most ~10
                // times a second rather than on every intermediate size.
                property int weeksThatFitWidth: liveWeeksThatFitWidth
                property bool oneWeekFitsHeight: liveOneWeekFitsHeight

                Timer {
                    id: resizeSettle
                    interval: 100
                    onTriggered: {
                        heatmapArea.weeksThatFitWidth = heatmapArea.liveWeeksThatFitWidth
                        heatmapArea.oneWeekFitsHeight = heatmapArea.liveOneWeekFitsHeight
                    }
                }
                onWidthChanged: resizeSettle.restart()
                onHeightChanged: resizeSettle.restart()

                readonly property string mode: contentColumn.displayMode

                readonly property int weeksToShow: Math.max(1, Math.min(root.gridData.length, weeksThatFitWidth))
                readonly property int firstVisibleWeekIdx: root.gridData.length - weeksToShow

                // "tiny" mode: the header is hidden entirely and this is the
                // only thing rendered - a single square for today, sized to
                // whatever tiny space is actually available.
                Rectangle {
                    visible: heatmapArea.mode === "tiny"
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(root.squareSize * 2, parent.width, parent.height)
                    height: width
                    radius: Math.max(1, width * 0.25)
                    antialiasing: true
                    color: {
                        const weeks = root.gridData
                        if (weeks.length === 0) return root.levelToColor(0)
                        const lastWeek = weeks[weeks.length - 1]
                        for (let d = lastWeek.length - 1; d >= 0; d--) {
                            if (lastWeek[d].date !== "--/--") return lastWeek[d].color
                        }
                        return root.levelToColor(0)
                    }
                    border.color: Theme.withAlpha(Theme.outline, 0.35)
                    border.width: 1
                }

                // "strip" mode: header stays visible, heatmap degrades to a
                // single horizontal row of the most recent 7 days - the
                // widget is too short for a full multi-week grid, but tall
                // enough that hiding the header entirely would be wasteful.
                Row {
                    visible: heatmapArea.mode === "strip"
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.squareSpacing

                    Repeater {
                        model: {
                            if (heatmapArea.mode !== "strip" || root.gridData.length === 0) return []
                            const flat = []
                            for (let w = 0; w < root.gridData.length; w++) {
                                for (let d = 0; d < root.gridData[w].length; d++) {
                                    if (root.gridData[w][d].date !== "--/--") flat.push(root.gridData[w][d])
                                }
                            }
                            return flat.slice(-7)
                        }

                        Rectangle {
                            width: Math.min(root.squareSize, heatmapArea.height)
                            height: width
                            radius: Math.max(1, width * 0.25)
                            antialiasing: true
                            color: modelData.color
                            border.color: Theme.withAlpha(Theme.outline, 0.35)
                            border.width: 1
                        }
                    }
                }

                // Grid view: up to 52 weeks x 7 days of fixed-size square
                // cells, laid out with GridLayout and centered via
                // anchors.centerIn on the GridLayout itself. An earlier
                // version manually computed each cell's x/y and a
                // centering offset by hand; that produced a small but
                // visible left/right asymmetry that was hard to pin down.
                // Using GridLayout's own (thoroughly-tested) column sizing
                // and Grid.rows/columns keeps every cell an exact square
                // (each cell's Layout.preferredWidth/Height is fixed to
                // root.squareSize, so the layout can't stretch them) while
                // leaving the actual centering arithmetic to Qt instead of
                // to us.
                Item {
                    id: gridContainer
                    visible: heatmapArea.mode === "grid"
                    anchors.fill: parent

                    GridLayout {
                        id: gridLayout
                        anchors.centerIn: parent
                        columns: Math.max(1, heatmapArea.weeksToShow)
                        rows: 7
                        flow: GridLayout.TopToBottom
                        rowSpacing: root.squareSpacing
                        columnSpacing: root.squareSpacing

                        Repeater {
                            model: gridLayout.visible ? heatmapArea.weeksToShow * 7 : 0

                            Rectangle {
                                readonly property int weekIdx: heatmapArea.firstVisibleWeekIdx + Math.floor(index / 7)
                                readonly property int dayIdx: index % 7
                                readonly property var dayData: {
                                    const week = root.gridData[weekIdx]
                                    return week && dayIdx < week.length ? week[dayIdx] : null
                                }

                                Layout.preferredWidth: root.squareSize
                                Layout.preferredHeight: root.squareSize
                                radius: Math.max(1, root.squareSize * 0.25)
                                antialiasing: true
                                color: dayData ? dayData.color : root.levelToColor(0)
                                border.color: Theme.withAlpha(Theme.outline, 0.3)
                                border.width: 1
                            }
                        }
                    }
                }
            }

            // Empty state: shown until the bar widget has fetched at least
            // once and populated the shared cache this surface reads from.
            StyledText {
                visible: root.gridData.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                text: root.githubUsername
                      ? "Waiting for data - open the GitHub Heatmap bar widget once to fetch it."
                      : "Set your GitHub username in the GitHub Heatmap plugin settings."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }
}
