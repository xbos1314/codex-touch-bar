import AppKit
import CodexTouchBarCore

@MainActor
protocol MenuBarControllerDelegate: AnyObject {
    func menuBarDidRequestOpenCurrentSession()
    func menuBarDidRequestOpenReadingFile()
    func menuBarDidRequestContinueReading()
    func menuBarDidRequestExitReadingMode()
    func menuBarDidTogglePause()
    func menuBarDidToggleAlwaysOn()
    func menuBarDidToggleCompletionSpeech()
    func menuBarDidSelectCompletionSpeechVoice(identifier: String?)
    func menuBarDidSelectCompletionSpeechRate(_ rate: CompletionSpeechRate)
    func menuBarDidSelectCompletionSpeechPitch(_ pitch: CompletionSpeechPitch)
    func menuBarDidSelectDetailDisplayMode(_ mode: TouchBarDetailDisplayMode)
    func menuBarDidSelectReadingAutoPageSpeed(_ speed: ReadingAutoPageSpeed)
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
    private let alwaysOnItem = NSMenuItem(title: "Experimental Always-On Touch Bar", action: #selector(toggleAlwaysOn), keyEquivalent: "a")
    private let pauseItem = NSMenuItem(title: "Pause Updates", action: #selector(togglePause), keyEquivalent: "p")
    private var completionSpeechVoiceMenuSignature = ""
    private var completionSpeechRateMenuSelection: CompletionSpeechRate?
    private var completionSpeechPitchMenuSelection: CompletionSpeechPitch?

    init() {
        statusItem.button?.title = ""
        statusItem.button?.image = Self.statusBarIcon()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Codex Touch Bar"
        statusItem.menu = makeMenu()
    }

    func apply(
        state: CodexDisplayState,
        paused: Bool,
        presentationMode: TouchBarPresentationMode,
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
        let readingPresentation = ReadingMenuPresentationPolicy.presentation(
            fileName: readingFileName,
            filePath: readingFilePath,
            progressTitle: readingProgressTitle,
            continueReadingFileName: continueReadingFileName
        )
        sessionItem.title = "Session: \(state.sessionId ?? "-")"
        projectItem.title = "Project: \(state.projectPath.isEmpty ? "-" : state.projectPath)"
        touchBarModeItem.title = "Touch Bar: \(alwaysOnStatus)"
        readingFileItem.title = readingPresentation.fileTitle
        readingPathItem.title = readingPresentation.pathTitle
        readingProgressItem.title = readingPresentation.progressTitle
        continueReadingItem.title = readingPresentation.continueReadingTitle
        continueReadingItem.isEnabled = readingPresentation.canContinueReading && !readingPresentation.isReadingActive
        detailDisplayModeItem.title = "Detail Display: \(detailDisplayMode.menuText)"
        readingAutoPageSpeedItem.title = "Reading Speed: \(readingAutoPageSpeed.menuText)"
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
        alwaysOnItem.state = presentationMode == .experimentalAlwaysOn ? .on : .off
        pauseItem.title = paused ? "Resume Updates" : "Pause Updates"
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        sessionSectionItem.isEnabled = false
        readingSectionItem.isEnabled = false
        touchBarSectionItem.isEnabled = false

        alwaysOnItem.target = self
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
        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

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
                menu.addItem(.separator())
            case .toggleAlwaysOn:
                menu.addItem(alwaysOnItem)
            case .detailDisplayHeader:
                menu.addItem(detailDisplayModeItem)
            case .selectScrollingDetailDisplay:
                menu.addItem(scrollingDetailItem)
            case .selectPagingDetailDisplay:
                menu.addItem(pagingDetailItem)
            case .readingAutoPageSpeedHeader:
                menu.addItem(.separator())
                menu.addItem(readingAutoPageSpeedItem)
            case .selectSlowReadingAutoPageSpeed:
                menu.addItem(slowReadingAutoPageSpeedItem)
            case .selectNormalReadingAutoPageSpeed:
                menu.addItem(normalReadingAutoPageSpeedItem)
            case .selectFastReadingAutoPageSpeed:
                menu.addItem(fastReadingAutoPageSpeedItem)
            case .touchBarSectionHeader:
                menu.addItem(.separator())
                menu.addItem(touchBarSectionItem)
            case .touchBarModeInfo:
                menu.addItem(touchBarModeItem)
            case .togglePause:
                menu.addItem(pauseItem)
            case .refreshNow:
                menu.addItem(refresh)
            case .showTouchBarHost:
                continue
            case .quit:
                menu.addItem(.separator())
                menu.addItem(quit)
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

    @objc private func toggleAlwaysOn() {
        delegate?.menuBarDidToggleAlwaysOn()
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
        completionSpeechVoiceItem.title = "Voice: \(selectedIdentifier == nil ? "Automatic Chinese" : activeVoiceName ?? "Selected")"

        let submenu = NSMenu()
        let automaticItem = NSMenuItem(
            title: "Automatic Chinese",
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
        completionSpeechRateItem.title = "Speech Rate: \(selectedRate.menuText)"
        let submenu = NSMenu()
        for rate in CompletionSpeechRate.allCases {
            let item = NSMenuItem(
                title: rate.menuText,
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
        completionSpeechPitchItem.title = "Speech Pitch: \(selectedPitch.menuText)"
        let submenu = NSMenu()
        for pitch in CompletionSpeechPitch.allCases {
            let item = NSMenuItem(
                title: pitch.menuText,
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
}
