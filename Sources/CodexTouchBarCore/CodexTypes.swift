import Foundation

public enum CodexJSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: CodexJSONValue])
    case array([CodexJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CodexJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: CodexJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        if case let .number(value) = self { return Int(value) }
        return nil
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    public var objectValue: [String: CodexJSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    public var arrayValue: [CodexJSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }
}

public struct CodexEvent: Decodable, Equatable {
    public var type: String
    public var timestamp: String?
    public var payload: [String: CodexJSONValue]?
}

public struct CodexMetadata: Decodable, Equatable {
    public var sessionId: String?
    public var cwd: String?
    public var originator: String?
    public var threadSource: String?
    public var parentThreadId: String?
    public var source: CodexJSONValue?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case originator
        case threadSource = "thread_source"
        case parentThreadId = "parent_thread_id"
        case source
    }

    public init(
        sessionId: String? = nil,
        cwd: String? = nil,
        originator: String? = nil,
        threadSource: String? = nil,
        parentThreadId: String? = nil,
        source: CodexJSONValue? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.originator = originator
        self.threadSource = threadSource
        self.parentThreadId = parentThreadId
        self.source = source
    }

    public var isSubagent: Bool {
        if threadSource?.trimmingCharacters(in: .whitespacesAndNewlines) == "subagent" { return true }
        if let parentThreadId, !parentThreadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return source?.objectValue?.keys.contains("subagent") == true
    }
}

public enum CodexActivityKind: String, Equatable {
    case thinking
    case fileRead
    case command
    case fileEdit
    case tool
    case imageGeneration
    case imageView
    case webSearch
    case subagent
    case approval
}

public enum CodexActivityStatus: String, Equatable {
    case running
    case completed
    case failed
}

public struct CodexActivity: Equatable {
    public var id: String
    public var timestamp: String
    public var kind: CodexActivityKind
    public var status: CodexActivityStatus
    public var text: String
    public var callId: String?
    public var agentNames: [String]

    public init(
        id: String,
        timestamp: String,
        kind: CodexActivityKind,
        status: CodexActivityStatus,
        text: String,
        callId: String? = nil,
        agentNames: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.status = status
        self.text = text
        self.callId = callId
        self.agentNames = agentNames
    }
}

public enum CodexStatus: String, Equatable {
    case idle
    case thinking
    case runningTool
    case readingFile
    case editingFile
    case waitingApproval
    case completed
    case failed
    case interrupted

    public var displayText: String {
        switch self {
        case .idle: return "空闲"
        case .thinking: return "正在思考"
        case .runningTool: return "正在调用工具"
        case .readingFile: return "正在查看文件"
        case .editingFile: return "正在编辑"
        case .waitingApproval: return "等待审批"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .interrupted: return "已停止"
        }
    }
}

public struct CodexDisplayState: Equatable {
    public var sessionId: String?
    public var activeTurnId: String?
    public var projectName: String
    public var projectPath: String
    public var status: CodexStatus
    public var latestActivity: CodexActivity?
    public var activities: [CodexActivity]
    public var latestAssistantText: String?
    public var latestAssistantTimestamp: String?
    public var latestUserText: String?
    public var latestUserTimestamp: String?
    public var isTaskRunning: Bool
    public var isTaskComplete: Bool
    public var lastUpdatedAt: Date?

    public init(
        sessionId: String?,
        activeTurnId: String? = nil,
        projectName: String,
        projectPath: String,
        status: CodexStatus,
        latestActivity: CodexActivity?,
        activities: [CodexActivity] = [],
        latestAssistantText: String?,
        latestAssistantTimestamp: String? = nil,
        latestUserText: String?,
        latestUserTimestamp: String? = nil,
        isTaskRunning: Bool = false,
        isTaskComplete: Bool = false,
        lastUpdatedAt: Date?
    ) {
        self.sessionId = sessionId
        self.activeTurnId = activeTurnId
        self.projectName = projectName
        self.projectPath = projectPath
        self.status = status
        self.latestActivity = latestActivity
        self.activities = activities
        self.latestAssistantText = latestAssistantText
        self.latestAssistantTimestamp = latestAssistantTimestamp
        self.latestUserText = latestUserText
        self.latestUserTimestamp = latestUserTimestamp
        self.isTaskRunning = isTaskRunning
        self.isTaskComplete = isTaskComplete
        self.lastUpdatedAt = lastUpdatedAt
    }

    public static func idle(message: String) -> CodexDisplayState {
        CodexDisplayState(
            sessionId: nil,
            projectName: "-",
            projectPath: "",
            status: .idle,
            latestActivity: CodexActivity(
                id: "idle",
                timestamp: "",
                kind: .thinking,
                status: .completed,
                text: message
            ),
            activities: [],
            latestAssistantText: nil,
            latestUserText: nil,
            lastUpdatedAt: Date()
        )
    }
}
