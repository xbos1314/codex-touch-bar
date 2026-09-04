import Foundation

public enum CodexMessageRole: String, Equatable {
    case user
    case assistant
}

public struct CodexVisibleMessage: Equatable {
    public var timestamp: String
    public var role: CodexMessageRole
    public var text: String

    public init(timestamp: String, role: CodexMessageRole, text: String) {
        self.timestamp = timestamp
        self.role = role
        self.text = text
    }
}

public final class CodexEventParser {
    private let decoder = JSONDecoder()
    private let maxActivities = 12

    public init() {}

    public func parseEvents(from jsonlText: String) -> [CodexEvent] {
        jsonlText.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return try? decoder.decode(CodexEvent.self, from: Data(trimmed.utf8))
        }
    }

    public func visibleMessages(from events: [CodexEvent]) -> [CodexVisibleMessage] {
        events.flatMap { event -> [CodexVisibleMessage] in
            guard event.type == "response_item",
                  event.payload?["type"]?.stringValue == "message",
                  let roleText = event.payload?["role"]?.stringValue,
                  let role = CodexMessageRole(rawValue: roleText),
                  let content = event.payload?["content"]?.arrayValue else {
                return []
            }

            return content.compactMap { item in
                guard let object = item.objectValue,
                      let itemType = object["type"]?.stringValue,
                      (itemType == "input_text" || itemType == "output_text"),
                      let text = object["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else {
                    return nil
                }
                return CodexVisibleMessage(timestamp: event.timestamp ?? "", role: role, text: text)
            }
        }
    }

    public func activities(from events: [CodexEvent], previous: [CodexActivity] = []) -> [CodexActivity] {
        var activities = previous
        let automaticTurnIDs = CodexAutomaticContextCompactionPolicy.automaticTurnIDs(in: events)

        for (index, event) in events.enumerated() {
            let payload = event.payload ?? [:]
            let payloadType = payload["type"]?.stringValue ?? ""

            if event.type == "event_msg", payloadType == "task_started" {
                if let turnID = payload["turn_id"]?.stringValue, automaticTurnIDs.contains(turnID) {
                    append(CodexActivity(
                        id: CodexAutomaticContextCompactionPolicy.activityID(for: turnID),
                        timestamp: event.timestamp ?? "",
                        kind: .thinking,
                        status: .running,
                        text: CodexAutomaticContextCompactionPolicy.activityText,
                        callId: turnID
                    ), to: &activities)
                    continue
                }

                append(CodexActivity(
                    id: payload["turn_id"]?.stringValue ?? "task-started-\(index)",
                    timestamp: event.timestamp ?? "",
                    kind: .thinking,
                    status: .running,
                    text: "正在思考"
                ), to: &activities)
                continue
            }

            if event.type == "event_msg", payloadType == "task_complete" {
                if CodexAutomaticContextCompactionPolicy.isAutomaticCompletion(
                    event,
                    automaticTurnIDs: automaticTurnIDs,
                    activities: activities
                ) {
                    if let turnID = payload["turn_id"]?.stringValue {
                        activities.removeAll { CodexAutomaticContextCompactionPolicy.isActivity($0, turnID: turnID) }
                    } else {
                        activities.removeAll { CodexAutomaticContextCompactionPolicy.isActivity($0) }
                    }
                    continue
                }

                for activityIndex in activities.indices where activities[activityIndex].status == .running {
                    activities[activityIndex] = completedCopy(of: activities[activityIndex])
                }
                continue
            }

            if event.type == "event_msg", payloadType == "sub_agent_activity" {
                guard let name = subagentName(payload["agent_path"]?.stringValue) else { continue }
                let text = payload["kind"]?.stringValue == "interacted" ? "子智能体有进展" : "子智能体已启动"
                append(CodexActivity(
                    id: "subagent-\(event.timestamp ?? String(index))-\(name)",
                    timestamp: event.timestamp ?? "",
                    kind: .subagent,
                    status: .running,
                    text: text,
                    agentNames: [name]
                ), to: &activities)
                continue
            }

            if event.type == "event_msg", payloadType == "patch_apply_end" {
                completePatchActivity(payload: payload, index: index, timestamp: event.timestamp ?? "", activities: &activities)
                continue
            }

            if event.type == "event_msg", payloadType == "web_search_end" {
                completeNamedActivity(callId: payload["call_id"]?.stringValue, kind: .webSearch, failed: outputFailed(payload), activities: &activities)
                continue
            }

            if event.type == "event_msg", payloadType == "image_generation_end" {
                completeNamedActivity(callId: payload["call_id"]?.stringValue, kind: .imageGeneration, failed: outputFailed(payload), activities: &activities)
                continue
            }

            if event.type == "response_item", payloadType == "agent_message" {
                guard payload["recipient"]?.stringValue == "/root",
                      let name = subagentName(payload["author"]?.stringValue) else { continue }
                append(CodexActivity(
                    id: "agent-message-\(event.timestamp ?? String(index))-\(name)",
                    timestamp: event.timestamp ?? "",
                    kind: .subagent,
                    status: .completed,
                    text: "收到子智能体反馈",
                    agentNames: [name]
                ), to: &activities)
                continue
            }

            if event.type == "response_item", payloadType == "reasoning" {
                append(CodexActivity(
                    id: "reasoning-\(event.timestamp ?? String(index))",
                    timestamp: event.timestamp ?? "",
                    kind: .thinking,
                    status: .running,
                    text: "正在思考"
                ), to: &activities)
                continue
            }

            if event.type == "event_msg", payloadType == "agent_reasoning" {
                append(CodexActivity(
                    id: "agent-reasoning-\(event.timestamp ?? String(index))",
                    timestamp: event.timestamp ?? "",
                    kind: .thinking,
                    status: .running,
                    text: "正在思考"
                ), to: &activities)
                continue
            }

            if event.type == "response_item", payloadType == "function_call" || payloadType == "custom_tool_call" {
                let activity = describeFunctionCall(payload: payload, timestamp: event.timestamp ?? "", index: index)
                completeRunningThinking(in: &activities)
                append(activity, to: &activities)
                continue
            }

            if event.type == "response_item", payloadType == "function_call_output" || payloadType == "custom_tool_call_output" {
                guard let callId = payload["call_id"]?.stringValue else { continue }
                completeActivity(callId: callId, failed: outputFailed(payload), activities: &activities)
                continue
            }
        }

        return activities
    }

    private func append(_ activity: CodexActivity, to activities: inout [CodexActivity]) {
        if activity.kind == .thinking, activities.last?.kind == .thinking, activities.last?.status == .running {
            activities[activities.count - 1] = activity
            return
        }
        activities.append(activity)
        if activities.count > maxActivities {
            activities.removeFirst(activities.count - maxActivities)
        }
    }

    private func completeRunningThinking(in activities: inout [CodexActivity]) {
        for index in activities.indices where activities[index].kind == .thinking && activities[index].status == .running {
            activities[index] = completedCopy(of: activities[index])
        }
    }

    private func completeActivity(callId: String, failed: Bool, activities: inout [CodexActivity]) {
        guard let index = activities.lastIndex(where: { $0.callId == callId && $0.status == .running }) else { return }
        activities[index] = failed ? failedCopy(of: activities[index]) : completedCopy(of: activities[index])
    }

    private func completeNamedActivity(callId: String?, kind: CodexActivityKind, failed: Bool, activities: inout [CodexActivity]) {
        guard let callId else { return }
        guard let index = activities.lastIndex(where: { $0.callId == callId && $0.status == .running }) else { return }
        var activity = activities[index]
        activity.kind = kind
        activities[index] = failed ? failedCopy(of: activity) : completedCopy(of: activity)
    }

    private func completePatchActivity(payload: [String: CodexJSONValue], index: Int, timestamp: String, activities: inout [CodexActivity]) {
        let callId = payload["call_id"]?.stringValue
        let changed = payload["files_changed"]?.intValue ?? payload["changed_files"]?.intValue ?? 1
        if let callId, let activityIndex = activities.lastIndex(where: { $0.callId == callId }) {
            var activity = activities[activityIndex]
            activity.kind = .fileEdit
            activity.status = payload["success"]?.boolValue == false ? .failed : .completed
            activity.text = activity.status == .failed ? "编辑文件失败" : "已编辑 \(changed) 个文件"
            activities[activityIndex] = activity
            return
        }
        append(CodexActivity(
            id: callId ?? "patch-\(index)",
            timestamp: timestamp,
            kind: .fileEdit,
            status: payload["success"]?.boolValue == false ? .failed : .completed,
            text: payload["success"]?.boolValue == false ? "编辑文件失败" : "已编辑 \(changed) 个文件",
            callId: callId
        ), to: &activities)
    }

    private func completedCopy(of activity: CodexActivity) -> CodexActivity {
        var copy = activity
        copy.status = .completed
        switch copy.kind {
        case .command:
            copy.text = copy.text.replacingOccurrences(of: "正在执行：", with: "已执行：")
        case .fileRead:
            copy.text = copy.text.replacingOccurrences(of: "正在查看 ", with: "已查看 ")
        case .fileEdit:
            copy.text = copy.text.replacingOccurrences(of: "正在编辑 ", with: "已编辑 ")
        case .tool:
            copy.text = copy.text.replacingOccurrences(of: "正在调用工具：", with: "已完成工具调用：")
        case .thinking:
            copy.text = "已完成思考"
        case .imageGeneration:
            copy.text = "图片创作完成"
        case .webSearch:
            copy.text = "网页搜索完成"
        case .imageView:
            copy.text = "已查看图片"
        case .subagent:
            if copy.text.hasPrefix("正在") { copy.text = "子智能体有进展" }
        case .approval:
            copy.text = copy.text.replacingOccurrences(of: "等待审批：", with: "已处理审批：")
        }
        return copy
    }

    private func failedCopy(of activity: CodexActivity) -> CodexActivity {
        var copy = activity
        copy.status = .failed
        switch copy.kind {
        case .command:
            copy.text = copy.text.replacingOccurrences(of: "正在执行：", with: "命令执行失败：")
        case .fileRead:
            copy.text = "查看文件失败"
        case .fileEdit:
            copy.text = "编辑文件失败"
        case .tool:
            copy.text = copy.text.replacingOccurrences(of: "正在调用工具：", with: "工具调用失败：")
        case .thinking:
            copy.text = "思考中断"
        case .imageGeneration:
            copy.text = "图片创作失败"
        case .webSearch:
            copy.text = "网页搜索失败"
        case .imageView:
            copy.text = "查看图片失败"
        case .subagent:
            copy.text = "子智能体异常"
        case .approval:
            copy.text = copy.text.replacingOccurrences(of: "等待审批：", with: "审批未通过：")
        }
        return copy
    }

    private func describeFunctionCall(payload: [String: CodexJSONValue], timestamp: String, index: Int) -> CodexActivity {
        let name = payload["name"]?.stringValue ?? payload["tool_name"]?.stringValue ?? "未知工具"
        let callId = payload["call_id"]?.stringValue ?? payload["id"]?.stringValue
        let command = commandText(from: payload)

        if requiresEscalatedApproval(payload) {
            return CodexActivity(
                id: callId ?? "call-\(index)",
                timestamp: timestamp,
                kind: .approval,
                status: .running,
                text: "等待审批：\(compact(command.isEmpty ? name : command))",
                callId: callId
            )
        }

        if name == "exec_command" || name == "exec" {
            if command.contains("apply_patch") || command.contains("*** Begin Patch") {
                return CodexActivity(
                    id: callId ?? "call-\(index)",
                    timestamp: timestamp,
                    kind: .fileEdit,
                    status: .running,
                    text: "正在编辑文件",
                    callId: callId
                )
            }
            if let readPath = pathFromReadCommand(command) {
                return CodexActivity(
                    id: callId ?? "call-\(index)",
                    timestamp: timestamp,
                    kind: .fileRead,
                    status: .running,
                    text: "正在查看 \(readPath)",
                    callId: callId
                )
            }
            return CodexActivity(
                id: callId ?? "call-\(index)",
                timestamp: timestamp,
                kind: .command,
                status: .running,
                text: "正在执行：\(compact(command.isEmpty ? "命令" : command))",
                callId: callId
            )
        }

        if name == "apply_patch" || name == "write_file" || name == "edit_file" {
            return CodexActivity(
                id: callId ?? "call-\(index)",
                timestamp: timestamp,
                kind: .fileEdit,
                status: .running,
                text: "正在编辑文件",
                callId: callId
            )
        }

        if name == "view_image" {
            return CodexActivity(id: callId ?? "call-\(index)", timestamp: timestamp, kind: .imageView, status: .running, text: "正在查看图片", callId: callId)
        }

        if name == "imagegen" || name.hasSuffix("__imagegen") {
            return CodexActivity(id: callId ?? "call-\(index)", timestamp: timestamp, kind: .imageGeneration, status: .running, text: "正在创作图片", callId: callId)
        }

        if name == "web.run" || name == "web__run" || name == "web_search" {
            return CodexActivity(id: callId ?? "call-\(index)", timestamp: timestamp, kind: .webSearch, status: .running, text: "正在搜索网页", callId: callId)
        }

        if name == "spawn_agent" {
            return CodexActivity(id: callId ?? "call-\(index)", timestamp: timestamp, kind: .subagent, status: .running, text: "正在创建子智能体", callId: callId)
        }

        if name == "wait_agent" {
            return CodexActivity(id: callId ?? "call-\(index)", timestamp: timestamp, kind: .subagent, status: .running, text: "正在等待子智能体", callId: callId)
        }

        return CodexActivity(
            id: callId ?? "call-\(index)",
            timestamp: timestamp,
            kind: .tool,
            status: .running,
            text: "正在调用工具：\(name)",
            callId: callId
        )
    }

    private func commandText(from payload: [String: CodexJSONValue]) -> String {
        let argumentObject = argumentObject(from: payload)
        if let cmd = argumentObject["cmd"]?.stringValue ?? argumentObject["command"]?.stringValue {
            return cmd
        }
        return payload["arguments"]?.stringValue ?? payload["input"]?.stringValue ?? ""
    }

    private func requiresEscalatedApproval(_ payload: [String: CodexJSONValue]) -> Bool {
        let arguments = argumentObject(from: payload)
        return arguments["sandbox_permissions"]?.stringValue == "require_escalated"
    }

    private func argumentObject(from payload: [String: CodexJSONValue]) -> [String: CodexJSONValue] {
        if let object = payload["arguments"]?.objectValue ?? payload["input"]?.objectValue {
            return object
        }

        guard let text = payload["arguments"]?.stringValue ?? payload["input"]?.stringValue,
              let data = text.data(using: .utf8),
              let object = try? JSONDecoder().decode([String: CodexJSONValue].self, from: data) else {
            return [:]
        }
        return object
    }

    private func pathFromReadCommand(_ command: String) -> String? {
        guard command.range(of: #"^\s*(cat|sed|head|tail|less|more|rg|grep|find|ls)\b"#, options: .regularExpression) != nil else {
            return nil
        }
        return command.split(separator: " ").last.map(String.init)
    }

    private func compact(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return normalized.count > 96 ? String(normalized.prefix(96)) + "..." : normalized
    }

    private func outputFailed(_ payload: [String: CodexJSONValue]) -> Bool {
        if payload["is_error"]?.boolValue == true { return true }
        if payload["error"]?.boolValue == true { return true }
        if payload["failed"]?.boolValue == true { return true }
        return payload["status"]?.stringValue?.lowercased() == "failed"
    }

    private func subagentName(_ value: String?) -> String? {
        guard let value else { return nil }
        let name = value.split(separator: "/").last.map(String.init) ?? ""
        guard name.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return name
    }
}
