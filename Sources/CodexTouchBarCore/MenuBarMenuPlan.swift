public enum MenuBarCommand: Equatable, Sendable {
    case sessionSectionHeader
    case sessionInfo
    case projectInfo
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
    case touchBarSectionHeader
    case touchBarModeInfo
    case toggleAlwaysOn
    case detailDisplayHeader
    case selectScrollingDetailDisplay
    case selectPagingDetailDisplay
    case readingAutoPageSpeedHeader
    case selectSlowReadingAutoPageSpeed
    case selectNormalReadingAutoPageSpeed
    case selectFastReadingAutoPageSpeed
    case togglePause
    case refreshNow
    case showTouchBarHost
    case quit
}

public enum MenuBarMenuPlan {
    public static let visibleCommands: [MenuBarCommand] = [
        .sessionSectionHeader,
        .sessionInfo,
        .projectInfo,
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
        .toggleAlwaysOn,
        .detailDisplayHeader,
        .selectScrollingDetailDisplay,
        .selectPagingDetailDisplay,
        .togglePause,
        .refreshNow,
        .quit
    ]
}
