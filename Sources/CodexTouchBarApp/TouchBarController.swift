import AppKit
import AVFoundation
import CodexTouchBarCore

@MainActor
protocol TouchBarControllerDelegate: AnyObject {
    func touchBarDidSelectAutomaticSession()
    func touchBarDidSelectSession(url: URL)
    func touchBarDidRequestOpenCurrentSession()
    func touchBarDidRequestIdleCurrentSession()
}

struct TouchBarReadingProgress: Equatable {
    var pageIndex: Int
    var pageCount: Int
}

@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let touchBarIdentifier = NSTouchBar.CustomizationIdentifier("com.local.codex-touch-bar.main")
    private static let projectItem = NSTouchBarItem.Identifier("com.local.codex-touch-bar.project")
    private static let detailContentItem = NSTouchBarItem.Identifier("com.local.codex-touch-bar.detail-content")
    private static let sessionSelectorItem = NSTouchBarItem.Identifier("com.local.codex-touch-bar.session-selector")
    private static let openSessionItem = NSTouchBarItem.Identifier("com.local.codex-touch-bar.open-session")
    private static let idleSessionItem = NSTouchBarItem.Identifier("com.local.codex-touch-bar.idle-session")
    private static let readingAutoPageItem = NSTouchBarItem.Identifier("com.local.codex-touch-bar.reading-auto-page")
    private static let readingPreviousPageItem = NSTouchBarItem.Identifier("com.local.codex-touch-bar.reading-previous-page")
    private static let readingNextPageItem = NSTouchBarItem.Identifier("com.local.codex-touch-bar.reading-next-page")
    private static let readingParagraphSelectorItem = NSTouchBarItem.Identifier("com.local.codex-touch-bar.reading-paragraph-selector")

    weak var delegate: TouchBarControllerDelegate?

    private let projectContainerView = NSView()
    private let detailLabel = NSTextField(labelWithString: "Waiting for Codex activity")
    private let detailIconView = NSImageView()
    private let detailDocumentView = NSView()
    private let detailScrollView = UserAwareTouchBarScrollView()
    private let openSessionButton = NSButton(title: "", target: nil, action: nil)
    private let idleSessionButton = NSButton(title: "", target: nil, action: nil)
    private let readingAutoPageButton = NSButton(title: "", target: nil, action: nil)
    private let readingPreviousPageButton = NSButton(title: "", target: nil, action: nil)
    private let readingNextPageButton = NSButton(title: "", target: nil, action: nil)
    private let sessionSelectionDocumentView = NSView()
    private let readingParagraphDocumentView = NSView()
    private let petView = TouchBarPetView()
    private let idlePlaygroundView = TouchBarPetView()
    private var projectContainerWidthConstraint: NSLayoutConstraint?
    private var usesIdlePlaygroundLayout = false
    private var lastRendered: (
        project: String,
        detail: CodexDetailPresentation,
        petMood: TouchBarPetMood,
        usesIdlePlayground: Bool,
        canOpenSession: Bool,
        canDismissCompletion: Bool
    )?
    private var lastSessionSelectorSignature = ""
    private var sessionChoices: [CodexSessionFile] = []
    private var sessionSelectionMode: CodexSessionSelectionMode = .automaticLatest
    private var isShowingSessionSelector = false
    private var detailDisplayMode: TouchBarDetailDisplayMode = .scrolling
    private var detailScrollSpeed: DetailDisplaySpeed = .normal
    private var detailPageSpeed: DetailDisplaySpeed = .normal
    private var detailPages: [String] = []
    private var detailPageIndex = 0
    private var lastItemIdentifiers: [NSTouchBarItem.Identifier] = []
    private var autoScrollTimer: Timer?
    private var pageTimer: Timer?
    private var readingPageTimer: Timer?
    private var lastAutoScrollDate: Date?
    private var lastPageAdvanceAt: TimeInterval?
    private var lastManualPageAdvanceAt: TimeInterval?
    private var autoScrollPauseUntil: Double?
    private var detailContentWidth: Double = 0
    private var detailAutoContentKey = ""
    private var detailAutoAdvanceSuppressed = false
    private var canOpenCurrentSession = false
    private var canDismissCompletedSession = false
    private var detailPagesMaxWidth: Double = 0
    private var readingDocument: ReadingDocument?
    private var readingPages: [String] = []
    private var readingPageIndex = 0
    private var readingPagesMaxWidth: Double = 0
    private var readingAutoPageEnabled = false
    private var readingAutoPageInterval: TimeInterval = ReadingAutoPageSpeed.normal.intervalSeconds
    private let readingParagraphSelectorButton = NSButton(title: "", target: nil, action: nil)
    private var readingParagraphs: [ReadingParagraph] = []
    private var isShowingReadingParagraphSelector = false
    private var lastReadingParagraphSignature = ""
    private var currentBasePetMood: TouchBarPetMood = .idle
    private var completionSoundState = CompletionSoundState()
    private let completionSound = NSSound(named: NSSound.Name("Ping"))
    private var displayLanguage: DisplayLanguage?

    lazy var touchBar: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.customizationIdentifier = Self.touchBarIdentifier
        let identifiers = itemIdentifiers()
        bar.defaultItemIdentifiers = identifiers
        bar.customizationAllowedItemIdentifiers = [
            Self.projectItem,
            Self.detailContentItem,
            Self.openSessionItem,
            Self.idleSessionItem,
            Self.readingAutoPageItem,
            Self.readingPreviousPageItem,
            Self.readingNextPageItem,
            Self.readingParagraphSelectorItem
        ]
        lastItemIdentifiers = identifiers
        return bar
    }()

    override init() {
        super.init()
        configureProjectContainerView()
        configurePetView()
        configureIdlePlaygroundView()
        configureDetailIconView()
        configureDetailLabel()
        configureDetailScrollView()
        configureOpenSessionButton()
        configureIdleSessionButton()
        configureReadingAutoPageButton()
        configureReadingPageButtons()
        configureReadingParagraphSelectorButton()
        startAutoScroll()
        scheduleNextPageAdvance()
    }

    func apply(
        state: CodexDisplayState,
        detail: CodexDetailPresentation,
        language: DisplayLanguage,
        displayMode: TouchBarDetailDisplayMode,
        detailScrollSpeed: DetailDisplaySpeed,
        detailPageSpeed: DetailDisplaySpeed,
        sessions: [CodexSessionFile],
        selectionMode: CodexSessionSelectionMode,
        completionSpeechEnabled: Bool,
        completionSpeechVoiceIdentifier: String?,
        completionSpeechVoiceOptions: [CompletionSpeechVoiceOption],
        completionSpeechRate: CompletionSpeechRate,
        completionSpeechPitch: CompletionSpeechPitch
    ) {
        updateLocalization(language)
        let leavingReadingMode = readingDocument != nil
        if leavingReadingMode {
            readingDocument = nil
            readingPages = []
            readingPageIndex = 0
            readingPagesMaxWidth = 0
            readingAutoPageEnabled = false
            readingParagraphs = []
            isShowingReadingParagraphSelector = false
            lastReadingParagraphSignature = ""
            readingPageTimer?.invalidate()
            readingPageTimer = nil
        }
        let project = state.projectName
        let basePetMood = TouchBarPetPolicy.mood(for: state, isReading: false)
        let completionSoundDecision = CompletionSoundPolicy.evaluate(
            previous: completionSoundState,
            sessionKey: state.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
            turnKey: completionSoundTurnKey(for: state),
            currentMood: basePetMood
        )
        completionSoundState = completionSoundDecision.next
        if completionSoundDecision.shouldPlay {
            playCompletionSound()
        }
        let completionSpeechDecision = CompletionSpeechPolicy.evaluate(
            previous: completionSpeechState,
            isEnabled: completionSpeechEnabled,
            sessionKey: state.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
            turnKey: completionSoundTurnKey(for: state),
            currentMood: basePetMood,
            assistantText: state.latestAssistantText
        )
        completionSpeechState = completionSpeechDecision.next
        if completionSpeechDecision.shouldStop {
            stopCompletionSpeech()
        }
        if let textToSpeak = completionSpeechDecision.textToSpeak {
            let voiceIdentifier = CompletionSpeechVoicePolicy.selectedVoiceIdentifier(
                from: completionSpeechVoiceOptions,
                preferredIdentifier: completionSpeechVoiceIdentifier
            )
            speakCompletionText(
                textToSpeak,
                voiceIdentifier: voiceIdentifier,
                rate: completionSpeechRate,
                pitch: completionSpeechPitch
            )
        }
        let petMood: TouchBarPetMood = isShowingSessionSelector ? .selecting : basePetMood
        let usesIdlePlayground = petMood == .idle
        let canOpenSession = state.sessionId?.isEmpty == false
        let canDismissCompletion = canOpenSession && state.isTaskComplete && state.status == .completed
        let effectiveSessions = isShowingSessionSelector
            ? stableSessionChoices(merging: sessions)
            : sessions
        let sessionSelectorSignature = CodexSessionSelectorSignature.value(
            sessions: effectiveSessions,
            selectionMode: selectionMode
        )
        let autoContentKey = "\(state.sessionId ?? project)|\(detail.text)"
        let contentChanged = detailAutoContentKey != autoContentKey
        let textChanged = contentChanged
            || lastRendered?.project != project
            || lastRendered?.detail.text != detail.text
        let modeChanged = detailDisplayMode != displayMode
        let scrollSpeedChanged = self.detailScrollSpeed != detailScrollSpeed
        let pageSpeedChanged = self.detailPageSpeed != detailPageSpeed
        let selectorChanged = lastSessionSelectorSignature != sessionSelectorSignature
        let currentPagingMaxWidth = displayMode == .paging ? detailPagingMaxWidth() : 0
        let pagingWidthChanged = abs(detailPagesMaxWidth - currentPagingMaxWidth) > 2
        guard lastRendered?.project != project
                || lastRendered?.detail != detail
                || lastRendered?.petMood != petMood
                || lastRendered?.usesIdlePlayground != usesIdlePlayground
                || lastRendered?.canOpenSession != canOpenSession
                || lastRendered?.canDismissCompletion != canDismissCompletion
                || modeChanged
                || scrollSpeedChanged
                || pageSpeedChanged
                || selectorChanged
                || pagingWidthChanged
                || leavingReadingMode
                || contentChanged else {
            return
        }
        if contentChanged {
            detailAutoContentKey = autoContentKey
            detailAutoAdvanceSuppressed = false
        }
        detailDisplayMode = displayMode
        self.detailScrollSpeed = detailScrollSpeed
        self.detailPageSpeed = detailPageSpeed
        canOpenCurrentSession = canOpenSession
        canDismissCompletedSession = canDismissCompletion
        currentBasePetMood = basePetMood
        sessionChoices = effectiveSessions
        sessionSelectionMode = selectionMode
        updateOpenSessionButton(canOpenSession: canOpenSession)
        updateIdleSessionButton(canDismissCompletion: canDismissCompletion)
        updatePetPresentation(mood: petMood, usesIdlePlayground: usesIdlePlayground, idleText: detail.text)
        if selectorChanged || sessionSelectionDocumentView.subviews.isEmpty {
            updateSessionSelectionButtons()
        }
        applyDetailPresentation(
            detail,
            resetPages: textChanged || modeChanged || pagingWidthChanged,
            pagingMaxWidth: currentPagingMaxWidth
        )
        resizeDetailDocument()
        switch detailDisplayMode {
        case .scrolling:
            if textChanged || modeChanged {
                if !isShowingSessionSelector {
                    if usesIdlePlayground {
                        showIdlePlaygroundDocument()
                    } else {
                        showDetailDocument()
                    }
                }
                lastAutoScrollDate = Date()
                autoScrollPauseUntil = TouchBarAutoScrollPolicy.pauseUntil(
                    afterContentResetAt: Date().timeIntervalSinceReferenceDate
                )
            }
        case .paging:
            if !isShowingSessionSelector {
                if usesIdlePlayground {
                    showIdlePlaygroundDocument()
                } else {
                    showDetailDocument()
                }
            }
            autoScrollPauseUntil = nil
            if textChanged || modeChanged || pageSpeedChanged {
                lastPageAdvanceAt = Date().timeIntervalSinceReferenceDate
                scheduleNextPageAdvance()
            }
        }
        applyItemIdentifiers()
        lastRendered = (project, detail, petMood, usesIdlePlayground, canOpenSession, canDismissCompletion)
        lastSessionSelectorSignature = sessionSelectorSignature
    }

    private func playCompletionSound() {
        guard let completionSound else {
            NSSound.beep()
            return
        }

        completionSound.stop()
        completionSound.currentTime = 0
        if !completionSound.play() {
            NSSound.beep()
        }
    }

    private func completionSoundTurnKey(for state: CodexDisplayState) -> String? {
        if let timestamp = state.latestUserTimestamp?.trimmingCharacters(in: .whitespacesAndNewlines),
           !timestamp.isEmpty {
            return timestamp
        }

        if let text = state.latestUserText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        return nil
    }

    private var completionSpeechState = CompletionSpeechState()
    private let completionSpeechSynthesizer = AVSpeechSynthesizer()

    func stopCompletionSpeech() {
        if completionSpeechSynthesizer.isSpeaking {
            completionSpeechSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func speakCompletionText(
        _ text: String,
        voiceIdentifier: String?,
        rate: CompletionSpeechRate,
        pitch: CompletionSpeechPitch
    ) {
        stopCompletionSpeech()
        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        }
        utterance.rate = rate.utteranceRate
        utterance.pitchMultiplier = pitch.multiplier
        completionSpeechSynthesizer.speak(utterance)
    }

    func applyReading(
        document: ReadingDocument,
        requestedPageIndex: Int,
        autoPageInterval: TimeInterval,
        language: DisplayLanguage
    ) -> TouchBarReadingProgress {
        updateLocalization(language)
        let documentChanged = readingDocument?.id != document.id
        let intervalChanged = abs(readingAutoPageInterval - autoPageInterval) > 0.001
        readingAutoPageInterval = autoPageInterval
        readingDocument = document
        completionSoundState = CompletionSoundState()
        completionSpeechState = CompletionSpeechState()
        stopCompletionSpeech()
        updatePetPresentation(mood: .reading, usesIdlePlayground: false, idleText: "")
        isShowingSessionSelector = false
        pageTimer?.invalidate()
        pageTimer = nil

        let maxWidth = detailPagingMaxWidth()
        let widthChanged = abs(readingPagesMaxWidth - maxWidth) > 2
        if documentChanged || widthChanged || readingPages.isEmpty {
            if documentChanged {
                readingAutoPageEnabled = false
                isShowingReadingParagraphSelector = false
                lastReadingParagraphSignature = ""
                readingPageTimer?.invalidate()
                readingPageTimer = nil
            }
            readingPages = measuredDetailPages(for: document.text, maxWidth: maxWidth)
            readingPageIndex = min(readingPageIndex, max(0, readingPages.count - 1))
            if documentChanged {
                readingPageIndex = min(max(requestedPageIndex, 0), max(0, readingPages.count - 1))
            }
            readingPagesMaxWidth = maxWidth
            if !ReadingAutoPagePolicy.canAdvanceAutomatically(currentIndex: readingPageIndex, pageCount: readingPages.count) {
                readingAutoPageEnabled = false
                readingPageTimer?.invalidate()
                readingPageTimer = nil
            }
        }

        detailPages = []
        detailPagesMaxWidth = 0
        detailPageIndex = 0
        let paragraphSignature = "\(document.id)#\(readingPages.joined(separator: "\u{001F}"))"
        if lastReadingParagraphSignature != paragraphSignature {
            readingParagraphs = ReadingParagraphPolicy.paragraphs(in: document.text)
            lastReadingParagraphSignature = paragraphSignature
            updateReadingParagraphButtons()
        }
        detailLabel.stringValue = readingPages[safe: readingPageIndex] ?? document.text
        detailIconView.image = nil
        detailIconView.toolTip = nil
        detailIconView.isHidden = true
        updateReadingAutoPageButton()
        updateReadingPageButtons()
        resizeDetailDocument()
        updateReadingParagraphSelectorButton()
        if isShowingReadingParagraphSelector {
            showReadingParagraphDocument(offset: detailScrollView.contentView.bounds.origin.x)
        } else {
            showDetailDocument()
        }
        if intervalChanged, readingAutoPageEnabled {
            scheduleReadingPageAdvance()
        }
        applyItemIdentifiers()
        return currentReadingProgress()
    }

    func currentReadingProgress() -> TouchBarReadingProgress {
        TouchBarReadingProgress(pageIndex: readingPageIndex, pageCount: readingPages.count)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.projectItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = projectContainerView
            return item
        case Self.detailContentItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = detailScrollView
            return item
        case Self.openSessionItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = openSessionButton
            return item
        case Self.idleSessionItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = idleSessionButton
            return item
        case Self.readingAutoPageItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = readingAutoPageButton
            return item
        case Self.readingPreviousPageItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = readingPreviousPageButton
            return item
        case Self.readingNextPageItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = readingNextPageButton
            return item
        case Self.readingParagraphSelectorItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = readingParagraphSelectorButton
            return item
        default:
            return nil
        }
    }

    private func configureProjectContainerView() {
        let frame = TouchBarProjectStatusLayout.frame()
        projectContainerView.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
        projectContainerView.translatesAutoresizingMaskIntoConstraints = false
        let widthConstraint = projectContainerView.widthAnchor.constraint(equalToConstant: CGFloat(frame.width))
        widthConstraint.isActive = true
        projectContainerWidthConstraint = widthConstraint
        projectContainerView.heightAnchor.constraint(equalToConstant: CGFloat(frame.height)).isActive = true
    }

    private func updatePetPresentation(mood: TouchBarPetMood, usesIdlePlayground: Bool, idleText: String) {
        usesIdlePlaygroundLayout = usesIdlePlayground
        petView.idleText = ""
        petView.usesIdlePlayground = false
        petView.mood = mood
        idlePlaygroundView.idleText = usesIdlePlayground ? idleText : ""
        idlePlaygroundView.usesIdlePlayground = usesIdlePlayground
        idlePlaygroundView.mood = mood
        if usesIdlePlayground, !isShowingSessionSelector, readingDocument == nil {
            showIdlePlaygroundDocument()
        } else if detailScrollView.documentView === idlePlaygroundView {
            showDetailDocument()
        }
    }

    private func configureDetailIconView() {
        detailIconView.imageScaling = .scaleProportionallyDown
        detailIconView.contentTintColor = .labelColor
        detailIconView.translatesAutoresizingMaskIntoConstraints = true
        detailIconView.isHidden = true
        if #available(macOS 11.0, *) {
            detailIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        }
    }

    private func configureDetailLabel() {
        detailLabel.lineBreakMode = .byClipping
        detailLabel.alignment = .left
        detailLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        detailLabel.translatesAutoresizingMaskIntoConstraints = true
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func configureDetailScrollView() {
        detailDocumentView.addSubview(detailIconView)
        detailDocumentView.addSubview(detailLabel)
        detailScrollView.documentView = detailDocumentView
        detailScrollView.drawsBackground = false
        detailScrollView.borderType = .noBorder
        detailScrollView.hasHorizontalScroller = false
        detailScrollView.hasVerticalScroller = false
        detailScrollView.horizontalScrollElasticity = .allowed
        detailScrollView.verticalScrollElasticity = .none
        detailScrollView.autohidesScrollers = true
        detailScrollView.onUserInteraction = { [weak self] in
            self?.handleDetailUserInteraction()
        }
        detailScrollView.onDocumentPress = { [weak self] point in
            guard let self,
                  self.usesIdlePlaygroundLayout,
                  self.detailScrollView.documentView === self.idlePlaygroundView
            else {
                return false
            }
            return self.idlePlaygroundView.handleIdlePlaygroundPress(at: point)
        }
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false
        detailScrollView.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(TouchBarLayoutMetrics.detailMinimumWidth)).isActive = true
        detailScrollView.heightAnchor.constraint(equalToConstant: CGFloat(TouchBarLayoutMetrics.detailViewportHeight)).isActive = true
        resizeDetailDocument()
    }

    private func configureOpenSessionButton() {
        openSessionButton.target = self
        openSessionButton.action = #selector(openCurrentSession)
        openSessionButton.setButtonType(.momentaryPushIn)
        openSessionButton.bezelStyle = .rounded
        openSessionButton.image = openSessionImage()
        openSessionButton.imagePosition = .imageOnly
        openSessionButton.imageScaling = .scaleProportionallyDown
        openSessionButton.toolTip = "Open Current Session"
        openSessionButton.setAccessibilityLabel("Open Current Session")
        openSessionButton.alignment = .center
        openSessionButton.translatesAutoresizingMaskIntoConstraints = false
        openSessionButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        openSessionButton.heightAnchor.constraint(equalToConstant: CGFloat(TouchBarLayoutMetrics.detailViewportHeight)).isActive = true
    }

    private func configureIdleSessionButton() {
        idleSessionButton.target = self
        idleSessionButton.action = #selector(idleCurrentSession)
        idleSessionButton.setButtonType(.momentaryPushIn)
        idleSessionButton.bezelStyle = .rounded
        idleSessionButton.image = idleSessionImage()
        idleSessionButton.imagePosition = .imageOnly
        idleSessionButton.imageScaling = .scaleProportionallyDown
        idleSessionButton.toolTip = "Dismiss to Idle"
        idleSessionButton.setAccessibilityLabel("Dismiss to Idle")
        idleSessionButton.alignment = .center
        idleSessionButton.translatesAutoresizingMaskIntoConstraints = false
        idleSessionButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        idleSessionButton.heightAnchor.constraint(equalToConstant: CGFloat(TouchBarLayoutMetrics.detailViewportHeight)).isActive = true
    }

    private func configureReadingAutoPageButton() {
        readingAutoPageButton.target = self
        readingAutoPageButton.action = #selector(toggleReadingAutoPage)
        readingAutoPageButton.setButtonType(.toggle)
        readingAutoPageButton.bezelStyle = .rounded
        readingAutoPageButton.imagePosition = .imageOnly
        readingAutoPageButton.imageScaling = .scaleProportionallyDown
        readingAutoPageButton.toolTip = "Auto Page"
        readingAutoPageButton.setAccessibilityLabel("Auto Page")
        readingAutoPageButton.alignment = .center
        readingAutoPageButton.translatesAutoresizingMaskIntoConstraints = false
        readingAutoPageButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        readingAutoPageButton.heightAnchor.constraint(equalToConstant: CGFloat(TouchBarLayoutMetrics.detailViewportHeight)).isActive = true
        updateReadingAutoPageButton()
    }

    private func configureReadingPageButtons() {
        configureReadingPageButton(
            readingPreviousPageButton,
            symbolNames: ["chevron.up", "arrow.up"],
            action: #selector(previousReadingPage),
            accessibilityDescription: "Previous Page"
        )
        configureReadingPageButton(
            readingNextPageButton,
            symbolNames: ["chevron.down", "arrow.down"],
            action: #selector(nextReadingPage),
            accessibilityDescription: "Next Page"
        )
    }

    private func configureReadingParagraphSelectorButton() {
        readingParagraphSelectorButton.target = self
        readingParagraphSelectorButton.action = #selector(toggleReadingParagraphSelector)
        readingParagraphSelectorButton.setButtonType(.toggle)
        readingParagraphSelectorButton.bezelStyle = .rounded
        readingParagraphSelectorButton.image = symbolImage(
            symbolNames: ["paragraphsign", "list.bullet"],
            accessibilityDescription: "Select Paragraph",
            pointSize: 14
        )
        readingParagraphSelectorButton.imagePosition = .imageOnly
        readingParagraphSelectorButton.imageScaling = .scaleProportionallyDown
        readingParagraphSelectorButton.toolTip = "Select Paragraph"
        readingParagraphSelectorButton.setAccessibilityLabel("Select Paragraph")
        readingParagraphSelectorButton.alignment = .center
        readingParagraphSelectorButton.translatesAutoresizingMaskIntoConstraints = false
        readingParagraphSelectorButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        readingParagraphSelectorButton.heightAnchor.constraint(equalToConstant: CGFloat(TouchBarLayoutMetrics.detailViewportHeight)).isActive = true
        updateReadingParagraphSelectorButton()
    }

    private func configurePetView() {
        let frame = TouchBarProjectStatusLayout.frame()
        petView.translatesAutoresizingMaskIntoConstraints = true
        petView.frame = NSRect(x: frame.iconX, y: frame.iconY, width: frame.iconSize, height: frame.height)
        petView.autoresizingMask = [.width, .height]
        petView.toolTip = "Switch Session"
        petView.onPress = { [weak self] in
            self?.toggleSessionSelector()
        }
        projectContainerView.addSubview(petView)
    }

    private func configureIdlePlaygroundView() {
        idlePlaygroundView.translatesAutoresizingMaskIntoConstraints = false
        idlePlaygroundView.toolTip = "Switch Session"
        idlePlaygroundView.onPress = { [weak self] in
            self?.toggleSessionSelector()
        }
        idlePlaygroundView.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(TouchBarLayoutMetrics.detailMinimumWidth)).isActive = true
        idlePlaygroundView.heightAnchor.constraint(equalToConstant: CGFloat(TouchBarLayoutMetrics.detailViewportHeight)).isActive = true
    }

    private func configureReadingPageButton(
        _ button: NSButton,
        symbolNames: [String],
        action: Selector,
        accessibilityDescription: String
    ) {
        button.target = self
        button.action = action
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .rounded
        button.image = symbolImage(
            symbolNames: symbolNames,
            accessibilityDescription: accessibilityDescription,
            pointSize: 14
        )
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = accessibilityDescription
        button.setAccessibilityLabel(accessibilityDescription)
        button.alignment = .center
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: CGFloat(TouchBarLayoutMetrics.detailViewportHeight)).isActive = true
    }

    private func openSessionImage(accessibilityDescription: String = "Open Current Session") -> NSImage? {
        symbolImage(
            symbolNames: ["arrow.up.forward", "arrow.up.right", "arrowshape.turn.up.right"],
            accessibilityDescription: accessibilityDescription,
            pointSize: 13
        )
    }

    private func idleSessionImage(accessibilityDescription: String = "Dismiss to Idle") -> NSImage? {
        symbolImage(
            symbolNames: ["moon.zzz.fill", "moon.zzz", "xmark.circle"],
            accessibilityDescription: accessibilityDescription,
            pointSize: 13
        )
    }

    private func symbolImage(
        symbolNames: [String],
        accessibilityDescription: String,
        pointSize: CGFloat
    ) -> NSImage? {
        for name in symbolNames {
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription) else {
                continue
            }
            if #available(macOS 11.0, *) {
                return image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium))
            }
            return image
        }
        return nil
    }

    private func measuredDetailPages(for text: String, maxWidth: Double) -> [String] {
        let font = detailLabel.font ?? NSFont.systemFont(ofSize: 14, weight: .medium)
        return TouchBarPagePolicy.pages(for: text, maxWidth: maxWidth) { page in
            (page as NSString).size(withAttributes: [.font: font]).width
        }
    }

    private func detailPagingMaxWidth() -> Double {
        let measuredWidth = Double(detailScrollView.contentView.bounds.width)
        let fallbackWidth = TouchBarLayoutMetrics.detailMinimumWidth
        let viewportWidth = measuredWidth > 80 ? measuredWidth : fallbackWidth
        return max(40, viewportWidth - TouchBarLayoutMetrics.detailTrailingPadding)
    }

    private func applyDetailPresentation(
        _ detail: CodexDetailPresentation,
        resetPages: Bool,
        pagingMaxWidth: Double
    ) {
        switch detailDisplayMode {
        case .scrolling:
            detailPages = []
            detailPageIndex = 0
            detailPagesMaxWidth = 0
            detailLabel.stringValue = detail.text
        case .paging:
            if resetPages || detailPages.isEmpty {
                detailPages = measuredDetailPages(for: detail.text, maxWidth: pagingMaxWidth)
                detailPageIndex = 0
                detailPagesMaxWidth = pagingMaxWidth
            }
            detailLabel.stringValue = detailPages[safe: detailPageIndex] ?? detail.text
        }

        detailIconView.image = nil
        detailIconView.toolTip = nil
        detailIconView.isHidden = true
    }

    private func resizeDetailDocument() {
        detailLabel.sizeToFit()
        let iconSize: CGFloat = detailIconView.isHidden ? 0 : 16
        let iconGap: CGFloat = detailIconView.isHidden ? 0 : 6
        let labelWidth = detailLabel.fittingSize.width
        let labelHeight = detailLabel.fittingSize.height
        let contentWidth = iconSize + iconGap + labelWidth
        let contentHeight = max(labelHeight, iconSize)
        detailContentWidth = Double(contentWidth)
        let width = max(
            TouchBarLayoutMetrics.detailMinimumWidth,
            Double(contentWidth) + TouchBarLayoutMetrics.detailTrailingPadding
        )
        let height = TouchBarLayoutMetrics.detailViewportHeight
        detailDocumentView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let contentFrame = TouchBarLayoutMetrics.centeredContentFrame(
            containerWidth: width,
            containerHeight: height,
            contentWidth: Double(contentWidth),
            contentHeight: Double(contentHeight)
        )
        if detailIconView.isHidden {
            detailIconView.frame = .zero
        } else {
            detailIconView.frame = NSRect(
                x: contentFrame.x,
                y: contentFrame.y + (contentFrame.height - Double(iconSize)) / 2,
                width: Double(iconSize),
                height: Double(iconSize)
            )
        }
        detailLabel.frame = NSRect(
            x: contentFrame.x + Double(iconSize + iconGap),
            y: contentFrame.y + (contentFrame.height - Double(labelHeight)) / 2,
            width: Double(labelWidth),
            height: Double(labelHeight)
        )
    }

    private func applyItemIdentifiers() {
        let identifiers = itemIdentifiers()
        guard identifiers != lastItemIdentifiers else { return }
        touchBar.defaultItemIdentifiers = identifiers
        lastItemIdentifiers = identifiers
    }

    private func itemIdentifiers() -> [NSTouchBarItem.Identifier] {
        if readingDocument != nil {
            return TouchBarLayoutPlan.readingRegions().map { region in
                switch region {
                case .readingAutoPage: return Self.readingAutoPageItem
                case .readingPreviousPage: return Self.readingPreviousPageItem
                case .detailContent: return Self.detailContentItem
                case .readingNextPage: return Self.readingNextPageItem
                case .readingParagraphSelector: return Self.readingParagraphSelectorItem
                default:
                    preconditionFailure("Unexpected region in reading mode")
                }
            }
        }

        return TouchBarLayoutPlan.visibleRegions(
            showingSessionSelector: isShowingSessionSelector,
            usesIdlePlayground: usesIdlePlaygroundLayout,
            hasOpenSession: canOpenCurrentSession,
            canDismissCompletion: canDismissCompletedSession
        ).map { region in
            switch region {
            case .project: return Self.projectItem
            case .detailContent: return Self.detailContentItem
            case .flexibleSpace: return .flexibleSpace
            case .sessionSelector: return Self.sessionSelectorItem
            case .openSession: return Self.openSessionItem
            case .idleSession: return Self.idleSessionItem
            case .readingAutoPage: return Self.readingAutoPageItem
            case .readingPreviousPage: return Self.readingPreviousPageItem
            case .readingNextPage: return Self.readingNextPageItem
            case .readingParagraphSelector: return Self.readingParagraphSelectorItem
            }
        }
    }

    private func updateOpenSessionButton(canOpenSession: Bool) {
        openSessionButton.isEnabled = canOpenSession
    }

    private func updateIdleSessionButton(canDismissCompletion: Bool) {
        idleSessionButton.isEnabled = canDismissCompletion
    }

    private func updateReadingPageButtons() {
        readingPreviousPageButton.isEnabled = !isShowingReadingParagraphSelector && readingPageIndex > 0
        readingNextPageButton.isEnabled = !isShowingReadingParagraphSelector && readingPageIndex < readingPages.count - 1
    }

    private func updateReadingAutoPageButton() {
        readingAutoPageButton.state = readingAutoPageEnabled ? .on : .off
        readingAutoPageButton.image = symbolImage(
            symbolNames: readingAutoPageEnabled ? ["pause.fill", "pause"] : ["play.fill", "play"],
            accessibilityDescription: localizedText(english: "Auto Page", chinese: "自动翻页"),
            pointSize: 13
        )
        readingAutoPageButton.isEnabled = readingPages.count > 1
    }

    private func updateReadingParagraphSelectorButton() {
        readingParagraphSelectorButton.state = isShowingReadingParagraphSelector ? .on : .off
        readingParagraphSelectorButton.isEnabled = !readingParagraphs.isEmpty
    }

    private func updateSessionSelectionButtons() {
        let previousOffset = detailScrollView.contentView.bounds.origin.x
        for view in sessionSelectionDocumentView.subviews {
            view.removeFromSuperview()
        }

        let buttons = [makeAutomaticSessionButton()]
            + sessionChoices.map { makeSessionButton(for: $0) as NSButton }
        let itemWidths = buttons.map { measuredSessionButtonWidth($0) }
        let frames = TouchBarSessionSelectorLayout.itemFrames(
            itemWidths: itemWidths,
            itemHeight: TouchBarLayoutMetrics.detailViewportHeight
        )
        for (button, frame) in zip(buttons, frames) {
            button.frame = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            sessionSelectionDocumentView.addSubview(button)
        }

        let width = TouchBarSessionSelectorLayout.contentWidth(itemWidths: itemWidths)
        sessionSelectionDocumentView.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: TouchBarLayoutMetrics.detailViewportHeight
        )
        if isShowingSessionSelector {
            showSessionSelectionDocument(offset: previousOffset)
        }
    }

    private func updateReadingParagraphButtons() {
        let previousOffset = detailScrollView.contentView.bounds.origin.x
        for view in readingParagraphDocumentView.subviews {
            view.removeFromSuperview()
        }

        let buttons: [NSButton]
        if readingParagraphs.isEmpty {
            let button = NSButton(title: localizedText(english: "No paragraphs", chinese: "没有段落"), target: nil, action: nil)
            configureSessionButton(button)
            button.isEnabled = false
            buttons = [button]
        } else {
            buttons = readingParagraphs.enumerated().map { index, paragraph in
                let button = ReadingParagraphButton(title: paragraph.title, target: self, action: #selector(selectReadingParagraph))
                configureSessionButton(button)
                button.paragraphIndex = index
                return button
            }
        }

        let itemWidths = buttons.map { measuredSessionButtonWidth($0) }
        let frames = TouchBarSessionSelectorLayout.itemFrames(
            itemWidths: itemWidths,
            itemHeight: TouchBarLayoutMetrics.detailViewportHeight
        )
        for (button, frame) in zip(buttons, frames) {
            button.frame = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            readingParagraphDocumentView.addSubview(button)
        }

        let width = TouchBarSessionSelectorLayout.contentWidth(itemWidths: itemWidths)
        readingParagraphDocumentView.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: TouchBarLayoutMetrics.detailViewportHeight
        )
        if isShowingReadingParagraphSelector {
            showReadingParagraphDocument(offset: previousOffset)
        }
    }

    private func updateLocalization(_ language: DisplayLanguage) {
        guard displayLanguage != language else { return }
        displayLanguage = language

        let openSession = localizedText(english: "Open Current Session", chinese: "打开当前会话")
        let dismissToIdle = localizedText(english: "Dismiss to Idle", chinese: "收起为空闲")
        let autoPage = localizedText(english: "Auto Page", chinese: "自动翻页")
        let previousPage = localizedText(english: "Previous Page", chinese: "上一页")
        let nextPage = localizedText(english: "Next Page", chinese: "下一页")
        let selectParagraph = localizedText(english: "Select Paragraph", chinese: "选择段落")
        let switchSession = localizedText(english: "Switch Session", chinese: "切换会话")

        openSessionButton.toolTip = openSession
        openSessionButton.setAccessibilityLabel(openSession)
        openSessionButton.image = openSessionImage(accessibilityDescription: openSession)
        idleSessionButton.toolTip = dismissToIdle
        idleSessionButton.setAccessibilityLabel(dismissToIdle)
        idleSessionButton.image = idleSessionImage(accessibilityDescription: dismissToIdle)
        readingAutoPageButton.toolTip = autoPage
        readingAutoPageButton.setAccessibilityLabel(autoPage)
        readingPreviousPageButton.toolTip = previousPage
        readingPreviousPageButton.setAccessibilityLabel(previousPage)
        readingPreviousPageButton.image = symbolImage(
            symbolNames: ["chevron.up", "arrow.up"],
            accessibilityDescription: previousPage,
            pointSize: 14
        )
        readingNextPageButton.toolTip = nextPage
        readingNextPageButton.setAccessibilityLabel(nextPage)
        readingNextPageButton.image = symbolImage(
            symbolNames: ["chevron.down", "arrow.down"],
            accessibilityDescription: nextPage,
            pointSize: 14
        )
        readingParagraphSelectorButton.toolTip = selectParagraph
        readingParagraphSelectorButton.setAccessibilityLabel(selectParagraph)
        readingParagraphSelectorButton.image = symbolImage(
            symbolNames: ["paragraphsign", "list.bullet"],
            accessibilityDescription: selectParagraph,
            pointSize: 14
        )
        petView.toolTip = switchSession
        idlePlaygroundView.toolTip = switchSession
        updateReadingAutoPageButton()
        updateReadingParagraphButtons()
    }

    private func localizedText(english: String, chinese: String) -> String {
        displayLanguage == .simplifiedChinese ? chinese : english
    }

    private func showDetailDocument() {
        if detailScrollView.documentView !== detailDocumentView {
            detailScrollView.documentView = detailDocumentView
        }
        detailScrollView.contentView.scroll(to: .zero)
        detailScrollView.reflectScrolledClipView(detailScrollView.contentView)
    }

    private func showIdlePlaygroundDocument() {
        let width = max(
            CGFloat(TouchBarLayoutMetrics.detailMinimumWidth),
            detailScrollView.contentView.bounds.width
        )
        idlePlaygroundView.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: CGFloat(TouchBarLayoutMetrics.detailViewportHeight)
        )
        if detailScrollView.documentView !== idlePlaygroundView {
            detailScrollView.documentView = idlePlaygroundView
        }
        detailScrollView.contentView.scroll(to: .zero)
        detailScrollView.reflectScrolledClipView(detailScrollView.contentView)
    }

    private func showSessionSelectionDocument(offset: CGFloat = 0) {
        if detailScrollView.documentView !== sessionSelectionDocumentView {
            detailScrollView.documentView = sessionSelectionDocumentView
        }
        detailScrollView.contentView.scroll(to: NSPoint(x: max(0, offset), y: 0))
        detailScrollView.reflectScrolledClipView(detailScrollView.contentView)
    }

    private func showReadingParagraphDocument(offset: CGFloat = 0) {
        if detailScrollView.documentView !== readingParagraphDocumentView {
            detailScrollView.documentView = readingParagraphDocumentView
        }
        detailScrollView.contentView.scroll(to: NSPoint(x: max(0, offset), y: 0))
        detailScrollView.reflectScrolledClipView(detailScrollView.contentView)
    }

    private func makeAutomaticSessionButton() -> NSButton {
        let button = NSButton(title: "Auto", target: self, action: #selector(selectAutomaticSession))
        configureSessionButton(button)
        button.state = sessionSelectionMode == .automaticLatest ? .on : .off
        return button
    }

    private func makeSessionButton(for session: CodexSessionFile) -> SessionChoiceButton {
        let button = SessionChoiceButton(title: sessionChoiceTitle(for: session), target: self, action: #selector(selectSession))
        configureSessionButton(button)
        button.sessionURL = session.url
        if case .locked(let url) = sessionSelectionMode, url == session.url {
            button.state = .on
        }
        return button
    }

    private func configureSessionButton(_ button: NSButton) {
        button.setButtonType(.toggle)
        button.bezelStyle = .rounded
        button.lineBreakMode = .byTruncatingTail
        button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        button.alignment = .center
        button.translatesAutoresizingMaskIntoConstraints = true
        button.autoresizingMask = []
    }

    private func measuredSessionButtonWidth(_ button: NSButton) -> Double {
        let measuredWidth = ceil(Double(button.fittingSize.width)) + 12
        return max(TouchBarSessionSelectorLayout.minimumItemWidth, measuredWidth)
    }

    private func sessionChoiceTitle(for session: CodexSessionFile) -> String {
        session.displayName
    }

    private func stableSessionChoices(merging sessions: [CodexSessionFile]) -> [CodexSessionFile] {
        let byURL = Dictionary(uniqueKeysWithValues: sessions.map { ($0.url, $0) })
        var merged = sessionChoices.compactMap { byURL[$0.url] }
        let existingURLs = Set(merged.map(\.url))
        merged.append(contentsOf: sessions.filter { !existingURLs.contains($0.url) })
        return merged
    }

    @objc private func selectAutomaticSession() {
        isShowingSessionSelector = false
        updatePetPresentation(mood: currentBasePetMood, usesIdlePlayground: currentBasePetMood == .idle, idleText: detailLabel.stringValue)
        showDetailDocument()
        applyItemIdentifiers()
        delegate?.touchBarDidSelectAutomaticSession()
    }

    @objc private func selectSession(_ sender: SessionChoiceButton) {
        guard let url = sender.sessionURL else { return }
        isShowingSessionSelector = false
        updatePetPresentation(mood: currentBasePetMood, usesIdlePlayground: currentBasePetMood == .idle, idleText: detailLabel.stringValue)
        showDetailDocument()
        applyItemIdentifiers()
        delegate?.touchBarDidSelectSession(url: url)
    }

    @objc private func toggleSessionSelector() {
        isShowingSessionSelector.toggle()
        let mood: TouchBarPetMood = isShowingSessionSelector ? .selecting : currentBasePetMood
        updatePetPresentation(
            mood: mood,
            usesIdlePlayground: !isShowingSessionSelector && currentBasePetMood == .idle,
            idleText: detailLabel.stringValue
        )
        updateSessionSelectionButtons()
        if isShowingSessionSelector {
            showSessionSelectionDocument()
        } else {
            showDetailDocument()
        }
        applyItemIdentifiers()
    }

    @objc private func openCurrentSession() {
        delegate?.touchBarDidRequestOpenCurrentSession()
    }

    @objc private func idleCurrentSession() {
        delegate?.touchBarDidRequestIdleCurrentSession()
    }

    @objc private func previousReadingPage() {
        advanceReadingPage(delta: -1)
    }

    @objc private func nextReadingPage() {
        advanceReadingPage(delta: 1)
    }

    @objc private func toggleReadingAutoPage() {
        guard !isShowingReadingParagraphSelector else { return }
        readingAutoPageEnabled.toggle()
        if readingAutoPageEnabled,
           !ReadingAutoPagePolicy.canAdvanceAutomatically(currentIndex: readingPageIndex, pageCount: readingPages.count) {
            readingAutoPageEnabled = false
        }
        updateReadingAutoPageButton()
        scheduleReadingPageAdvance()
    }

    @objc private func toggleReadingParagraphSelector() {
        guard readingDocument != nil else { return }
        isShowingReadingParagraphSelector.toggle()
        if isShowingReadingParagraphSelector {
            readingAutoPageEnabled = false
            readingPageTimer?.invalidate()
            readingPageTimer = nil
            updateReadingParagraphButtons()
            showReadingParagraphDocument()
        } else {
            showDetailDocument()
        }
        updateReadingAutoPageButton()
        updateReadingPageButtons()
        updateReadingParagraphSelectorButton()
        applyItemIdentifiers()
    }

    @objc private func selectReadingParagraph(_ sender: NSButton) {
        guard let sender = sender as? ReadingParagraphButton,
              readingDocument != nil,
              readingParagraphs.indices.contains(sender.paragraphIndex) else {
            return
        }
        let paragraph = readingParagraphs[sender.paragraphIndex]
        readingPageIndex = ReadingParagraphPolicy.pageIndex(forParagraph: paragraph, pages: readingPages)
        readingAutoPageEnabled = false
        readingPageTimer?.invalidate()
        readingPageTimer = nil
        isShowingReadingParagraphSelector = false
        detailLabel.stringValue = readingPages[safe: readingPageIndex] ?? paragraph.text
        resizeDetailDocument()
        showDetailDocument()
        updateReadingAutoPageButton()
        updateReadingPageButtons()
        updateReadingParagraphSelectorButton()
    }

    private func advanceReadingPage(delta: Int) {
        guard readingDocument != nil, !isShowingReadingParagraphSelector, !readingPages.isEmpty else { return }
        let nextIndex = min(max(readingPageIndex + delta, 0), readingPages.count - 1)
        guard nextIndex != readingPageIndex else { return }
        readingPageIndex = nextIndex
        detailLabel.stringValue = readingPages[readingPageIndex]
        updateReadingPageButtons()
        resizeDetailDocument()
        scrollDetail(to: 0)
        if readingAutoPageEnabled {
            scheduleReadingPageAdvance()
        }
    }

    private func scheduleReadingPageAdvance() {
        readingPageTimer?.invalidate()
        guard readingAutoPageEnabled,
              readingDocument != nil,
              !isShowingReadingParagraphSelector,
              ReadingAutoPagePolicy.canAdvanceAutomatically(currentIndex: readingPageIndex, pageCount: readingPages.count) else {
            readingPageTimer = nil
            return
        }
        let timer = Timer(timeInterval: readingAutoPageInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.advanceReadingPageAutomatically()
            }
        }
        readingPageTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceReadingPageAutomatically() {
        guard readingAutoPageEnabled else { return }
        advanceReadingPage(delta: 1)
        if !ReadingAutoPagePolicy.canAdvanceAutomatically(currentIndex: readingPageIndex, pageCount: readingPages.count) {
            readingAutoPageEnabled = false
            updateReadingAutoPageButton()
            readingPageTimer?.invalidate()
            readingPageTimer = nil
        }
    }

    private func startAutoScroll() {
        autoScrollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.autoScrollTick()
            }
        }
        autoScrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleNextPageAdvance() {
        pageTimer?.invalidate()
        guard readingDocument == nil,
              detailDisplayMode == .paging,
              !usesIdlePlaygroundLayout,
              !detailAutoAdvanceSuppressed else {
            pageTimer = nil
            return
        }
        let now = Date().timeIntervalSinceReferenceDate
        let delay = TouchBarPagePolicy.automaticAdvanceDelay(
            now: now,
            lastAdvanceAt: lastPageAdvanceAt,
            interval: detailPageSpeed.pageIntervalSeconds
        )
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.advanceDetailPageAutomatically()
            }
        }
        pageTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func autoScrollTick() {
        guard detailDisplayMode == .scrolling,
              readingDocument == nil,
              !isShowingSessionSelector,
              !usesIdlePlaygroundLayout,
              !detailAutoAdvanceSuppressed else {
            lastAutoScrollDate = Date()
            return
        }

        let now = Date()
        guard let lastAutoScrollDate else {
            self.lastAutoScrollDate = now
            return
        }

        let documentWidth = Double(detailDocumentView.frame.width)
        let measuredViewportWidth = Double(detailScrollView.contentView.bounds.width)
        let viewportWidth = measuredViewportWidth > 0 ? measuredViewportWidth : TouchBarLayoutMetrics.detailMinimumWidth
        let currentOffset = Double(detailScrollView.contentView.bounds.origin.x)
        let step = TouchBarAutoScrollPolicy.nextStep(
            currentOffset: currentOffset,
            contentWidth: detailContentWidth,
            documentWidth: documentWidth,
            viewportWidth: viewportWidth,
            elapsedSeconds: now.timeIntervalSince(lastAutoScrollDate),
            now: now.timeIntervalSinceReferenceDate,
            pauseUntil: autoScrollPauseUntil,
            pixelsPerSecond: detailScrollSpeed.scrollPixelsPerSecond
        )
        self.lastAutoScrollDate = now

        if step.reachedEnd {
            autoScrollPauseUntil = TouchBarAutoScrollPolicy.pauseUntil(
                afterWrapAt: now.timeIntervalSinceReferenceDate
            )
        }

        guard abs(step.offset - currentOffset) >= 0.5 else { return }
        scrollDetail(to: CGFloat(step.offset))
    }

    private func pauseAutoScrollForUserInteraction() {
        detailAutoAdvanceSuppressed = true
        autoScrollPauseUntil = nil
        lastAutoScrollDate = Date()
    }

    private func handleDetailUserInteraction() {
        if readingDocument != nil {
            advanceReadingPage(delta: 1)
            return
        }
        guard !isShowingSessionSelector else { return }
        detailAutoAdvanceSuppressed = true
        pageTimer?.invalidate()
        pageTimer = nil
        switch detailDisplayMode {
        case .scrolling:
            pauseAutoScrollForUserInteraction()
        case .paging:
            advanceDetailPageAfterUserInteraction()
        }
    }

    private func advanceDetailPageAfterUserInteraction() {
        guard !isShowingSessionSelector else { return }
        let now = Date().timeIntervalSinceReferenceDate
        guard TouchBarPagePolicy.canAdvanceAfterUserInteraction(
            now: now,
            lastAdvanceAt: lastManualPageAdvanceAt
        ) else {
            return
        }
        lastManualPageAdvanceAt = now
        lastPageAdvanceAt = now
        advanceDetailPageIfNeeded()
    }

    private func advanceDetailPageAutomatically() {
        guard !detailAutoAdvanceSuppressed else { return }
        guard !isShowingSessionSelector else {
            scheduleNextPageAdvance()
            return
        }
        lastPageAdvanceAt = Date().timeIntervalSinceReferenceDate
        advanceDetailPageIfNeeded()
        scheduleNextPageAdvance()
    }

    private func advanceDetailPageIfNeeded() {
        guard !isShowingSessionSelector, detailDisplayMode == .paging, detailPages.count > 1 else { return }
        detailPageIndex = TouchBarPagePolicy.nextPageIndex(
            currentIndex: detailPageIndex,
            pageCount: detailPages.count
        )
        detailLabel.stringValue = detailPages[detailPageIndex]
        resizeDetailDocument()
        scrollDetail(to: 0)
    }

    private func scrollDetail(to x: CGFloat) {
        detailScrollView.contentView.scroll(to: NSPoint(x: max(0, x), y: 0))
        detailScrollView.reflectScrolledClipView(detailScrollView.contentView)
    }
}

private final class SessionChoiceButton: NSButton {
    var sessionURL: URL?
}

private final class ReadingParagraphButton: NSButton {
    var paragraphIndex = 0
}

@MainActor
private final class TouchBarPetView: NSView {
    private enum IdleWalkDirection {
        case left
        case right

        var drawingDirection: TouchBarRobotPetWalkDirection {
            switch self {
            case .left: return .left
            case .right: return .right
            }
        }
    }

    private enum IdleMarkerShape: CaseIterable {
        case circle
        case diamond
        case square
        case sparkle
    }

    private struct IdleMarker {
        var x: CGFloat
        var y: CGFloat
        var shape: IdleMarkerShape
        var color: NSColor
    }

    private static let maximumIdleMarkerCount = 5
    private static let idleConsumptionJumpOffsets: [Double] = [0, 2, 3.5, 2, 0]
    private static let idleConsumptionEyeShapes: [TouchBarRobotPetEyeShape] = [
        .circle,
        .smallCircle,
        .closedLine,
        .smallCircle,
        .circle
    ]

    var onPress: (() -> Void)?

    var idleText = "" {
        didSet {
            if oldValue != idleText {
                idleTargetHeadX = nil
                idleWalkDirection = nil
                trimMarkersToPlayableArea()
                needsDisplay = true
            }
        }
    }

    var usesIdlePlayground = false {
        didSet {
            if oldValue != usesIdlePlayground {
                idleTargetHeadX = nil
                idleWalkDirection = nil
                if !usesIdlePlayground {
                    idleMarkers.removeAll()
                    idleAccentColor = nil
                    idleConsumptionFrame = nil
                }
                scheduleNextIdleMove()
                invalidateIntrinsicContentSize()
                needsDisplay = true
            }
        }
    }

    var mood: TouchBarPetMood = .idle {
        didSet {
            if oldValue != mood {
                frameIndex = 0
                if mood != .idle {
                    idleTargetHeadX = nil
                    idleWalkDirection = nil
                    idleMarkers.removeAll()
                    idleAccentColor = nil
                    idleConsumptionFrame = nil
                }
                needsDisplay = true
            }
        }
    }

    private var frameIndex = 0
    private var animationTimer: Timer?
    private var lastPressAt: TimeInterval = 0
    private var lastAnimationTickAt: TimeInterval?
    private var idleHeadX: CGFloat?
    private var idleTargetHeadX: CGFloat?
    private var idleWalkDirection: IdleWalkDirection?
    private var nextIdleMoveAt: TimeInterval = 0
    private var idleMarkers: [IdleMarker] = []
    private var idleAccentColor: NSColor?
    private var idleConsumptionFrame: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        wantsRestingTouches = true
        startAnimation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        wantsRestingTouches = true
        startAnimation()
    }

    override var intrinsicContentSize: NSSize {
        let width = usesIdlePlayground ? TouchBarLayoutMetrics.detailMinimumWidth : 46
        return NSSize(width: width, height: TouchBarLayoutMetrics.detailViewportHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if usesIdlePlayground, mood == .idle {
            drawIdleText()
            drawIdleMarkers()
        }

        let walkDirection = usesIdlePlayground && mood == .idle
            ? idleWalkDirection?.drawingDirection
            : nil
        var style = TouchBarRobotPetDrawingPolicy.style(
            for: mood,
            frameIndex: frameIndex,
            walkDirection: walkDirection
        )
        applyIdleConsumptionPresentation(to: &style)
        let headRect = robotHeadRect(for: style)
        drawSideModules(around: headRect, style: style)
        drawAntennas(on: headRect, style: style)
        drawHead(in: headRect, style: style)
        drawFace(in: headRect, style: style)
    }

    private func robotHeadRect(for style: TouchBarRobotPetStyle) -> NSRect {
        let x: CGFloat
        if usesIdlePlayground, mood == .idle {
            x = clampedIdleHeadX(for: style)
        } else {
            x = (bounds.width - style.headWidth) / 2
        }
        return NSRect(
            x: x,
            y: (bounds.height - style.headHeight) / 2 + style.verticalOffset,
            width: style.headWidth,
            height: style.headHeight
        )
    }

    private func drawHead(in rect: NSRect, style: TouchBarRobotPetStyle) {
        let path = robotHeadPath(in: rect, style: style)
        bodyColor(for: style.tone).setFill()
        path.fill()

        strokeColor(for: style.tone).setStroke()
        path.lineWidth = 1.1
        path.stroke()

        if style.showsInnerScreen {
            let screenRect = rect.insetBy(dx: 3.8, dy: 4)
            let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: 3.2, yRadius: 3.2)
            NSColor.black.withAlphaComponent(0.28).setFill()
            screenPath.fill()
            strokeColor(for: style.tone).withAlphaComponent(0.55).setStroke()
            screenPath.lineWidth = 0.8
            screenPath.stroke()
        }

        if style.showsHeadHighlight {
            let highlight = NSBezierPath()
            highlight.move(to: NSPoint(x: rect.minX + 6, y: rect.maxY - 4.2))
            highlight.curve(
                to: NSPoint(x: rect.midX - 3, y: rect.maxY - 3.5),
                controlPoint1: NSPoint(x: rect.minX + 10, y: rect.maxY - 2.5),
                controlPoint2: NSPoint(x: rect.midX - 6, y: rect.maxY - 3)
            )
            NSColor.white.withAlphaComponent(0.28).setStroke()
            highlight.lineWidth = 0.8
            highlight.stroke()
        }
    }

    private func robotHeadPath(in rect: NSRect, style: TouchBarRobotPetStyle) -> NSBezierPath {
        switch style.bodyShape {
        case .roundedTv:
            return NSBezierPath(roundedRect: rect, xRadius: style.cornerRadius, yRadius: style.cornerRadius)
        case .cyberTv:
            let cut: CGFloat = 4.2
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX + cut, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX - cut, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY + cut))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - cut))
            path.line(to: NSPoint(x: rect.maxX - cut, y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX + cut, y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY - cut))
            path.line(to: NSPoint(x: rect.minX, y: rect.minY + cut))
            path.close()
            return path
        }
    }

    private func drawFace(in headRect: NSRect, style: TouchBarRobotPetStyle) {
        let faceRect = NSRect(
            x: headRect.midX - style.faceWidth / 2,
            y: headRect.midY - style.faceHeight / 2 - 0.3,
            width: style.faceWidth,
            height: style.faceHeight
        )
        if style.showsFacePanel {
            let facePath = NSBezierPath(roundedRect: faceRect, xRadius: 4, yRadius: 4)
            NSColor(calibratedRed: 0.92, green: 0.97, blue: 1.0, alpha: 0.96).setFill()
            facePath.fill()
            strokeColor(for: style.tone).withAlphaComponent(0.35).setStroke()
            facePath.lineWidth = 0.8
            facePath.stroke()
        }

        drawGeometricFace(in: faceRect, style: style)
    }

    private func drawGeometricFace(in faceRect: NSRect, style: TouchBarRobotPetStyle) {
        let expression = style.faceExpression
        let eyeY = faceRect.midY + 1.3
        let eyeGap: CGFloat = 7.5
        let lookOffset = CGFloat(style.eyeHorizontalOffset)
        drawEye(
            expression.leftEye,
            center: NSPoint(x: faceRect.midX - eyeGap + lookOffset, y: eyeY),
            diameter: CGFloat(style.eyeDiameter),
            color: eyeColor(for: expression.leftEye)
        )
        drawEye(
            expression.rightEye,
            center: NSPoint(x: faceRect.midX + eyeGap + lookOffset, y: eyeY),
            diameter: CGFloat(style.eyeDiameter),
            color: eyeColor(for: expression.rightEye)
        )
    }

    private func drawEye(_ shape: TouchBarRobotPetEyeShape, center: NSPoint, diameter: CGFloat, color: NSColor) {
        let radius = diameter / 2
        switch shape {
        case .circle, .dimCircle:
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: diameter, height: diameter)).fill()
        case .smallCircle:
            let smallDiameter = diameter * 0.58
            let smallRadius = smallDiameter / 2
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - smallRadius, y: center.y - smallRadius, width: smallDiameter, height: smallDiameter)).fill()
        case .closedLine:
            drawRoundedLine(
                from: NSPoint(x: center.x - radius, y: center.y),
                to: NSPoint(x: center.x + radius, y: center.y),
                width: 1.35,
                color: color
            )
        case .happyArc:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: center.x - 3.1, y: center.y - 0.2))
            path.curve(
                to: NSPoint(x: center.x + 3.1, y: center.y - 0.2),
                controlPoint1: NSPoint(x: center.x - 1.7, y: center.y + 2.2),
                controlPoint2: NSPoint(x: center.x + 1.7, y: center.y + 2.2)
            )
            color.setStroke()
            path.lineWidth = 1.35
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    private func drawRoundedLine(from start: NSPoint, to end: NSPoint, width: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        color.setStroke()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
    }

    private func drawIdleText() {
        let text = idleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let attributes = idleTextAttributes()
        let availableWidth = max(0, textMaximumWidth())
        guard availableWidth > 8 else { return }

        let measuredSize = (text as NSString).size(withAttributes: attributes)
        let textHeight = ceil(measuredSize.height)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .left

        var drawingAttributes = attributes
        drawingAttributes[.paragraphStyle] = paragraph

        let rect = NSRect(
            x: 0,
            y: max(0, (bounds.height - textHeight) / 2),
            width: min(ceil(measuredSize.width), availableWidth),
            height: textHeight
        )
        (text as NSString).draw(in: rect, withAttributes: drawingAttributes)
    }

    private func drawIdleMarkers() {
        for marker in idleMarkers {
            drawIdleMarker(marker)
        }
    }

    private func drawIdleMarker(_ marker: IdleMarker) {
        let size: CGFloat = 6
        let rect = NSRect(
            x: marker.x - size / 2,
            y: marker.y - size / 2,
            width: size,
            height: size
        )
        marker.color.setFill()
        marker.color.withAlphaComponent(0.95).setStroke()

        switch marker.shape {
        case .circle:
            let path = NSBezierPath(ovalIn: rect)
            path.fill()
        case .square:
            let path = NSBezierPath(roundedRect: rect, xRadius: 1.4, yRadius: 1.4)
            path.fill()
        case .diamond:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.midX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
            path.line(to: NSPoint(x: rect.midX, y: rect.minY))
            path.line(to: NSPoint(x: rect.minX, y: rect.midY))
            path.close()
            path.fill()
        case .sparkle:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: marker.x, y: marker.y + 4))
            path.line(to: NSPoint(x: marker.x + 1.6, y: marker.y + 1.6))
            path.line(to: NSPoint(x: marker.x + 4, y: marker.y))
            path.line(to: NSPoint(x: marker.x + 1.6, y: marker.y - 1.6))
            path.line(to: NSPoint(x: marker.x, y: marker.y - 4))
            path.line(to: NSPoint(x: marker.x - 1.6, y: marker.y - 1.6))
            path.line(to: NSPoint(x: marker.x - 4, y: marker.y))
            path.line(to: NSPoint(x: marker.x - 1.6, y: marker.y + 1.6))
            path.close()
            path.fill()
        }
    }

    private func drawSideModules(around headRect: NSRect, style: TouchBarRobotPetStyle) {
        guard style.hasSideModules else { return }
        let moduleWidth = CGFloat(style.sideModuleWidth)
        let moduleHeight = CGFloat(style.sideModuleHeight)
        let innerOverlap = CGFloat(style.sideModuleInnerOverlap)
        let y = headRect.midY - moduleHeight / 2
        let left = NSRect(x: headRect.minX - moduleWidth + innerOverlap, y: y, width: moduleWidth, height: moduleHeight)
        let right = NSRect(x: headRect.maxX - innerOverlap, y: y, width: moduleWidth, height: moduleHeight)
        let color = strokeColor(for: style.tone)
        let normalFillColor = style.sideModulesBlendWithBody ? bodyColor(for: style.tone) : color.withAlphaComponent(0.58)
        let highlightedFillColor = color.withAlphaComponent(0.78)
        (style.highlightedSideModule == .left ? highlightedFillColor : normalFillColor).setFill()
        NSBezierPath(roundedRect: left, xRadius: 1.4, yRadius: 1.4).fill()
        (style.highlightedSideModule == .right ? highlightedFillColor : normalFillColor).setFill()
        NSBezierPath(roundedRect: right, xRadius: 1.4, yRadius: 1.4).fill()
        color.withAlphaComponent(0.82).setStroke()
        let leftPath = NSBezierPath(roundedRect: left, xRadius: 1.4, yRadius: 1.4)
        let rightPath = NSBezierPath(roundedRect: right, xRadius: 1.4, yRadius: 1.4)
        leftPath.lineWidth = 0.85
        rightPath.lineWidth = 0.85
        leftPath.stroke()
        rightPath.stroke()
    }

    private func drawAntennas(on headRect: NSRect, style: TouchBarRobotPetStyle) {
        guard style.antennaCount > 0 else { return }
        let color = strokeColor(for: style.tone)
        let swing = CGFloat(style.antennaHorizontalOffset)
        switch style.antennaLayout {
        case .centerFork:
            let base = NSPoint(x: headRect.midX, y: headRect.maxY - 0.3)
            let leftTip = NSPoint(x: max(bounds.minX + 6, headRect.midX - 9 + swing), y: min(bounds.maxY - 1.5, headRect.maxY + 5))
            let rightTip = NSPoint(x: min(bounds.maxX - 6, headRect.midX + 9 + swing), y: min(bounds.maxY - 1.5, headRect.maxY + 5))
            if style.antennaCount == 1 {
                drawLine(from: base, to: rightTip, width: 1.1, color: color)
                drawAntennaTip(at: rightTip, color: color)
                return
            }
            drawLine(from: base, to: leftTip, width: 1.1, color: color)
            drawLine(from: base, to: rightTip, width: 1.1, color: color)
            drawAntennaTip(at: leftTip, color: color)
            drawAntennaTip(at: rightTip, color: color)
        case .splitTop:
            let leftBase = NSPoint(x: headRect.minX + 9.5, y: headRect.maxY - 0.2)
            let rightBase = NSPoint(x: headRect.maxX - 9.5, y: headRect.maxY - 0.2)
            let leftTip = NSPoint(x: max(bounds.minX + 7, leftBase.x - 2.8 + swing), y: min(bounds.maxY - 1.5, headRect.maxY + 4.4))
            let rightTip = NSPoint(x: min(bounds.maxX - 7, rightBase.x + 2.8 + swing), y: min(bounds.maxY - 1.5, headRect.maxY + 4.4))
            if style.antennaCount == 1 {
                drawLine(from: rightBase, to: rightTip, width: 1.1, color: color)
                drawAntennaTip(at: rightTip, color: color)
                return
            }
            drawLine(from: leftBase, to: leftTip, width: 1.1, color: color)
            drawLine(from: rightBase, to: rightTip, width: 1.1, color: color)
            drawAntennaTip(at: leftTip, color: color)
            drawAntennaTip(at: rightTip, color: color)
        }
    }

    private func drawAntennaTip(at point: NSPoint, color: NSColor) {
        color.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - 1.25, y: point.y - 1.25, width: 2.5, height: 2.5)).fill()
    }

    private func drawLine(from start: NSPoint, to end: NSPoint, width: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        color.setStroke()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
    }

    private func eyeColor(for shape: TouchBarRobotPetEyeShape) -> NSColor {
        switch shape {
        case .dimCircle:
            return NSColor.white.withAlphaComponent(0.58)
        case .circle, .smallCircle, .closedLine, .happyArc:
            return NSColor.white.withAlphaComponent(0.96)
        }
    }

    private func bodyColor(for tone: TouchBarRobotPetTone) -> NSColor {
        switch tone {
        case .idle:
            if let idleAccentColor {
                return idleAccentColor.withAlphaComponent(0.28)
            }
            return NSColor(calibratedRed: 0.25, green: 0.36, blue: 0.48, alpha: 0.28)
        case .thinking:
            return NSColor.systemPurple.withAlphaComponent(0.24)
        case .running:
            return NSColor.systemBlue.withAlphaComponent(0.34)
        case .approval:
            return NSColor.systemOrange.withAlphaComponent(0.36)
        case .completed:
            return NSColor.systemGreen.withAlphaComponent(0.34)
        case .failed:
            return NSColor.systemRed.withAlphaComponent(0.32)
        case .reading:
            return NSColor.systemIndigo.withAlphaComponent(0.32)
        case .selecting:
            return NSColor.systemCyan.withAlphaComponent(0.34)
        }
    }

    private func strokeColor(for tone: TouchBarRobotPetTone) -> NSColor {
        switch tone {
        case .idle:
            if let idleAccentColor {
                return idleAccentColor.withAlphaComponent(0.9)
            }
            return NSColor(calibratedRed: 0.46, green: 0.62, blue: 0.8, alpha: 0.9)
        case .thinking:
            return NSColor.systemPurple.withAlphaComponent(0.82)
        case .running:
            return .systemBlue
        case .approval:
            return .systemOrange
        case .completed:
            return .systemGreen
        case .failed:
            return .systemRed
        case .reading:
            return .systemIndigo
        case .selecting:
            return .systemCyan
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !handlePress(at: point) {
            super.mouseDown(with: event)
        }
    }

    override func touchesBegan(with event: NSEvent) {
        let touches = event.touches(matching: .touching, in: self)
        if let touch = touches.first {
            let handled = handlePress(at: touch.location(in: self))
            if !handled {
                super.touchesBegan(with: event)
            }
        } else {
            triggerPress()
            super.touchesBegan(with: event)
        }
    }

    func handleIdlePlaygroundPress(at point: NSPoint) -> Bool {
        handlePress(at: point)
    }

    private func handlePress(at point: NSPoint) -> Bool {
        guard usesIdlePlayground, mood == .idle else {
            triggerPress()
            return true
        }

        let style = TouchBarRobotPetDrawingPolicy.style(for: .idle, frameIndex: frameIndex)
        let headRect = robotHeadRect(for: style).insetBy(dx: -8, dy: -5)
        if headRect.contains(point) {
            triggerPress()
            return true
        }

        guard idleMovementArea().contains(point) else { return false }
        addIdleMarker(at: point)
        return true
    }

    private func triggerPress() {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastPressAt > 0.2 else { return }
        lastPressAt = now
        onPress?()
    }

    private func startAnimation() {
        animationTimer?.invalidate()
        let timer = Timer(timeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = Date().timeIntervalSinceReferenceDate
                let elapsed = min(0.36, max(0.01, now - (self.lastAnimationTickAt ?? now)))
                self.lastAnimationTickAt = now
                self.frameIndex = (self.frameIndex + 1) % 36
                self.advanceIdleConsumptionAnimation()
                self.updateIdleWalk(now: now, elapsed: elapsed)
                self.needsDisplay = true
            }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateIdleWalk(now: TimeInterval, elapsed: TimeInterval) {
        let style = TouchBarRobotPetDrawingPolicy.style(for: .idle, frameIndex: frameIndex)
        let range = idleHeadRange(for: style)
        guard usesIdlePlayground, mood == .idle else {
            idleTargetHeadX = nil
            idleWalkDirection = nil
            return
        }
        guard range.upperBound - range.lowerBound > 12 else {
            idleHeadX = range.lowerBound
            idleTargetHeadX = nil
            idleWalkDirection = nil
            return
        }

        var currentX = min(max(idleHeadX ?? range.lowerBound, range.lowerBound), range.upperBound)
        if let marker = idleMarkers.first {
            let target = min(max(marker.x - CGFloat(style.headWidth) / 2, range.lowerBound), range.upperBound)
            let direction: IdleWalkDirection = target >= currentX ? .right : .left
            let speed = CGFloat(42)
            let step = speed * CGFloat(elapsed)
            let delta = target - currentX
            if abs(delta) <= step {
                currentX = target
            } else {
                currentX += direction == .right ? step : -step
            }
            idleHeadX = min(max(currentX, range.lowerBound), range.upperBound)
            idleWalkDirection = abs(marker.x - petCenterX(style: style)) > 7 ? direction : nil
            consumeReachedIdleMarkers(style: style)
            return
        }

        if let targetX = idleTargetHeadX, let direction = idleWalkDirection {
            let speed = CGFloat(30)
            let step = speed * CGFloat(elapsed)
            let delta = targetX - currentX
            if abs(delta) <= step {
                currentX = targetX
                idleTargetHeadX = nil
                idleWalkDirection = nil
                nextIdleMoveAt = now + Double.random(in: 0.45...1.25)
            } else {
                currentX += direction == .right ? step : -step
            }
            idleHeadX = min(max(currentX, range.lowerBound), range.upperBound)
            return
        }

        idleHeadX = currentX
        if nextIdleMoveAt == 0 {
            scheduleNextIdleMove(from: now)
        }
        guard now >= nextIdleMoveAt else { return }

        let direction = nextIdleWalkDirection(currentX: currentX, range: range)
        let distance = CGFloat.random(in: 18...56)
        let proposedTarget = currentX + (direction == .right ? distance : -distance)
        let target = min(max(proposedTarget, range.lowerBound), range.upperBound)
        if abs(target - currentX) > 2 {
            idleTargetHeadX = target
            idleWalkDirection = direction
        } else {
            nextIdleMoveAt = now + Double.random(in: 0.35...0.9)
        }
    }

    private func nextIdleWalkDirection(currentX: CGFloat, range: ClosedRange<CGFloat>) -> IdleWalkDirection {
        if currentX <= range.lowerBound + 3 {
            return .right
        }
        if currentX >= range.upperBound - 3 {
            return .left
        }
        return Bool.random() ? .left : .right
    }

    private func scheduleNextIdleMove(from now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        nextIdleMoveAt = now + Double.random(in: 0.7...1.9)
    }

    private func addIdleMarker(at point: NSPoint) {
        let area = idleMovementArea()
        let style = TouchBarRobotPetDrawingPolicy.style(for: .idle, frameIndex: frameIndex)
        let reachableX = idleMarkerXRange(for: style)
        let marker = IdleMarker(
            x: min(max(point.x, reachableX.lowerBound), reachableX.upperBound),
            y: min(max(point.y, area.minY + 5), area.maxY - 5),
            shape: IdleMarkerShape.allCases.randomElement() ?? .circle,
            color: randomIdleMarkerColor()
        )
        idleMarkers.append(marker)
        if idleMarkers.count > Self.maximumIdleMarkerCount {
            idleMarkers.removeFirst(idleMarkers.count - Self.maximumIdleMarkerCount)
        }
        idleTargetHeadX = nil
        idleWalkDirection = nil
        needsDisplay = true
    }

    private func consumeReachedIdleMarkers(style: TouchBarRobotPetStyle) {
        let headRect = robotHeadRect(for: style)
        let sideModuleAllowance = CGFloat(style.hasSideModules ? style.sideModuleWidth : 0)
        let contactRect = headRect.insetBy(dx: -(sideModuleAllowance + 4), dy: -6)
        let beforeCount = idleMarkers.count
        let consumedMarker = idleMarkers.first { marker in
            contactRect.contains(NSPoint(x: marker.x, y: marker.y))
        }
        idleMarkers.removeAll { marker in
            contactRect.contains(NSPoint(x: marker.x, y: marker.y))
        }
        if beforeCount != idleMarkers.count {
            idleAccentColor = consumedMarker?.color
            idleConsumptionFrame = 0
            idleTargetHeadX = nil
            idleWalkDirection = nil
            if idleMarkers.isEmpty {
                scheduleNextIdleMove(from: Date().timeIntervalSinceReferenceDate)
            }
        }
    }

    private func advanceIdleConsumptionAnimation() {
        guard let idleConsumptionFrame else { return }
        let nextFrame = idleConsumptionFrame + 1
        self.idleConsumptionFrame = nextFrame < Self.idleConsumptionJumpOffsets.count ? nextFrame : nil
    }

    private func applyIdleConsumptionPresentation(to style: inout TouchBarRobotPetStyle) {
        guard usesIdlePlayground,
              mood == .idle,
              let idleConsumptionFrame,
              Self.idleConsumptionJumpOffsets.indices.contains(idleConsumptionFrame)
        else {
            return
        }

        let eyeShape = Self.idleConsumptionEyeShapes[idleConsumptionFrame]
        style.verticalOffset += Self.idleConsumptionJumpOffsets[idleConsumptionFrame]
        style.faceExpression = TouchBarRobotPetFaceExpression(
            leftEye: eyeShape,
            rightEye: eyeShape,
            mouth: .flat
        )
    }

    private func clampedIdleHeadX(for style: TouchBarRobotPetStyle) -> CGFloat {
        let range = idleHeadRange(for: style)
        let current = idleHeadX ?? range.lowerBound
        let clamped = min(max(current, range.lowerBound), range.upperBound)
        idleHeadX = clamped
        return clamped
    }

    private func idleHeadRange(for style: TouchBarRobotPetStyle) -> ClosedRange<CGFloat> {
        let sideModuleAllowance = CGFloat(style.hasSideModules ? style.sideModuleWidth : 0)
        let inset = CGFloat(5) + sideModuleAllowance
        let minX = bounds.minX + idleTextReservedWidth() + inset
        let maxX = max(minX, bounds.maxX - CGFloat(style.headWidth) - inset)
        return minX...maxX
    }

    private func idleMovementArea() -> NSRect {
        let minX = bounds.minX + idleTextReservedWidth()
        return NSRect(
            x: minX,
            y: bounds.minY,
            width: max(0, bounds.maxX - minX),
            height: bounds.height
        )
    }

    private func idleMarkerXRange(for style: TouchBarRobotPetStyle) -> ClosedRange<CGFloat> {
        let movementArea = idleMovementArea()
        let headRange = idleHeadRange(for: style)
        let sideModuleAllowance = CGFloat(style.hasSideModules ? style.sideModuleWidth : 0)
        let edgeInset = sideModuleAllowance + 5
        let minX = max(movementArea.minX + edgeInset, headRange.lowerBound - sideModuleAllowance)
        let maxX = max(minX, min(movementArea.maxX - edgeInset, headRange.upperBound + CGFloat(style.headWidth) + sideModuleAllowance))
        return minX...maxX
    }

    private func petCenterX(style: TouchBarRobotPetStyle) -> CGFloat {
        clampedIdleHeadX(for: style) + CGFloat(style.headWidth) / 2
    }

    private func trimMarkersToPlayableArea() {
        let style = TouchBarRobotPetDrawingPolicy.style(for: .idle, frameIndex: frameIndex)
        let area = idleMovementArea()
        let reachableX = idleMarkerXRange(for: style)
        idleMarkers.removeAll { marker in
            marker.x < reachableX.lowerBound
                || marker.x > reachableX.upperBound
                || !area.insetBy(dx: -2, dy: -2).contains(NSPoint(x: marker.x, y: marker.y))
        }
    }

    private func idleTextReservedWidth() -> CGFloat {
        guard usesIdlePlayground, mood == .idle else { return 0 }
        let text = idleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 0 }
        let measuredWidth = ceil((text as NSString).size(withAttributes: idleTextAttributes()).width)
        return min(measuredWidth, textMaximumWidth()) + 14
    }

    private func textMaximumWidth() -> CGFloat {
        let minimumPetTrackWidth: CGFloat = 230
        return max(0, bounds.width - minimumPetTrackWidth)
    }

    private func idleTextAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.92)
        ]
    }

    private func randomIdleMarkerColor() -> NSColor {
        [
            NSColor.systemBlue,
            NSColor.systemCyan,
            NSColor.systemGreen,
            NSColor.systemOrange,
            NSColor.systemPink,
            NSColor.systemPurple
        ].randomElement()?.withAlphaComponent(0.86) ?? NSColor.systemBlue.withAlphaComponent(0.86)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

@MainActor
private final class UserAwareTouchBarScrollView: NSScrollView {
    var onUserInteraction: (() -> Void)?
    var onDocumentPress: ((NSPoint) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsRestingTouches = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsRestingTouches = true
    }

    override func scrollWheel(with event: NSEvent) {
        onUserInteraction?()
        super.scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if let documentView, onDocumentPress?(documentView.convert(event.locationInWindow, from: nil)) == true {
            return
        }
        onUserInteraction?()
        super.mouseDown(with: event)
    }

    override func touchesBegan(with event: NSEvent) {
        if let documentView,
           let touch = event.touches(matching: .touching, in: self).first,
           onDocumentPress?(touch.location(in: documentView)) == true {
            return
        }
        onUserInteraction?()
        super.touchesBegan(with: event)
    }

    override func touchesMoved(with event: NSEvent) {
        onUserInteraction?()
        super.touchesMoved(with: event)
    }
}
