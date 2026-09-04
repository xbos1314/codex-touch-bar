import AppKit
import AVFoundation
import CodexTouchBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, MenuBarControllerDelegate, TouchBarControllerDelegate {
    private let sessionStore = CodexSessionStore()
    private let tailer = JSONLTailer()
    private let parser = CodexEventParser()
    private lazy var reducer = DisplayStateReducer(parser: parser)
    private let rotation = RotatingDetailSelector()
    private var settings = TouchBarSettings()
    private let completionSpeechController = CompletionSpeechController()
    private let quotaClient = CodexQuotaClient()
    private let touchBarAvailable = TouchBarHardwareCapability.isAvailable
    private lazy var touchBarController: TouchBarController? = touchBarAvailable ? TouchBarController() : nil
    private lazy var alwaysOnPresenter: PrivateTouchBarPresenter? = touchBarAvailable ? PrivateTouchBarPresenter() : nil
    private lazy var menuBarController = MenuBarController(isTouchBarAvailable: touchBarAvailable)
    private let fileEventQueue = DispatchQueue(label: "com.local.codex-touch-bar.file-events")
    private let sessionsRootURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)

    private var state = CodexDisplayState.idle(message: "Waiting for Codex activity")
    private var availableSessions: [CodexSessionFile] = []
    private var sessionSelectionMode: CodexSessionSelectionMode = .automaticLatest
    private var selectedURL: URL?
    private var monitoredSessionURL: URL?
    private var cursor: UInt64 = 0
    private var paused = false
    private var sessionsDirectoryMonitor: FileSystemEventMonitor?
    private var selectedSessionMonitor: FileSystemEventMonitor?
    private var scanTimer: Timer?
    private var tailTimer: Timer?
    private var rotationTimer: Timer?
    private var quotaRefreshTimer: Timer?
    private var quotaSnapshot = CodexQuotaSnapshot.unavailable
    private var readingDocument: ReadingDocument?
    private var readingPageIndex = 0
    private var readingPageCount = 0
    private lazy var cachedCompletionSpeechVoiceOptions: [CompletionSpeechVoiceOption] = loadCompletionSpeechVoiceOptions()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController.delegate = self
        touchBarController?.delegate = self
        quotaClient.onSnapshot = { [weak self] snapshot in
            self?.quotaSnapshot = snapshot
            self?.render()
        }
        render()
        applyPresentationMode()
        startTimers()
        quotaClient.start()
        refreshSession()
    }

    func applicationWillTerminate(_ notification: Notification) {
        completionSpeechController.stop()
        quotaRefreshTimer?.invalidate()
        quotaClient.stop()
        persistReadingProgress()
        alwaysOnPresenter?.dismiss()
        sessionsDirectoryMonitor?.stop()
        selectedSessionMonitor?.stop()
    }

    private func startTimers() {
        startSessionsDirectoryMonitor()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.startSessionsDirectoryMonitor()
                self?.refreshSession()
            }
        }
        tailTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollTail() }
        }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
        quotaRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.paused else { return }
                self.quotaClient.refresh()
            }
        }
    }

    private func refreshSession() {
        guard !paused else { return }
        do {
            availableSessions = try sessionStore.recentPrimarySessions()
            sessionSelectionMode = CodexSessionSelectionPolicy.validatedMode(
                sessionSelectionMode,
                sessions: availableSessions
            )

            guard let session = CodexSessionSelectionPolicy.selectedSession(
                from: availableSessions,
                mode: sessionSelectionMode
            ) else {
                state = .idle(message: waitingForCodexActivity())
                cursor = 0
                selectedURL = nil
                stopSelectedSessionMonitor()
                render()
                return
            }

            if selectedURL != session.url {
                try loadSession(session)
            } else {
                render()
            }
        } catch {
            state = .idle(message: cannotReadCodexSession())
            render()
        }
    }

    private func loadSession(_ session: CodexSessionFile) throws {
        selectedURL = session.url
        let tail = try tailer.readTail(fileURL: session.url)
        cursor = tail.nextOffset
        let events = parser.parseEvents(from: tail.text)
        state = reducer.reduce(state: reducer.reset(session: session), events: events, session: session)
        watchSelectedSession(at: session.url)
        render()
    }

    private func pollTail() {
        guard !paused, let currentURL = selectedURL else { return }
        do {
            guard let session = try sessionStore.sessionFile(at: currentURL) else {
                if case .locked(let url) = sessionSelectionMode, url == currentURL {
                    sessionSelectionMode = .automaticLatest
                }
                selectedURL = nil
                cursor = 0
                refreshSession()
                return
            }
            if session.size < cursor {
                selectedURL = nil
                cursor = 0
                refreshSession()
                return
            }
            let result = try tailer.readCompleteRange(fileURL: currentURL, offset: cursor, size: session.size)
            guard result.nextOffset != cursor else {
                render()
                return
            }
            cursor = result.nextOffset
            let events = parser.parseEvents(from: result.text)
            state = reducer.reduce(state: state, events: events, session: session)
            render()
        } catch {
            state = .idle(message: cannotReadCodexSession())
            render()
        }
    }

    private func startSessionsDirectoryMonitor() {
        guard sessionsDirectoryMonitor == nil else { return }
        let monitor = FileSystemEventMonitor(
            url: sessionsRootURL,
            eventMask: [.write, .extend, .delete, .rename],
            queue: fileEventQueue
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.refreshSession()
            }
        }
        guard monitor.start() else { return }
        sessionsDirectoryMonitor = monitor
    }

    private func watchSelectedSession(at url: URL) {
        guard monitoredSessionURL != url else { return }
        stopSelectedSessionMonitor()
        let monitor = FileSystemEventMonitor(
            url: url,
            eventMask: [.write, .extend, .delete, .rename],
            queue: fileEventQueue
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.pollTail()
            }
        }
        guard monitor.start() else { return }
        monitoredSessionURL = url
        selectedSessionMonitor = monitor
    }

    private func stopSelectedSessionMonitor() {
        selectedSessionMonitor?.stop()
        selectedSessionMonitor = nil
        monitoredSessionURL = nil
    }

    private func render() {
        let voiceOptions = completionSpeechVoiceOptions()
        let codexDetail = rotation.detailPresentation(
            for: state,
            idleTargetName: idleTargetName(),
            language: settings.displayLanguage
        )
        let statusBarContent = readingDocument.map {
            (text: $0.text, key: "reading|\($0.id)")
        } ?? (text: codexDetail.text, key: "codex|\(state.sessionId ?? "-")|\(codexDetail.text)")
        if readingDocument == nil {
            completionSpeechController.apply(
                state: state,
                isEnabled: settings.completionSpeechEnabled,
                voiceIdentifier: settings.completionSpeechVoiceIdentifier,
                voiceOptions: voiceOptions,
                rate: settings.completionSpeechRate,
                pitch: settings.completionSpeechPitch
            )
        } else {
            completionSpeechController.stop()
        }
        if let readingDocument, let touchBarController {
            let progress = touchBarController.applyReading(
                document: readingDocument,
                requestedPageIndex: readingPageIndex,
                autoPageInterval: settings.readingAutoPageSpeed.intervalSeconds,
                language: settings.displayLanguage
            )
            readingPageIndex = progress.pageIndex
            readingPageCount = progress.pageCount
            persistReadingProgress()
        } else if let touchBarController {
            touchBarController.apply(
                state: state,
                detail: codexDetail,
                language: settings.displayLanguage,
                displayMode: settings.detailDisplayMode,
                detailScrollSpeed: settings.detailScrollSpeed,
                detailPageSpeed: settings.detailPageSpeed,
                sessions: availableSessions,
                selectionMode: sessionSelectionMode
            )
            readingPageCount = 0
        } else {
            readingPageCount = 0
        }
        let progressTitle = ReadingProgressPresentationPolicy.presentation(
            pageIndex: readingPageIndex,
            pageCount: readingDocument == nil ? 0 : readingPageCount,
            language: settings.displayLanguage
        ).progressTitle
        menuBarController.apply(
            state: state,
            quotaSnapshot: quotaSnapshot,
            language: settings.displayLanguage,
            statusBarContentEnabled: settings.statusBarContentEnabled,
            statusBarContentText: statusBarContent.text,
            statusBarContentKey: statusBarContent.key,
            sessions: availableSessions,
            sessionSelectionMode: sessionSelectionMode,
            paused: paused,
            detailDisplayMode: settings.detailDisplayMode,
            detailScrollSpeed: settings.detailScrollSpeed,
            detailPageSpeed: settings.detailPageSpeed,
            statusBarPageSpeed: settings.statusBarPageSpeed,
            readingAutoPageSpeed: settings.readingAutoPageSpeed,
            alwaysOnStatus: alwaysOnPresenter?.status.menuText(language: settings.displayLanguage) ?? "",
            readingFileName: readingDocument?.fileName,
            readingFilePath: readingDocument?.fileURL.path,
            readingProgressTitle: progressTitle,
            continueReadingFileName: resumableReadingFileName(),
            completionSpeechEnabled: settings.completionSpeechEnabled,
            completionSpeechVoiceIdentifier: settings.completionSpeechVoiceIdentifier,
            completionSpeechVoiceOptions: voiceOptions,
            completionSpeechRate: settings.completionSpeechRate,
            completionSpeechPitch: settings.completionSpeechPitch
        )
    }

    func menuBarDidTogglePause() {
        paused.toggle()
        render()
    }

    func menuBarDidToggleStatusBarContent() {
        settings.statusBarContentEnabled.toggle()
        render()
    }

    func menuBarDidRequestOpenCurrentSession() {
        openCurrentSessionInDesktop()
    }

    func menuBarDidSelectAutomaticSession() {
        touchBarDidSelectAutomaticSession()
    }

    func menuBarDidSelectSession(url: URL) {
        touchBarDidSelectSession(url: url)
    }

    func menuBarDidRequestOpenReadingFile() {
        openReadingFilePanel()
    }

    func menuBarDidRequestContinueReading() {
        guard let path = settings.lastReadingFilePath else { return }
        openReadingFile(at: URL(fileURLWithPath: path))
    }

    func menuBarDidRequestExitReadingMode() {
        persistReadingProgress()
        readingDocument = nil
        readingPageIndex = 0
        readingPageCount = 0
        render()
    }

    func menuBarDidToggleCompletionSpeech() {
        settings.completionSpeechEnabled.toggle()
        if !settings.completionSpeechEnabled {
            completionSpeechController.stop()
        }
        render()
    }

    func menuBarDidSelectCompletionSpeechVoice(identifier: String?) {
        settings.completionSpeechVoiceIdentifier = identifier
        completionSpeechController.stop()
        render()
    }

    func menuBarDidSelectCompletionSpeechRate(_ rate: CompletionSpeechRate) {
        settings.completionSpeechRate = rate
        completionSpeechController.stop()
        render()
    }

    func menuBarDidSelectCompletionSpeechPitch(_ pitch: CompletionSpeechPitch) {
        settings.completionSpeechPitch = pitch
        completionSpeechController.stop()
        render()
    }

    func menuBarDidSelectDetailDisplayMode(_ mode: TouchBarDetailDisplayMode) {
        settings.detailDisplayMode = mode
        render()
    }

    func menuBarDidSelectDetailScrollSpeed(_ speed: DetailDisplaySpeed) {
        settings.detailScrollSpeed = speed
        render()
    }

    func menuBarDidSelectDetailPageSpeed(_ speed: DetailDisplaySpeed) {
        settings.detailPageSpeed = speed
        render()
    }

    func menuBarDidSelectStatusBarPageSpeed(_ speed: DetailDisplaySpeed) {
        settings.statusBarPageSpeed = speed
        render()
    }

    func menuBarDidSelectReadingAutoPageSpeed(_ speed: ReadingAutoPageSpeed) {
        settings.readingAutoPageSpeed = speed
        render()
    }

    func menuBarDidSelectDisplayLanguage(_ language: DisplayLanguage) {
        guard settings.displayLanguage != language else { return }
        settings.displayLanguage = language
        render()
    }

    func menuBarDidRequestRefresh() {
        refreshSession()
        pollTail()
        quotaClient.refresh()
    }

    func touchBarDidSelectAutomaticSession() {
        sessionSelectionMode = .automaticLatest
        selectedURL = nil
        cursor = 0
        refreshSession()
    }

    func touchBarDidSelectSession(url: URL) {
        sessionSelectionMode = .locked(url)
        selectedURL = nil
        cursor = 0
        refreshSession()
    }

    func touchBarDidRequestOpenCurrentSession() {
        openCurrentSessionInDesktop()
    }

    func touchBarDidRequestIdleCurrentSession() {
        state = idleDisplayStateKeepingCurrentSession()
        completionSpeechController.stop()
        render()
    }

    private func applyPresentationMode() {
        guard let alwaysOnPresenter, let touchBarController else { return }
        _ = alwaysOnPresenter.present(touchBarController.touchBar)
        render()
    }

    private func idleTargetName() -> String {
        switch sessionSelectionMode {
        case .automaticLatest:
            return "AUTO"
        case .locked:
            let projectName = state.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            return projectName.isEmpty || projectName == "-" ? currentProjectLabel() : projectName
        }
    }

    private func waitingForCodexActivity() -> String {
        settings.displayLanguage == .english ? "Waiting for Codex activity" : "等待 Codex 活动"
    }

    private func cannotReadCodexSession() -> String {
        settings.displayLanguage == .english ? "Unable to read Codex session" : "无法读取 Codex 会话"
    }

    private func currentProjectLabel() -> String {
        settings.displayLanguage == .english ? "Current Project" : "当前项目"
    }

    private func openCurrentSessionInDesktop() {
        guard let rawSessionId = state.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawSessionId.isEmpty,
              let encodedSessionId = rawSessionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "codex://threads/\(encodedSessionId)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func idleDisplayStateKeepingCurrentSession() -> CodexDisplayState {
        CodexDisplayState(
            sessionId: state.sessionId,
            projectName: state.projectName,
            projectPath: state.projectPath,
            status: .idle,
            latestActivity: CodexActivity(
                id: "idle-dismissed-completion",
                timestamp: "",
                kind: .thinking,
                status: .completed,
                text: waitingForCodexActivity()
            ),
            activities: state.activities,
            latestAssistantText: nil,
            latestAssistantTimestamp: nil,
            latestUserText: nil,
            latestUserTimestamp: nil,
            isTaskRunning: false,
            isTaskComplete: false,
            lastUpdatedAt: Date()
        )
    }

    private func openReadingFilePanel() {
        let panel = NSOpenPanel()
        panel.title = settings.displayLanguage == .english ? "Open Reading File" : "打开阅读文件"
        panel.prompt = settings.displayLanguage == .english ? "Open" : "打开"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        openReadingFile(at: url)
    }

    private func openReadingFile(at url: URL) {
        do {
            let document = try ReadingFileLoader.load(from: url)
            completionSpeechController.reset()
            readingDocument = document
            settings.statusBarContentEnabled = true
            settings.lastReadingFilePath = url.path
            readingPageIndex = settings.readingPageIndex(forFilePath: url.path)
            readingPageCount = 0
            render()
        } catch {
            showReadingError(error, fileName: url.lastPathComponent)
        }
    }

    private func persistReadingProgress() {
        guard let readingDocument else { return }
        let progress = touchBarController?.currentReadingProgress()
        let pageIndex: Int
        if let progress, progress.pageCount > 0 {
            pageIndex = progress.pageIndex
        } else {
            pageIndex = readingPageIndex
        }
        settings.lastReadingFilePath = readingDocument.fileURL.path
        settings.setReadingPageIndex(pageIndex, forFilePath: readingDocument.fileURL.path)
    }

    private func resumableReadingFileName() -> String? {
        guard let path = settings.lastReadingFilePath,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func showReadingError(_ error: Error, fileName: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = settings.displayLanguage == .english ? "Unable to Read File" : "无法读取文件"
        alert.informativeText = "\(fileName)\n\(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func completionSpeechVoiceOptions() -> [CompletionSpeechVoiceOption] {
        cachedCompletionSpeechVoiceOptions
    }

    private func loadCompletionSpeechVoiceOptions() -> [CompletionSpeechVoiceOption] {
        AVSpeechSynthesisVoice.speechVoices().map { voice in
            CompletionSpeechVoiceOption(
                identifier: voice.identifier,
                name: voice.name,
                language: voice.language,
                qualityRank: Int(voice.quality.rawValue)
            )
        }
    }
}
