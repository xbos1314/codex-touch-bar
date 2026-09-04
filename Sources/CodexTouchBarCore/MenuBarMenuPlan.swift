public enum MenuBarCommand: Equatable, Sendable {
    case quotaSectionHeader
    case quotaSubscriptionInfo
    case quotaMainInfo
    case quotaResetCreditsInfo
    case sessionSectionHeader
    case sessionInfo
    case projectInfo
    case switchSession
    case openCurrentSession
    case toggleCompletionSpeech
    case completionSpeechVoiceMenu
    case completionSpeechRateMenu
    case completionSpeechPitchMenu
    case readingSectionHeader
    case readingFileInfo
    case readingPathInfo
    case readingProgressInfo
    case openReadingFile
    case continueReading
    case exitReadingMode
    case readingAutoPageSpeedHeader
    case selectSlowReadingAutoPageSpeed
    case selectNormalReadingAutoPageSpeed
    case selectFastReadingAutoPageSpeed
    case touchBarSectionHeader
    case touchBarModeInfo
    case statusBarSectionHeader
    case toggleStatusBarContent
    case detailDisplayHeader
    case selectScrollingDetailDisplay
    case selectPagingDetailDisplay
    case detailScrollSpeed
    case selectSlowDetailScrollSpeed
    case selectNormalDetailScrollSpeed
    case selectFastDetailScrollSpeed
    case detailPageSpeed
    case selectSlowDetailPageSpeed
    case selectNormalDetailPageSpeed
    case selectFastDetailPageSpeed
    case statusBarPageSpeed
    case selectSlowStatusBarPageSpeed
    case selectNormalStatusBarPageSpeed
    case selectFastStatusBarPageSpeed
    case togglePause
    case refreshNow
    case showTouchBarHost
    case quit
}

public enum MenuBarMenuPlan {
    public static let visibleCommands: [MenuBarCommand] = [
        .quotaSectionHeader,
        .quotaSubscriptionInfo,
        .quotaMainInfo,
        .quotaResetCreditsInfo,
        .sessionSectionHeader,
        .sessionInfo,
        .projectInfo,
        .switchSession,
        .openCurrentSession,
        .toggleCompletionSpeech,
        .completionSpeechVoiceMenu,
        .completionSpeechRateMenu,
        .completionSpeechPitchMenu,
        .readingSectionHeader,
        .readingFileInfo,
        .readingPathInfo,
        .readingProgressInfo,
        .openReadingFile,
        .continueReading,
        .exitReadingMode,
        .readingAutoPageSpeedHeader,
        .selectSlowReadingAutoPageSpeed,
        .selectNormalReadingAutoPageSpeed,
        .selectFastReadingAutoPageSpeed,
        .touchBarSectionHeader,
        .touchBarModeInfo,
        .detailDisplayHeader,
        .selectScrollingDetailDisplay,
        .selectPagingDetailDisplay,
        .detailScrollSpeed,
        .selectSlowDetailScrollSpeed,
        .selectNormalDetailScrollSpeed,
        .selectFastDetailScrollSpeed,
        .detailPageSpeed,
        .selectSlowDetailPageSpeed,
        .selectNormalDetailPageSpeed,
        .selectFastDetailPageSpeed,
        .statusBarSectionHeader,
        .toggleStatusBarContent,
        .statusBarPageSpeed,
        .selectSlowStatusBarPageSpeed,
        .selectNormalStatusBarPageSpeed,
        .selectFastStatusBarPageSpeed,
        .togglePause,
        .refreshNow,
        .quit
    ]
}
