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

    public func detailText(for state: CodexDisplayState, now: Date = Date(), idleTargetName: String? = nil) -> String {
        detailPresentation(for: state, now: now, idleTargetName: idleTargetName).fallbackText
    }

    public func detailPresentation(
        for state: CodexDisplayState,
        now: Date = Date(),
        idleTargetName: String? = nil
    ) -> CodexDetailPresentation {
        if let activity = state.latestActivity, activity.kind == .approval, activity.status == .running {
            return CodexDetailPresentation(text: fit(activity.text))
        }

        if let activity = state.latestActivity,
           shouldShowFinishedActivityBeforeMessage(activity, state: state, now: now) {
            return CodexDetailPresentation(text: fit(activity.text))
        }

        if let assistant = primaryMessageText(from: state) {
            if let prefix = activityPrefix(for: state.latestActivity, now: now) {
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
            return CodexDetailPresentation(text: fit(activity.text))
        }

        if state.status == .idle, let idleText = idleText(targetName: idleTargetName) {
            return CodexDetailPresentation(text: idleText)
        }

        if let activity = state.latestActivity,
           (activity.status == .completed || activity.status == .failed),
           let updated = state.lastUpdatedAt,
           now.timeIntervalSince(updated) <= completedHoldSeconds {
            return CodexDetailPresentation(text: fit(activity.text))
        }

        if let assistant = state.latestAssistantText, !assistant.isEmpty {
            return CodexDetailPresentation(text: fit(assistant))
        }

        if let activity = state.latestActivity {
            return CodexDetailPresentation(text: fit(activity.text))
        }

        return CodexDetailPresentation(text: idleText(targetName: idleTargetName) ?? "等待 Codex 活动")
    }

    public func activityPrefix(for activity: CodexActivity?, now: Date = Date()) -> CodexActivityPrefix? {
        guard let activity, activity.status == .running else { return nil }
        switch activity.kind {
        case .thinking:
            return thinkingFrame(now: now)
        case .fileRead:
            return CodexActivityPrefix(systemSymbolName: "doc.text.magnifyingglass", accessibilityLabel: "查看文件", fallbackText: "查看")
        case .imageView:
            return CodexActivityPrefix(systemSymbolName: "photo", accessibilityLabel: "查看图片", fallbackText: "图片")
        case .webSearch:
            return CodexActivityPrefix(systemSymbolName: "globe", accessibilityLabel: "搜索网页", fallbackText: "搜索")
        case .fileEdit:
            return CodexActivityPrefix(systemSymbolName: "square.and.pencil", accessibilityLabel: "编辑文件", fallbackText: "编辑")
        case .command:
            return CodexActivityPrefix(systemSymbolName: "terminal", accessibilityLabel: "执行命令", fallbackText: "命令")
        case .tool:
            return CodexActivityPrefix(systemSymbolName: "wrench.and.screwdriver", accessibilityLabel: "调用工具", fallbackText: "工具")
        case .imageGeneration:
            return CodexActivityPrefix(systemSymbolName: "wand.and.stars", accessibilityLabel: "创作图片", fallbackText: "创作")
        case .subagent:
            return CodexActivityPrefix(systemSymbolName: "person.2", accessibilityLabel: "子智能体", fallbackText: "子任务")
        case .approval:
            return CodexActivityPrefix(systemSymbolName: "hand.raised", accessibilityLabel: "等待审批", fallbackText: "审批")
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

    private func idleText(targetName: String?) -> String? {
        guard let targetName = targetName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !targetName.isEmpty,
              targetName != "-" else {
            return nil
        }
        return "\(targetName) · 暂无进行中的任务"
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

    private func thinkingFrame(now: Date) -> CodexActivityPrefix {
        let frames = ["brain.head.profile", "ellipsis.bubble", "brain.head.profile", "ellipsis.bubble"]
        let index = Int(now.timeIntervalSince1970 * 2) % frames.count
        return CodexActivityPrefix(systemSymbolName: frames[index], accessibilityLabel: "正在思考", fallbackText: "思考")
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
