import AppKit
import CodexTouchBarCore

@MainActor
protocol MenuBarControllerDelegate: AnyObject {
    func menuBarDidRequestOpenCurrentSession()
    func menuBarDidRequestOpenReadingFile()
    func menuBarDidRequestContinueReading()
    func menuBarDidRequestExitReadingMode()
    func menuBarDidTogglePause()
    func menuBarDidToggleStatusBarContent()
    func menuBarDidSelectAutomaticSession()
    func menuBarDidSelectSession(url: URL)
    func menuBarDidToggleCompletionSpeech()
    func menuBarDidSelectCompletionSpeechVoice(identifier: String?)
    func menuBarDidSelectCompletionSpeechRate(_ rate: CompletionSpeechRate)
    func menuBarDidSelectCompletionSpeechPitch(_ pitch: CompletionSpeechPitch)
    func menuBarDidSelectDetailDisplayMode(_ mode: TouchBarDetailDisplayMode)
    func menuBarDidSelectDetailScrollSpeed(_ speed: DetailDisplaySpeed)
    func menuBarDidSelectDetailPageSpeed(_ speed: DetailDisplaySpeed)
    func menuBarDidSelectStatusBarPageSpeed(_ speed: DetailDisplaySpeed)
    func menuBarDidSelectReadingAutoPageSpeed(_ speed: ReadingAutoPageSpeed)
    func menuBarDidSelectDisplayLanguage(_ language: DisplayLanguage)
    func menuBarDidRequestRefresh()
}

private enum MenuBarStatusBadge {
    case idle
    case thinking
    case running
    case approval
    case completed
    case failed

    init(state: CodexDisplayState) {
        switch TouchBarPetPolicy.mood(for: state, isReading: false) {
        case .idle, .reading, .selecting:
            self = .idle
        case .thinking:
            self = .thinking
        case .running:
            self = .running
        case .approval:
            self = .approval
        case .completed:
            self = .completed
        case .failed:
            self = .failed
        }
    }

    var color: NSColor {
        switch self {
        case .idle: return .systemGray
        case .thinking: return .systemPurple.withAlphaComponent(0.75)
        case .running: return .systemBlue
        case .approval: return .systemOrange
        case .completed: return .systemGreen
        case .failed: return .systemRed
        }
    }

    func label(language: DisplayLanguage) -> String {
        switch (language, self) {
        case (.english, .idle): return "Idle"
        case (.english, .thinking): return "Thinking"
        case (.english, .running): return "Working"
        case (.english, .approval): return "Waiting for approval"
        case (.english, .completed): return "Completed"
        case (.english, .failed): return "Failed"
        case (.simplifiedChinese, .idle): return "空闲"
        case (.simplifiedChinese, .thinking): return "思考中"
        case (.simplifiedChinese, .running): return "执行中"
        case (.simplifiedChinese, .approval): return "等待审批"
        case (.simplifiedChinese, .completed): return "已完成"
        case (.simplifiedChinese, .failed): return "失败"
        }
    }
}

@MainActor
final class MenuBarController {
    weak var delegate: MenuBarControllerDelegate?
    private let isTouchBarAvailable: Bool
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let quotaSectionItem = NSMenuItem(title: "Quota", action: nil, keyEquivalent: "")
    private let quotaSubscriptionItem = NSMenuItem(title: "Subscription: Unavailable", action: nil, keyEquivalent: "")
    private let quotaMainItem = NSMenuItem(title: "Main quota: Unavailable", action: nil, keyEquivalent: "")
    private let quotaResetCreditsItem = NSMenuItem(title: "Available resets: Unavailable", action: nil, keyEquivalent: "")
    private let sessionSectionItem = NSMenuItem(title: "Codex Session", action: nil, keyEquivalent: "")
    private let sessionItem = NSMenuItem(title: "Session: -", action: nil, keyEquivalent: "")
    private let projectItem = NSMenuItem(title: "Project: -", action: nil, keyEquivalent: "")
    private let sessionSwitchItem = NSMenuItem(title: "Switch Session", action: nil, keyEquivalent: "")
    private let readingSectionItem = NSMenuItem(title: "Reading", action: nil, keyEquivalent: "")
    private let touchBarModeItem = NSMenuItem(title: "Touch Bar: Official host window", action: nil, keyEquivalent: "")
    private let readingFileItem = NSMenuItem(title: "Reading File: -", action: nil, keyEquivalent: "")
    private let readingPathItem = NSMenuItem(title: "Reading Path: -", action: nil, keyEquivalent: "")
    private let readingProgressItem = NSMenuItem(title: "Reading Progress: -", action: nil, keyEquivalent: "")
    private let touchBarSectionItem = NSMenuItem(title: "Touch Bar", action: nil, keyEquivalent: "")
    private let statusBarSectionItem = NSMenuItem(title: "Menu Bar", action: nil, keyEquivalent: "")
    private let detailDisplayModeItem = NSMenuItem(title: "Detail Display: Scrolling", action: nil, keyEquivalent: "")
    private let scrollingDetailItem = NSMenuItem(title: "Scrolling", action: #selector(selectScrollingDetailDisplay), keyEquivalent: "")
    private let pagingDetailItem = NSMenuItem(title: "Paging", action: #selector(selectPagingDetailDisplay), keyEquivalent: "")
    private let detailScrollSpeedItem = NSMenuItem(title: "Scrolling Speed: Normal", action: nil, keyEquivalent: "")
    private let slowDetailScrollSpeedItem = NSMenuItem(title: "Slow", action: #selector(selectSlowDetailScrollSpeed), keyEquivalent: "")
    private let normalDetailScrollSpeedItem = NSMenuItem(title: "Normal", action: #selector(selectNormalDetailScrollSpeed), keyEquivalent: "")
    private let fastDetailScrollSpeedItem = NSMenuItem(title: "Fast", action: #selector(selectFastDetailScrollSpeed), keyEquivalent: "")
    private let detailPageSpeedItem = NSMenuItem(title: "Paging Speed: Normal", action: nil, keyEquivalent: "")
    private let slowDetailPageSpeedItem = NSMenuItem(title: "Slow", action: #selector(selectSlowDetailPageSpeed), keyEquivalent: "")
    private let normalDetailPageSpeedItem = NSMenuItem(title: "Normal", action: #selector(selectNormalDetailPageSpeed), keyEquivalent: "")
    private let fastDetailPageSpeedItem = NSMenuItem(title: "Fast", action: #selector(selectFastDetailPageSpeed), keyEquivalent: "")
    private let readingAutoPageSpeedItem = NSMenuItem(title: "Reading Speed: Normal", action: nil, keyEquivalent: "")
    private let slowReadingAutoPageSpeedItem = NSMenuItem(title: "Slow", action: #selector(selectSlowReadingAutoPageSpeed), keyEquivalent: "")
    private let normalReadingAutoPageSpeedItem = NSMenuItem(title: "Normal", action: #selector(selectNormalReadingAutoPageSpeed), keyEquivalent: "")
    private let fastReadingAutoPageSpeedItem = NSMenuItem(title: "Fast", action: #selector(selectFastReadingAutoPageSpeed), keyEquivalent: "")
    private let openCurrentSessionItem = NSMenuItem(title: "Open Current Session", action: #selector(openCurrentSession), keyEquivalent: "o")
    private let completionSpeechItem = NSMenuItem(title: "Read Completion Aloud", action: #selector(toggleCompletionSpeech), keyEquivalent: "")
    private let completionSpeechVoiceItem = NSMenuItem(title: "Voice: Automatic Chinese", action: nil, keyEquivalent: "")
    private let completionSpeechRateItem = NSMenuItem(title: "Speech Rate: Normal", action: nil, keyEquivalent: "")
    private let completionSpeechPitchItem = NSMenuItem(title: "Speech Pitch: Normal", action: nil, keyEquivalent: "")
    private let openReadingFileItem = NSMenuItem(title: "Open Reading File...", action: #selector(openReadingFile), keyEquivalent: "f")
    private let continueReadingItem = NSMenuItem(title: "Continue Reading", action: #selector(continueReading), keyEquivalent: "")
    private let exitReadingModeItem = NSMenuItem(title: "Exit Reading Mode", action: #selector(exitReadingMode), keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Updates", action: #selector(togglePause), keyEquivalent: "p")
    private let statusBarContentItem = NSMenuItem(title: "Show Content in Menu Bar", action: #selector(toggleStatusBarContent), keyEquivalent: "")
    private let statusBarPageSpeedItem = NSMenuItem(title: "Paging Speed: Normal", action: nil, keyEquivalent: "")
    private let slowStatusBarPageSpeedItem = NSMenuItem(title: "Slow", action: #selector(selectSlowStatusBarPageSpeed), keyEquivalent: "")
    private let normalStatusBarPageSpeedItem = NSMenuItem(title: "Normal", action: #selector(selectNormalStatusBarPageSpeed), keyEquivalent: "")
    private let fastStatusBarPageSpeedItem = NSMenuItem(title: "Fast", action: #selector(selectFastStatusBarPageSpeed), keyEquivalent: "")
    private let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
    private let englishLanguageItem = NSMenuItem(title: "English", action: #selector(selectEnglishLanguage), keyEquivalent: "")
    private let chineseLanguageItem = NSMenuItem(title: "简体中文", action: #selector(selectSimplifiedChineseLanguage), keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
    private let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    private var completionSpeechVoiceMenuSignature = ""
    private var completionSpeechRateMenuSelection: CompletionSpeechRate?
    private var completionSpeechPitchMenuSelection: CompletionSpeechPitch?
    private var sessionSwitchMenuSignature = ""
    private var displayLanguage: DisplayLanguage = .english
    private var statusMenu: NSMenu?
    private var statusBarContentPages: [String] = [""]
    private var statusBarContentPageIndex = 0
    private var statusBarContentKey = ""
    private var statusBarPageTimer: Timer?
    private var statusBarPageSpeed: DetailDisplaySpeed = .normal
    private var statusBarBadge: MenuBarStatusBadge = .idle

    init(isTouchBarAvailable: Bool) {
        self.isTouchBarAvailable = isTouchBarAvailable
        let menu = makeMenu()
        statusMenu = menu
        statusItem.menu = menu
        applyStatusBarIcon()
    }

    func apply(
        state: CodexDisplayState,
        quotaSnapshot: CodexQuotaSnapshot,
        language: DisplayLanguage,
        statusBarContentEnabled: Bool,
        statusBarContentText: String,
        statusBarContentKey: String,
        sessions: [CodexSessionFile],
        sessionSelectionMode: CodexSessionSelectionMode,
        paused: Bool,
        detailDisplayMode: TouchBarDetailDisplayMode,
        detailScrollSpeed: DetailDisplaySpeed,
        detailPageSpeed: DetailDisplaySpeed,
        statusBarPageSpeed: DetailDisplaySpeed,
        readingAutoPageSpeed: ReadingAutoPageSpeed,
        alwaysOnStatus: String,
        readingFileName: String?,
        readingFilePath: String?,
        readingProgressTitle: String,
        continueReadingFileName: String?,
        completionSpeechEnabled: Bool,
        completionSpeechVoiceIdentifier: String?,
        completionSpeechVoiceOptions: [CompletionSpeechVoiceOption],
        completionSpeechRate: CompletionSpeechRate,
        completionSpeechPitch: CompletionSpeechPitch
    ) {
        let languageChanged = displayLanguage != language
        displayLanguage = language
        statusBarBadge = MenuBarStatusBadge(state: state)
        if languageChanged {
            completionSpeechVoiceMenuSignature = ""
            completionSpeechRateMenuSelection = nil
            completionSpeechPitchMenuSelection = nil
            sessionSwitchMenuSignature = ""
        }
        updateStatusBarContent(
            isEnabled: statusBarContentEnabled,
            text: statusBarContentText,
            contentKey: statusBarContentKey,
            language: language,
            pageSpeed: statusBarPageSpeed
        )
        updateQuotaItems(snapshot: quotaSnapshot, language: language)
        updateSessionSwitchMenu(sessions: sessions, selectionMode: sessionSelectionMode)
        let readingPresentation = ReadingMenuPresentationPolicy.presentation(
            fileName: readingFileName,
            filePath: readingFilePath,
            progressTitle: readingProgressTitle,
            continueReadingFileName: continueReadingFileName,
            language: language
        )
        updateLocalizedTitles(
            language: language,
            state: state,
            paused: paused,
            detailDisplayMode: detailDisplayMode,
            detailScrollSpeed: detailScrollSpeed,
            detailPageSpeed: detailPageSpeed,
            statusBarPageSpeed: statusBarPageSpeed,
            readingAutoPageSpeed: readingAutoPageSpeed,
            alwaysOnStatus: alwaysOnStatus
        )
        readingFileItem.title = readingPresentation.fileTitle
        readingPathItem.title = readingPresentation.pathTitle
        readingProgressItem.title = readingPresentation.progressTitle
        continueReadingItem.title = readingPresentation.continueReadingTitle
        continueReadingItem.isEnabled = readingPresentation.canContinueReading && !readingPresentation.isReadingActive
        scrollingDetailItem.state = detailDisplayMode == .scrolling ? .on : .off
        pagingDetailItem.state = detailDisplayMode == .paging ? .on : .off
        slowDetailScrollSpeedItem.state = detailScrollSpeed == .slow ? .on : .off
        normalDetailScrollSpeedItem.state = detailScrollSpeed == .normal ? .on : .off
        fastDetailScrollSpeedItem.state = detailScrollSpeed == .fast ? .on : .off
        slowDetailPageSpeedItem.state = detailPageSpeed == .slow ? .on : .off
        normalDetailPageSpeedItem.state = detailPageSpeed == .normal ? .on : .off
        fastDetailPageSpeedItem.state = detailPageSpeed == .fast ? .on : .off
        slowStatusBarPageSpeedItem.state = statusBarPageSpeed == .slow ? .on : .off
        normalStatusBarPageSpeedItem.state = statusBarPageSpeed == .normal ? .on : .off
        fastStatusBarPageSpeedItem.state = statusBarPageSpeed == .fast ? .on : .off
        slowReadingAutoPageSpeedItem.state = readingAutoPageSpeed == .slow ? .on : .off
        normalReadingAutoPageSpeedItem.state = readingAutoPageSpeed == .normal ? .on : .off
        fastReadingAutoPageSpeedItem.state = readingAutoPageSpeed == .fast ? .on : .off
        openCurrentSessionItem.isEnabled = state.sessionId?.isEmpty == false
        completionSpeechItem.state = completionSpeechEnabled ? .on : .off
        updateCompletionSpeechVoiceMenu(
            selectedIdentifier: completionSpeechVoiceIdentifier,
            options: completionSpeechVoiceOptions
        )
        updateCompletionSpeechRateMenu(selectedRate: completionSpeechRate)
        updateCompletionSpeechPitchMenu(selectedPitch: completionSpeechPitch)
        exitReadingModeItem.isEnabled = readingPresentation.isReadingActive
        exitReadingModeItem.isHidden = !readingPresentation.isReadingActive
        statusBarContentItem.state = statusBarContentEnabled ? .on : .off
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        quotaSectionItem.isEnabled = false
        quotaSubscriptionItem.isEnabled = false
        quotaMainItem.isEnabled = false
        quotaResetCreditsItem.isEnabled = false
        sessionSectionItem.isEnabled = false
        readingSectionItem.isEnabled = false
        touchBarSectionItem.isEnabled = false
        statusBarSectionItem.isEnabled = false

        scrollingDetailItem.target = self
        pagingDetailItem.target = self
        slowDetailScrollSpeedItem.target = self
        normalDetailScrollSpeedItem.target = self
        fastDetailScrollSpeedItem.target = self
        slowDetailPageSpeedItem.target = self
        normalDetailPageSpeedItem.target = self
        fastDetailPageSpeedItem.target = self
        slowReadingAutoPageSpeedItem.target = self
        normalReadingAutoPageSpeedItem.target = self
        fastReadingAutoPageSpeedItem.target = self
        openCurrentSessionItem.target = self
        completionSpeechItem.target = self
        openReadingFileItem.target = self
        continueReadingItem.target = self
        exitReadingModeItem.target = self
        pauseItem.target = self
        statusBarContentItem.target = self
        slowStatusBarPageSpeedItem.target = self
        normalStatusBarPageSpeedItem.target = self
        fastStatusBarPageSpeedItem.target = self
        englishLanguageItem.target = self
        chineseLanguageItem.target = self
        refreshItem.target = self
        let languageMenu = NSMenu()
        languageMenu.addItem(englishLanguageItem)
        languageMenu.addItem(chineseLanguageItem)
        languageItem.submenu = languageMenu
        let detailDisplayMenu = NSMenu()
        detailDisplayMenu.addItem(scrollingDetailItem)
        detailDisplayMenu.addItem(pagingDetailItem)
        detailDisplayModeItem.submenu = detailDisplayMenu
        detailScrollSpeedItem.submenu = makeSpeedMenu(
            slowDetailScrollSpeedItem,
            normalDetailScrollSpeedItem,
            fastDetailScrollSpeedItem
        )
        detailPageSpeedItem.submenu = makeSpeedMenu(
            slowDetailPageSpeedItem,
            normalDetailPageSpeedItem,
            fastDetailPageSpeedItem
        )
        let readingSpeedMenu = NSMenu()
        readingSpeedMenu.addItem(slowReadingAutoPageSpeedItem)
        readingSpeedMenu.addItem(normalReadingAutoPageSpeedItem)
        readingSpeedMenu.addItem(fastReadingAutoPageSpeedItem)
        readingAutoPageSpeedItem.submenu = readingSpeedMenu
        statusBarPageSpeedItem.submenu = makeSpeedMenu(
            slowStatusBarPageSpeedItem,
            normalStatusBarPageSpeedItem,
            fastStatusBarPageSpeedItem
        )

        for command in MenuBarMenuPlan.visibleCommands {
            switch command {
            case .quotaSectionHeader:
                menu.addItem(quotaSectionItem)
            case .quotaSubscriptionInfo:
                menu.addItem(quotaSubscriptionItem)
            case .quotaMainInfo:
                menu.addItem(quotaMainItem)
            case .quotaResetCreditsInfo:
                menu.addItem(quotaResetCreditsItem)
                menu.addItem(.separator())
            case .sessionSectionHeader:
                menu.addItem(sessionSectionItem)
            case .sessionInfo:
                menu.addItem(sessionItem)
            case .projectInfo:
                menu.addItem(projectItem)
            case .switchSession:
                menu.addItem(sessionSwitchItem)
            case .openCurrentSession:
                menu.addItem(openCurrentSessionItem)
            case .toggleCompletionSpeech:
                menu.addItem(completionSpeechItem)
            case .completionSpeechVoiceMenu:
                menu.addItem(completionSpeechVoiceItem)
            case .completionSpeechRateMenu:
                menu.addItem(completionSpeechRateItem)
            case .completionSpeechPitchMenu:
                menu.addItem(completionSpeechPitchItem)
            case .readingSectionHeader:
                menu.addItem(.separator())
                menu.addItem(readingSectionItem)
            case .readingFileInfo:
                menu.addItem(readingFileItem)
            case .readingPathInfo:
                menu.addItem(readingPathItem)
            case .readingProgressInfo:
                menu.addItem(readingProgressItem)
            case .openReadingFile:
                menu.addItem(openReadingFileItem)
            case .continueReading:
                menu.addItem(continueReadingItem)
            case .exitReadingMode:
                menu.addItem(exitReadingModeItem)
            case .readingAutoPageSpeedHeader:
                menu.addItem(readingAutoPageSpeedItem)
            case .detailDisplayHeader:
                guard isTouchBarAvailable else { continue }
                menu.addItem(detailDisplayModeItem)
            case .selectScrollingDetailDisplay:
                continue
            case .selectPagingDetailDisplay:
                continue
            case .detailScrollSpeed:
                guard isTouchBarAvailable else { continue }
                menu.addItem(detailScrollSpeedItem)
            case .selectSlowDetailScrollSpeed, .selectNormalDetailScrollSpeed, .selectFastDetailScrollSpeed:
                continue
            case .detailPageSpeed:
                guard isTouchBarAvailable else { continue }
                menu.addItem(detailPageSpeedItem)
            case .selectSlowDetailPageSpeed, .selectNormalDetailPageSpeed, .selectFastDetailPageSpeed:
                continue
            case .selectSlowReadingAutoPageSpeed:
                continue
            case .selectNormalReadingAutoPageSpeed:
                continue
            case .selectFastReadingAutoPageSpeed:
                continue
            case .touchBarSectionHeader:
                guard isTouchBarAvailable else { continue }
                menu.addItem(.separator())
                menu.addItem(touchBarSectionItem)
            case .touchBarModeInfo:
                if isTouchBarAvailable {
                    menu.addItem(touchBarModeItem)
                }
            case .statusBarSectionHeader:
                menu.addItem(.separator())
                menu.addItem(statusBarSectionItem)
            case .toggleStatusBarContent:
                menu.addItem(statusBarContentItem)
                menu.addItem(languageItem)
            case .statusBarPageSpeed:
                menu.addItem(statusBarPageSpeedItem)
            case .selectSlowStatusBarPageSpeed, .selectNormalStatusBarPageSpeed, .selectFastStatusBarPageSpeed:
                continue
            case .togglePause:
                menu.addItem(pauseItem)
            case .refreshNow:
                menu.addItem(refreshItem)
            case .showTouchBarHost:
                continue
            case .quit:
                menu.addItem(.separator())
                menu.addItem(quitItem)
            }
        }
        return menu
    }

    private func makeSpeedMenu(_ slow: NSMenuItem, _ normal: NSMenuItem, _ fast: NSMenuItem) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(slow)
        menu.addItem(normal)
        menu.addItem(fast)
        return menu
    }

    @objc private func togglePause() {
        delegate?.menuBarDidTogglePause()
    }

    @objc private func toggleStatusBarContent() {
        delegate?.menuBarDidToggleStatusBarContent()
    }

    @objc private func openCurrentSession() {
        delegate?.menuBarDidRequestOpenCurrentSession()
    }

    @objc private func selectAutomaticSession() {
        delegate?.menuBarDidSelectAutomaticSession()
    }

    @objc private func selectSession(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        delegate?.menuBarDidSelectSession(url: url)
    }

    @objc private func toggleCompletionSpeech() {
        delegate?.menuBarDidToggleCompletionSpeech()
    }

    @objc private func selectCompletionSpeechVoice(_ sender: NSMenuItem) {
        delegate?.menuBarDidSelectCompletionSpeechVoice(identifier: sender.representedObject as? String)
    }

    @objc private func selectCompletionSpeechRate(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let rate = CompletionSpeechRate(rawValue: rawValue) else {
            return
        }
        delegate?.menuBarDidSelectCompletionSpeechRate(rate)
    }

    @objc private func selectCompletionSpeechPitch(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let pitch = CompletionSpeechPitch(rawValue: rawValue) else {
            return
        }
        delegate?.menuBarDidSelectCompletionSpeechPitch(pitch)
    }

    @objc private func openReadingFile() {
        delegate?.menuBarDidRequestOpenReadingFile()
    }

    @objc private func continueReading() {
        delegate?.menuBarDidRequestContinueReading()
    }

    @objc private func exitReadingMode() {
        delegate?.menuBarDidRequestExitReadingMode()
    }

    @objc private func selectScrollingDetailDisplay() {
        delegate?.menuBarDidSelectDetailDisplayMode(.scrolling)
    }

    @objc private func selectPagingDetailDisplay() {
        delegate?.menuBarDidSelectDetailDisplayMode(.paging)
    }

    @objc private func selectSlowDetailScrollSpeed() {
        delegate?.menuBarDidSelectDetailScrollSpeed(.slow)
    }

    @objc private func selectNormalDetailScrollSpeed() {
        delegate?.menuBarDidSelectDetailScrollSpeed(.normal)
    }

    @objc private func selectFastDetailScrollSpeed() {
        delegate?.menuBarDidSelectDetailScrollSpeed(.fast)
    }

    @objc private func selectSlowDetailPageSpeed() {
        delegate?.menuBarDidSelectDetailPageSpeed(.slow)
    }

    @objc private func selectNormalDetailPageSpeed() {
        delegate?.menuBarDidSelectDetailPageSpeed(.normal)
    }

    @objc private func selectFastDetailPageSpeed() {
        delegate?.menuBarDidSelectDetailPageSpeed(.fast)
    }

    @objc private func selectSlowStatusBarPageSpeed() {
        delegate?.menuBarDidSelectStatusBarPageSpeed(.slow)
    }

    @objc private func selectNormalStatusBarPageSpeed() {
        delegate?.menuBarDidSelectStatusBarPageSpeed(.normal)
    }

    @objc private func selectFastStatusBarPageSpeed() {
        delegate?.menuBarDidSelectStatusBarPageSpeed(.fast)
    }

    @objc private func selectSlowReadingAutoPageSpeed() {
        delegate?.menuBarDidSelectReadingAutoPageSpeed(.slow)
    }

    @objc private func selectNormalReadingAutoPageSpeed() {
        delegate?.menuBarDidSelectReadingAutoPageSpeed(.normal)
    }

    @objc private func selectFastReadingAutoPageSpeed() {
        delegate?.menuBarDidSelectReadingAutoPageSpeed(.fast)
    }

    @objc private func selectEnglishLanguage() {
        delegate?.menuBarDidSelectDisplayLanguage(.english)
    }

    @objc private func selectSimplifiedChineseLanguage() {
        delegate?.menuBarDidSelectDisplayLanguage(.simplifiedChinese)
    }

    @objc private func refreshNow() {
        delegate?.menuBarDidRequestRefresh()
    }

    private func updateStatusBarContent(
        isEnabled: Bool,
        text: String,
        contentKey: String,
        language: DisplayLanguage,
        pageSpeed: DetailDisplaySpeed
    ) {
        guard isEnabled else {
            stopStatusBarPageTimer()
            statusBarContentKey = ""
            applyStatusBarIcon()
            return
        }

        let pageSpeedChanged = statusBarPageSpeed != pageSpeed
        statusBarPageSpeed = pageSpeed
        if statusBarContentKey != contentKey || pageSpeedChanged {
            statusBarContentKey = contentKey
            statusBarContentPages = statusBarContentPages(for: text)
            statusBarContentPageIndex = 0
            startStatusBarPageTimer()
        }
        applyStatusBarContentPage(language: language)
    }

    private func applyStatusBarIcon() {
        guard let button = statusItem.button else { return }
        statusItem.menu = statusMenu
        button.target = nil
        button.action = nil
        button.title = ""
        button.image = Self.statusBarIcon(badgeColor: statusBarBadge.color)
        button.imagePosition = .imageOnly
        button.toolTip = statusBarBadge.label(language: displayLanguage)
    }

    private func applyStatusBarContentPage(language: DisplayLanguage? = nil) {
        guard let button = statusItem.button else { return }
        let currentLanguage = language ?? displayLanguage
        let page = statusBarContentPages[statusBarContentPageIndex]
        statusItem.menu = statusMenu
        button.target = nil
        button.action = nil
        button.title = page
        button.image = Self.statusBarIcon(badgeColor: statusBarBadge.color)
        button.imagePosition = .imageRight
        button.font = NSFont.menuBarFont(ofSize: 13)
        button.lineBreakMode = .byTruncatingTail
        let status = statusBarBadge.label(language: currentLanguage)
        button.toolTip = statusBarContentPages.count > 1
            ? "\(status) · \(statusBarContentPageIndex + 1)/\(statusBarContentPages.count)"
            : status
    }

    private func startStatusBarPageTimer() {
        stopStatusBarPageTimer()
        guard statusBarContentPages.count > 1 else { return }
        statusBarPageTimer = Timer.scheduledTimer(
            withTimeInterval: statusBarPageSpeed.pageIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.statusBarContentPageIndex = TouchBarPagePolicy.nextPageIndex(
                    currentIndex: self.statusBarContentPageIndex,
                    pageCount: self.statusBarContentPages.count
                )
                self.applyStatusBarContentPage()
            }
        }
    }

    private func stopStatusBarPageTimer() {
        statusBarPageTimer?.invalidate()
        statusBarPageTimer = nil
    }

    private func statusBarContentPages(for text: String) -> [String] {
        let font = NSFont.menuBarFont(ofSize: 13)
        return TouchBarPagePolicy.pages(for: text, maxWidth: 272) { page in
            (page as NSString).size(withAttributes: [.font: font]).width
        }
    }

    private func updateSessionSwitchMenu(
        sessions: [CodexSessionFile],
        selectionMode: CodexSessionSelectionMode
    ) {
        let recentSessions = Array(sessions.prefix(10))
        let signature = CodexSessionSelectorSignature.value(
            sessions: recentSessions,
            selectionMode: selectionMode
        )
        guard signature != sessionSwitchMenuSignature else { return }
        sessionSwitchMenuSignature = signature

        let menu = NSMenu()
        let automaticItem = NSMenuItem(title: "AUTO", action: #selector(selectAutomaticSession), keyEquivalent: "")
        automaticItem.target = self
        automaticItem.state = selectionMode == .automaticLatest ? .on : .off
        menu.addItem(automaticItem)

        if !recentSessions.isEmpty {
            menu.addItem(.separator())
        }

        for session in recentSessions {
            let item = NSMenuItem(title: session.displayName, action: #selector(selectSession(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = session.url
            if case .locked(let url) = selectionMode, url == session.url {
                item.state = .on
            }
            menu.addItem(item)
        }

        sessionSwitchItem.submenu = menu
        sessionSwitchItem.isEnabled = true
    }

    private func updateQuotaItems(snapshot: CodexQuotaSnapshot, language: DisplayLanguage) {
        let isEnglish = language == .english
        let unavailable = isEnglish ? "Unavailable" : "不可用"
        let separator = localizedLabelSeparator()
        quotaSectionItem.title = isEnglish ? "Quota" : "额度"
        let plan = snapshot.planType?.trimmingCharacters(in: .whitespacesAndNewlines)
        quotaSubscriptionItem.title = "\(isEnglish ? "Subscription" : "订阅")\(separator)\(plan?.isEmpty == false ? plan!.capitalized : unavailable)"

        if let usedPercent = snapshot.mainUsedPercent,
           let resetsAt = snapshot.mainResetsAt {
            let label = isEnglish ? "Main quota" : "主额度"
            let used = isEnglish ? "\(usedPercent)% used" : "已用 \(usedPercent)%"
            let reset = isEnglish ? "Resets \(localizedQuotaDate(resetsAt, language: language))" : "重置时间：\(localizedQuotaDate(resetsAt, language: language))"
            quotaMainItem.title = "\(label)\(separator)\(used) · \(reset)"
        } else {
            quotaMainItem.title = "\(isEnglish ? "Main quota" : "主额度")\(separator)\(unavailable)"
        }

        if let count = snapshot.availableResetCount {
            let label = isEnglish ? "Available resets" : "可用重置"
            let amount = isEnglish ? "\(count)" : "\(count) 次"
            if let expiresAt = snapshot.availableResetExpiresAt {
                let expiration = isEnglish ? "Expires \(localizedQuotaDate(expiresAt, language: language))" : "到期于 \(localizedQuotaDate(expiresAt, language: language))"
                quotaResetCreditsItem.title = "\(label)\(separator)\(amount) · \(expiration)"
            } else {
                quotaResetCreditsItem.title = "\(label)\(separator)\(amount)"
            }
        } else {
            quotaResetCreditsItem.title = "\(isEnglish ? "Available resets" : "可用重置")\(separator)\(unavailable)"
        }
    }

    private func localizedQuotaDate(_ date: Date, language: DisplayLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .english ? "en_US" : "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func statusBarIcon(badgeColor: NSColor? = nil) -> NSImage {
        let size = NSSize(width: 24, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.labelColor.setStroke()
        NSColor.labelColor.setFill()

        let barPath = NSBezierPath(roundedRect: NSRect(x: 0.8, y: 3, width: 20.4, height: 12), xRadius: 6, yRadius: 6)
        barPath.lineWidth = 1.4
        barPath.stroke()

        let cursorPath = NSBezierPath(roundedRect: NSRect(x: 6.3, y: 5.4, width: 2.8, height: 7.2), xRadius: 1.4, yRadius: 1.4)
        cursorPath.fill()

        let dotDiameter: CGFloat = 2.9
        for x in [12.3, 15.7] as [CGFloat] {
            NSBezierPath(ovalIn: NSRect(x: x, y: 7.05, width: dotDiameter, height: dotDiameter)).fill()
        }

        if let badgeColor {
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 17.1, y: 0.1, width: 6.2, height: 6.2)).fill()
            badgeColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 18.1, y: 1.1, width: 4.2, height: 4.2)).fill()
        }

        image.unlockFocus()
        image.isTemplate = badgeColor == nil
        return image
    }

    private func updateCompletionSpeechVoiceMenu(
        selectedIdentifier: String?,
        options: [CompletionSpeechVoiceOption]
    ) {
        let signature = makeCompletionSpeechVoiceMenuSignature(
            selectedIdentifier: selectedIdentifier,
            options: options
        )
        guard signature != completionSpeechVoiceMenuSignature else { return }
        completionSpeechVoiceMenuSignature = signature

        let sortedOptions = CompletionSpeechVoicePolicy.sortedVoiceOptions(options)
        let activeIdentifier = CompletionSpeechVoicePolicy.selectedVoiceIdentifier(
            from: options,
            preferredIdentifier: selectedIdentifier
        )
        let activeVoiceName = sortedOptions.first(where: { $0.identifier == activeIdentifier })?.name
        let automaticVoice = displayLanguage == .english ? "Automatic Chinese" : "自动中文"
        let selectedVoice = displayLanguage == .english ? "Selected" : "已选择"
        completionSpeechVoiceItem.title = "\(displayLanguage == .english ? "Voice" : "语音")\(localizedLabelSeparator())\(selectedIdentifier == nil ? automaticVoice : activeVoiceName ?? selectedVoice)"

        let submenu = NSMenu()
        let automaticItem = NSMenuItem(
            title: automaticVoice,
            action: #selector(selectCompletionSpeechVoice(_:)),
            keyEquivalent: ""
        )
        automaticItem.target = self
        automaticItem.state = selectedIdentifier == nil ? .on : .off
        submenu.addItem(automaticItem)

        if !sortedOptions.isEmpty {
            submenu.addItem(.separator())
        }

        for option in sortedOptions {
            let item = NSMenuItem(
                title: "\(option.name) (\(option.language))",
                action: #selector(selectCompletionSpeechVoice(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = option.identifier
            item.state = option.identifier == selectedIdentifier ? .on : .off
            submenu.addItem(item)
        }

        completionSpeechVoiceItem.submenu = submenu
    }

    private func updateCompletionSpeechRateMenu(selectedRate: CompletionSpeechRate) {
        guard completionSpeechRateMenuSelection != selectedRate else { return }
        completionSpeechRateMenuSelection = selectedRate
        completionSpeechRateItem.title = "\(displayLanguage == .english ? "Speech Rate" : "朗读语速")\(localizedLabelSeparator())\(localizedSpeechRate(selectedRate))"
        let submenu = NSMenu()
        for rate in CompletionSpeechRate.allCases {
            let item = NSMenuItem(
                title: localizedSpeechRate(rate),
                action: #selector(selectCompletionSpeechRate(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = rate.rawValue
            item.state = rate == selectedRate ? .on : .off
            submenu.addItem(item)
        }
        completionSpeechRateItem.submenu = submenu
    }

    private func updateCompletionSpeechPitchMenu(selectedPitch: CompletionSpeechPitch) {
        guard completionSpeechPitchMenuSelection != selectedPitch else { return }
        completionSpeechPitchMenuSelection = selectedPitch
        completionSpeechPitchItem.title = "\(displayLanguage == .english ? "Speech Pitch" : "朗读音调")\(localizedLabelSeparator())\(localizedSpeechPitch(selectedPitch))"
        let submenu = NSMenu()
        for pitch in CompletionSpeechPitch.allCases {
            let item = NSMenuItem(
                title: localizedSpeechPitch(pitch),
                action: #selector(selectCompletionSpeechPitch(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = pitch.rawValue
            item.state = pitch == selectedPitch ? .on : .off
            submenu.addItem(item)
        }
        completionSpeechPitchItem.submenu = submenu
    }

    private func makeCompletionSpeechVoiceMenuSignature(
        selectedIdentifier: String?,
        options: [CompletionSpeechVoiceOption]
    ) -> String {
        let voiceSignature = options
            .map { "\($0.identifier)|\($0.name)|\($0.language)|\($0.qualityRank)" }
            .joined(separator: "\n")
        return "\(selectedIdentifier ?? "<automatic>")\n\(voiceSignature)"
    }

    private func updateLocalizedTitles(
        language: DisplayLanguage,
        state: CodexDisplayState,
        paused: Bool,
        detailDisplayMode: TouchBarDetailDisplayMode,
        detailScrollSpeed: DetailDisplaySpeed,
        detailPageSpeed: DetailDisplaySpeed,
        statusBarPageSpeed: DetailDisplaySpeed,
        readingAutoPageSpeed: ReadingAutoPageSpeed,
        alwaysOnStatus: String
    ) {
        let isEnglish = language == .english
        sessionSectionItem.title = isEnglish ? "Codex Session" : "Codex 会话"
        sessionItem.title = "\(isEnglish ? "Session" : "会话")\(localizedLabelSeparator())\(state.sessionId ?? "-")"
        projectItem.title = "\(isEnglish ? "Project" : "项目")\(localizedLabelSeparator())\(state.projectPath.isEmpty ? "-" : state.projectPath)"
        sessionSwitchItem.title = isEnglish ? "Switch Session" : "切换会话"
        readingSectionItem.title = isEnglish ? "Reading" : "阅读"
        touchBarSectionItem.title = "Touch Bar"
        touchBarModeItem.title = "Touch Bar\(localizedLabelSeparator())\(alwaysOnStatus)"
        statusBarSectionItem.title = isEnglish ? "Menu Bar" : "状态栏"
        statusBarContentItem.title = isEnglish ? "Show Content in Menu Bar" : "在状态栏显示正文"
        detailDisplayModeItem.title = "\(isEnglish ? "Detail Display" : "正文显示")\(localizedLabelSeparator())\(localizedDetailDisplayMode(detailDisplayMode))"
        scrollingDetailItem.title = localizedDetailDisplayMode(.scrolling)
        pagingDetailItem.title = localizedDetailDisplayMode(.paging)
        detailScrollSpeedItem.title = "\(isEnglish ? "Scrolling Speed" : "滚动速度")\(localizedLabelSeparator())\(localizedDetailDisplaySpeed(detailScrollSpeed))"
        slowDetailScrollSpeedItem.title = localizedDetailDisplaySpeed(.slow)
        normalDetailScrollSpeedItem.title = localizedDetailDisplaySpeed(.normal)
        fastDetailScrollSpeedItem.title = localizedDetailDisplaySpeed(.fast)
        detailPageSpeedItem.title = "\(isEnglish ? "Paging Speed" : "翻页速度")\(localizedLabelSeparator())\(localizedDetailDisplaySpeed(detailPageSpeed))"
        slowDetailPageSpeedItem.title = localizedDetailDisplaySpeed(.slow)
        normalDetailPageSpeedItem.title = localizedDetailDisplaySpeed(.normal)
        fastDetailPageSpeedItem.title = localizedDetailDisplaySpeed(.fast)
        statusBarPageSpeedItem.title = "\(isEnglish ? "Paging Speed" : "翻页速度")\(localizedLabelSeparator())\(localizedDetailDisplaySpeed(statusBarPageSpeed))"
        slowStatusBarPageSpeedItem.title = localizedDetailDisplaySpeed(.slow)
        normalStatusBarPageSpeedItem.title = localizedDetailDisplaySpeed(.normal)
        fastStatusBarPageSpeedItem.title = localizedDetailDisplaySpeed(.fast)
        readingAutoPageSpeedItem.title = "\(isEnglish ? "Reading Speed" : "阅读速度")\(localizedLabelSeparator())\(localizedReadingAutoPageSpeed(readingAutoPageSpeed))"
        slowReadingAutoPageSpeedItem.title = localizedReadingAutoPageSpeed(.slow)
        normalReadingAutoPageSpeedItem.title = localizedReadingAutoPageSpeed(.normal)
        fastReadingAutoPageSpeedItem.title = localizedReadingAutoPageSpeed(.fast)
        openCurrentSessionItem.title = isEnglish ? "Open Current Session" : "打开当前会话"
        completionSpeechItem.title = isEnglish ? "Read Completion Aloud" : "完成后自动朗读"
        openReadingFileItem.title = isEnglish ? "Open Reading File..." : "打开阅读文件..."
        exitReadingModeItem.title = isEnglish ? "Exit Reading Mode" : "退出阅读模式"
        languageItem.title = isEnglish ? "Language" : "语言"
        englishLanguageItem.title = "English"
        chineseLanguageItem.title = "简体中文"
        englishLanguageItem.state = language == .english ? .on : .off
        chineseLanguageItem.state = language == .simplifiedChinese ? .on : .off
        pauseItem.title = paused ? (isEnglish ? "Resume Updates" : "继续更新") : (isEnglish ? "Pause Updates" : "暂停更新")
        refreshItem.title = isEnglish ? "Refresh Now" : "立即刷新"
        quitItem.title = isEnglish ? "Quit" : "退出"
    }

    private func localizedDetailDisplayMode(_ mode: TouchBarDetailDisplayMode) -> String {
        switch (displayLanguage, mode) {
        case (.english, .scrolling): return "Scrolling"
        case (.english, .paging): return "Paging"
        case (.simplifiedChinese, .scrolling): return "滚动"
        case (.simplifiedChinese, .paging): return "翻页"
        }
    }

    private func localizedLabelSeparator() -> String {
        displayLanguage == .english ? ": " : "："
    }

    private func localizedReadingAutoPageSpeed(_ speed: ReadingAutoPageSpeed) -> String {
        switch (displayLanguage, speed) {
        case (.english, .slow): return "Slow"
        case (.english, .normal): return "Normal"
        case (.english, .fast): return "Fast"
        case (.simplifiedChinese, .slow): return "慢"
        case (.simplifiedChinese, .normal): return "正常"
        case (.simplifiedChinese, .fast): return "快"
        }
    }

    private func localizedDetailDisplaySpeed(_ speed: DetailDisplaySpeed) -> String {
        switch (displayLanguage, speed) {
        case (.english, .slow): return "Slow"
        case (.english, .normal): return "Normal"
        case (.english, .fast): return "Fast"
        case (.simplifiedChinese, .slow): return "慢"
        case (.simplifiedChinese, .normal): return "正常"
        case (.simplifiedChinese, .fast): return "快"
        }
    }

    private func localizedSpeechRate(_ rate: CompletionSpeechRate) -> String {
        switch (displayLanguage, rate) {
        case (.english, .slow): return "Slow"
        case (.english, .normal): return "Normal"
        case (.english, .fast): return "Fast"
        case (.simplifiedChinese, .slow): return "慢"
        case (.simplifiedChinese, .normal): return "正常"
        case (.simplifiedChinese, .fast): return "快"
        }
    }

    private func localizedSpeechPitch(_ pitch: CompletionSpeechPitch) -> String {
        switch (displayLanguage, pitch) {
        case (.english, .lower): return "Lower"
        case (.english, .normal): return "Normal"
        case (.english, .higher): return "Higher"
        case (.simplifiedChinese, .lower): return "低"
        case (.simplifiedChinese, .normal): return "正常"
        case (.simplifiedChinese, .higher): return "高"
        }
    }
}
