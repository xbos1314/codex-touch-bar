public enum CodexAutomaticContextCompactionPolicy {
    public static let activityText = "正在自动压缩上下文"

    public static func automaticTurnIDs(in events: [CodexEvent]) -> Set<String> {
        Set(events.compactMap { event in
            guard isAutomaticTurnContext(event) else { return nil }
            return event.payload?["turn_id"]?.stringValue
        })
    }

    public static func isTaskStartedEvent(_ event: CodexEvent) -> Bool {
        event.type == "event_msg" && event.payload?["type"]?.stringValue == "task_started"
    }

    public static func isTaskCompleteEvent(_ event: CodexEvent) -> Bool {
        event.type == "event_msg" && event.payload?["type"]?.stringValue == "task_complete"
    }

    public static func isAutomaticCompletion(
        _ event: CodexEvent,
        automaticTurnIDs: Set<String>,
        activities: [CodexActivity]
    ) -> Bool {
        guard isTaskCompleteEvent(event),
              let turnID = event.payload?["turn_id"]?.stringValue else {
            return false
        }
        return automaticTurnIDs.contains(turnID) || activities.contains { isActivity($0, turnID: turnID) }
    }

    public static func activityID(for turnID: String) -> String {
        "context-compaction-\(turnID)"
    }

    public static func isActivity(_ activity: CodexActivity, turnID: String? = nil) -> Bool {
        if let turnID {
            return activity.id == activityID(for: turnID)
                || (activity.callId == turnID && activity.text == activityText)
        }
        return activity.id.hasPrefix("context-compaction-") || activity.text == activityText
    }

    private static func isAutomaticTurnContext(_ event: CodexEvent) -> Bool {
        guard event.type == "turn_context",
              let summary = event.payload?["summary"]?.stringValue?.lowercased() else {
            return false
        }
        return summary == "auto"
    }
}
