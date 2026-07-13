import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import QtQuick.Layouts
import QtQuick.Controls

PluginComponent {
    id: root

    popoutWidth: 320
    popoutHeight: 460

    property bool showNotifications: (pluginData && pluginData.showNotifications !== undefined) ? pluginData.showNotifications : true
    
    // Icons
    readonly property string iconBar: "commit"
    readonly property string iconRefresh: "refresh"
    readonly property string iconError: "error"
    readonly property string iconOpen: "open_in_browser"
    readonly property string iconSuccess: "check_circle"

    // Settings from pluginData
    property string githubUsername: (pluginData && pluginData.username) ? pluginData.username : ""
    property int refreshInterval: (pluginData && pluginData.refreshInterval) ? pluginData.refreshInterval : 300
    property bool followThemeColor: (pluginData && pluginData.followThemeColor !== undefined) ? pluginData.followThemeColor : false
    property string faGithubGlyph: "\uf09b"
    property string faFamily: "Font Awesome 6 Brands, Font Awesome 5 Brands, Font Awesome 6 Free, Font Awesome 5 Free"

    // Top-bar pill appearance settings
    property int pillSquareSize: (pluginData && pluginData.pillSquareSize) ? pluginData.pillSquareSize : 10
    property int pillSpacing: (pluginData && pluginData.pillSpacing !== undefined) ? pluginData.pillSpacing : 3
    property bool pillShowSingleDay: (pluginData && pluginData.pillShowSingleDay !== undefined) ? pluginData.pillShowSingleDay : false
    property bool showDisplayName: (pluginData && pluginData.showDisplayName !== undefined) ? pluginData.showDisplayName : false

    // Classic GitHub-style palette (used when followThemeColor is false).
    // Level 0 (no contributions) intentionally does NOT use a fixed color here -
    // see levelToColor(), which maps it to Theme.surfaceContainer so it adapts
    // to the active DMS light/dark mode instead of always rendering near-black.
    readonly property var classicPalette: ["#202329", "#0e4429", "#006d32", "#26a641", "#39d353"]

    // Map a contribution level (0-4) to a color, either the classic palette
    // or a set of shades derived from the current DMS theme's primary color.
    function levelToColor(level) {
        const lvl = Math.max(0, Math.min(4, Math.round(level || 0)))
        if (lvl === 0) {
            // No contributions: derive a faint tint from the theme's own text color
            // instead of relying on Theme.surfaceContainer directly. Some DMS theme
            // presets give surfaceContainer a much darker/lighter value than expected
            // for a "recessed empty slot", which caused level-0 squares to look
            // inverted (near-black in light mode, pale in dark mode). Blending a low
            // alpha of surfaceText over the background reliably reads as "faint" in
            // both modes since surfaceText itself is already contrast-correct.
            return Theme.withAlpha(Theme.surfaceText, 0.08)
        }
        if (!root.followThemeColor) {
            return root.classicPalette[lvl]
        }
        // Blend the theme's primary color from a faint tint (level 1) up to
        // full strength (level 4), so the heatmap reads as an intensity scale
        // in whatever hue the active DMS theme uses.
        const steps = [0.25, 0.5, 0.75, 1.0]
        return Theme.withAlpha(Theme.primary, steps[lvl - 1])
    }

    // Re-derive all cached colors when the theme toggle or the primary color itself changes,
    // so the heatmap updates immediately without requiring a fresh network fetch.
    function recolorGrid() {
        if (!root.gridData || root.gridData.length === 0) return
        const newGrid = []
        for (let w = 0; w < root.gridData.length; w++) {
            const week = []
            for (let d = 0; d < root.gridData[w].length; d++) {
                const day = root.gridData[w][d]
                week.push(Object.assign({}, day, { color: root.levelToColor(day.level) }))
            }
            newGrid.push(week)
        }
        root.gridData = newGrid

        if (root.contributions && root.contributions.length > 0) {
            root.contributions = root.contributions.map(day => Object.assign({}, day, { color: root.levelToColor(day.level) }))
        }
        // selectedDay/todayDay/yesterdayDay reference objects inside the old gridData;
        // point them at their freshly-recolored counterparts by matching on date.
        if (root.selectedDay) {
            root.selectedDay = root.findDayByDate(root.selectedDay.date) || root.selectedDay
        }
        if (root.todayDay) {
            root.todayDay = root.findDayByDate(root.todayDay.date) || root.todayDay
        }
        if (root.yesterdayDay) {
            root.yesterdayDay = root.findDayByDate(root.yesterdayDay.date) || root.yesterdayDay
        }
    }

    function findDayByDate(dateStr) {
        for (let w = 0; w < root.gridData.length; w++) {
            for (let d = 0; d < root.gridData[w].length; d++) {
                if (root.gridData[w][d].date === dateStr) return root.gridData[w][d]
            }
        }
        return null
    }

    onFollowThemeColorChanged: recolorGrid()

    // Re-derive heatmap colors whenever anything about the active DMS theme changes -
    // not just the accent color, but also a light/dark mode switch. levelToColor()
    // bakes Theme.primary and Theme.surfaceText into plain color values stored inside
    // gridData/contributions (not live QML bindings), so those stored colors go stale
    // when the theme changes and must be explicitly recomputed here.
    Connections {
        target: Theme
        function onPrimaryChanged() {
            root.recolorGrid()
        }
        function onSurfaceTextChanged() {
            root.recolorGrid()
        }
        function onSurfaceContainerChanged() {
            root.recolorGrid()
        }
    }

    // State - Always 7 items for fixed width
    property var contributions: []
    property var gridData: []  // 4 weeks of data for calendar grid
    property string totalContributions: "0"
    property string githubDisplayName: ""
    property bool isError: false
    property bool isLoading: false
    property string errorMessage: ""
    property var lastRefreshTime: null
    property bool isManualRefresh: false
    property var selectedDay: null
    property var todayDay: null
    property var yesterdayDay: null

    // Initialize with cached data if available
    Component.onCompleted: {
        const cachedTotal = SettingsData.getPluginSetting(root.pluginId, "cachedTotal", "")
        const cachedGridStr = SettingsData.getPluginSetting(root.pluginId, "cachedGrid", "")
        root.githubDisplayName = SettingsData.getPluginSetting(root.pluginId, "cachedDisplayName", "")
        
        if (cachedTotal && cachedGridStr) {
            try {
                const cachedGrid = JSON.parse(cachedGridStr)
                root.totalContributions = cachedTotal
                root.gridData = cachedGrid
                
                // Restore todayDay, yesterdayDay and selectedDay
                let validDays = []
                for (let w = 0; w < root.gridData.length; w++) {
                    for (let d = 0; d < root.gridData[w].length; d++) {
                        if (root.gridData[w][d].date !== "--/--") {
                            validDays.push(root.gridData[w][d])
                        }
                    }
                }
                if (validDays.length > 0) {
                    root.todayDay = validDays[validDays.length - 1]
                    if (validDays.length > 1) {
                        root.yesterdayDay = validDays[validDays.length - 2]
                    }
                } else if (root.gridData.length > 0) {
                    const lastWeek = root.gridData[root.gridData.length - 1]
                    root.todayDay = lastWeek[lastWeek.length - 1]
                    if (lastWeek.length > 1) {
                        root.yesterdayDay = lastWeek[lastWeek.length - 2]
                    } else if (root.gridData.length > 1) {
                        const prevWeek = root.gridData[root.gridData.length - 2]
                        root.yesterdayDay = prevWeek[prevWeek.length - 1]
                    }
                }
                root.selectedDay = root.todayDay
                root.isError = false

                // Backfill missing `level` field for caches written by older plugin versions,
                // and re-apply the current color scheme so it matches the followThemeColor setting.
                root.gridData = root.gridData.map(week =>
                    week.map(day => Object.assign({}, day, {
                        level: day.level !== undefined ? day.level : 0,
                        color: day.date === "--/--" ? root.levelToColor(0) : root.levelToColor(day.level)
                    }))
                )
                root.selectedDay = root.findDayByDate(root.selectedDay ? root.selectedDay.date : "") || root.selectedDay
                root.todayDay = root.findDayByDate(root.todayDay ? root.todayDay.date : "") || root.todayDay
                if (root.yesterdayDay) {
                    root.yesterdayDay = root.findDayByDate(root.yesterdayDay.date) || root.yesterdayDay
                }
            } catch (e) {
                console.error("GitHub: Failed to parse persistent cache")
                initializePlaceholders()
            }
        } else {
            initializePlaceholders()
        }

        // Start timer after a delay to ensure network is ready
        startupDelay.start()
    }

    Timer {
        id: startupDelay
        interval: 5000 // 5 second delay for network stability
        repeat: false
        onTriggered: {
            if (githubUsername) {
                refreshTimer.start()
            }
        }
    }

    // Watch for credential changes
    onGithubUsernameChanged: checkAndStartTimer()
    onRefreshIntervalChanged: {
        if (refreshTimer.running) {
            refreshTimer.restart()
        }
    }

    function checkAndStartTimer() {
        if (githubUsername) {
            if (!refreshTimer.running) {
                refreshTimer.start()
                root.refreshHeatmap() // Immediate fetch on username change
            }
        } else {
            refreshTimer.stop()
            initializePlaceholders()
        }
    }

    // Initialize 7 placeholder squares
    function initializePlaceholders() {
        const placeholders = []
        const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        for (let i = 0; i < 7; i++) {
            placeholders.push({
                weekday: days[i],
                date: "--/--",
                count: 0,
                level: 0,
                color: Theme.surfaceContainer
            })
        }

        contributions = placeholders
        totalContributions = "0"
        isError = false

        // Initialize grid placeholders (8 weeks × 7 days)
        const gridPlaceholders = []
        for (let week = 0; week < 8; week++) {
            const weekData = []
            for (let day = 0; day < 7; day++) {
                weekData.push({
                    weekday: day,
                    weekdayName: days[day],
                    date: "--/--",
                    count: 0,
                    level: 0,
                    color: Theme.surfaceContainer
                })
            }
            gridPlaceholders.push(weekData)
        }
        gridData = gridPlaceholders

        // Initialize todayDay, yesterdayDay and selectedDay with the newest placeholder
        let pValidDays = []
        for (let w = 0; w < gridPlaceholders.length; w++) {
            for (let d = 0; d < gridPlaceholders[w].length; d++) {
                if (gridPlaceholders[w][d].date !== "--/--") {
                    pValidDays.push(gridPlaceholders[w][d])
                }
            }
        }
        if (pValidDays.length > 0) {
            root.todayDay = pValidDays[pValidDays.length - 1]
            if (pValidDays.length > 1) {
                root.yesterdayDay = pValidDays[pValidDays.length - 2]
            }
        } else if (gridPlaceholders.length > 0) {
            const lastWeek = gridPlaceholders[gridPlaceholders.length - 1]
            root.todayDay = lastWeek[lastWeek.length - 1]
            if (lastWeek.length > 1) {
                root.yesterdayDay = lastWeek[lastWeek.length - 2]
            } else if (gridPlaceholders.length > 1) {
                const prevWeek = gridPlaceholders[gridPlaceholders.length - 2]
                root.yesterdayDay = prevWeek[prevWeek.length - 1]
            }
        }
        root.selectedDay = root.todayDay
    }

    // Shell escape function for security
    function escapeShellString(str) {
        if (!str) return ""
        return str.replace(/\\/g, "\\\\")
                  .replace(/"/g, "\\\"")
                  .replace(/\$/g, "\\$")
                  .replace(/`/g, "\\`")
    }

    function showTooltip(text, mouseArea) {
        // DankTooltipV2 handles all coordinate mapping internally by passing the item
        tooltip.show(text, mouseArea);
    }

    // Auto-refresh timer
    Timer {
        id: refreshTimer
        interval: root.refreshInterval * 1000
        repeat: true
        running: false
        triggeredOnStart: true
        onTriggered: {
            if (root.githubUsername) {
                root.isManualRefresh = false  // Automatic refresh
                root.refreshHeatmap()
            } else {
                root.isError = true
                root.errorMessage = "Configure GitHub username in settings"
            }
        }
    }

    // Refresh function
    function refreshHeatmap() {
        if (!githubUsername) {
            isError = true
            errorMessage = "Configure GitHub username in settings"
            return
        }

        // Cooldown: prevent refreshes within 30 seconds of last successful refresh
        const now = Date.now()
        if (lastRefreshTime && (now - lastRefreshTime) < 30000 && !root.isRetrying) {
            console.log("GitHub: Skipping refresh (cooldown active)")
            if (root.isManualRefresh && root.showNotifications) {
                notifyCooldown.running = true
            }
            root.isManualRefresh = false
            return
        }

        console.log("GitHub: Starting fetch...")
        isLoading = true
        root.isRetrying = false
        githubProcess.running = false
        githubProcess.running = true
    }

    // Handle failure and setup retry
    property bool isRetrying: false
    function handleFetchFailure(msg) {
        root.isError = true
        root.errorMessage = msg
        root.isLoading = false
        root.isRetrying = true
        retryTimer.start()
    }

    Timer {
        id: retryTimer
        interval: 2000
        repeat: false
        onTriggered: root.refreshHeatmap()
    }

    // Build the embedded Bash script
    function buildScript() {
        const escapedUsername = escapeShellString(githubUsername)

        // NOTE: We must escape ${} as \${} to prevent JS interpolation
        return `
# GitHub Heatmap Fetcher (Bash + Public API)
GITHUB_USERNAME="${escapedUsername}"

# GitHub contribution color scheme (dark theme) - fallback / classic palette
COLOR_0="#202329"
COLOR_1="#0e4429"
COLOR_2="#006d32"
COLOR_3="#26a641"
COLOR_4="#39d353"

# 1. Calculate date range
today=$(date +%Y-%m-%d)
today_dow=$(date -d "$today" +%u)

if [ "$today_dow" = "7" ]; then
    current_sunday="$today"
else
    current_sunday=$(date -d "$today -$today_dow days" +%Y-%m-%d)
fi

# 52 weeks back, so grid_json covers a full year (like GitHub's own year
# view) instead of just the last 8 weeks. The bar widget's popout still only
# displays the most recent 8 weeks of this (see JS-side slicing below), but
# the desktop widget's year view needs the full range, and re-fetching for
# it separately would be wasteful since jogruber.de already returns a whole
# year of data per request (?y=last) - we were just discarding most of it.
start_date=$(date -d "$current_sunday -363 days" +%Y-%m-%d)
today_timestamp=$(date -d "$today" +%s)

# 2. Fetch Data (Public API)
url="https://github-contributions-api.jogruber.de/v4/$GITHUB_USERNAME?y=last"

temp_response=$(mktemp)
http_code=$(curl -s --retry 3 --retry-delay 2 --connect-timeout 10 -w "%{http_code}" -o "$temp_response" "$url")
body=$(cat "$temp_response")
rm -f "$temp_response"

# 3. Validation
if [ "$http_code" != "200" ]; then
    printf '{"contributions":[],"total":0,"error":true,"errorMessage":"User not found or API error (HTTP %s)"}\n' "$http_code"
    exit 1
fi

# 3b. Fetch display name (best-effort - GitHub public API, unauthenticated).
# If this fails or is rate-limited, we simply fall back to the username itself
# and never fail the whole refresh because of it.
display_name=""
name_temp=$(mktemp)
name_http_code=$(curl -s --connect-timeout 5 --max-time 8 -w "%{http_code}" -o "$name_temp" -H "Accept: application/vnd.github+json" "https://api.github.com/users/$GITHUB_USERNAME")
if [ "$name_http_code" = "200" ]; then
    display_name=$(jq -r '.name // empty' "$name_temp" 2>/dev/null)
fi
rm -f "$name_temp"
# Escape for embedding into our own printf'd JSON below
display_name_json=$(printf '%s' "$display_name" | jq -Rs '.' 2>/dev/null)
if [ -z "$display_name_json" ]; then display_name_json='""'; fi

# 4. Process Data
# We use jq to filter relevant days (>= start_date)
relevant_days=$(echo "$body" | jq -c --arg start "$start_date" '.contributions[] | select(.date >= $start)')

total_contributions=0
all_days=()

# Read filtered JSON lines
while read -r day_json; do
    if [ -z "$day_json" ]; then continue; fi
    
    date=$(echo "$day_json" | jq -r '.date')
    count=$(echo "$day_json" | jq -r '.count')
    level=$(echo "$day_json" | jq -r '.level')

    # Guard against non-numeric level/count from unexpected API payloads
    case "$level" in ''|*[!0-9]*) level=0 ;; esac
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    
    day_timestamp=$(date -d "$date" +%s)
    
    if [ "$day_timestamp" -le "$today_timestamp" ]; then
        
        case "$level" in
            0) color="$COLOR_0" ;;
            1) color="$COLOR_1" ;;
            2) color="$COLOR_2" ;;
            3) color="$COLOR_3" ;;
            4) color="$COLOR_4" ;;
            *) color="$COLOR_0" ;;
        esac

        total_contributions=$((total_contributions + count))

        weekday=$(date -d "$date" +%w)
        formatted_date=$(date -d "$date" "+%d / %b / %y")
        tooltip_text=$(date -d "$date" "+%d / %b :: $count")
        
        weekday_names=("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat")
        # Fix: Escape \${} to prevent JS interpolation
        weekday_name="\${weekday_names[$weekday]}"

        all_days+=("$date|$weekday|$count|$color|$formatted_date|$weekday_name|$tooltip_text|$level")
    fi
done <<< "$relevant_days"

# 5. Build Grid
# Fix: Escape \${} to prevent JS interpolation
IFS=$'\\n' sorted_days=($(sort <<<"\${all_days[*]}"))
unset IFS

grid_json="["
current_week="["
current_week_day=-1
first_week=1
first_day_in_week=1

# Fix: Escape \${} to prevent JS interpolation
for day_data in "\${sorted_days[@]}"; do
    IFS='|' read -r date weekday count color formatted_date weekday_name tooltip_text level <<< "$day_data"
    
    if [ "$weekday" == "0" ] && [ "$first_day_in_week" == "0" ]; then
        current_week="$current_week]"
        if [ "$first_week" == "1" ]; then
            grid_json="$grid_json$current_week"
            first_week=0
        else
            grid_json="$grid_json,$current_week"
        fi
        current_week="["
        first_day_in_week=1
    fi

    day_obj="{\\\"weekday\\\":$weekday,\\\"weekdayName\\\":\\\"$weekday_name\\\",\\\"date\\\":\\\"$formatted_date\\\",\\\"count\\\":$count,\\\"color\\\":\\\"$color\\\",\\\"level\\\":$level,\\\"tooltipText\\\":\\\"$tooltip_text\\\"}"

    if [ "$first_day_in_week" == "1" ]; then
        current_week="$current_week$day_obj"
        first_day_in_week=0
    else
        current_week="$current_week,$day_obj"
    fi
done

current_week="$current_week]"
if [ "$first_week" == "1" ]; then
    grid_json="$grid_json$current_week"
else
    grid_json="$grid_json,$current_week"
fi
grid_json="$grid_json]"

# 6. Build Pill Data
# Fix: Escape \${} to prevent JS interpolation
day_count=\${#sorted_days[@]}
pill_start=$((day_count - 7))
if [ $pill_start -lt 0 ]; then pill_start=0; fi

pill_json="["
pill_count=0

for (( i=pill_start; i<day_count; i++ )); do
    # Fix: Escape \${} to prevent JS interpolation
    day_data="\${sorted_days[$i]}"
    IFS='|' read -r date weekday count color formatted_date weekday_name tooltip_text level <<< "$day_data"

    if [ $pill_count -gt 0 ]; then
        pill_json="$pill_json,"
    fi
    pill_json="$pill_json{\\\"weekday\\\":\\\"$weekday_name\\\",\\\"date\\\":\\\"$formatted_date\\\",\\\"count\\\":$count,\\\"color\\\":\\\"$color\\\",\\\"level\\\":$level,\\\"tooltipText\\\":\\\"$tooltip_text\\\"}"
    pill_count=$((pill_count + 1))
done
pill_json="$pill_json]"

printf '{"contributions":%s,"gridData":%s,"total":%d,"displayName":%s,"error":false}\\n' "$pill_json" "$grid_json" "$total_contributions" "$display_name_json"
exit 0
`
    }

    // Bash process
    Process {
        id: githubProcess
        command: ["/usr/bin/env", "bash", "-c", buildScript()]
        running: false

        stdout: SplitParser {
            onRead: data => {
                try {
                    const result = JSON.parse(data.trim())

                    if (result.error) {
                        console.error("GitHub: API error -", result.errorMessage)
                        root.isError = true
                        root.errorMessage = result.errorMessage || "Unknown error"
                        root.initializePlaceholders()
                        root.isLoading = false
                        if (root.isManualRefresh) {
                            notifyFail.running = true
                        }
                        return
                    }

                    console.log("GitHub: Successfully fetched", result.contributions.length, "days for pill,", result.gridData.length, "weeks for grid")

                    root.isError = false
                    root.isLoading = false

                    // Ensure we always have exactly 7 items for pill
                    let newContributions = result.contributions || []

                    // Pad with placeholders if less than 7
                    while (newContributions.length < 7) {
                        newContributions.push({
                            weekday: "---",
                            date: "--/--",
                            count: 0,
                            level: 0,
                            color: Theme.surfaceContainer
                        })
                    }

                    // Trim if more than 7
                    newContributions = newContributions.slice(0, 7)

                    // Apply current color scheme (classic or theme-derived) based on level
                    newContributions = newContributions.map(day =>
                        Object.assign({}, day, { color: day.date === "--/--" ? root.levelToColor(0) : root.levelToColor(day.level) })
                    )

                    root.contributions = newContributions
                    root.totalContributions = result.total.toString()
                    root.githubDisplayName = result.displayName || ""

                    // Process grid data - ensure a full year with 7 days per week
                    const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                    let newGridData = result.gridData || []

                    // Ensure each week has 7 days
                    for (let w = 0; w < newGridData.length; w++) {
                        while (newGridData[w].length < 7) {
                            const missingDay = newGridData[w].length
                            newGridData[w].push({
                                weekday: missingDay,
                                weekdayName: days[missingDay],
                                date: "--/--",
                                count: 0,
                                level: 0,
                                color: Theme.surfaceContainer
                            })
                        }
                    }

                    // Pad the front to a full 52 weeks so both the bar widget's
                    // 8-week slice below and the desktop widget's year view (which
                    // reads the full-year cache separately) have a consistent,
                    // fully-rectangular grid to work with.
                    while (newGridData.length < 52) {
                        const emptyWeek = []
                        for (let d = 0; d < 7; d++) {
                            emptyWeek.push({
                                weekday: d,
                                weekdayName: days[d],
                                date: "--/--",
                                count: 0,
                                level: 0,
                                color: Theme.surfaceContainer
                            })
                        }
                        newGridData.unshift(emptyWeek)
                    }

                    // Apply current color scheme (classic or theme-derived) based on level,
                    // then cache the full year before trimming down to the bar widget's
                    // own 8-week display.
                    const fullYearGrid = newGridData.map(week =>
                        week.map(day => Object.assign({}, day, { color: day.date === "--/--" ? root.levelToColor(0) : root.levelToColor(day.level) }))
                    )

                    // Take only last 8 weeks for the bar widget's own popout display
                    newGridData = fullYearGrid.slice(-8)
                    root.gridData = newGridData

                    // Cache successful fetch persistently. Both the 8-week slice
                    // (kept for backwards compatibility / anything reading
                    // cachedGrid) and the full year (for the desktop widget's year
                    // view) are stored. Writing through SettingsData.setPluginSetting
                    // updates the shared plugin_settings.json that every surface of
                    // this composite plugin reads from - see the comment in
                    // Settings.qml for why we use this instead of pluginService
                    // directly.
                    SettingsData.setPluginSetting(root.pluginId, "cachedTotal", root.totalContributions)
                    SettingsData.setPluginSetting(root.pluginId, "cachedGrid", JSON.stringify(root.gridData))
                    SettingsData.setPluginSetting(root.pluginId, "cachedGridYear", JSON.stringify(fullYearGrid))
                    SettingsData.setPluginSetting(root.pluginId, "cachedDisplayName", root.githubDisplayName)

                    // Set default selected day to the most recent one
                    let nValidDays = []
                    for (let w = 0; w < newGridData.length; w++) {
                        for (let d = 0; d < newGridData[w].length; d++) {
                            if (newGridData[w][d].date !== "--/--") {
                                nValidDays.push(newGridData[w][d])
                            }
                        }
                    }
                    if (nValidDays.length > 0) {
                        root.todayDay = nValidDays[nValidDays.length - 1]
                        if (nValidDays.length > 1) {
                            root.yesterdayDay = nValidDays[nValidDays.length - 2]
                        }
                    } else if (newGridData.length > 0) {
                        const lastWeek = newGridData[newGridData.length - 1]
                        root.todayDay = lastWeek[lastWeek.length - 1]
                        if (lastWeek.length > 1) {
                            root.yesterdayDay = lastWeek[lastWeek.length - 2]
                        } else if (newGridData.length > 1) {
                            const prevWeek = newGridData[newGridData.length - 2]
                            root.yesterdayDay = prevWeek[prevWeek.length - 1]
                        }
                    }
                    // gridData is a fresh array, so any previously-hovered selectedDay
                    // now references a stale object. Always reset to today after a refresh
                    // to avoid the detail card getting stuck on an orphaned entry.
                    root.selectedDay = root.todayDay

                    if (root.isManualRefresh && root.showNotifications) {
                        notifySuccess.running = true
                    }

                } catch (e) {
                    console.error("GitHub: Failed to parse response -", e, "Data:", data)
                    root.isError = true
                    root.errorMessage = "Failed to parse GitHub response"
                    root.initializePlaceholders()
                    root.isLoading = false
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.isLoading = false
            if (exitCode !== 0 && !root.isError) {
                console.error("GitHub: Script failed with exit code", exitCode)
                root.isError = true
                root.errorMessage = "Script failed with exit code: " + exitCode
                if (root.isManualRefresh && root.showNotifications) {
                    notifyFail.running = true
                }
                root.handleFetchFailure("Sync failed (Check logs)")
            }
        }
    }

    // Notification processes
    Process {
        id: notifySuccess
        command: ["notify-send", "-t", "3000", "GitHub Synced", "Contributions refreshed successfully"]
        running: false
    }

    Process {
        id: notifyFail
        command: ["notify-send", "-u", "critical", "-t", "5000", "GitHub Sync Failed", root.errorMessage]
        running: false
    }

    Process {
        id: notifyCooldown
        command: ["notify-send", "-t", "2500", "GitHub Heatmap", "Please wait a bit before refreshing again"]
        running: false
    }

    Process {
        id: openProfileProcess
        command: ["xdg-open", "https://github.com/" + root.githubUsername]
        running: false
    }

    // Horizontal bar pill - shows 7 squares, or just today's square in compact mode
    horizontalBarPill: Component {
        RowLayout {
            spacing: root.pillSpacing
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                model: root.pillShowSingleDay ? 1 : 7

                Rectangle {
                    Layout.preferredWidth: root.pillSquareSize
                    Layout.preferredHeight: root.pillSquareSize
                    radius: Math.max(1, root.pillSquareSize * 0.3)
                    property int dataIndex: root.pillShowSingleDay ? (root.contributions.length - 1) : index
                    color: dataIndex >= 0 && dataIndex < root.contributions.length
                           ? root.contributions[dataIndex].color
                           : root.levelToColor(0)
                    border.color: Theme.withAlpha(Theme.outline, 0.35)
                    border.width: 1
                    antialiasing: true
                    opacity: root.isLoading ? 0.6 : 1.0

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }
            }
        }
    }

    // Vertical bar pill - shows 7 squares, or just today's square in compact mode
    verticalBarPill: Component {
        Column {
            spacing: root.pillSpacing

            Repeater {
                model: root.pillShowSingleDay ? 1 : 7

                Rectangle {
                    width: root.pillSquareSize
                    height: root.pillSquareSize
                    radius: Math.max(1, root.pillSquareSize * 0.3)
                    property int dataIndex: root.pillShowSingleDay ? (root.contributions.length - 1) : index
                    color: dataIndex >= 0 && dataIndex < root.contributions.length
                           ? root.contributions[dataIndex].color
                           : root.levelToColor(0)
                    border.color: Theme.withAlpha(Theme.outline, 0.35)
                    border.width: 1
                    antialiasing: true
                    opacity: root.isLoading ? 0.6 : 1.0

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }
            }
        }
    }

    // Popout position persistence
    property int popoutX: (pluginData && pluginData.popoutX) ? pluginData.popoutX : -1
    property int popoutY: (pluginData && pluginData.popoutY) ? pluginData.popoutY : -1

    function savePopoutPosition(x, y) {
        SettingsData.setPluginSetting(root.pluginId, "popoutX", x)
        SettingsData.setPluginSetting(root.pluginId, "popoutY", y)
    }

    // --- Popout Content ---
    popoutContent: Component {
        PopoutComponent {
            id: popoutContainer

            // Restore saved position
            x: root.popoutX >= 0 ? root.popoutX : x
            y: root.popoutY >= 0 ? root.popoutY : y

            // Save position when moved
            onXChanged: if (visible) Qt.callLater(() => root.savePopoutPosition(x, y))
            onYChanged: if (visible) Qt.callLater(() => root.savePopoutPosition(x, y))

            showCloseButton: false
            headerText: "" 

            Loader {
                id: popoutLoader
                width: parent.width
                asynchronous: true
                sourceComponent: heatmapWidgetContent
            }
        }
    }


    Component {
        id: heatmapWidgetContent
        Column {
            id: mainCol
            width: parent.width
            spacing: Theme.spacingM
            padding: 0
            topPadding: 0
            bottomPadding: 2

            // Header card
            StyledRect {
                width: parent.width
                anchors.horizontalCenter: parent.horizontalCenter
                height: 72
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 1
                border.color: Theme.withAlpha(Theme.primary, 0.15)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingM

                    Rectangle {
                        width: 42
                        height: 42
                        radius: 21
                        color: Theme.withAlpha(Theme.primary, 0.2)
                        
                        MouseArea {
                            id: profileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => profileRipple.trigger(mouse.x, mouse.y)
                            onClicked: if (root.githubUsername) openProfileProcess.running = true
                        }

                        StyledText {
                            text: root.faGithubGlyph
                            font.family: root.faFamily
                            font.pixelSize: 22
                            color: Theme.primary
                            anchors.centerIn: parent
                            scale: profileArea.containsMouse ? 1.2 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                        }

                        DankRipple {
                            id: profileRipple
                            rippleColor: Theme.surfaceText
                            cornerRadius: 21
                            anchors.fill: parent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        
                        StyledText {
                            id: usernameText
                            Layout.fillWidth: true
                            text: {
                                if (root.showDisplayName && root.githubDisplayName) {
                                    return root.githubDisplayName
                                }
                                return root.githubUsername || "GitHub User"
                            }
                            font.bold: true
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                        }

                        StyledText {
                            id: contributionStatusText
                            Layout.fillWidth: true
                            text: root.isError ? "Connection Error" : (root.isLoading ? "Syncing..." : root.totalContributions + " contributions")
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: Theme.primary
                            opacity: 0.8
                        }
                    }

                    Item {
                        width: 38
                        height: 38
                        Layout.alignment: Qt.AlignVCenter
                        scale: refreshArea.pressed ? 0.9 : (refreshArea.containsMouse ? 1.1 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                        MouseArea {
                            id: refreshArea
                            anchors.fill: parent
                            hoverEnabled: !root.isLoading
                            enabled: !root.isLoading
                            cursorShape: root.isLoading ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onPressed: mouse => refreshRipple.trigger(mouse.x, mouse.y)
                            onClicked: {
                                root.isManualRefresh = true
                                root.refreshHeatmap()
                            }
                            onExited: {
                                if (!root.isLoading) {
                                    refreshIcon.rotation = 0
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.cornerRadius
                            color: refreshArea.pressed ? Theme.withAlpha(Theme.primary, 0.18) : (refreshArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.10) : Theme.withAlpha(Theme.secondary, 0.04))
                            border.width: 1
                            border.color: refreshArea.pressed ? Theme.withAlpha(Theme.primary, 0.60) : (refreshArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.40) : Theme.withAlpha(Theme.secondary, 0.15))
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }

                        DankIcon {
                            id: refreshIcon
                            name: root.isLoading ? "cached" : root.iconRefresh
                            size: 20
                            color: Theme.primary
                            anchors.centerIn: parent

                            SequentialAnimation {
                                id: hoverSpinAnim
                                running: refreshArea.containsMouse && !root.isLoading
                                loops: Animation.Infinite
                                onStopped: refreshIcon.rotation = 0
                                NumberAnimation { target: refreshIcon; property: "rotation"; to: -8; duration: 150; easing.type: Easing.InOutQuad }
                                NumberAnimation { target: refreshIcon; property: "rotation"; to: 8; duration: 150; easing.type: Easing.InOutQuad }
                                NumberAnimation { target: refreshIcon; property: "rotation"; to: 0; duration: 150; easing.type: Easing.InOutQuad }
                                PauseAnimation { duration: 400 }
                            }

                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 1000
                                loops: Animation.Infinite
                                running: root.isLoading
                                onStopped: refreshIcon.rotation = 0
                            }
                        }

                        DankRipple {
                            id: refreshRipple
                            rippleColor: Theme.surfaceText
                            cornerRadius: Theme.cornerRadius
                            anchors.fill: parent
                        }
                    }
                }
            }

            // Error display
            StyledRect {
                width: parent.width
                anchors.horizontalCenter: parent.horizontalCenter
                height: root.isError ? 60 : 0
                radius: Theme.cornerRadius
                color: Theme.errorContainer || Theme.surfaceContainerHigh
                visible: root.isError
                clip: true
                Behavior on height { NumberAnimation { duration: 150 } }

                StyledText {
                    anchors.centerIn: parent
                    width: Math.max(0, parent.width - Theme.spacingL * 2)
                    text: root.errorMessage
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.onErrorContainer || Theme.error
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            // Calendar grid container
            StyledRect {
                id: gridContainer
                width: parent.width
                anchors.horizontalCenter: parent.horizontalCenter
                height: 240
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 1
                border.color: Theme.withAlpha(Theme.primary, 0.15)
                visible: !root.isError

                    // Detect when the mouse leaves the entire grid area to reset to "today"
                    HoverHandler {
                        id: gridHover
                        onHoveredChanged: if (!hovered) root.selectedDay = root.todayDay
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        // Day labels
                        Column {
                            spacing: 4
                            topPadding: 4

                            Repeater {
                                model: ["S", "M", "T", "W", "T", "F", "S"]
                                StyledText {
                                    text: modelData
                                    font.pixelSize: 10
                                    color: Theme.surfaceVariantText
                                    width: 14
                                    height: 26
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }

                        // Grid
                        Row {
                            spacing: 4
                            Repeater {
                                model: root.gridData
                                Column {
                                    spacing: 4
                                    required property var modelData
                                    Repeater {
                                        model: modelData
                                        Rectangle {
                                            width: 26
                                            height: 26
                                            radius: root.selectedDay === modelData ? 13 : 4
                                            Behavior on radius { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                            color: modelData.color || Theme.surfaceContainer
                                            border.color: root.selectedDay === modelData ? Theme.primary : Qt.darker(color, 1.15)
                                            border.width: root.selectedDay === modelData ? 2 : 1
                                            required property var modelData
                                            opacity: root.isLoading ? 0.6 : 1.0
                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                            Behavior on color { ColorAnimation { duration: 150 } }

                                            MouseArea {
                                                id: cellMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onEntered: root.selectedDay = modelData
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Contribution detail card
                StyledRect {
                    width: parent.width
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 80
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                    border.width: 1
                    border.color: root.selectedDay ? Qt.rgba(root.selectedDay.color.r, root.selectedDay.color.g, root.selectedDay.color.b, 0.4) : Theme.withAlpha(Theme.primary, 0.15)
                    visible: root.selectedDay !== null && !root.isError
                    clip: true

                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        // Count large display
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            width: 80

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 6

                                // Small color swatch shows the day's intensity color,
                                // while the number itself always uses the theme's
                                // readable text color instead of the (sometimes very
                                // light or very dark) heatmap color.
                                Rectangle {
                                    width: 10
                                    height: 10
                                    radius: 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.selectedDay ? root.selectedDay.color : root.levelToColor(0)
                                    border.color: Theme.withAlpha(Theme.outline, 0.35)
                                    border.width: 1
                                    antialiasing: true
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                StyledText {
                                    text: root.selectedDay ? root.selectedDay.count : "0"
                                    font.pixelSize: 32
                                    font.bold: true
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            StyledText {
                                text: "contributions"
                                font.pixelSize: 10
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        // Vertical separator
                        Rectangle {
                            height: parent.height - Theme.spacingS
                            width: 1
                            color: Theme.outlineVariant
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Date and day info
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Row {
                                spacing: Theme.spacingS
                                DankIcon {
                                    name: root.iconBar
                                    size: 16
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: root.selectedDay ? root.selectedDay.weekdayName : ""
                                    font.bold: true
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceText
                                }
                            }

                            StyledText {
                                text: {
                                    if (!root.selectedDay) return ""
                                    if (root.selectedDay === root.todayDay) return "Today"
                                    if (root.selectedDay === root.yesterdayDay) return "Yesterday"
                                    return root.selectedDay.date
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
            }
        }
    }

    // Single global tooltip instance for the plugin
    DankTooltipV2 {
        id: tooltip
    }
}
