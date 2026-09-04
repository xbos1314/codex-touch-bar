import Foundation

public enum TouchBarPetMood: Equatable, Sendable {
    case idle
    case thinking
    case running
    case approval
    case completed
    case failed
    case reading
    case selecting
}

public enum TouchBarPetPolicy {
    public static func mood(for state: CodexDisplayState, isReading: Bool) -> TouchBarPetMood {
        if isReading {
            return .reading
        }

        if state.status == .failed || state.latestActivity?.status == .failed {
            return .failed
        }

        if state.isTaskComplete, state.status == .completed {
            return .completed
        }

        if state.status == .waitingApproval || isRunningApproval(state.latestActivity) {
            return .approval
        }

        if state.status == .thinking || isRunningThinking(state.latestActivity) {
            return .thinking
        }

        if state.isTaskRunning || isRunning(state) {
            return .running
        }

        return .idle
    }

    private static func isRunning(_ state: CodexDisplayState) -> Bool {
        if state.latestActivity?.status == .running {
            return true
        }

        switch state.status {
        case .thinking, .runningTool, .readingFile, .editingFile, .waitingApproval:
            return true
        case .idle, .completed, .failed, .interrupted:
            return false
        }
    }

    private static func isRunningApproval(_ activity: CodexActivity?) -> Bool {
        activity?.kind == .approval && activity?.status == .running
    }

    private static func isRunningThinking(_ activity: CodexActivity?) -> Bool {
        activity?.kind == .thinking && activity?.status == .running
    }
}
