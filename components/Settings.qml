import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

PluginSettings {
    id: root
    pluginId: "githubHeatmapDMS"

    // IMPORTANT: we deliberately do NOT use the base PluginSettings.saveValue()/
    // loadValue(), even though they exist. Those wrap this component's
    // `pluginService` property - and DMS injects a DIFFERENT pluginService
    // depending on which UI opened this settings file:
    //   - Settings -> Plugins (PluginListItem.qml) injects the real global
    //     PluginService singleton.
    //   - The desktop widget's own settings panel
    //     (PluginDesktopWidgetSettings.qml) injects an instance-scoped wrapper
    //     that redirects saves into that one placed widget's private
    //     instanceData.config instead of the shared plugin_settings.json.
    // Since this plugin's settings (GitHub username, refresh interval, bar
    // pill sizing, etc.) are meant to be one shared configuration - not a
    // per-placement override - we bypass `pluginService` entirely and call
    // the underlying shared storage (SettingsData.getPluginSetting /
    // setPluginSetting) directly. This is the same storage BarWidget.qml's
    // PluginService.savePluginData/loadPluginData calls ultimately read and
    // write, so all three surfaces (bar widget, desktop widget, and this
    // settings panel, however it was opened) now agree on one copy of the data.
    function saveValue(key, value) {
        SettingsData.setPluginSetting(root.pluginId, key, value)
        root.settingChanged()
    }

    function loadValue(key, defaultValue) {
        return SettingsData.getPluginSetting(root.pluginId, key, defaultValue)
    }

    property string currentUsername: loadValue("username", "")
    property string currentInterval: loadValue("refreshInterval", 300).toString()

    // Load persisted settings when settings UI opens
    Component.onCompleted: {
        console.log("GitHub Heatmap: Settings loaded from disk")

        const savedNotify = loadValue("showNotifications", true)
        notifyToggle.checked = (savedNotify === true || savedNotify === "true")

        const savedFollowTheme = loadValue("followThemeColor", false)
        themeColorToggle.checked = (savedFollowTheme === true || savedFollowTheme === "true")

        const savedSingleDay = loadValue("pillShowSingleDay", false)
        singleDayToggle.checked = (savedSingleDay === true || savedSingleDay === "true")

        const savedSize = loadValue("pillSquareSize", 10)
        sizeSlider.value = Number(savedSize) || 10

        const savedSpacing = loadValue("pillSpacing", 3)
        spacingSlider.value = (savedSpacing !== undefined && savedSpacing !== "") ? Number(savedSpacing) : 3

        const savedShowDisplayName = loadValue("showDisplayName", false)
        displayNameToggle.checked = (savedShowDisplayName === true || savedShowDisplayName === "true")

        const savedDesktopOpacity = loadValue("desktopBackgroundOpacity", 70)
        desktopOpacitySlider.value = Number(savedDesktopOpacity) || 70

        const savedDesktopSquareSize = loadValue("desktopSquareSize", 11)
        desktopSquareSizeSlider.value = Number(savedDesktopSquareSize) || 11

        const savedDesktopSquareSpacing = loadValue("desktopSquareSpacing", 3)
        desktopSquareSpacingSlider.value = (savedDesktopSquareSpacing !== undefined && savedDesktopSquareSpacing !== "") ? Number(savedDesktopSquareSpacing) : 3
    }

    Component {
        id: settingsCardTemplate
        Rectangle {
            width: parent ? parent.width : 0
            height: Math.max(0, contentCol.implicitHeight + Theme.spacingM * 2)
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1

            property string iconName
            property string titleText
            property string subtitleText
            property Component controlContent

            Column {
                id: contentCol
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                Row {
                    width: parent.width
                    spacing: Theme.spacingM
                    DankIcon { id: cardIcon; name: iconName; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                    Column {
                        width: Math.max(0, parent.width - cardIcon.width - Theme.spacingM)
                        spacing: Theme.spacingXXS
                        StyledText {
                            text: titleText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }
                        StyledText {
                            text: subtitleText
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            width: parent.width
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Loader {
                    id: cardContent
                    width: parent.width
                    sourceComponent: controlContent
                    asynchronous: true
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingL

        StyledText {
            width: parent.width
            text: "GitHub Account & Sync"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Applies to both the DankBar widget and the desktop widget."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        // --- Account Section ---
        Loader {
            width: parent.width
            asynchronous: true
            sourceComponent: settingsCardTemplate
            onLoaded: {
                item.iconName = "person"
                item.titleText = "GitHub Identity"
                item.subtitleText = "Your GitHub username used to fetch public contribution data."
                item.controlContent = accountControlComponent
            }
        }

        Component {
            id: accountControlComponent
            DankTextField {
                width: parent ? parent.width : 0
                placeholderText: "e.g. josh-overton"
                text: root.currentUsername
                onTextChanged: {
                    root.currentUsername = text
                }
            }
        }

        // --- Display Name toggle ---
        Rectangle {
            width: parent.width
            height: Math.max(0, displayNameRow.implicitHeight + Theme.spacingM * 2)
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.8

            RowLayout {
                id: displayNameRow
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                DankIcon {
                    name: "badge"
                    size: 22
                    opacity: 0.8
                    Layout.alignment: Qt.AlignVCenter
                }

                Column {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXXS
                    Layout.alignment: Qt.AlignVCenter
                    StyledText {
                        text: "Show Display Name"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                    StyledText {
                        text: "Show the GitHub profile's display name instead of the username. Falls back to the username if none is set."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }

                DankToggle {
                    id: displayNameToggle
                    Layout.alignment: Qt.AlignVCenter
                    checked: false
                    onClicked: {
                        checked = !checked
                    }
                }
            }
        }

        // --- Performance Section ---
        Loader {
            width: parent.width
            asynchronous: true
            sourceComponent: settingsCardTemplate
            onLoaded: {
                item.iconName = "schedule"
                item.titleText = "Refresh Rate"
                item.subtitleText = "Frequency of updates in seconds. Higher values save battery."
                item.controlContent = perfControlComponent
            }
        }

        Component {
            id: perfControlComponent
            DankTextField {
                width: parent ? parent.width : 0
                placeholderText: "300 (5 minutes)"
                text: root.currentInterval
                onTextChanged: {
                    root.currentInterval = text
                }
                validator: IntValidator { bottom: 60; top: 86400 }
            }
        }

        // --- Notification Section ---
        Rectangle {
            width: parent.width
            height: Math.max(0, notifyRow.implicitHeight + Theme.spacingM * 2)
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.8

            RowLayout {
                id: notifyRow
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                DankIcon { 
                    name: "notifications"
                    size: 22
                    opacity: 0.8
                    Layout.alignment: Qt.AlignVCenter 
                }
                
                Column {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXXS
                    Layout.alignment: Qt.AlignVCenter
                    StyledText {
                        text: "System Alerts"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                    StyledText {
                        text: "Show desktop notifications for sync status."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }

                DankToggle {
                    id: notifyToggle
                    Layout.alignment: Qt.AlignVCenter
                    checked: true
                    onClicked: {
                        checked = !checked
                    }
                }
            }
        }

        // --- Appearance Section ---
        Rectangle {
            width: parent.width
            height: Math.max(0, themeRow.implicitHeight + Theme.spacingM * 2)
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.8

            RowLayout {
                id: themeRow
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                DankIcon {
                    name: "palette"
                    size: 22
                    opacity: 0.8
                    Layout.alignment: Qt.AlignVCenter
                }

                Column {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXXS
                    Layout.alignment: Qt.AlignVCenter
                    StyledText {
                        text: "Follow DMS Theme Color"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                    StyledText {
                        text: "Use your DMS accent color for the heatmap instead of the classic GitHub green."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }

                DankToggle {
                    id: themeColorToggle
                    Layout.alignment: Qt.AlignVCenter
                    checked: false
                    onClicked: {
                        checked = !checked
                    }
                }
            }
        }

        StyledText {
            width: parent.width
            text: "DankBar Widget"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Only affects the pill in your DankBar. The desktop widget always shows the full calendar or a compact strip depending on how you resize it."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        // --- Top Bar Display Section ---
        Rectangle {
            width: parent.width
            height: Math.max(0, topbarCol.implicitHeight + Theme.spacingM * 2)
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.8

            Column {
                id: topbarCol
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM

                    DankIcon {
                        name: "view_column"
                        size: 22
                        opacity: 0.8
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXXS
                        Layout.alignment: Qt.AlignVCenter
                        StyledText {
                            text: "Compact Mode (Today Only)"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }
                        StyledText {
                            text: "Show only today's square in the top bar instead of the last 7 days."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            width: parent.width
                            wrapMode: Text.WordWrap
                        }
                    }

                    DankToggle {
                        id: singleDayToggle
                        Layout.alignment: Qt.AlignVCenter
                        checked: false
                        onClicked: {
                            checked = !checked
                        }
                    }
                }

                // Square size slider
                Column {
                    width: parent.width
                    spacing: Theme.spacingXXS

                    RowLayout {
                        width: parent.width
                        StyledText {
                            text: "Square Size"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                        }
                        StyledText {
                            text: sizeSlider.value.toFixed(0) + "px"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    Slider {
                        id: sizeSlider
                        width: parent.width
                        from: 6
                        to: 18
                        stepSize: 1
                        value: 10

                        background: Rectangle {
                            x: sizeSlider.leftPadding
                            y: sizeSlider.topPadding + sizeSlider.availableHeight / 2 - height / 2
                            width: sizeSlider.availableWidth
                            height: 4
                            radius: 2
                            color: Theme.withAlpha(Theme.outline, 0.3)

                            Rectangle {
                                width: sizeSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 2
                                color: Theme.primary
                            }
                        }

                        handle: Rectangle {
                            x: sizeSlider.leftPadding + sizeSlider.visualPosition * (sizeSlider.availableWidth - width)
                            y: sizeSlider.topPadding + sizeSlider.availableHeight / 2 - height / 2
                            width: 16
                            height: 16
                            radius: 8
                            color: Theme.primary
                            border.color: Theme.withAlpha(Theme.surfaceText, 0.15)
                            border.width: sizeSlider.pressed ? 2 : 0
                            scale: sizeSlider.pressed ? 1.15 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }
                        }
                    }
                }

                // Spacing slider
                Column {
                    width: parent.width
                    spacing: Theme.spacingXXS

                    RowLayout {
                        width: parent.width
                        StyledText {
                            text: "Spacing"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                        }
                        StyledText {
                            text: spacingSlider.value.toFixed(0) + "px"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    Slider {
                        id: spacingSlider
                        width: parent.width
                        from: 0
                        to: 8
                        stepSize: 1
                        value: 3

                        background: Rectangle {
                            x: spacingSlider.leftPadding
                            y: spacingSlider.topPadding + spacingSlider.availableHeight / 2 - height / 2
                            width: spacingSlider.availableWidth
                            height: 4
                            radius: 2
                            color: Theme.withAlpha(Theme.outline, 0.3)

                            Rectangle {
                                width: spacingSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 2
                                color: Theme.primary
                            }
                        }

                        handle: Rectangle {
                            x: spacingSlider.leftPadding + spacingSlider.visualPosition * (spacingSlider.availableWidth - width)
                            y: spacingSlider.topPadding + spacingSlider.availableHeight / 2 - height / 2
                            width: 16
                            height: 16
                            radius: 8
                            color: Theme.primary
                            border.color: Theme.withAlpha(Theme.surfaceText, 0.15)
                            border.width: spacingSlider.pressed ? 2 : 0
                            scale: spacingSlider.pressed ? 1.15 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }
                        }
                    }
                }
            }
        }

        StyledText {
            width: parent.width
            text: "Desktop Widget"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Only affects the resizable card you place on your desktop."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        // --- Desktop Background Opacity ---
        Rectangle {
            width: parent.width
            height: Math.max(0, desktopOpacityCol.implicitHeight + Theme.spacingM * 2)
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.8

            Column {
                id: desktopOpacityCol
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM

                    DankIcon {
                        name: "opacity"
                        size: 22
                        opacity: 0.8
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXXS
                        Layout.alignment: Qt.AlignVCenter
                        StyledText {
                            text: "Background Opacity"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }
                        StyledText {
                            text: "How solid the desktop widget's card background looks."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            width: parent.width
                            wrapMode: Text.WordWrap
                        }
                    }

                    StyledText {
                        text: desktopOpacitySlider.value.toFixed(0) + "%"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                Slider {
                    id: desktopOpacitySlider
                    width: parent.width
                    from: 0
                    to: 100
                    stepSize: 5
                    value: 70

                    background: Rectangle {
                        x: desktopOpacitySlider.leftPadding
                        y: desktopOpacitySlider.topPadding + desktopOpacitySlider.availableHeight / 2 - height / 2
                        width: desktopOpacitySlider.availableWidth
                        height: 4
                        radius: 2
                        color: Theme.withAlpha(Theme.outline, 0.3)

                        Rectangle {
                            width: desktopOpacitySlider.visualPosition * parent.width
                            height: parent.height
                            radius: 2
                            color: Theme.primary
                        }
                    }

                    handle: Rectangle {
                        x: desktopOpacitySlider.leftPadding + desktopOpacitySlider.visualPosition * (desktopOpacitySlider.availableWidth - width)
                        y: desktopOpacitySlider.topPadding + desktopOpacitySlider.availableHeight / 2 - height / 2
                        width: 16
                        height: 16
                        radius: 8
                        color: Theme.primary
                        border.color: Theme.withAlpha(Theme.surfaceText, 0.15)
                        border.width: desktopOpacitySlider.pressed ? 2 : 0
                        scale: desktopOpacitySlider.pressed ? 1.15 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }
                    }
                }
            }
        }

        // --- Desktop Square Size & Spacing ---
        Rectangle {
            width: parent.width
            height: Math.max(0, desktopGridCol.implicitHeight + Theme.spacingM * 2)
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.8

            Column {
                id: desktopGridCol
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                StyledText {
                    text: "Contribution squares are always rendered square, never stretched. These settings control how big each one is - the widget automatically shows fewer weeks (or just today, if it's very small) if a full year doesn't fit."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    width: parent.width
                    wrapMode: Text.WordWrap
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXXS

                    RowLayout {
                        width: parent.width
                        StyledText {
                            text: "Square Size"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                        }
                        StyledText {
                            text: desktopSquareSizeSlider.value.toFixed(0) + "px"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    Slider {
                        id: desktopSquareSizeSlider
                        width: parent.width
                        from: 6
                        to: 24
                        stepSize: 1
                        value: 11

                        background: Rectangle {
                            x: desktopSquareSizeSlider.leftPadding
                            y: desktopSquareSizeSlider.topPadding + desktopSquareSizeSlider.availableHeight / 2 - height / 2
                            width: desktopSquareSizeSlider.availableWidth
                            height: 4
                            radius: 2
                            color: Theme.withAlpha(Theme.outline, 0.3)

                            Rectangle {
                                width: desktopSquareSizeSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 2
                                color: Theme.primary
                            }
                        }

                        handle: Rectangle {
                            x: desktopSquareSizeSlider.leftPadding + desktopSquareSizeSlider.visualPosition * (desktopSquareSizeSlider.availableWidth - width)
                            y: desktopSquareSizeSlider.topPadding + desktopSquareSizeSlider.availableHeight / 2 - height / 2
                            width: 16
                            height: 16
                            radius: 8
                            color: Theme.primary
                            border.color: Theme.withAlpha(Theme.surfaceText, 0.15)
                            border.width: desktopSquareSizeSlider.pressed ? 2 : 0
                            scale: desktopSquareSizeSlider.pressed ? 1.15 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXXS

                    RowLayout {
                        width: parent.width
                        StyledText {
                            text: "Square Spacing"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                        }
                        StyledText {
                            text: desktopSquareSpacingSlider.value.toFixed(0) + "px"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    Slider {
                        id: desktopSquareSpacingSlider
                        width: parent.width
                        from: 0
                        to: 8
                        stepSize: 1
                        value: 3

                        background: Rectangle {
                            x: desktopSquareSpacingSlider.leftPadding
                            y: desktopSquareSpacingSlider.topPadding + desktopSquareSpacingSlider.availableHeight / 2 - height / 2
                            width: desktopSquareSpacingSlider.availableWidth
                            height: 4
                            radius: 2
                            color: Theme.withAlpha(Theme.outline, 0.3)

                            Rectangle {
                                width: desktopSquareSpacingSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 2
                                color: Theme.primary
                            }
                        }

                        handle: Rectangle {
                            x: desktopSquareSpacingSlider.leftPadding + desktopSquareSpacingSlider.visualPosition * (desktopSquareSpacingSlider.availableWidth - width)
                            y: desktopSquareSpacingSlider.topPadding + desktopSquareSpacingSlider.availableHeight / 2 - height / 2
                            width: 16
                            height: 16
                            radius: 8
                            color: Theme.primary
                            border.color: Theme.withAlpha(Theme.surfaceText, 0.15)
                            border.width: desktopSquareSpacingSlider.pressed ? 2 : 0
                            scale: desktopSquareSpacingSlider.pressed ? 1.15 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }
                        }
                    }
                }
            }
        }

        // --- Save Action ---
        Item {
            id: saveBtn
            width: parent.width
            height: 44
            
            scale: saveArea.pressed ? 0.96 : (saveArea.containsMouse ? 1.02 : 1.0)
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

            MouseArea {
                id: saveArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => saveRipple.trigger(mouse.x, mouse.y)
                onClicked: {
                    const name = root.currentUsername.trim()
                    if (!name) {
                        ToastService.showError("Please enter a GitHub username")
                        return
                    }

                    const interval = parseInt(root.currentInterval) || 300
                    if (interval < 60) {
                        ToastService.showError("Interval must be at least 60 seconds")
                        return
                    }

                    const notify = notifyToggle.checked
                    const followTheme = themeColorToggle.checked
                    const singleDay = singleDayToggle.checked
                    const squareSize = Math.round(sizeSlider.value)
                    const squareSpacing = Math.round(spacingSlider.value)
                    const showName = displayNameToggle.checked
                    const desktopOpacity = Math.round(desktopOpacitySlider.value)
                    const desktopSquareSize = Math.round(desktopSquareSizeSlider.value)
                    const desktopSquareSpacing = Math.round(desktopSquareSpacingSlider.value)

                    // Persist & Notify
                    root.saveValue("username", name)
                    root.saveValue("refreshInterval", interval)
                    root.saveValue("showNotifications", notify)
                    root.saveValue("followThemeColor", followTheme)
                    root.saveValue("pillShowSingleDay", singleDay)
                    root.saveValue("pillSquareSize", squareSize)
                    root.saveValue("pillSpacing", squareSpacing)
                    root.saveValue("showDisplayName", showName)
                    root.saveValue("desktopBackgroundOpacity", desktopOpacity)
                    root.saveValue("desktopSquareSize", desktopSquareSize)
                    root.saveValue("desktopSquareSpacing", desktopSquareSpacing)

                    ToastService.showSuccess("Settings updated successfully")
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.cornerRadius
                color: saveArea.pressed ? Theme.withAlpha(Theme.primary, 0.18) : (saveArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.10) : Theme.withAlpha(Theme.secondary, 0.04))
                border.width: 1
                border.color: saveArea.pressed ? Theme.withAlpha(Theme.primary, 0.60) : (saveArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.40) : Theme.withAlpha(Theme.secondary, 0.15))
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }
            }

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingS
                
                DankIcon {
                    id: saveIcon
                    name: "published_with_changes"
                    size: 20
                    color: Theme.primary
                    
                    SequentialAnimation {
                        running: saveArea.containsMouse
                        loops: Animation.Infinite
                        onStopped: saveIcon.rotation = 0
                        NumberAnimation { target: saveIcon; property: "rotation"; to: -8; duration: 150; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: saveIcon; property: "rotation"; to: 8; duration: 150; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: saveIcon; property: "rotation"; to: 0; duration: 150; easing.type: Easing.InOutQuad }
                        PauseAnimation { duration: 400 }
                    }
                }
                
                StyledText {
                    text: "Save & Synchronize"
                    color: Theme.primary
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: true
                    verticalAlignment: Text.AlignVCenter
                }
            }

            DankRipple {
                id: saveRipple
                rippleColor: Theme.surfaceText
                cornerRadius: Theme.cornerRadius
                anchors.fill: parent
            }
        }
    }
}
