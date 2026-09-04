import Foundation

public struct CodexDetailPresentation: Equatable {
    public var text: String
    public var activitySymbolName: String?
    public var activityAccessibilityLabel: String?
    public var fallbackPrefix: String?

    public init(
        text: String,
        activitySymbolName: String? = nil,
        activityAccessibilityLabel: String? = nil,
        fallbackPrefix: String? = nil
    ) {
        self.text = text
        self.activitySymbolName = activitySymbolName
        self.activityAccessibilityLabel = activityAccessibilityLabel
        self.fallbackPrefix = fallbackPrefix
    }

    public var fallbackText: String {
        guard let fallbackPrefix else { return text }
        return "\(fallbackPrefix) \(text)"
    }
}

public final class RotatingDetailSelector {
    private let completedHoldSeconds: TimeInterval

    public init(completedHoldSeconds: TimeInterval = 2.5) {
        self.completedHoldSeconds = completedHoldSeconds
    }

    public func detailText(
        for state: CodexDisplayState,
        now: Date = Date(),
        idleTargetName: String? = nil,
        language: DisplayLanguage = .english
    ) -> String {
        detailPresentation(for: state, now: now, idleTargetName: idleTargetName, language: language).fallbackText
    }

    public func detailPresentation(
        for state: CodexDisplayState,
        now: Date = Date(),
        idleTargetName: String? = nil,
        language: DisplayLanguage = .english
    ) -> CodexDetailPresentation {
        if let activity = state.latestActivity, activity.kind == .approval, activity.status == .running {
            return CodexDetailPresentation(text: activityText(activity, language: language))
        }

        if let activity = state.latestActivity,
           shouldShowFinishedActivityBeforeMessage(activity, state: state, now: now) {
            return CodexDetailPresentation(text: activityText(activity, language: language))
        }

        if let assistant = primaryMessageText(from: state) {
            if let prefix = activityPrefix(for: state.latestActivity, now: now, language: language) {
                return CodexDetailPresentation(
                    text: assistant,
                    activitySymbolName: prefix.systemSymbolName,
                    activityAccessibilityLabel: prefix.accessibilityLabel,
                    fallbackPrefix: prefix.fallbackText
                )
            }
            return CodexDetailPresentation(text: assistant)
        }

        if let activity = state.latestActivity, activity.status == .running {
            return CodexDetailPresentation(text: activityText(activity, language: language))
        }

        if state.status == .idle, let idleText = idleText(targetName: idleTargetName, language: language) {
            return CodexDetailPresentation(text: idleText)
        }

        if let activity = state.latestActivity,
           (activity.status == .completed || activity.status == .failed),
           let updated = state.lastUpdatedAt,
           now.timeIntervalSince(updated) <= completedHoldSeconds {
            return CodexDetailPresentation(text: activityText(activity, language: language))
        }

        if let assistant = state.latestAssistantText, !assistant.isEmpty {
            return CodexDetailPresentation(text: fit(assistant))
        }

        if let activity = state.latestActivity {
            return CodexDetailPresentation(text: activityText(activity, language: language))
        }

        return CodexDetailPresentation(text: idleText(targetName: idleTargetName, language: language) ?? waitingForCodexActivity(language: language))
    }

    public func activityPrefix(
        for activity: CodexActivity?,
        now: Date = Date(),
        language: DisplayLanguage = .english
    ) -> CodexActivityPrefix? {
        guard let activity, activity.status == .running else { return nil }
        switch activity.kind {
        case .thinking:
            return thinkingFrame(now: now, language: language)
        case .fileRead:
            return activityPrefix(symbol: "doc.text.magnifyingglass", english: ("Viewing file", "Viewing"), chinese: ("查看文件", "查看"), language: language)
        case .imageView:
            return activityPrefix(symbol: "photo", english: ("Viewing image", "Image"), chinese: ("查看图片", "图片"), language: language)
        case .webSearch:
            return activityPrefix(symbol: "globe", english: ("Searching web", "Search"), chinese: ("搜索网页", "搜索"), language: language)
        case .fileEdit:
            return activityPrefix(symbol: "square.and.pencil", english: ("Editing file", "Editing"), chinese: ("编辑文件", "编辑"), language: language)
        case .command:
            return activityPrefix(symbol: "terminal", english: ("Running command", "Command"), chinese: ("执行命令", "命令"), language: language)
        case .tool:
            return activityPrefix(symbol: "wrench.and.screwdriver", english: ("Using tool", "Tool"), chinese: ("调用工具", "工具"), language: language)
        case .imageGeneration:
            return activityPrefix(symbol: "wand.and.stars", english: ("Generating image", "Generate"), chinese: ("创作图片", "创作"), language: language)
        case .subagent:
            return activityPrefix(symbol: "person.2", english: ("Subagent working", "Subagent"), chinese: ("子智能体", "子任务"), language: language)
        case .approval:
            return activityPrefix(symbol: "hand.raised", english: ("Waiting for approval", "Approval"), chinese: ("等待审批", "审批"), language: language)
        }
    }

    public func fit(_ text: String, maxCharacters: Int = 80) -> String {
        let normalized = CodexDisplayTextFormatter.displayText(from: text)
        guard normalized.count > maxCharacters else { return normalized }
        return String(normalized.prefix(maxCharacters - 3)) + "..."
    }

    private func primaryMessageText(from state: CodexDisplayState) -> String? {
        let assistant = normalizedMessageText(state.latestAssistantText)
        let user = normalizedMessageText(state.latestUserText)

        if let user, userIsNewerThanAssistant(in: state) {
            return user
        }

        return assistant ?? user
    }

    private func normalizedMessageText(_ text: String?) -> String? {
        guard let text else { return nil }
        let normalized = CodexDisplayTextFormatter.displayText(from: text)
        return normalized.isEmpty ? nil : normalized
    }

    private func userIsNewerThanAssistant(in state: CodexDisplayState) -> Bool {
        guard state.latestUserText != nil else { return false }
        guard let userTimestamp = state.latestUserTimestamp else { return state.latestAssistantText == nil }
        guard let assistantTimestamp = state.latestAssistantTimestamp else { return true }
        return userTimestamp > assistantTimestamp
    }

    private func idleText(targetName: String?, language: DisplayLanguage) -> String? {
        guard let targetName = targetName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !targetName.isEmpty,
              targetName != "-" else {
            return nil
        }
        switch language {
        case .english:
            return "\(targetName) · No active tasks"
        case .simplifiedChinese:
            return "\(targetName) · 暂无进行中的任务"
        }
    }

    private func shouldShowFinishedActivityBeforeMessage(
        _ activity: CodexActivity,
        state: CodexDisplayState,
        now: Date
    ) -> Bool {
        guard activity.status == .completed || activity.status == .failed,
              let updated = state.lastUpdatedAt,
              now.timeIntervalSince(updated) <= completedHoldSeconds,
              let assistantTimestamp = state.latestAssistantTimestamp,
              !assistantTimestamp.isEmpty,
              !activity.timestamp.isEmpty else {
            return false
        }
        return activity.timestamp > assistantTimestamp
    }

    private func thinkingFrame(now: Date, language: DisplayLanguage) -> CodexActivityPrefix {
        let frames = ["brain.head.profile", "ellipsis.bubble", "brain.head.profile", "ellipsis.bubble"]
        let index = Int(now.timeIntervalSince1970 * 2) % frames.count
        return activityPrefix(symbol: frames[index], english: ("Thinking", "Thinking"), chinese: ("正在思考", "思考"), language: language)
    }

    private func activityPrefix(
        symbol: String,
        english: (String, String),
        chinese: (String, String),
        language: DisplayLanguage
    ) -> CodexActivityPrefix {
        let text = language == .english ? english : chinese
        return CodexActivityPrefix(systemSymbolName: symbol, accessibilityLabel: text.0, fallbackText: text.1)
    }

    private func waitingForCodexActivity(language: DisplayLanguage) -> String {
        language == .english ? "Waiting for Codex activity" : "等待 Codex 活动"
    }

    private func activityText(_ activity: CodexActivity, language: DisplayLanguage) -> String {
        guard language == .english else { return fit(activity.text) }

        let title = localizedActivityTitle(kind: activity.kind, status: activity.status)
        guard let detail = activityDetail(from: activity.text), !detail.isEmpty else {
            return title
        }
        return "\(title): \(detail)"
    }

    private func localizedActivityTitle(kind: CodexActivityKind, status: CodexActivityStatus) -> String {
        switch status {
        case .running:
            switch kind {
            case .thinking: return "Thinking"
            case .fileRead: return "Viewing file"
            case .imageView: return "Viewing image"
            case .webSearch: return "Searching web"
            case .fileEdit: return "Editing file"
            case .command: return "Running command"
            case .tool: return "Using tool"
            case .imageGeneration: return "Generating image"
            case .subagent: return "Subagent working"
            case .approval: return "Waiting for approval"
            }
        case .completed:
            switch kind {
            case .thinking: return "Thinking completed"
            case .fileRead: return "File viewed"
            case .imageView: return "Image viewed"
            case .webSearch: return "Web search completed"
            case .fileEdit: return "File edit completed"
            case .command: return "Command completed"
            case .tool: return "Tool call completed"
            case .imageGeneration: return "Image generated"
            case .subagent: return "Subagent updated"
            case .approval: return "Approval handled"
            }
        case .failed:
            switch kind {
            case .thinking: return "Thinking interrupted"
            case .fileRead: return "File view failed"
            case .imageView: return "Image view failed"
            case .webSearch: return "Web search failed"
            case .fileEdit: return "File edit failed"
            case .command: return "Command failed"
            case .tool: return "Tool call failed"
            case .imageGeneration: return "Image generation failed"
            case .subagent: return "Subagent failed"
            case .approval: return "Approval declined"
            }
        }
    }

    private func activityDetail(from text: String) -> String? {
        var value = CodexDisplayTextFormatter.displayText(from: text)
        let prefixes = [
            "正在执行：", "已执行：", "命令执行失败：",
            "正在查看 ", "已查看 ", "查看文件失败",
            "正在编辑 ", "已编辑 ", "编辑文件失败",
            "正在调用工具：", "已完成工具调用：", "工具调用失败：",
            "等待审批：", "已处理审批：", "审批未通过："
        ]
        for prefix in prefixes where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) else {
            return nil
        }
        return fit(value)
    }
}

public struct CodexActivityPrefix: Equatable {
    public var systemSymbolName: String
    public var accessibilityLabel: String
    public var fallbackText: String

    public init(systemSymbolName: String, accessibilityLabel: String, fallbackText: String) {
        self.systemSymbolName = systemSymbolName
        self.accessibilityLabel = accessibilityLabel
        self.fallbackText = fallbackText
    }
}
