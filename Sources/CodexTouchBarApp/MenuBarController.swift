import AppKit
import CodexTouchBarCore

@MainActor
protocol MenuBarControllerDelegate: AnyObject {
    func menuBarDidRequestOpenCurrentSession()
    func menuBarDidRequestOpenReadingFile()
    func menuBarDidRequestContinueReading()
    func menuBarDidRequestExitReadingMode()
    func menuBarDidTogglePause()
    func menuBarDidToggleCompletionSpeech()
    func menuBarDidSelectCompletionSpeechVoice(identifier: String?)
    func menuBarDidSelectCompletionSpeechRate(_ rate: CompletionSpeechRate)
    func menuBarDidSelectCompletionSpeechPitch(_ pitch: CompletionSpeechPitch)
    func menuBarDidSelectDetailDisplayMode(_ mode: TouchBarDetailDisplayMode)
    func menuBarDidSelectReadingAutoPageSpeed(_ speed: ReadingAutoPageSpeed)
    func menuBarDidSelectDisplayLanguage(_ language: DisplayLanguage)
    func menuBarDidRequestRefresh()
}

@MainActor
final class MenuBarController {
    weak var delegate: MenuBarControllerDelegate?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let sessionSectionItem = NSMenuItem(title: "Codex Session", action: nil, keyEquivalent: "")
    private let sessionItem = NSMenuItem(title: "Session: -", action: nil, keyEquivalent: "")
    private let projectItem = NSMenuItem(title: "Project: -", action: nil, keyEquivalent: "")
    private let readingSectionItem = NSMenuItem(title: "Reading", action: nil, keyEquivalent: "")
    private let touchBarModeItem = NSMenuItem(title: "Touch Bar: Official host window", action: nil, keyEquivalent: "")
    private let readingFileItem = NSMenuItem(title: "Reading File: -", action: nil, keyEquivalent: "")
    private let readingPathItem = NSMenuItem(title: "Reading Path: -", action: nil, keyEquivalent: "")
    private let readingProgressItem = NSMenuItem(title: "Reading Progress: -", action: nil, keyEquivalent: "")
    private let touchBarSectionItem = NSMenuItem(title: "Touch Bar", action: nil, keyEquivalent: "")
    private let detailDisplayModeItem = NSMenuItem(title: "Detail Display: Scrolling", action: nil, keyEquivalent: "")
    private let scrollingDetailItem = NSMenuItem(title: "Scrolling", action: #selector(selectScrollingDetailDisplay), keyEquivalent: "")
    private let pagingDetailItem = NSMenuItem(title: "Paging", action: #selector(selectPagingDetailDisplay), keyEquivalent: "")
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
    private let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
    private let englishLanguageItem = NSMenuItem(title: "English", action: #selector(selectEnglishLanguage), keyEquivalent: "")
    private let chineseLanguageItem = NSMenuItem(title: "简体中文", action: #selector(selectSimplifiedChineseLanguage), keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
    private let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    private var completionSpeechVoiceMenuSignature = ""
    private var completionSpeechRateMenuSelection: CompletionSpeechRate?
    private var completionSpeechPitchMenuSelection: CompletionSpeechPitch?
    private var displayLanguage: DisplayLanguage = .english

    init() {
        statusItem.button?.title = ""
        statusItem.button?.image = Self.statusBarIcon()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Codex Touch Bar"
        statusItem.menu = makeMenu()
    }

    func apply(
        state: CodexDisplayState,
        language: DisplayLanguage,
        paused: Bool,
        detailDisplayMode: TouchBarDetailDisplayMode,
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
        if languageChanged {
            completionSpeechVoiceMenuSignature = ""
            completionSpeechRateMenuSelection = nil
            completionSpeechPitchMenuSelection = nil
        }
        let readingPresentation = ReadingMenuPresentationPolicy.presentation(
            fileName: readingFileName,
            filePath: readingFilePath,
            progressTitle: readingProgressTitle,
            continueReadingFileName: continueReadingFileName,
            language: language
        )
        updateLocalizedTitles(language: language, state: state, paused: paused, detailDisplayMode: detailDisplayMode, readingAutoPageSpeed: readingAutoPageSpeed, alwaysOnStatus: alwaysOnStatus)
        readingFileItem.title = readingPresentation.fileTitle
        readingPathItem.title = readingPresentation.pathTitle
        readingProgressItem.title = readingPresentation.progressTitle
        continueReadingItem.title = readingPresentation.continueReadingTitle
        continueReadingItem.isEnabled = readingPresentation.canContinueReading && !readingPresentation.isReadingActive
        scrollingDetailItem.state = detailDisplayMode == .scrolling ? .on : .off
        pagingDetailItem.state = detailDisplayMode == .paging ? .on : .off
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
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        sessionSectionItem.isEnabled = false
        readingSectionItem.isEnabled = false
        touchBarSectionItem.isEnabled = false

        scrollingDetailItem.target = self
        pagingDetailItem.target = self
        slowReadingAutoPageSpeedItem.target = self
        normalReadingAutoPageSpeedItem.target = self
        fastReadingAutoPageSpeedItem.target = self
        openCurrentSessionItem.target = self
        completionSpeechItem.target = self
        openReadingFileItem.target = self
        continueReadingItem.target = self
        exitReadingModeItem.target = self
        pauseItem.target = self
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
        let readingSpeedMenu = NSMenu()
        readingSpeedMenu.addItem(slowReadingAutoPageSpeedItem)
        readingSpeedMenu.addItem(normalReadingAutoPageSpeedItem)
        readingSpeedMenu.addItem(fastReadingAutoPageSpeedItem)
        readingAutoPageSpeedItem.submenu = readingSpeedMenu

        for command in MenuBarMenuPlan.visibleCommands {
            switch command {
            case .sessionSectionHeader:
                menu.addItem(sessionSectionItem)
            case .sessionInfo:
                menu.addItem(sessionItem)
            case .projectInfo:
                menu.addItem(projectItem)
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
                menu.addItem(detailDisplayModeItem)
            case .selectScrollingDetailDisplay:
                continue
            case .selectPagingDetailDisplay:
                continue
            case .selectSlowReadingAutoPageSpeed:
                continue
            case .selectNormalReadingAutoPageSpeed:
                continue
            case .selectFastReadingAutoPageSpeed:
                continue
            case .touchBarSectionHeader:
                menu.addItem(.separator())
                menu.addItem(touchBarSectionItem)
            case .touchBarModeInfo:
                menu.addItem(touchBarModeItem)
                menu.addItem(languageItem)
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

    @objc private func togglePause() {
        delegate?.menuBarDidTogglePause()
    }

    @objc private func openCurrentSession() {
        delegate?.menuBarDidRequestOpenCurrentSession()
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

    private static func statusBarIcon() -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let barPath = NSBezierPath(roundedRect: NSRect(x: 0.8, y: 3, width: 20.4, height: 12), xRadius: 6, yRadius: 6)
        barPath.lineWidth = 1.4
        barPath.stroke()

        let cursorPath = NSBezierPath(roundedRect: NSRect(x: 6.3, y: 5.4, width: 2.8, height: 7.2), xRadius: 1.4, yRadius: 1.4)
        cursorPath.fill()

        let dotDiameter: CGFloat = 2.9
        for x in [12.3, 15.7] as [CGFloat] {
            NSBezierPath(ovalIn: NSRect(x: x, y: 7.05, width: dotDiameter, height: dotDiameter)).fill()
        }

        image.unlockFocus()
        image.isTemplate = true
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
        readingAutoPageSpeed: ReadingAutoPageSpeed,
        alwaysOnStatus: String
    ) {
        let isEnglish = language == .english
        sessionSectionItem.title = isEnglish ? "Codex Session" : "Codex 会话"
        sessionItem.title = "\(isEnglish ? "Session" : "会话")\(localizedLabelSeparator())\(state.sessionId ?? "-")"
        projectItem.title = "\(isEnglish ? "Project" : "项目")\(localizedLabelSeparator())\(state.projectPath.isEmpty ? "-" : state.projectPath)"
        readingSectionItem.title = isEnglish ? "Reading" : "阅读"
        touchBarSectionItem.title = "Touch Bar"
        touchBarModeItem.title = "Touch Bar\(localizedLabelSeparator())\(alwaysOnStatus)"
        detailDisplayModeItem.title = "\(isEnglish ? "Detail Display" : "正文显示")\(localizedLabelSeparator())\(localizedDetailDisplayMode(detailDisplayMode))"
        scrollingDetailItem.title = localizedDetailDisplayMode(.scrolling)
        pagingDetailItem.title = localizedDetailDisplayMode(.paging)
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
