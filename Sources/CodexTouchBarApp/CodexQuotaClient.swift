import Foundation
import CodexTouchBarCore

@MainActor
final class CodexQuotaClient {
    var onSnapshot: ((CodexQuotaSnapshot) -> Void)?

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var outputBuffer = Data()
    private var nextRequestID = 1
    private var latestSnapshot: CodexQuotaSnapshot?
    private var isStopping = false

    func start() {
        guard process == nil else {
            refresh()
            return
        }
        guard let command = codexCommand() else {
            publishUnavailableIfNeeded()
            return
        }

        let input = Pipe()
        let output = Pipe()
        let task = Process()
        task.executableURL = command.executableURL
        task.arguments = command.arguments
        task.standardInput = input
        task.standardOutput = output
        task.standardError = Pipe()
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleProcessTermination()
            }
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async {
                self?.receive(data)
            }
        }

        do {
            try task.run()
            isStopping = false
            process = task
            inputHandle = input.fileHandleForWriting
            outputHandle = output.fileHandleForReading
            send([
                "method": "initialize",
                "id": requestID(),
                "params": [
                    "clientInfo": [
                        "name": "codex-touch-bar",
                        "title": "Codex Touch Bar",
                        "version": "1.0.0"
                    ]
                ]
            ])
            send(["method": "initialized", "params": [:]])
            refresh()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            publishUnavailableIfNeeded()
        }
    }

    func refresh() {
        guard process?.isRunning == true else {
            start()
            return
        }
        send([
            "method": "account/rateLimits/read",
            "id": requestID(),
            "params": [:]
        ])
    }

    func stop() {
        isStopping = true
        outputHandle?.readabilityHandler = nil
        inputHandle?.closeFile()
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        inputHandle = nil
        outputHandle = nil
        outputBuffer.removeAll(keepingCapacity: false)
    }

    private func receive(_ data: Data) {
        outputBuffer.append(data)
        let newline = Data([0x0A])
        while let range = outputBuffer.range(of: newline) {
            let lineData = outputBuffer.subdata(in: outputBuffer.startIndex..<range.lowerBound)
            outputBuffer.removeSubrange(outputBuffer.startIndex...range.lowerBound)
            handleLine(lineData)
        }
    }

    private func handleLine(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let message = object as? [String: Any] else {
            return
        }

        if message["method"] as? String == "account/rateLimits/updated" {
            refresh()
            return
        }
        guard let result = message["result"] as? [String: Any],
              let snapshot = snapshot(from: result) else {
            return
        }
        latestSnapshot = snapshot
        onSnapshot?(snapshot)
    }

    private func snapshot(from result: [String: Any]) -> CodexQuotaSnapshot? {
        let quota: [String: Any]?
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any],
           let main = buckets["codex"] as? [String: Any] {
            quota = main
        } else if let legacy = result["rateLimits"] as? [String: Any],
                  legacy["limitId"] as? String == "codex" {
            quota = legacy
        } else {
            quota = nil
        }
        guard let quota else { return nil }

        let primary = quota["primary"] as? [String: Any]
        let resetCredits = result["rateLimitResetCredits"] as? [String: Any]
        return CodexQuotaSnapshot(
            planType: quota["planType"] as? String,
            mainUsedPercent: integer(from: primary?["usedPercent"]),
            mainResetsAt: date(from: primary?["resetsAt"]),
            availableResetCount: integer(from: resetCredits?["availableCount"]),
            availableResetExpiresAt: earliestAvailableCreditExpiration(from: resetCredits)
        )
    }

    private func earliestAvailableCreditExpiration(from resetCredits: [String: Any]?) -> Date? {
        let credits = resetCredits?["credits"] as? [[String: Any]] ?? []
        return credits
            .filter { ($0["status"] as? String) == "available" }
            .compactMap { date(from: $0["expiresAt"]) }
            .min()
    }

    private func integer(from value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private func date(from value: Any?) -> Date? {
        if let value = value as? TimeInterval {
            return Date(timeIntervalSince1970: value)
        }
        if let value = value as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue)
        }
        return nil
    }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              var line = String(data: data, encoding: .utf8)?.data(using: .utf8) else {
            return
        }
        line.append(0x0A)
        inputHandle?.write(line)
    }

    private func requestID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    private func handleProcessTermination() {
        process = nil
        inputHandle = nil
        outputHandle = nil
        outputBuffer.removeAll(keepingCapacity: false)
        guard !isStopping else { return }
        publishUnavailableIfNeeded()
    }

    private func publishUnavailableIfNeeded() {
        guard latestSnapshot == nil else { return }
        onSnapshot?(.unavailable)
    }

    private func codexCommand() -> (executableURL: URL, arguments: [String])? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let directCandidates = [
            home.appendingPathComponent(".codex/plugins/.plugin-appserver/codex"),
            home.appendingPathComponent(".codex/packages/standalone/current/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]
        if let executableURL = directCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return (executableURL, ["app-server"])
        }

        let nvmVersions = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let versionDirectories = try? fileManager.contentsOfDirectory(
            at: nvmVersions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            let nvmCandidates = versionDirectories
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
                .map { $0.appendingPathComponent("bin/codex") }
            if let executableURL = nvmCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
                return (executableURL, ["app-server"])
            }
        }

        return (URL(fileURLWithPath: "/usr/bin/env"), ["codex", "app-server"])
    }
}
