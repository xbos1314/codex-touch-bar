import Foundation

public struct JSONLReadResult: Equatable {
    public var text: String
    public var nextOffset: UInt64

    public init(text: String, nextOffset: UInt64) {
        self.text = text
        self.nextOffset = nextOffset
    }
}

public final class JSONLTailer {
    public init() {}

    public func readTail(fileURL: URL, maxBytes: Int = 512 * 1024) throws -> JSONLReadResult {
        let size = try fileSize(fileURL)
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        let result = try readCompleteRange(
            fileURL: fileURL,
            offset: offset,
            size: size,
            maxBytes: maxBytes,
            maxRecordBytes: 16 * 1024 * 1024
        )
        guard offset > 0, let firstNewline = result.text.firstIndex(of: "\n") else {
            return result
        }
        let trimmed = String(result.text[result.text.index(after: firstNewline)...])
        return JSONLReadResult(text: trimmed, nextOffset: result.nextOffset)
    }

    public func readCompleteRange(
        fileURL: URL,
        offset: UInt64,
        size: UInt64,
        maxBytes: Int = 512 * 1024,
        maxRecordBytes: Int = 16 * 1024 * 1024
    ) throws -> JSONLReadResult {
        guard size > offset else { return JSONLReadResult(text: "", nextOffset: offset) }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)

        let wanted = min(UInt64(maxBytes), size - offset)
        let initial = try handle.read(upToCount: Int(wanted)) ?? Data()
        if let newline = initial.lastIndex(of: 0x0A) {
            let complete = initial.prefix(through: newline)
            return JSONLReadResult(
                text: String(data: complete, encoding: .utf8) ?? "",
                nextOffset: offset + UInt64(complete.count)
            )
        }

        var position = offset + UInt64(initial.count)
        var recordBytes = initial.count
        var chunks: [Data] = [initial]
        var skipRecord = recordBytes > maxRecordBytes

        while position < size {
            try handle.seek(toOffset: position)
            let readSize = min(64 * 1024, Int(size - position))
            let chunk = try handle.read(upToCount: readSize) ?? Data()
            if chunk.isEmpty { break }

            let newlineIndex = chunk.firstIndex(of: 0x0A)
            let consumed = newlineIndex.map { $0 + 1 } ?? chunk.count
            recordBytes += consumed
            if recordBytes > maxRecordBytes { skipRecord = true }
            if !skipRecord { chunks.append(chunk.prefix(consumed)) }
            position += UInt64(consumed)

            if newlineIndex != nil {
                if skipRecord {
                    return JSONLReadResult(text: "", nextOffset: position)
                }
                var combined = Data()
                for chunk in chunks {
                    combined.append(chunk)
                }
                let text = String(data: combined, encoding: .utf8) ?? ""
                return JSONLReadResult(text: text, nextOffset: position)
            }
        }

        return JSONLReadResult(text: "", nextOffset: offset)
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values.fileSize ?? 0)
    }
}
