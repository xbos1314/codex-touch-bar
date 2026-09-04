import Foundation

public struct CodexSessionFile: Equatable {
    public var url: URL
    public var metadata: CodexMetadata
    public var modifiedAt: Date
    public var size: UInt64
    public var threadName: String?

    public init(
        url: URL,
        metadata: CodexMetadata,
        modifiedAt: Date,
        size: UInt64,
        threadName: String? = nil
    ) {
        self.url = url
        self.metadata = metadata
        self.modifiedAt = modifiedAt
        self.size = size
        self.threadName = threadName
    }

    public var sessionId: String? { metadata.sessionId }
    public var displayName: String {
        if let threadName = threadName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !threadName.isEmpty {
            return threadName
        }
        return projectName
    }

    public var projectPath: String { metadata.cwd ?? "" }
    public var projectName: String {
        let path = projectPath
        if path.isEmpty { return "-" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

public extension CodexMetadata {
    var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "-" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

public final class CodexSessionStore {
    private let sessionsRoot: URL
    private let sessionIndexURL: URL
    private let headerBytes: Int

    public init(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions", isDirectory: true),
        sessionIndexURL: URL? = nil,
        headerBytes: Int = 64 * 1024
    ) {
        self.sessionsRoot = sessionsRoot
        self.sessionIndexURL = sessionIndexURL
            ?? sessionsRoot.deletingLastPathComponent().appendingPathComponent("session_index.jsonl")
        self.headerBytes = headerBytes
    }

    public func latestPrimarySession() throws -> CodexSessionFile? {
        try recentPrimarySessions(limit: nil).first
    }

    public func recentPrimarySessions(limit: Int? = nil) throws -> [CodexSessionFile] {
        let candidates = try sessionFileURLs()
        let threadNamesById = try readThreadNamesById()
        var entries: [CodexSessionFile] = []

        for url in candidates {
            guard let metadata = try readMetadata(from: url), !metadata.isSubagent else { continue }
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            entries.append(CodexSessionFile(
                url: url,
                metadata: metadata,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                size: UInt64(values.fileSize ?? 0),
                threadName: metadata.sessionId.flatMap { threadNamesById[$0] }
            ))
        }

        let sorted = entries.sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.url.lastPathComponent > $1.url.lastPathComponent
        }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    public func sessionFile(at url: URL) throws -> CodexSessionFile? {
        guard let metadata = try readMetadata(from: url), !metadata.isSubagent else { return nil }
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let threadNamesById = try readThreadNamesById()
        return CodexSessionFile(
            url: url,
            metadata: metadata,
            modifiedAt: values.contentModificationDate ?? .distantPast,
            size: UInt64(values.fileSize ?? 0),
            threadName: metadata.sessionId.flatMap { threadNamesById[$0] }
        )
    }

    public func readMetadata(from fileURL: URL) throws -> CodexMetadata? {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: headerBytes) ?? Data()
        guard let firstLine = String(data: data, encoding: .utf8)?.split(separator: "\n", maxSplits: 1).first else {
            return nil
        }
        let lineData = Data(String(firstLine).utf8)
        let envelope = try JSONDecoder().decode(SessionMetaEnvelope.self, from: lineData)
        guard envelope.type == "session_meta" else { return nil }
        return envelope.payload
    }

    private func sessionFileURLs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: sessionsRoot.path) else { return [] }
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try url.resourceValues(forKeys: keys)
            if values.isRegularFile == true { urls.append(url) }
        }
        return urls
    }

    private func readThreadNamesById() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: sessionIndexURL.path) else { return [:] }
        let text = try String(contentsOf: sessionIndexURL, encoding: .utf8)
        var names: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let entry = try? JSONDecoder().decode(SessionIndexEntry.self, from: data) else {
                continue
            }
            let name = entry.threadName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !entry.id.isEmpty, !name.isEmpty {
                names[entry.id] = name
            }
        }
        return names
    }
}

private struct SessionMetaEnvelope: Decodable {
    var type: String
    var payload: CodexMetadata
}

private struct SessionIndexEntry: Decodable {
    var id: String
    var threadName: String

    enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
    }
}
