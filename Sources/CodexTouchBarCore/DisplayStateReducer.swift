import Foundation

public final class DisplayStateReducer {
    private let parser: CodexEventParser

    private struct TurnLifecycle {
        var startedTurnIDs: [String] = []
        var completedTurnIDs: [String] = []
        var hasUnidentifiedCompletion = false
    }

    public init(parser: CodexEventParser = CodexEventParser()) {
        self.parser = parser
    }

    public func reset(session: CodexSessionFile) -> CodexDisplayState {
        CodexDisplayState(
            sessionId: session.sessionId,
            projectName: session.projectName,
            projectPath: session.projectPath,
            status: .idle,
            latestActivity: CodexActivity(
                id: "session-selected",
                timestamp: "",
                kind: .thinking,
                status: .completed,
                text: "等待 Codex 活动"
            ),
            activities: [],
            latestAssistantText: nil,
            latestUserText: nil,
            lastUpdatedAt: Date()
        )
    }

    public func reduce(state: CodexDisplayState, events: [CodexEvent], session: CodexSessionFile) -> CodexDisplayState {
        var next = state
        if next.sessionId != session.sessionId {
            next = reset(session: session)
        }

        next.sessionId = session.sessionId
        next.projectName = session.projectName
        next.projectPath = session.projectPath
        next.lastUpdatedAt = Date()

        for message in parser.visibleMessages(from: events) {
            let text = normalizedText(message.text)
            switch message.role {
            case .assistant:
                next.latestAssistantText = text
                next.latestAssistantTimestamp = message.timestamp
            case .user:
                next.latestUserText = text
                next.latestUserTimestamp = message.timestamp
                next.isTaskRunning = true
                next.isTaskComplete = false
            }
        }

        let automaticTurnIDs = CodexAutomaticContextCompactionPolicy.automaticTurnIDs(in: events)
        let lifecycle = turnLifecycle(
            in: events,
            automaticTurnIDs: automaticTurnIDs,
            currentActivities: next.activities
        )
        if let startedTurnID = lifecycle.startedTurnIDs.last {
            next.activeTurnId = startedTurnID
            next.isTaskRunning = true
            next.isTaskComplete = false
        }
        let sawTaskComplete = sawTaskComplete(lifecycle: lifecycle, state: next)
        let previousActivities = next.activities
        let activities = parser.activities(from: events, previous: next.activities)
        if let latest = activities.last {
            next.activities = activities
            next.latestActivity = latest
            if sawTaskComplete {
                next.activeTurnId = nil
                next.isTaskRunning = false
                next.isTaskComplete = true
                next.status = .completed
            } else {
                if latest.status == .failed {
                    next.isTaskRunning = false
                    next.status = .failed
                } else {
                    next.isTaskRunning = true
                    next.status = runningStatus(for: latest)
                }
                if latest.status == .running {
                    next.isTaskComplete = false
                }
                if shouldIgnoreStaleCompletedActivity(latest, state: next) {
                    next.latestActivity = nil
                    next.status = .thinking
                }
            }
        } else if sawTaskComplete {
            next.activeTurnId = nil
            next.isTaskRunning = false
            next.isTaskComplete = true
            next.status = .completed
        } else if activities != previousActivities {
            next.activities = activities
            next.latestActivity = nil
            next.activeTurnId = nil
            next.isTaskRunning = false
            next.isTaskComplete = false
            next.status = .idle
        }

        if shouldInferCompletedFromAssistantReply(state: next) {
            next.isTaskRunning = false
            next.isTaskComplete = true
            next.status = .completed
        }

        return next
    }

    private func normalizedText(_ text: String) -> String {
        CodexDisplayTextFormatter.displayText(from: text)
    }

    private func turnLifecycle(
        in events: [CodexEvent],
        automaticTurnIDs: Set<String>,
        currentActivities: [CodexActivity]
    ) -> TurnLifecycle {
        var lifecycle = TurnLifecycle()
        for event in events {
            if CodexAutomaticContextCompactionPolicy.isTaskStartedEvent(event),
               let turnID = turnID(from: event),
               !automaticTurnIDs.contains(turnID) {
                lifecycle.startedTurnIDs.append(turnID)
            }

            guard CodexAutomaticContextCompactionPolicy.isTaskCompleteEvent(event),
                  !CodexAutomaticContextCompactionPolicy.isAutomaticCompletion(
                    event,
                    automaticTurnIDs: automaticTurnIDs,
                    activities: currentActivities
                  ) else {
                continue
            }

            if let turnID = turnID(from: event) {
                lifecycle.completedTurnIDs.append(turnID)
            } else {
                lifecycle.hasUnidentifiedCompletion = true
            }
        }
        return lifecycle
    }

    private func turnID(from event: CodexEvent) -> String? {
        guard let rawTurnID = event.payload?["turn_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTurnID.isEmpty else {
            return nil
        }
        return rawTurnID
    }

    private func sawTaskComplete(lifecycle: TurnLifecycle, state: CodexDisplayState) -> Bool {
        if let activeTurnId = state.activeTurnId {
            return lifecycle.completedTurnIDs.contains(activeTurnId)
        }

        return (lifecycle.startedTurnIDs.isEmpty && lifecycle.completedTurnIDs.count == 1)
            || lifecycle.hasUnidentifiedCompletion
    }

    private func runningStatus(for activity: CodexActivity) -> CodexStatus {
        switch activity.kind {
        case .thinking: return .thinking
        case .fileRead: return .readingFile
        case .fileEdit: return .editingFile
        case .approval:
            return activity.status == .running ? .waitingApproval : .runningTool
        case .command, .tool, .imageGeneration, .imageView, .webSearch, .subagent:
            return .runningTool
        }
    }

    private func shouldIgnoreStaleCompletedActivity(_ activity: CodexActivity, state: CodexDisplayState) -> Bool {
        guard activity.status == .completed,
              state.isTaskRunning,
              !state.isTaskComplete,
              let userTimestamp = state.latestUserTimestamp,
              !userTimestamp.isEmpty,
              !activity.timestamp.isEmpty else {
            return false
        }
        return activity.timestamp < userTimestamp
    }

    private func shouldInferCompletedFromAssistantReply(state: CodexDisplayState) -> Bool {
        guard state.isTaskRunning,
              !state.isTaskComplete,
              state.activeTurnId == nil,
              let userTimestamp = state.latestUserTimestamp,
              let assistantTimestamp = state.latestAssistantTimestamp,
              !userTimestamp.isEmpty,
              !assistantTimestamp.isEmpty,
              assistantTimestamp > userTimestamp else {
            return false
        }

        if state.latestActivity?.status == .running { return false }
        let currentTurnActivityTimestamps = state.activities
            .map(\.timestamp)
            .filter { !$0.isEmpty && $0 > userTimestamp }
        if let latestActivityTimestamp = currentTurnActivityTimestamps.max(),
           assistantTimestamp <= latestActivityTimestamp {
            return false
        }

        return !state.activities.contains { $0.status == .running }
    }
}
